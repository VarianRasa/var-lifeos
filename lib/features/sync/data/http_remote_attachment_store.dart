/// HTTP adapter for negotiated remote attachment transfer.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../../mindmap/domain/node_attachment.dart';
import '../domain/attachment_sync.dart';
import '../domain/remote_attachment_store.dart';

typedef HttpAttachmentAuthSnapshotProvider =
    FutureOr<HttpAttachmentAuthSnapshot> Function();

const int _maxControlResponseBytes = 64 * 1024;

final class HttpAttachmentAuthSnapshot {
  HttpAttachmentAuthSnapshot({
    required String accountId,
    required String revision,
    Map<String, String> headers = const {},
  }) : accountId = _safeIdentity(accountId, 'accountId'),
       revision = _safeIdentity(revision, 'revision'),
       headers = Map<String, String>.unmodifiable(_safeAuthHeaders(headers));

  final String accountId;
  final String revision;
  final Map<String, String> headers;

  bool hasSameSession(HttpAttachmentAuthSnapshot other) =>
      accountId == other.accountId && revision == other.revision;
}

final class HttpRemoteAttachmentStore
    implements RemoteAttachmentStore, AttachmentSyncAdapter {
  HttpRemoteAttachmentStore._({
    required Uri endpoint,
    required http.Client client,
    required HttpAttachmentAuthSnapshotProvider authSnapshotProvider,
    required HttpAttachmentAuthSnapshot negotiatedAuth,
    required this.maxBytes,
    required this.supportsUpload,
    required this.supportsDownload,
    required this.supportsDelete,
    required this.requestTimeout,
  }) : _endpoint = _normalizeEndpoint(endpoint),
       _client = client,
       _authSnapshotProvider = authSnapshotProvider,
       _negotiatedAuth = negotiatedAuth;

  static Future<HttpRemoteAttachmentStore?> connect({
    required Uri endpoint,
    required http.Client client,
    required HttpAttachmentAuthSnapshotProvider authSnapshotProvider,
    Duration requestTimeout = const Duration(seconds: 20),
  }) async {
    final normalizedEndpoint = _normalizeEndpoint(endpoint);
    try {
      final auth = await Future<HttpAttachmentAuthSnapshot>.value(
        authSnapshotProvider(),
      );
      await _assertAuthCurrent(authSnapshotProvider, auth);
      final request = http.Request(
        'GET',
        normalizedEndpoint.resolve('capabilities'),
      )..followRedirects = false;
      request.headers.addAll(auth.headers);
      request.headers['accept'] = 'application/json';
      final response = await client.send(request).timeout(requestTimeout);
      try {
        await _assertAuthCurrent(authSnapshotProvider, auth);
      } on Object {
        await _disposeResponseSafely(response.stream, requestTimeout);
        rethrow;
      }
      if (_isRedirectStatus(response.statusCode) ||
          response.statusCode != 200) {
        await _disposeResponseSafely(response.stream, requestTimeout);
        return null;
      }
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > _maxControlResponseBytes) {
        await _disposeResponseSafely(response.stream, requestTimeout);
        return null;
      }
      final body = utf8.decode(
        await _readBounded(
          response.stream.timeout(requestTimeout),
          maxBytes: _maxControlResponseBytes,
        ),
      );
      await _assertAuthCurrent(authSnapshotProvider, auth);
      final decoded = jsonDecode(body);
      if (decoded is! Map<Object?, Object?>) return null;
      final attachments = decoded['attachments'];
      if (attachments is! Map<Object?, Object?>) return null;
      final version = attachments['version'];
      final upload = attachments['upload'];
      final download = attachments['download'];
      final delete = attachments['delete'];
      final maxBytes = attachments['maxBytes'];
      if (version != remoteAttachmentSchemaVersion ||
          upload is! bool ||
          download is! bool ||
          delete is! bool ||
          maxBytes is! int ||
          maxBytes <= 0 ||
          maxBytes > maxRemoteAttachmentBytes ||
          (!upload && !download)) {
        return null;
      }
      return HttpRemoteAttachmentStore._(
        endpoint: normalizedEndpoint,
        client: client,
        authSnapshotProvider: authSnapshotProvider,
        negotiatedAuth: auth,
        maxBytes: maxBytes,
        supportsUpload: upload,
        supportsDownload: download,
        supportsDelete: delete,
        requestTimeout: requestTimeout,
      );
    } on Object {
      return null;
    }
  }

  final Uri _endpoint;
  final http.Client _client;
  final HttpAttachmentAuthSnapshotProvider _authSnapshotProvider;
  final HttpAttachmentAuthSnapshot _negotiatedAuth;
  final Duration requestTimeout;
  final int maxBytes;
  final bool supportsUpload;
  final bool supportsDownload;
  final bool supportsDelete;

  @override
  AttachmentSyncCapability get capability => AttachmentSyncCapability.supported;

  @override
  AttachmentSyncCapability get attachmentSyncCapability => capability;

  @override
  Future<RemoteAttachmentMetadata?> head(String attachmentId) async {
    _requireDownload();
    final response = await _send(
      'HEAD',
      attachmentId,
      acceptedStatuses: const {200, 404},
    );
    if (response.statusCode == 404) return null;
    return _metadataFromHeaders(response.headers, attachmentId);
  }

  @override
  Future<void> upload({
    required NodeAttachment metadata,
    required Stream<List<int>> bytes,
  }) async {
    if (!supportsUpload) {
      throw _failure(
        RemoteAttachmentFailureKind.unavailable,
        'Remote attachment upload is unavailable.',
      );
    }
    final auth = await _operationAuth();
    final remoteMetadata = RemoteAttachmentMetadata.fromNodeAttachment(
      metadata,
    );
    if (remoteMetadata.byteLength > maxBytes) {
      throw _failure(
        RemoteAttachmentFailureKind.sizeLimit,
        'Remote attachment exceeds server size limit.',
      );
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in bytes) {
      if (chunk.any((byte) => byte < 0 || byte > 255)) {
        throw _failure(
          RemoteAttachmentFailureKind.integrity,
          'Attachment stream contains invalid bytes.',
        );
      }
      length += chunk.length;
      if (length > remoteMetadata.byteLength || length > maxBytes) {
        throw _failure(
          RemoteAttachmentFailureKind.integrity,
          'Attachment stream length does not match metadata.',
        );
      }
      builder.add(chunk);
    }
    if (length != remoteMetadata.byteLength) {
      throw _failure(
        RemoteAttachmentFailureKind.integrity,
        'Attachment stream length does not match metadata.',
      );
    }
    final body = builder.takeBytes();
    if (await _checksum(body) != remoteMetadata.checksum) {
      throw _failure(
        RemoteAttachmentFailureKind.integrity,
        'Attachment stream checksum does not match metadata.',
      );
    }
    await _assertOperationAuth(auth);
    await _send(
      'PUT',
      remoteMetadata.attachmentId,
      acceptedStatuses: const {200, 201, 204},
      auth: auth,
      body: body,
      metadata: remoteMetadata,
    );
  }

  @override
  Future<RemoteAttachmentDownload> download(String attachmentId) async {
    _requireDownload();
    final validId = validateRemoteAttachmentId(attachmentId);
    final response = await _send('GET', validId, acceptedStatuses: const {200});
    final metadata = _metadataFromHeaders(response.headers, validId);
    return RemoteAttachmentDownload.verified(
      metadata: metadata,
      bytes: response.body,
    );
  }

  @override
  Future<void> delete({
    required String attachmentId,
    required String tombstoneVersion,
  }) async {
    if (!supportsDelete) {
      throw _failure(
        RemoteAttachmentFailureKind.unavailable,
        'Remote attachment delete is unavailable.',
      );
    }
    final validTombstone = validateRemoteAttachmentTombstoneVersion(
      tombstoneVersion,
    );
    await _send(
      'DELETE',
      attachmentId,
      acceptedStatuses: const {200, 204},
      extraHeaders: {'x-var-attachment-tombstone': validTombstone},
    );
  }

  void _requireDownload() {
    if (!supportsDownload) {
      throw _failure(
        RemoteAttachmentFailureKind.unavailable,
        'Remote attachment download is unavailable.',
      );
    }
  }

  Future<HttpAttachmentAuthSnapshot> _operationAuth() async {
    final auth = await Future<HttpAttachmentAuthSnapshot>.value(
      _authSnapshotProvider(),
    );
    if (!_negotiatedAuth.hasSameSession(auth)) {
      throw _unauthorizedSession();
    }
    return auth;
  }

  Future<void> _assertOperationAuth(HttpAttachmentAuthSnapshot auth) async {
    await _assertAuthCurrent(_authSnapshotProvider, auth);
    if (!_negotiatedAuth.hasSameSession(auth)) {
      throw _unauthorizedSession();
    }
  }

  Future<_HttpAttachmentResponse> _send(
    String method,
    String attachmentId, {
    required Set<int> acceptedStatuses,
    HttpAttachmentAuthSnapshot? auth,
    Uint8List? body,
    RemoteAttachmentMetadata? metadata,
    Map<String, String> extraHeaders = const {},
  }) async {
    final validId = validateRemoteAttachmentId(attachmentId);
    final operationAuth = auth ?? await _operationAuth();
    http.StreamedResponse? response;
    var streamHandled = false;
    try {
      await _assertOperationAuth(operationAuth);
      final request = http.StreamedRequest(
        method,
        _endpoint.resolve('attachments/$validId'),
      )..followRedirects = false;
      request.headers.addAll(operationAuth.headers);
      request.headers.addAll(extraHeaders);
      request.headers['accept'] = 'application/octet-stream, application/json';
      if (metadata != null) {
        request.headers.addAll(_metadataHeaders(metadata));
        request.headers['content-type'] = metadata.mimeType;
        request.contentLength = metadata.byteLength;
      }
      if (body != null) request.sink.add(body);
      final closeFuture = request.sink.close();
      final sendFuture = _client.send(request).timeout(requestTimeout);
      await closeFuture;
      response = await sendFuture;
      try {
        await _assertOperationAuth(operationAuth);
      } on Object {
        streamHandled = true;
        await _disposeResponseSafely(response.stream, requestTimeout);
        rethrow;
      }
      if (_isRedirectStatus(response.statusCode)) {
        streamHandled = true;
        await _disposeResponseSafely(response.stream, requestTimeout);
        _validateRedirect(response);
      }
      final statusCode = response.statusCode;
      final headers = response.headers;
      if (!acceptedStatuses.contains(statusCode)) {
        streamHandled = true;
        final exceeded = await _disposeResponse(
          response.stream,
          requestTimeout,
        );
        if (exceeded) {
          throw _failure(
            RemoteAttachmentFailureKind.sizeLimit,
            'Remote attachment response is too large.',
          );
        }
        _requireStatus(statusCode, acceptedStatuses);
      }
      final isSuccessfulGet = method == 'GET' && statusCode == 200;
      if (method == 'HEAD') {
        streamHandled = true;
        await _disposeResponseSafely(response.stream, requestTimeout);
        await _assertOperationAuth(operationAuth);
        return _HttpAttachmentResponse(
          statusCode: statusCode,
          headers: headers,
        );
      }
      final bodyLimit = isSuccessfulGet ? maxBytes : _maxControlResponseBytes;
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > bodyLimit) {
        streamHandled = true;
        await _disposeResponseSafely(response.stream, requestTimeout);
        throw _failure(
          RemoteAttachmentFailureKind.sizeLimit,
          'Remote attachment response is too large.',
        );
      }
      streamHandled = true;
      final responseBody = await _readBounded(
        response.stream.timeout(requestTimeout),
        maxBytes: bodyLimit,
      );
      await _assertOperationAuth(operationAuth);
      return _HttpAttachmentResponse(
        statusCode: statusCode,
        headers: headers,
        body: responseBody,
      );
    } on RemoteAttachmentException {
      if (response != null && !streamHandled) {
        await _disposeResponseSafely(response.stream, requestTimeout);
      }
      rethrow;
    } on Object catch (error) {
      if (response != null && !streamHandled) {
        await _disposeResponseSafely(response.stream, requestTimeout);
      }
      throw RemoteAttachmentException(
        RemoteAttachmentFailureKind.transport,
        'Remote attachment request failed.',
        cause: error,
      );
    }
  }

  Never _validateRedirect(http.StreamedResponse response) {
    final location = response.headers['location'];
    if (location != null) {
      final target = response.request?.url.resolve(location);
      if (target != null &&
          (target.scheme != _endpoint.scheme ||
              target.host != _endpoint.host)) {
        throw _failure(
          RemoteAttachmentFailureKind.transport,
          'Cross-origin attachment redirect was rejected.',
        );
      }
    }
    throw _failure(
      RemoteAttachmentFailureKind.transport,
      'Remote attachment redirects are disabled.',
    );
  }

  RemoteAttachmentMetadata _metadataFromHeaders(
    Map<String, String> headers,
    String expectedId,
  ) {
    try {
      final schema = int.tryParse(
        headers['x-var-attachment-schema-version'] ?? '',
      );
      if (schema != remoteAttachmentSchemaVersion) {
        throw const FormatException('Attachment schema is invalid.');
      }
      final metadata = RemoteAttachmentMetadata.validated(
        attachmentId: headers['x-var-attachment-id'],
        checksum: headers['x-var-attachment-sha256'],
        byteLength: int.tryParse(headers['x-var-attachment-byte-length'] ?? ''),
        mimeType: headers['content-type'],
        fileName: Uri.decodeComponent(
          headers['x-var-attachment-file-name'] ?? '',
        ),
      );
      if (metadata.attachmentId != expectedId ||
          metadata.byteLength > maxBytes) {
        throw const FormatException(
          'Attachment metadata does not match request.',
        );
      }
      final contentLength = int.tryParse(headers['content-length'] ?? '');
      if (contentLength != null && contentLength != metadata.byteLength) {
        throw const FormatException('Attachment content length is invalid.');
      }
      return metadata;
    } on FormatException catch (error) {
      throw RemoteAttachmentException(
        RemoteAttachmentFailureKind.invalidMetadata,
        'Remote attachment metadata is invalid.',
        cause: error,
      );
    }
  }

  void _requireStatus(int statusCode, Set<int> accepted) {
    if (accepted.contains(statusCode)) return;
    final kind = switch (statusCode) {
      401 || 403 => RemoteAttachmentFailureKind.unauthorized,
      404 => RemoteAttachmentFailureKind.notFound,
      409 => RemoteAttachmentFailureKind.conflict,
      413 => RemoteAttachmentFailureKind.sizeLimit,
      429 || >= 500 => RemoteAttachmentFailureKind.unavailable,
      _ => RemoteAttachmentFailureKind.transport,
    };
    throw _failure(kind, 'Remote attachment request was rejected.');
  }

  Map<String, String> _metadataHeaders(RemoteAttachmentMetadata metadata) => {
    'x-var-attachment-schema-version': '$remoteAttachmentSchemaVersion',
    'x-var-attachment-id': metadata.attachmentId,
    'x-var-attachment-sha256': metadata.checksum,
    'x-var-attachment-byte-length': '${metadata.byteLength}',
    'x-var-attachment-file-name': Uri.encodeComponent(metadata.fileName),
  };
}

final class _HttpAttachmentResponse {
  const _HttpAttachmentResponse({
    required this.statusCode,
    required this.headers,
    this.body = const [],
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
}

RemoteAttachmentException _failure(
  RemoteAttachmentFailureKind kind,
  String message,
) => RemoteAttachmentException(kind, message);

RemoteAttachmentException _unauthorizedSession() => _failure(
  RemoteAttachmentFailureKind.unauthorized,
  'Remote attachment authentication session changed.',
);

Future<void> _assertAuthCurrent(
  HttpAttachmentAuthSnapshotProvider provider,
  HttpAttachmentAuthSnapshot expected,
) async {
  final current = await Future<HttpAttachmentAuthSnapshot>.value(provider());
  if (!expected.hasSameSession(current)) throw _unauthorizedSession();
}

Uri _normalizeEndpoint(Uri endpoint) {
  if (endpoint.scheme != 'https' &&
      !(endpoint.scheme == 'http' &&
          (endpoint.host == 'localhost' || endpoint.host == '127.0.0.1'))) {
    throw ArgumentError.value(endpoint, 'endpoint', 'HTTPS endpoint required.');
  }
  if (endpoint.host.isEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment ||
      endpoint.userInfo.isNotEmpty) {
    throw ArgumentError.value(endpoint, 'endpoint', 'Unsafe endpoint.');
  }
  final value = endpoint.toString();
  return Uri.parse(value.endsWith('/') ? value : '$value/');
}

Map<String, String> _safeAuthHeaders(Map<String, String> headers) {
  String? authorization;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'authorization') {
      authorization = entry.value.trim();
      break;
    }
  }
  if (authorization == null || authorization.isEmpty) return const {};
  if (_controlCharacterPattern.hasMatch(authorization)) {
    throw const FormatException('HTTP authorization header is invalid.');
  }
  return {'authorization': authorization};
}

String _safeIdentity(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty || _controlCharacterPattern.hasMatch(normalized)) {
    throw ArgumentError.value(value, name, 'Safe non-empty value required.');
  }
  return normalized;
}

Future<List<int>> _readBounded(
  Stream<List<int>> stream, {
  required int maxBytes,
}) async {
  final builder = BytesBuilder(copy: false);
  var length = 0;
  await for (final chunk in stream) {
    length += chunk.length;
    if (length > maxBytes) {
      throw _failure(
        RemoteAttachmentFailureKind.sizeLimit,
        'Remote attachment response is too large.',
      );
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<bool> _disposeResponse(
  Stream<List<int>> stream,
  Duration timeout,
) async {
  final iterator = StreamIterator<List<int>>(stream.timeout(timeout));
  var length = 0;
  try {
    while (await iterator.moveNext()) {
      length += iterator.current.length;
      if (length > _maxControlResponseBytes) return true;
    }
    return false;
  } finally {
    await iterator.cancel();
  }
}

Future<void> _disposeResponseSafely(
  Stream<List<int>> stream,
  Duration timeout,
) async {
  try {
    await _disposeResponse(stream, timeout);
  } on Object {
    return;
  }
}

Future<String> _checksum(List<int> bytes) async {
  final digest = await Sha256().hash(bytes);
  return digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

final RegExp _controlCharacterPattern = RegExp(r'[\x00-\x1f\x7f]');

bool _isRedirectStatus(int statusCode) =>
    statusCode == 301 ||
    statusCode == 302 ||
    statusCode == 303 ||
    statusCode == 307 ||
    statusCode == 308;

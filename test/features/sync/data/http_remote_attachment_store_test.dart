import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/sync/data/http_remote_attachment_store.dart';
import 'package:var_app/features/sync/domain/remote_attachment_store.dart';

const _id = '123e4567-e89b-42d3-a456-426614174000';
const _checksum =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';

void main() {
  test(
    'connect negotiates capability with auth and normalized endpoint',
    () async {
      final client = _QueueClient([
        _jsonResponse({
          'attachments': {
            'version': 1,
            'upload': true,
            'download': true,
            'delete': false,
            'maxBytes': 1024,
          },
        }),
      ]);

      final store = await HttpRemoteAttachmentStore.connect(
        endpoint: Uri.parse('https://api.var.app/sync'),
        client: client,
        authSnapshotProvider: () => _auth(),
      );

      expect(store, isNotNull);
      expect(
        client.requests.single.url.toString(),
        'https://api.var.app/sync/capabilities',
      );
      expect(client.requests.single.headers['authorization'], 'Bearer token');
      expect(client.requests.single.followRedirects, isFalse);
      expect(store!.maxBytes, 1024);
    },
  );

  test('capability ignores unsafe caller-controlled request headers', () async {
    final client = _QueueClient([_capability()]);

    final store = await HttpRemoteAttachmentStore.connect(
      endpoint: Uri.parse('https://api.var.app/sync'),
      client: client,
      authSnapshotProvider: () => _auth(
        headers: {
          'authorization': 'Bearer token',
          'host': 'evil.test',
          'content-length': '999',
          'x-var-attachment-id': 'spoofed',
        },
      ),
    );

    expect(store, isNotNull);
    expect(client.requests.single.headers['authorization'], 'Bearer token');
    expect(client.requests.single.headers['host'], isNull);
    expect(client.requests.single.headers['content-length'], isNull);
    expect(client.requests.single.headers['x-var-attachment-id'], isNull);
  });

  test(
    'missing malformed unsupported or oversized capability falls back',
    () async {
      for (final response in [
        _jsonResponse(<String, Object?>{}),
        _response(200, utf8.encode('{')),
        _jsonResponse({
          'attachments': {
            'version': 2,
            'upload': true,
            'download': true,
            'delete': false,
            'maxBytes': 1024,
          },
        }),
        _jsonResponse({
          'attachments': {
            'version': 1,
            'upload': true,
            'download': true,
            'delete': false,
            'maxBytes': maxNodeAttachmentBytes + 1,
          },
        }),
      ]) {
        final store = await HttpRemoteAttachmentStore.connect(
          endpoint: Uri.parse('https://api.var.app/'),
          client: _QueueClient([response]),
          authSnapshotProvider: () => _auth(headers: const {}),
        );
        expect(store, isNull);
      }
    },
  );

  test(
    'upload sends exact route metadata headers and verified bytes',
    () async {
      final client = _QueueClient([_capability(), _response(204, const [])]);
      final store = await _connect(client);

      await store.upload(
        metadata: _attachment(),
        bytes: Stream.value([1, 2, 3]),
      );

      final request = client.requests.last;
      expect(request.method, 'PUT');
      expect(request.url.path, '/sync/attachments/$_id');
      expect(request.headers['content-type'], 'image/png');
      expect(request.contentLength, 3);
      expect(request.headers['x-var-attachment-schema-version'], '1');
      expect(request.headers['x-var-attachment-sha256'], _checksum);
      expect(request.headers['x-var-attachment-file-name'], 'photo.png');
      expect(request.body, [1, 2, 3]);
      expect(request.requestType, http.StreamedRequest);
    },
  );

  test('upload rejects corrupt stream before network write', () async {
    final client = _QueueClient([_capability()]);
    final store = await _connect(client);

    await expectLater(
      store.upload(metadata: _attachment(), bytes: Stream.value([1, 2, 4])),
      throwsA(_failure(RemoteAttachmentFailureKind.integrity)),
    );
    expect(client.requests, hasLength(1));
  });

  test('head and download parse safe metadata and verify checksum', () async {
    final headers = _metadataHeaders();
    final client = _QueueClient([
      _capability(),
      _response(200, const [], headers: headers),
      _response(200, const [1, 2, 3], headers: headers),
    ]);
    final store = await _connect(client);

    expect((await store.head(_id))?.fileName, 'photo.png');
    expect((await store.download(_id)).bytes, [1, 2, 3]);
    expect(client.requests[1].method, 'HEAD');
    expect(client.requests[1].url.path, '/sync/attachments/$_id');
    expect(client.requests[2].method, 'GET');
    expect(client.requests[2].url.path, '/sync/attachments/$_id');
  });

  test('HEAD cancels a malicious response body without allocation', () async {
    final body = _CancelableBody();
    final client = _QueueClient([
      _capability(),
      http.StreamedResponse(body.stream, 200, headers: _metadataHeaders()),
    ]);

    expect((await (await _connect(client)).head(_id))?.attachmentId, _id);
    expect(body.canceled, isTrue);
  });

  test('head rejects mismatched server metadata', () async {
    final client = _QueueClient([
      _capability(),
      _response(
        200,
        const [],
        headers: {
          ..._metadataHeaders(),
          'x-var-attachment-id': '123e4567-e89b-42d3-a456-426614174001',
        },
      ),
    ]);

    await expectLater(
      (await _connect(client)).head(_id),
      throwsA(_failure(RemoteAttachmentFailureKind.invalidMetadata)),
    );
  });

  test('unsafe attachment id is rejected before transfer request', () async {
    final client = _QueueClient([_capability()]);
    final store = await _connect(client);

    expect(() => store.download('../secret'), throwsFormatException);
    expect(client.requests, hasLength(1));
  });

  test('download rejects corrupt bytes and oversized content length', () async {
    final corrupt = _QueueClient([
      _capability(),
      _response(200, const [1, 2, 4], headers: _metadataHeaders()),
    ]);
    await expectLater(
      (await _connect(corrupt)).download(_id),
      throwsA(_failure(RemoteAttachmentFailureKind.integrity)),
    );

    final oversized = _QueueClient([
      _capability(maxBytes: 3),
      _response(200, const [1, 2, 3, 4], headers: {'content-length': '4'}),
    ]);
    await expectLater(
      (await _connect(oversized)).download(_id),
      throwsA(_failure(RemoteAttachmentFailureKind.sizeLimit)),
    );
  });

  test('oversized error and upload responses are rejected', () async {
    final oversized = List<int>.filled(64 * 1024 + 1, 1);
    final errorClient = _QueueClient([
      _capability(),
      _response(500, oversized),
    ]);
    await expectLater(
      (await _connect(errorClient)).download(_id),
      throwsA(_failure(RemoteAttachmentFailureKind.sizeLimit)),
    );

    final uploadClient = _QueueClient([
      _capability(),
      _response(204, oversized),
    ]);
    await expectLater(
      (await _connect(
        uploadClient,
      )).upload(metadata: _attachment(), bytes: Stream.value([1, 2, 3])),
      throwsA(_failure(RemoteAttachmentFailureKind.sizeLimit)),
    );
  });

  test(
    'upload aborts before PUT when auth changes while reading bytes',
    () async {
      final auth = _MutableAuth();
      final client = _QueueClient([_capability()]);
      final store = (await HttpRemoteAttachmentStore.connect(
        endpoint: Uri.parse('https://api.var.app/sync/'),
        client: client,
        authSnapshotProvider: auth.call,
      ))!;

      Stream<List<int>> changingBytes() async* {
        yield [1];
        auth.change(accountId: 'account-b', revision: 'session-b');
        yield [2, 3];
      }

      await expectLater(
        store.upload(metadata: _attachment(), bytes: changingBytes()),
        throwsA(_failure(RemoteAttachmentFailureKind.unauthorized)),
      );
      expect(client.requests, hasLength(1));
    },
  );

  test('head and download reject auth changes during request', () async {
    for (final operation in ['head', 'download']) {
      final auth = _MutableAuth();
      final body = _CancelableBody();
      final client = _QueueClient(
        [
          _capability(),
          http.StreamedResponse(body.stream, 200, headers: _metadataHeaders()),
        ],
        onSend: (index, request) {
          if (index == 1) {
            auth.change(accountId: 'account-b', revision: 'session-b');
          }
        },
      );
      final store = (await HttpRemoteAttachmentStore.connect(
        endpoint: Uri.parse('https://api.var.app/sync/'),
        client: client,
        authSnapshotProvider: auth.call,
      ))!;

      await expectLater(
        operation == 'head' ? store.head(_id) : store.download(_id),
        throwsA(_failure(RemoteAttachmentFailureKind.unauthorized)),
      );
      expect(client.requests.last.headers['authorization'], 'Bearer token-a');
      expect(body.canceled, isTrue);
    }
  });

  test('capability negotiation rejects auth change during response', () async {
    final auth = _MutableAuth();
    final body = _CancelableBody();
    final client = _QueueClient(
      [http.StreamedResponse(body.stream, 200)],
      onSend: (index, request) {
        auth.change(accountId: 'account-b', revision: 'session-b');
      },
    );

    expect(
      await HttpRemoteAttachmentStore.connect(
        endpoint: Uri.parse('https://api.var.app/sync/'),
        client: client,
        authSnapshotProvider: auth.call,
      ),
      isNull,
    );
    expect(body.canceled, isTrue);
  });

  test('redirects are disabled and cross host is rejected', () async {
    final body = _CancelableBody();
    final client = _QueueClient([
      _capability(),
      http.StreamedResponse(
        body.stream,
        302,
        headers: {'location': 'http://evil.test/file'},
      ),
    ]);
    final store = await _connect(client);

    await expectLater(
      store.download(_id),
      throwsA(_failure(RemoteAttachmentFailureKind.transport)),
    );
    expect(client.requests.last.followRedirects, isFalse);
    expect(body.canceled, isTrue);
  });

  test('maps stable HTTP failures', () async {
    for (final entry in const {
      401: RemoteAttachmentFailureKind.unauthorized,
      403: RemoteAttachmentFailureKind.unauthorized,
      404: RemoteAttachmentFailureKind.notFound,
      409: RemoteAttachmentFailureKind.conflict,
      413: RemoteAttachmentFailureKind.sizeLimit,
      429: RemoteAttachmentFailureKind.unavailable,
      500: RemoteAttachmentFailureKind.unavailable,
    }.entries) {
      final client = _QueueClient([
        _capability(),
        _response(entry.key, const []),
      ]);
      final store = await _connect(client);
      await expectLater(store.download(_id), throwsA(_failure(entry.value)));
    }
  });

  test('delete requires advertised capability and tombstone header', () async {
    final disabled = await _connect(_QueueClient([_capability()]));
    await expectLater(
      disabled.delete(attachmentId: _id, tombstoneVersion: 'device-1.1'),
      throwsA(_failure(RemoteAttachmentFailureKind.unavailable)),
    );

    final client = _QueueClient([
      _capability(delete: true),
      _response(204, const []),
    ]);
    final store = await _connect(client);
    await store.delete(attachmentId: _id, tombstoneVersion: 'device-1.1');
    expect(client.requests.last.method, 'DELETE');
    expect(client.requests.last.url.path, '/sync/attachments/$_id');
    expect(
      client.requests.last.headers['x-var-attachment-tombstone'],
      'device-1.1',
    );
  });

  test('rejects non-HTTPS production endpoint', () async {
    expect(
      () => HttpRemoteAttachmentStore.connect(
        endpoint: Uri.parse('http://api.var.app'),
        client: _QueueClient(const []),
        authSnapshotProvider: () => _auth(headers: const {}),
      ),
      throwsArgumentError,
    );
  });

  test('rejects endpoint credentials query and fragment', () {
    for (final endpoint in [
      'https://user:pass@api.var.app/sync',
      'https://api.var.app/sync?token=secret',
      'https://api.var.app/sync#fragment',
    ]) {
      expect(
        () => HttpRemoteAttachmentStore.connect(
          endpoint: Uri.parse(endpoint),
          client: _QueueClient(const []),
          authSnapshotProvider: () => _auth(headers: const {}),
        ),
        throwsArgumentError,
      );
    }
  });
}

Future<HttpRemoteAttachmentStore> _connect(_QueueClient client) async =>
    (await HttpRemoteAttachmentStore.connect(
      endpoint: Uri.parse('https://api.var.app/sync/'),
      client: client,
      authSnapshotProvider: () => _auth(),
    ))!;

HttpAttachmentAuthSnapshot _auth({
  String accountId = 'account-a',
  String revision = 'session-a',
  Map<String, String> headers = const {'authorization': 'Bearer token'},
}) => HttpAttachmentAuthSnapshot(
  accountId: accountId,
  revision: revision,
  headers: headers,
);

NodeAttachment _attachment() => NodeAttachment(
  id: _id,
  fileName: 'photo.png',
  mimeType: 'image/png',
  byteLength: 3,
  checksum: _checksum,
  createdAt: DateTime(2026),
);

http.StreamedResponse _capability({int maxBytes = 1024, bool delete = false}) =>
    _jsonResponse({
      'attachments': {
        'version': 1,
        'upload': true,
        'download': true,
        'delete': delete,
        'maxBytes': maxBytes,
      },
    });

Map<String, String> _metadataHeaders() => {
  'x-var-attachment-schema-version': '1',
  'x-var-attachment-id': _id,
  'x-var-attachment-sha256': _checksum,
  'x-var-attachment-byte-length': '3',
  'x-var-attachment-file-name': 'photo.png',
  'content-type': 'image/png',
  'content-length': '3',
};

http.StreamedResponse _jsonResponse(Map<String, Object?> value) => _response(
  200,
  utf8.encode(jsonEncode(value)),
  headers: {'content-type': 'application/json'},
);

http.StreamedResponse _response(
  int status,
  List<int> body, {
  Map<String, String> headers = const {},
}) => http.StreamedResponse(Stream.value(body), status, headers: headers);

Matcher _failure(RemoteAttachmentFailureKind kind) =>
    isA<RemoteAttachmentException>().having(
      (error) => error.kind,
      'kind',
      kind,
    );

final class _QueueClient extends http.BaseClient {
  _QueueClient(this.responses, {this.onSend});

  final List<http.StreamedResponse> responses;
  final void Function(int index, http.BaseRequest request)? onSend;
  final List<_RecordedRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    requests.add(
      _RecordedRequest(
        method: request.method,
        url: request.url,
        followRedirects: request.followRedirects,
        headers: Map<String, String>.of(request.headers),
        body: body,
        contentLength: request.contentLength,
        requestType: request.runtimeType,
      ),
    );
    onSend?.call(requests.length - 1, request);
    final response = responses.removeAt(0);
    return http.StreamedResponse(
      response.stream,
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

final class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.url,
    required this.followRedirects,
    required this.headers,
    required this.body,
    required this.contentLength,
    required this.requestType,
  });

  final String method;
  final Uri url;
  final bool followRedirects;
  final Map<String, String> headers;
  final List<int> body;
  final int? contentLength;
  final Type requestType;
}

final class _MutableAuth {
  HttpAttachmentAuthSnapshot snapshot = _auth(
    headers: const {'authorization': 'Bearer token-a'},
  );

  HttpAttachmentAuthSnapshot call() => snapshot;

  void change({required String accountId, required String revision}) {
    snapshot = _auth(
      accountId: accountId,
      revision: revision,
      headers: const {'authorization': 'Bearer token-b'},
    );
  }
}

final class _CancelableBody {
  _CancelableBody() {
    _controller = StreamController<List<int>>(
      onListen: () {
        _controller.add(List<int>.filled(64 * 1024 + 1, 1));
      },
      onCancel: () {
        canceled = true;
      },
    );
  }

  late final StreamController<List<int>> _controller;
  bool canceled = false;

  Stream<List<int>> get stream => _controller.stream;
}

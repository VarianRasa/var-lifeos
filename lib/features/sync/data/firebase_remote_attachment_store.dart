/// Firebase Storage adapter for authenticated remote attachments.
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../mindmap/domain/node_attachment.dart';
import '../domain/attachment_sync.dart';
import '../domain/remote_attachment_store.dart';

final class FirebaseStorageGatewayException implements Exception {
  const FirebaseStorageGatewayException(this.code, {this.cause});

  final String code;
  final Object? cause;
}

final class FirebaseStorageObjectMetadata {
  const FirebaseStorageObjectMetadata({
    required this.contentType,
    required this.customMetadata,
  });

  final String? contentType;
  final Map<String, String>? customMetadata;
}

final class FirebaseStorageObject extends FirebaseStorageObjectMetadata {
  const FirebaseStorageObject({
    required this.bytes,
    required super.contentType,
    required super.customMetadata,
  });

  final Uint8List bytes;
}

abstract interface class FirebaseStorageGateway {
  Future<void> put({
    required String key,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
  });

  Future<FirebaseStorageObjectMetadata?> head(String key);

  Future<FirebaseStorageObject?> get(String key, {required int maxBytes});
}

final class FirebaseStorageGatewayImpl implements FirebaseStorageGateway {
  FirebaseStorageGatewayImpl({FirebaseStorage? storage}) : _storage = storage;

  final FirebaseStorage? _storage;

  FirebaseStorage get _instance => _storage ?? FirebaseStorage.instance;

  @override
  Future<void> put({
    required String key,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
  }) async {
    try {
      await _instance
          .ref(key)
          .putData(
            bytes,
            SettableMetadata(
              contentType: contentType,
              customMetadata: customMetadata,
            ),
          );
    } on FirebaseException catch (error) {
      throw FirebaseStorageGatewayException(error.code, cause: error);
    }
  }

  @override
  Future<FirebaseStorageObjectMetadata?> head(String key) async {
    try {
      final metadata = await _instance.ref(key).getMetadata();
      return FirebaseStorageObjectMetadata(
        contentType: metadata.contentType,
        customMetadata: metadata.customMetadata,
      );
    } on FirebaseException catch (error) {
      if (_isMissing(error.code)) return null;
      throw FirebaseStorageGatewayException(error.code, cause: error);
    }
  }

  @override
  Future<FirebaseStorageObject?> get(
    String key, {
    required int maxBytes,
  }) async {
    try {
      final reference = _instance.ref(key);
      final metadata = await reference.getMetadata();
      final bytes = await reference.getData(maxBytes);
      if (bytes == null) return null;
      return FirebaseStorageObject(
        bytes: bytes,
        contentType: metadata.contentType,
        customMetadata: metadata.customMetadata,
      );
    } on FirebaseException catch (error) {
      if (_isMissing(error.code)) return null;
      throw FirebaseStorageGatewayException(error.code, cause: error);
    }
  }
}

final class FirebaseRemoteAttachmentStore
    implements RemoteAttachmentStore, AttachmentSyncAdapter {
  FirebaseRemoteAttachmentStore({
    required FirebaseStorageGateway gateway,
    required String? Function() userIdProvider,
  }) : _gateway = gateway,
       _userIdProvider = userIdProvider;

  final FirebaseStorageGateway _gateway;
  final String? Function() _userIdProvider;

  @override
  AttachmentSyncCapability get capability => AttachmentSyncCapability.supported;

  @override
  AttachmentSyncCapability get attachmentSyncCapability => capability;

  @override
  Future<void> upload({
    required NodeAttachment metadata,
    required Stream<List<int>> bytes,
  }) async {
    final userId = _snapshotUserId();
    final remoteMetadata = _metadataFromAttachment(metadata);
    final builder = BytesBuilder(copy: false);
    var byteLength = 0;
    await for (final chunk in bytes) {
      if (chunk.any((byte) => byte < 0 || byte > 255)) {
        throw _integrity('Attachment stream contains invalid bytes.');
      }
      byteLength += chunk.length;
      if (byteLength > remoteMetadata.byteLength ||
          byteLength > maxRemoteAttachmentBytes) {
        throw _integrity('Attachment stream length does not match metadata.');
      }
      builder.add(chunk);
    }
    if (byteLength != remoteMetadata.byteLength) {
      throw _integrity('Attachment stream length does not match metadata.');
    }
    final ownedBytes = builder.takeBytes();
    final checksum = await _checksum(ownedBytes);
    if (checksum != remoteMetadata.checksum) {
      throw _integrity('Attachment stream checksum does not match metadata.');
    }
    _assertCurrentUser(userId);
    await _guardGateway(
      () => _gateway.put(
        key: _key(userId, remoteMetadata.attachmentId),
        bytes: ownedBytes,
        contentType: remoteMetadata.mimeType,
        customMetadata: _firebaseMetadata(remoteMetadata),
      ),
    );
    _assertCurrentUser(userId);
  }

  @override
  Future<RemoteAttachmentMetadata?> head(String attachmentId) async {
    final userId = _snapshotUserId();
    final validId = _validId(attachmentId);
    final result = await _guardGateway(
      () => _gateway.head(_key(userId, validId)),
    );
    _assertCurrentUser(userId);
    if (result == null) return null;
    final metadata = _parseMetadata(result);
    if (metadata.attachmentId != validId) {
      throw const RemoteAttachmentException(
        RemoteAttachmentFailureKind.invalidMetadata,
        'Remote attachment metadata ID does not match object key.',
      );
    }
    return metadata;
  }

  @override
  Future<RemoteAttachmentDownload> download(String attachmentId) async {
    final userId = _snapshotUserId();
    final validId = _validId(attachmentId);
    final result = await _guardGateway(
      () => _gateway.get(
        _key(userId, validId),
        maxBytes: maxRemoteAttachmentBytes,
      ),
    );
    _assertCurrentUser(userId);
    if (result == null) {
      throw const RemoteAttachmentException(
        RemoteAttachmentFailureKind.notFound,
        'Remote attachment was not found.',
      );
    }
    final metadata = _parseMetadata(result);
    if (metadata.attachmentId != validId) {
      throw const RemoteAttachmentException(
        RemoteAttachmentFailureKind.invalidMetadata,
        'Remote attachment metadata ID does not match object key.',
      );
    }
    return RemoteAttachmentDownload.verified(
      metadata: metadata,
      bytes: result.bytes,
    );
  }

  @override
  Future<void> delete({
    required String attachmentId,
    required String tombstoneVersion,
  }) async {
    _validId(attachmentId);
    try {
      validateRemoteAttachmentTombstoneVersion(tombstoneVersion);
    } on FormatException catch (error) {
      throw RemoteAttachmentException(
        RemoteAttachmentFailureKind.invalidMetadata,
        error.message,
        cause: error,
      );
    }
    throw const RemoteAttachmentException(
      RemoteAttachmentFailureKind.unavailable,
      'Firebase attachment deletion is disabled until server-verified tombstones exist.',
    );
  }

  String _snapshotUserId() {
    final userId = _userIdProvider()?.trim();
    if (userId == null || userId.isEmpty) {
      throw const RemoteAttachmentException(
        RemoteAttachmentFailureKind.unauthorized,
        'Firebase attachment sync requires an authenticated user.',
      );
    }
    try {
      return validateFirebaseUserIdSegment(userId);
    } on FormatException catch (error) {
      throw RemoteAttachmentException(
        RemoteAttachmentFailureKind.unauthorized,
        'Firebase attachment user is invalid.',
        cause: error,
      );
    }
  }

  void _assertCurrentUser(String expectedUserId) {
    final currentUserId = _userIdProvider()?.trim();
    if (currentUserId != expectedUserId) {
      throw const RemoteAttachmentException(
        RemoteAttachmentFailureKind.unauthorized,
        'Firebase attachment account changed during transfer.',
      );
    }
  }

  String _key(String userId, String attachmentId) =>
      firebaseAttachmentObjectKey(userId: userId, attachmentId: attachmentId);
}

RemoteAttachmentMetadata _metadataFromAttachment(NodeAttachment attachment) {
  try {
    return RemoteAttachmentMetadata.fromNodeAttachment(attachment);
  } on FormatException catch (error) {
    throw RemoteAttachmentException(
      RemoteAttachmentFailureKind.invalidMetadata,
      error.message,
      cause: error,
    );
  }
}

String _validId(String attachmentId) {
  try {
    return validateRemoteAttachmentId(attachmentId);
  } on FormatException catch (error) {
    throw RemoteAttachmentException(
      RemoteAttachmentFailureKind.invalidMetadata,
      error.message,
      cause: error,
    );
  }
}

RemoteAttachmentMetadata _parseMetadata(FirebaseStorageObjectMetadata object) {
  final raw = object.customMetadata;
  try {
    if (raw == null ||
        raw['schemaVersion'] != '$remoteAttachmentSchemaVersion') {
      throw const FormatException('Remote attachment schema is invalid.');
    }
    final metadata = RemoteAttachmentMetadata.validated(
      attachmentId: raw['attachmentId'],
      checksum: raw['checksum'],
      byteLength: int.tryParse(raw['byteLength'] ?? ''),
      mimeType: raw['mimeType'],
      fileName: raw['fileName'],
    );
    if (object.contentType != metadata.mimeType) {
      throw const FormatException('Remote attachment content type is invalid.');
    }
    return metadata;
  } on FormatException catch (error) {
    throw RemoteAttachmentException(
      RemoteAttachmentFailureKind.invalidMetadata,
      error.message,
      cause: error,
    );
  }
}

Map<String, String> _firebaseMetadata(RemoteAttachmentMetadata metadata) => {
  'schemaVersion': '$remoteAttachmentSchemaVersion',
  'attachmentId': metadata.attachmentId,
  'checksum': metadata.checksum,
  'byteLength': '${metadata.byteLength}',
  'mimeType': metadata.mimeType,
  'fileName': metadata.fileName,
};

Future<T> _guardGateway<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on FirebaseStorageGatewayException catch (error) {
    throw RemoteAttachmentException(
      _failureKind(error.code),
      'Firebase attachment request failed.',
      cause: error.cause ?? error,
    );
  }
}

RemoteAttachmentFailureKind _failureKind(String code) => switch (code) {
  'unauthenticated' ||
  'unauthorized' => RemoteAttachmentFailureKind.unauthorized,
  'object-not-found' => RemoteAttachmentFailureKind.notFound,
  'retry-limit-exceeded' ||
  'quota-exceeded' ||
  'project-not-found' => RemoteAttachmentFailureKind.unavailable,
  'invalid-checksum' => RemoteAttachmentFailureKind.integrity,
  'invalid-argument' => RemoteAttachmentFailureKind.invalidMetadata,
  _ => RemoteAttachmentFailureKind.transport,
};

bool _isMissing(String code) => code == 'object-not-found';

RemoteAttachmentException _integrity(String message) =>
    RemoteAttachmentException(RemoteAttachmentFailureKind.integrity, message);

Future<String> _checksum(Uint8List bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

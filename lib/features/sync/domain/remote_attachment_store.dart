/// Remote attachment transfer boundary shared by Firebase and HTTP adapters.
library;

import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';

import '../../mindmap/domain/node_attachment.dart';

const int remoteAttachmentSchemaVersion = 1;
const int maxRemoteAttachmentBytes = maxNodeAttachmentBytes;

enum AttachmentSyncCapability { supported, unsupported, localOnly }

enum RemoteAttachmentFailureKind {
  unavailable,
  unauthorized,
  notFound,
  conflict,
  invalidMetadata,
  integrity,
  sizeLimit,
  transport,
}

final class RemoteAttachmentException implements Exception {
  const RemoteAttachmentException(this.kind, this.message, {this.cause});

  final RemoteAttachmentFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'RemoteAttachmentException(${kind.name}): $message';
}

final class RemoteAttachmentMetadata {
  const RemoteAttachmentMetadata._({
    required this.attachmentId,
    required this.checksum,
    required this.byteLength,
    required this.mimeType,
    required this.fileName,
  });

  factory RemoteAttachmentMetadata.validated({
    required Object? attachmentId,
    required Object? checksum,
    required Object? byteLength,
    required Object? mimeType,
    required Object? fileName,
  }) {
    final validAttachmentId = validateRemoteAttachmentId(attachmentId);
    final validChecksum = validateRemoteAttachmentChecksum(checksum);
    final validByteLength = validateRemoteAttachmentByteLength(byteLength);
    final validMimeType = validateRemoteAttachmentMimeType(mimeType);
    final validFileName = validateRemoteAttachmentFileName(fileName);
    return RemoteAttachmentMetadata._(
      attachmentId: validAttachmentId,
      checksum: validChecksum,
      byteLength: validByteLength,
      mimeType: validMimeType,
      fileName: validFileName,
    );
  }

  factory RemoteAttachmentMetadata.fromNodeAttachment(
    NodeAttachment attachment,
  ) => RemoteAttachmentMetadata.validated(
    attachmentId: attachment.id,
    checksum: attachment.checksum,
    byteLength: attachment.byteLength,
    mimeType: attachment.mimeType,
    fileName: attachment.fileName,
  );

  factory RemoteAttachmentMetadata.fromJson(Map<String, Object?> json) =>
      RemoteAttachmentMetadata.validated(
        attachmentId: json['attachmentId'],
        checksum: json['checksum'],
        byteLength: json['byteLength'],
        mimeType: json['mimeType'],
        fileName: json['fileName'],
      );

  final String attachmentId;
  final String checksum;
  final int byteLength;
  final String mimeType;
  final String fileName;

  Map<String, Object?> toJson() => {
    'schemaVersion': remoteAttachmentSchemaVersion,
    'attachmentId': attachmentId,
    'checksum': checksum,
    'byteLength': byteLength,
    'mimeType': mimeType,
    'fileName': fileName,
  };

  bool hasSameContent(RemoteAttachmentMetadata other) =>
      checksum == other.checksum &&
      byteLength == other.byteLength &&
      mimeType == other.mimeType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteAttachmentMetadata &&
          attachmentId == other.attachmentId &&
          checksum == other.checksum &&
          byteLength == other.byteLength &&
          mimeType == other.mimeType &&
          fileName == other.fileName;

  @override
  int get hashCode =>
      Object.hash(attachmentId, checksum, byteLength, mimeType, fileName);
}

final class RemoteAttachmentDownload {
  RemoteAttachmentDownload._({required this.metadata, required List<int> bytes})
    : bytes = UnmodifiableListView<int>(bytes);

  static Future<RemoteAttachmentDownload> verified({
    required RemoteAttachmentMetadata metadata,
    required List<int> bytes,
  }) async {
    final ownedBytes = _validatedBytes(metadata, bytes);
    final hash = await Sha256().hash(ownedBytes);
    final checksum = _hexEncode(hash.bytes);
    if (checksum != metadata.checksum) {
      throw const RemoteAttachmentException(
        RemoteAttachmentFailureKind.integrity,
        'Remote attachment checksum mismatch.',
      );
    }
    return RemoteAttachmentDownload._(metadata: metadata, bytes: ownedBytes);
  }

  final RemoteAttachmentMetadata metadata;
  final List<int> bytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteAttachmentDownload &&
          metadata == other.metadata &&
          const ListEquality<int>().equals(bytes, other.bytes);

  @override
  int get hashCode =>
      Object.hash(metadata, const ListEquality<int>().hash(bytes));
}

abstract interface class RemoteAttachmentStore {
  AttachmentSyncCapability get capability;

  Future<RemoteAttachmentMetadata?> head(String attachmentId);

  Future<void> upload({
    required NodeAttachment metadata,
    required Stream<List<int>> bytes,
  });

  Future<RemoteAttachmentDownload> download(String attachmentId);

  Future<void> delete({
    required String attachmentId,
    required String tombstoneVersion,
  });
}

String firebaseAttachmentObjectKey({
  required Object? userId,
  required Object? attachmentId,
}) {
  final validUserId = validateFirebaseUserIdSegment(userId);
  final validAttachmentId = validateRemoteAttachmentId(attachmentId);
  return 'attachments/$validUserId/$validAttachmentId';
}

String httpAttachmentRoute(Object? attachmentId) =>
    '/attachments/${validateRemoteAttachmentId(attachmentId)}';

String validateRemoteAttachmentId(Object? value) {
  if (value is! String || !_attachmentIdPattern.hasMatch(value)) {
    throw const FormatException('Remote attachment ID is invalid.');
  }
  return value;
}

String validateRemoteAttachmentChecksum(Object? value) {
  if (value is! String || !_checksumPattern.hasMatch(value)) {
    throw const FormatException('Remote attachment checksum is invalid.');
  }
  return value.toLowerCase();
}

int validateRemoteAttachmentByteLength(Object? value) {
  if (value is! int || value <= 0 || value > maxRemoteAttachmentBytes) {
    throw const FormatException('Remote attachment size is invalid.');
  }
  return value;
}

String validateRemoteAttachmentMimeType(Object? value) {
  if (value is! String) {
    throw const FormatException('Remote attachment MIME type is invalid.');
  }
  final normalized = value.trim().toLowerCase();
  if (!_mimeTypePattern.hasMatch(normalized) ||
      !supportedNodeAttachmentMimeTypes.contains(normalized)) {
    throw const FormatException('Remote attachment MIME type is invalid.');
  }
  return normalized;
}

String validateRemoteAttachmentFileName(Object? value) {
  if (value is! String) {
    throw const FormatException('Remote attachment filename is invalid.');
  }
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > 255 ||
      normalized == '.' ||
      normalized == '..' ||
      normalized.endsWith('.') ||
      normalized.contains('/') ||
      normalized.contains(r'\') ||
      normalized.codeUnits.contains(34) ||
      _unsafeFileNameCharacterPattern.hasMatch(normalized) ||
      _controlCharacterPattern.hasMatch(normalized)) {
    throw const FormatException('Remote attachment filename is invalid.');
  }
  final stem = normalized.split('.').first.toUpperCase();
  if (_reservedFileNames.contains(stem)) {
    throw const FormatException('Remote attachment filename is invalid.');
  }
  return normalized;
}

String validateFirebaseUserIdSegment(Object? value) {
  if (value is! String ||
      !_firebaseUserIdPattern.hasMatch(value) ||
      value == '.' ||
      value == '..') {
    throw const FormatException('Firebase attachment user ID is invalid.');
  }
  return value;
}

String validateRemoteAttachmentTombstoneVersion(Object? value) {
  if (value is! String || !_tombstoneVersionPattern.hasMatch(value)) {
    throw const FormatException('Attachment tombstone version is invalid.');
  }
  return value;
}

List<int> _validatedBytes(RemoteAttachmentMetadata metadata, List<int> bytes) {
  if (bytes.length != metadata.byteLength ||
      bytes.any((byte) => byte < 0 || byte > 255)) {
    throw const RemoteAttachmentException(
      RemoteAttachmentFailureKind.integrity,
      'Remote attachment byte content is invalid.',
    );
  }
  return List<int>.of(bytes, growable: false);
}

String _hexEncode(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

final RegExp _attachmentIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final RegExp _checksumPattern = RegExp(r'^[0-9a-fA-F]{64}$');
final RegExp _mimeTypePattern = RegExp(
  r'^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$',
);
final RegExp _firebaseUserIdPattern = RegExp(r'^[A-Za-z0-9._~-]{1,128}$');
final RegExp _tombstoneVersionPattern = RegExp(r'^[A-Za-z0-9._~-]{1,128}$');
final RegExp _controlCharacterPattern = RegExp(r'[\x00-\x1f\x7f]');
final RegExp _unsafeFileNameCharacterPattern = RegExp(r'[<>:|?*]');
const Set<String> _reservedFileNames = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};

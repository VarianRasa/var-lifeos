/// Attachment metadata and persistence boundary for mindmap media.
library;

const int nodeAttachmentManifestVersion = 1;
const int maxNodeAttachmentBytes = 100 * 1024 * 1024;

const Set<String> supportedNodeAttachmentMimeTypes = {
  'application/octet-stream',
  'application/pdf',
  'image/gif',
  'image/jpeg',
  'image/png',
  'image/webp',
  'video/mp4',
  'video/quicktime',
  'video/webm',
  'audio/aac',
  'audio/m4a',
  'audio/mpeg',
  'audio/mp4',
  'audio/ogg',
  'audio/wav',
  'audio/webm',
};

final class NodeAttachment {
  const NodeAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.byteLength,
    required this.checksum,
    required this.createdAt,
  });
  final String id;
  final String fileName;
  final String mimeType;
  final int byteLength;
  final String checksum;
  final DateTime createdAt;
}

final class NodeAttachmentManifestEntry {
  const NodeAttachmentManifestEntry({
    required this.version,
    required this.attachment,
  });
  final int version;
  final NodeAttachment attachment;
}

final class NodeAttachmentRestoreItem {
  const NodeAttachmentRestoreItem({
    required this.attachment,
    required this.bytes,
  });

  final NodeAttachment attachment;
  final List<int> bytes;
}

final class NodeAttachmentRestorePlan {
  const NodeAttachmentRestorePlan({
    required this.itemsToImport,
    required this.identicalAttachmentIds,
  });

  final List<NodeAttachmentRestoreItem> itemsToImport;
  final Set<String> identicalAttachmentIds;
}

abstract interface class NodeAttachmentRepository {
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  });
  Future<NodeAttachment?> resolve(String attachmentId);
  Future<List<int>?> readBytes(String attachmentId);
  Future<List<int>?> exportBytes(String attachmentId);
  Future<void> delete(String attachmentId);
  Future<List<NodeAttachmentManifestEntry>> buildManifest();
}

abstract interface class NodeAttachmentRestoreRepository {
  Future<NodeAttachmentRestorePlan> preflightRestore(
    List<NodeAttachmentRestoreItem> items,
  );

  Future<NodeAttachment> restoreBytes({
    required NodeAttachment attachment,
    required List<int> bytes,
  });
}

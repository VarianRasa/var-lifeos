/// Attachment metadata planning seam for sync transports.
library;

import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_attachment.dart';
import 'remote_attachment_store.dart';

export 'remote_attachment_store.dart' show AttachmentSyncCapability;

// ponytail: Add delete only after remote tombstones and ownership are modeled.
enum AttachmentSyncDirection { upload, download }

enum AttachmentSyncConflictKind {
  checksumMismatch,
  metadataMismatch,
  duplicateMetadata,
}

final class AttachmentSyncMetadata {
  const AttachmentSyncMetadata({
    required this.attachmentId,
    required this.checksum,
    required this.byteLength,
    required this.mimeType,
    required this.remoteObjectKey,
  });

  final String attachmentId;
  final String checksum;
  final int byteLength;
  final String mimeType;
  final String remoteObjectKey;

  factory AttachmentSyncMetadata.fromJson(Map<String, Object?> json) {
    return AttachmentSyncMetadata.validated(
      attachmentId: json['attachmentId'],
      checksum: json['checksum'],
      byteLength: json['byteLength'],
      mimeType: json['mimeType'],
      remoteObjectKey: json['remoteObjectKey'],
    );
  }

  factory AttachmentSyncMetadata.validated({
    required Object? attachmentId,
    required Object? checksum,
    required Object? byteLength,
    required Object? mimeType,
    required Object? remoteObjectKey,
  }) {
    final validAttachmentId = validateRemoteAttachmentId(attachmentId);
    final validChecksum = validateRemoteAttachmentChecksum(checksum);
    final validByteLength = validateRemoteAttachmentByteLength(byteLength);
    final validMimeType = validateRemoteAttachmentMimeType(mimeType);
    final canonicalKey = 'attachments/$validAttachmentId';
    if (remoteObjectKey is! String || remoteObjectKey != canonicalKey) {
      throw const FormatException('Attachment sync object key is invalid.');
    }
    return AttachmentSyncMetadata(
      attachmentId: validAttachmentId,
      checksum: validChecksum,
      byteLength: validByteLength,
      mimeType: validMimeType,
      remoteObjectKey: canonicalKey,
    );
  }

  factory AttachmentSyncMetadata.fromLocal(NodeAttachment attachment) {
    return AttachmentSyncMetadata.validated(
      attachmentId: attachment.id,
      checksum: attachment.checksum,
      byteLength: attachment.byteLength,
      mimeType: attachment.mimeType,
      remoteObjectKey: 'attachments/${attachment.id}',
    );
  }

  Map<String, Object?> toJson() => {
    'attachmentId': attachmentId,
    'checksum': checksum,
    'byteLength': byteLength,
    'mimeType': mimeType,
    'remoteObjectKey': remoteObjectKey,
  };

  bool hasSameContent(AttachmentSyncMetadata other) {
    return attachmentId == other.attachmentId &&
        checksum == other.checksum &&
        byteLength == other.byteLength &&
        mimeType == other.mimeType &&
        remoteObjectKey == other.remoteObjectKey;
  }
}

final class AttachmentSyncWorkItem {
  const AttachmentSyncWorkItem({
    required this.direction,
    required this.metadata,
  });

  final AttachmentSyncDirection direction;
  final AttachmentSyncMetadata metadata;

  Map<String, Object?> toJson() => {
    'direction': direction.name,
    'metadata': metadata.toJson(),
  };
}

final class AttachmentSyncConflict {
  const AttachmentSyncConflict({
    required this.attachmentId,
    required this.kind,
    required this.message,
  });

  final String attachmentId;
  final AttachmentSyncConflictKind kind;
  final String message;
}

final class AttachmentSyncPlan {
  const AttachmentSyncPlan({
    required this.workItems,
    required this.conflicts,
    required this.warnings,
  });

  final List<AttachmentSyncWorkItem> workItems;
  final List<AttachmentSyncConflict> conflicts;
  final List<String> warnings;
}

abstract interface class AttachmentSyncAdapter {
  AttachmentSyncCapability get attachmentSyncCapability;
}

final class UnsupportedAttachmentSyncAdapter implements AttachmentSyncAdapter {
  const UnsupportedAttachmentSyncAdapter(this.attachmentSyncCapability);

  @override
  final AttachmentSyncCapability attachmentSyncCapability;
}

final class AttachmentSyncPlanner {
  const AttachmentSyncPlanner();

  AttachmentSyncPlan plan({
    required Iterable<MindmapNode> nodes,
    required Iterable<NodeAttachmentManifestEntry> localManifest,
    Iterable<Map<String, Object?>> remoteManifest = const [],
  }) {
    final referencedIds = <String>{};
    for (final node in nodes) {
      _collectAttachmentIds(node.data, referencedIds);
    }
    final warnings = <String>[];
    final conflicts = <AttachmentSyncConflict>[];
    final blockedIds = <String>{};
    final localById = <String, AttachmentSyncMetadata>{};
    for (final entry in localManifest) {
      try {
        final metadata = AttachmentSyncMetadata.fromLocal(entry.attachment);
        _addMetadata(
          target: localById,
          metadata: metadata,
          source: 'local',
          conflicts: conflicts,
          blockedIds: blockedIds,
        );
      } on FormatException {
        warnings.add('Ignored malformed local attachment metadata.');
      }
    }
    final remoteById = <String, AttachmentSyncMetadata>{};
    for (final raw in remoteManifest) {
      try {
        final metadata = AttachmentSyncMetadata.fromJson(raw);
        _addMetadata(
          target: remoteById,
          metadata: metadata,
          source: 'remote',
          conflicts: conflicts,
          blockedIds: blockedIds,
        );
      } on FormatException {
        warnings.add('Ignored malformed remote attachment metadata.');
      }
    }

    final workItems = <AttachmentSyncWorkItem>[];
    final sortedIds = referencedIds.toList()..sort();
    for (final attachmentId in sortedIds) {
      if (blockedIds.contains(attachmentId)) continue;
      final local = localById[attachmentId];
      final remote = remoteById[attachmentId];
      if (local != null && remote != null && !local.hasSameContent(remote)) {
        final checksumMismatch = local.checksum != remote.checksum;
        final message = checksumMismatch
            ? 'Local and remote attachment checksums differ.'
            : 'Local and remote attachment size or MIME metadata differs.';
        conflicts.add(
          AttachmentSyncConflict(
            attachmentId: attachmentId,
            kind: checksumMismatch
                ? AttachmentSyncConflictKind.checksumMismatch
                : AttachmentSyncConflictKind.metadataMismatch,
            message: message,
          ),
        );
        warnings.add(message);
        continue;
      }
      if (local == null && remote != null) {
        workItems.add(
          AttachmentSyncWorkItem(
            direction: AttachmentSyncDirection.download,
            metadata: remote,
          ),
        );
      } else if (local != null && remote == null) {
        workItems.add(
          AttachmentSyncWorkItem(
            direction: AttachmentSyncDirection.upload,
            metadata: local,
          ),
        );
      }
    }
    workItems.sort((left, right) {
      final idOrder = left.metadata.attachmentId.compareTo(
        right.metadata.attachmentId,
      );
      return idOrder != 0
          ? idOrder
          : left.direction.index - right.direction.index;
    });
    conflicts.sort((left, right) {
      final idOrder = left.attachmentId.compareTo(right.attachmentId);
      return idOrder != 0 ? idOrder : left.kind.index - right.kind.index;
    });
    return AttachmentSyncPlan(
      workItems: List.unmodifiable(workItems),
      conflicts: List.unmodifiable(conflicts),
      warnings: List.unmodifiable(warnings),
    );
  }
}

void _addMetadata({
  required Map<String, AttachmentSyncMetadata> target,
  required AttachmentSyncMetadata metadata,
  required String source,
  required List<AttachmentSyncConflict> conflicts,
  required Set<String> blockedIds,
}) {
  final existing = target[metadata.attachmentId];
  if (existing == null) {
    target[metadata.attachmentId] = metadata;
    return;
  }
  if (existing.hasSameContent(metadata)) return;
  blockedIds.add(metadata.attachmentId);
  target.remove(metadata.attachmentId);
  conflicts.add(
    AttachmentSyncConflict(
      attachmentId: metadata.attachmentId,
      kind: AttachmentSyncConflictKind.duplicateMetadata,
      message: 'Conflicting duplicate $source attachment metadata.',
    ),
  );
}

void _collectAttachmentIds(Object? value, Set<String> result) {
  if (value is Map<Object?, Object?>) {
    for (final entry in value.entries) {
      if ((entry.key == 'attachmentId' ||
              entry.key == 'thumbnailAttachmentId') &&
          entry.value is String &&
          _attachmentIdPattern.hasMatch(entry.value! as String)) {
        result.add(entry.value! as String);
      } else {
        _collectAttachmentIds(entry.value, result);
      }
    }
  } else if (value is Iterable<Object?>) {
    for (final item in value) {
      _collectAttachmentIds(item, result);
    }
  }
}

final RegExp _attachmentIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

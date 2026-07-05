/// Versioned backup document for portable mindmap data.
library;

import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

final class SyncDeviceIdentity {
  const SyncDeviceIdentity({required this.id, required this.label});

  factory SyncDeviceIdentity.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String? ?? '';
    final label = json['label'] as String? ?? '';
    if (id.trim().isEmpty) {
      throw const FormatException('Backup device id is required.');
    }

    return SyncDeviceIdentity(id: id.trim(), label: label.trim());
  }

  final String id;
  final String label;

  Map<String, Object?> toJson() => {'id': id, 'label': label};

  @override
  bool operator ==(Object other) {
    return other is SyncDeviceIdentity &&
        other.id == id &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(id, label);
}

final class MindmapBackupDocument {
  MindmapBackupDocument._({
    required this.schemaVersion,
    required this.type,
    required this.exportedAt,
    required this.sourceDevice,
    required List<MindmapNode> nodes,
  }) : nodes = List.unmodifiable(_sortNodes(nodes));

  factory MindmapBackupDocument.create({
    required SyncDeviceIdentity sourceDevice,
    required DateTime exportedAt,
    required Iterable<MindmapNode> nodes,
  }) {
    return MindmapBackupDocument._(
      schemaVersion: currentSchemaVersion,
      type: documentType,
      exportedAt: exportedAt,
      sourceDevice: sourceDevice,
      nodes: nodes.toList(),
    );
  }

  factory MindmapBackupDocument.fromJson(Map<String, Object?> json) {
    final type = json['type'] as String? ?? '';
    if (type != documentType) {
      throw const FormatException('Unsupported backup document type.');
    }

    final schemaVersion = json['schemaVersion'] as int? ?? 0;
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported backup schema version.');
    }

    final exportedAtValue = json['exportedAt'];
    final exportedAt = exportedAtValue is String
        ? DateTime.tryParse(exportedAtValue)
        : null;
    if (exportedAt == null) {
      throw const FormatException('Backup exportedAt is invalid.');
    }

    final rawDevice = json['sourceDevice'];
    final sourceDevice = rawDevice is Map<Object?, Object?>
        ? SyncDeviceIdentity.fromJson(rawDevice.cast<String, Object?>())
        : throw const FormatException('Backup sourceDevice is invalid.');

    final rawNodes = json['nodes'];
    if (rawNodes is! List<Object?>) {
      throw const FormatException('Backup nodes must be a list.');
    }

    return MindmapBackupDocument._(
      schemaVersion: schemaVersion,
      type: type,
      exportedAt: exportedAt,
      sourceDevice: sourceDevice,
      nodes: [
        for (final rawNode in rawNodes)
          if (rawNode is Map<Object?, Object?>)
            MindmapNode.fromJson(rawNode.cast<String, Object?>()),
      ],
    );
  }

  static const int currentSchemaVersion = 1;
  static const String documentType = 'var.mindmap.backup';

  final int schemaVersion;
  final String type;
  final DateTime exportedAt;
  final SyncDeviceIdentity sourceDevice;
  final List<MindmapNode> nodes;

  Map<String, Object?> toJson() => {
    'type': type,
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt.toIso8601String(),
    'sourceDevice': sourceDevice.toJson(),
    'nodes': [for (final node in nodes) node.toJson()],
  };
}

List<MindmapNode> _sortNodes(List<MindmapNode> nodes) {
  return nodes..sort((a, b) {
    final day = a.day.dateOnly.compareTo(b.day.dateOnly);
    if (day != 0) return day;
    final created = a.createdAt.compareTo(b.createdAt);
    if (created != 0) return created;
    return a.title.compareTo(b.title);
  });
}

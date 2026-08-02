/// Local restore points for backup recovery.
library;

import '../../mindmap/domain/mindmap_node.dart';
import 'mindmap_backup_document.dart';

final class SyncRestorePointImpact {
  const SyncRestorePointImpact({
    required this.addedTitles,
    required this.updatedTitles,
    required this.deletedTitles,
    required this.unchangedCount,
  });

  factory SyncRestorePointImpact.compare({
    required Iterable<MindmapNode> currentNodes,
    required Iterable<MindmapNode> targetNodes,
  }) {
    final currentById = _nodesById(currentNodes);
    final targetById = _nodesById(targetNodes);
    final nodeIds = <String>{...currentById.keys, ...targetById.keys}.toList()
      ..sort();

    final addedTitles = <String>[];
    final updatedTitles = <String>[];
    final deletedTitles = <String>[];
    var unchangedCount = 0;

    for (final nodeId in nodeIds) {
      final current = currentById[nodeId];
      final target = targetById[nodeId];

      if (current == null && target != null) {
        addedTitles.add(_nodeLabel(target));
        continue;
      }

      if (current != null && target == null) {
        deletedTitles.add(_nodeLabel(current));
        continue;
      }

      if (current == null || target == null) continue;
      if (current == target) {
        unchangedCount += 1;
      } else {
        updatedTitles.add(_nodeLabel(target));
      }
    }

    return SyncRestorePointImpact(
      addedTitles: List.unmodifiable(addedTitles),
      updatedTitles: List.unmodifiable(updatedTitles),
      deletedTitles: List.unmodifiable(deletedTitles),
      unchangedCount: unchangedCount,
    );
  }

  final List<String> addedTitles;
  final List<String> updatedTitles;
  final List<String> deletedTitles;
  final int unchangedCount;

  int get addedCount => addedTitles.length;

  int get updatedCount => updatedTitles.length;

  int get deletedCount => deletedTitles.length;

  int get totalChanges => addedCount + updatedCount + deletedCount;

  bool get hasChanges => totalChanges > 0;

  bool get isDestructive => deletedCount > 0;

  String get riskLabel {
    if (!hasChanges) return 'No changes';
    if (isDestructive || totalChanges >= 3) return 'High impact';
    return 'Low impact';
  }

  List<String> get affectedTitles {
    return List.unmodifiable([
      ...addedTitles,
      ...updatedTitles,
      ...deletedTitles,
    ]);
  }

  String get summaryLabel {
    final parts = <String>[
      if (addedCount > 0) _impactPart(addedCount, 'add', 'adds'),
      if (updatedCount > 0) _impactPart(updatedCount, 'update', 'updates'),
      if (deletedCount > 0) _impactPart(deletedCount, 'delete', 'deletes'),
    ];
    return parts.isEmpty ? 'No local changes' : parts.join(' / ');
  }
}

final class SyncRestorePointTimeline {
  const SyncRestorePointTimeline._({
    required this.points,
    required this.sourceLabels,
    required this.selectedSource,
    required this.filteredPoints,
  });

  factory SyncRestorePointTimeline.create({
    required Iterable<SyncRestorePoint> points,
    String selectedSource = allSourcesLabel,
  }) {
    final orderedPoints = List<SyncRestorePoint>.unmodifiable(points);
    final sourceLabels = <String>[allSourcesLabel];
    final seenSources = <String>{allSourcesLabel};

    for (final point in orderedPoints) {
      final label = point.deviceLabel;
      if (seenSources.add(label)) {
        sourceLabels.add(label);
      }
    }

    final normalizedSource = sourceLabels.contains(selectedSource)
        ? selectedSource
        : allSourcesLabel;
    final filteredPoints = normalizedSource == allSourcesLabel
        ? orderedPoints
        : orderedPoints
              .where((point) => point.deviceLabel == normalizedSource)
              .toList();

    return SyncRestorePointTimeline._(
      points: orderedPoints,
      sourceLabels: List.unmodifiable(sourceLabels),
      selectedSource: normalizedSource,
      filteredPoints: List<SyncRestorePoint>.unmodifiable(filteredPoints),
    );
  }

  static const String allSourcesLabel = 'All';

  final List<SyncRestorePoint> points;
  final List<String> sourceLabels;
  final String selectedSource;
  final List<SyncRestorePoint> filteredPoints;

  int get hiddenCount => points.length - filteredPoints.length;
}

final class SyncRestorePoint {
  const SyncRestorePoint({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.document,
    this.accountEmail = '',
  });

  factory SyncRestorePoint.fromJson(Map<String, Object?> json) {
    final rawCreatedAt = json['createdAt'];
    final createdAt = rawCreatedAt is String
        ? DateTime.tryParse(rawCreatedAt)
        : null;
    final rawDocument = json['document'];

    return SyncRestorePoint(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      accountEmail: json['accountEmail'] as String? ?? '',
      document: rawDocument is Map<Object?, Object?>
          ? MindmapBackupDocument.fromJson(rawDocument.cast<String, Object?>())
          : throw const FormatException('Restore point document is invalid.'),
    );
  }

  final String id;
  final String label;
  final DateTime createdAt;
  final MindmapBackupDocument document;
  final String accountEmail;

  int get nodeCount => document.nodes.length;

  String get deviceLabel {
    final label = document.sourceDevice.label.trim();
    return label.isEmpty ? document.sourceDevice.id : label;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'createdAt': createdAt.toIso8601String(),
    'document': document.toJson(),
    'accountEmail': accountEmail,
  };
}

extension SyncRestorePointPreview on SyncRestorePoint {
  SyncRestorePointImpact previewAgainst(Iterable<MindmapNode> currentNodes) {
    return SyncRestorePointImpact.compare(
      currentNodes: currentNodes,
      targetNodes: document.nodes,
    );
  }
}

abstract interface class SyncRestorePointStore {
  Future<void> add(SyncRestorePoint point);

  Future<void> delete(String id);

  Future<SyncRestorePoint?> read(String id);

  Future<List<SyncRestorePoint>> recent({int limit = 5, String? accountEmail});

  Future<void> prune({required int keepLatest, String? accountEmail});

  Future<void> clear();
}

Map<String, MindmapNode> _nodesById(Iterable<MindmapNode> nodes) {
  return {for (final node in nodes) node.id: node};
}

String _nodeLabel(MindmapNode node) {
  final title = node.title.trim();
  return title.isEmpty ? node.id : title;
}

String _impactPart(int count, String singular, String plural) {
  return count == 1 ? '1 $singular' : '$count $plural';
}

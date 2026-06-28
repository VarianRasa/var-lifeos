import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';
import 'package:var_app/features/sync/domain/sync_restore_point.dart';

void main() {
  test('serializes restore points with their backup document', () {
    final document = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'laptop', label: 'Laptop'),
      exportedAt: DateTime(2026, 6, 20, 10),
      nodes: [
        MindmapNode.create(
          id: 'note-1',
          type: NodeType.note,
          title: 'Restore me',
          day: DateTime(2026, 6, 20),
          now: DateTime(2026, 6, 20, 9),
        ),
      ],
    );
    final point = SyncRestorePoint(
      id: 'restore-1',
      label: 'Portable export',
      createdAt: DateTime(2026, 6, 20, 11),
      document: document,
    );

    final restored = SyncRestorePoint.fromJson(point.toJson());

    expect(restored.id, 'restore-1');
    expect(restored.label, 'Portable export');
    expect(restored.createdAt, DateTime(2026, 6, 20, 11));
    expect(restored.nodeCount, 1);
    expect(restored.deviceLabel, 'Laptop');
    expect(restored.document.nodes.single.title, 'Restore me');
  });

  test('previews restore impact against current local nodes', () {
    final original = _node(id: 'shared-note', title: 'Original snapshot');
    final point = SyncRestorePoint(
      id: 'restore-1',
      label: 'Portable export',
      createdAt: DateTime(2026, 6, 20, 11),
      document: MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'laptop', label: 'Laptop'),
        exportedAt: DateTime(2026, 6, 20, 10),
        nodes: [
          original,
          _node(id: 'backup-only', title: 'Backup-only note'),
        ],
      ),
    );

    final preview = point.previewAgainst([
      original.copyWith(
        title: 'Local draft',
        updatedAt: DateTime(2026, 6, 20, 12),
      ),
      _node(id: 'local-only', title: 'Temporary local note'),
    ]);

    expect(preview.addedCount, 1);
    expect(preview.updatedCount, 1);
    expect(preview.deletedCount, 1);
    expect(preview.unchangedCount, 0);
    expect(preview.totalChanges, 3);
    expect(preview.summaryLabel, '1 add / 1 update / 1 delete');
    expect(preview.addedTitles, ['Backup-only note']);
    expect(preview.updatedTitles, ['Original snapshot']);
    expect(preview.deletedTitles, ['Temporary local note']);
  });

  test('scores restore impact severity from change volume and deletes', () {
    final original = _node(id: 'shared-note', title: 'Original snapshot');
    final noChanges = SyncRestorePointImpact.compare(
      currentNodes: [original],
      targetNodes: [original],
    );
    final lowImpact = SyncRestorePointImpact.compare(
      currentNodes: const [],
      targetNodes: [_node(id: 'new-note', title: 'New note')],
    );
    final highImpact = SyncRestorePointImpact.compare(
      currentNodes: [
        original.copyWith(
          title: 'Local draft',
          updatedAt: DateTime(2026, 6, 20, 12),
        ),
        _node(id: 'local-only', title: 'Temporary local note'),
      ],
      targetNodes: [original],
    );

    expect(noChanges.riskLabel, 'No changes');
    expect(lowImpact.riskLabel, 'Low impact');
    expect(highImpact.riskLabel, 'High impact');
    expect(highImpact.isDestructive, isTrue);
  });

  test('builds restore timeline filters from source devices', () {
    final phone = _point(
      id: 'phone-restore',
      label: 'Phone snapshot',
      sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
    );
    final laptop = _point(
      id: 'laptop-restore',
      label: 'Laptop snapshot',
      sourceDevice: const SyncDeviceIdentity(id: 'laptop', label: 'Laptop'),
    );
    final unlabeled = _point(
      id: 'tablet-restore',
      label: 'Tablet snapshot',
      sourceDevice: const SyncDeviceIdentity(id: 'tablet', label: ''),
    );

    final timeline = SyncRestorePointTimeline.create(
      points: [phone, laptop, unlabeled],
      selectedSource: 'Laptop',
    );
    final fallback = SyncRestorePointTimeline.create(
      points: [phone, laptop],
      selectedSource: 'Missing device',
    );

    expect(timeline.sourceLabels, ['All', 'Phone', 'Laptop', 'tablet']);
    expect(timeline.selectedSource, 'Laptop');
    expect(timeline.filteredPoints, [laptop]);
    expect(timeline.hiddenCount, 2);
    expect(fallback.selectedSource, 'All');
    expect(fallback.filteredPoints, [phone, laptop]);
  });
}

MindmapNode _node({required String id, required String title}) {
  return MindmapNode.create(
    id: id,
    type: NodeType.note,
    title: title,
    day: DateTime(2026, 6, 20),
    now: DateTime(2026, 6, 20, 9),
  );
}

SyncRestorePoint _point({
  required String id,
  required String label,
  required SyncDeviceIdentity sourceDevice,
}) {
  return SyncRestorePoint(
    id: id,
    label: label,
    createdAt: DateTime(2026, 6, 20, 11),
    document: MindmapBackupDocument.create(
      sourceDevice: sourceDevice,
      exportedAt: DateTime(2026, 6, 20, 10),
      nodes: [_node(id: '$id-node', title: label)],
    ),
  );
}

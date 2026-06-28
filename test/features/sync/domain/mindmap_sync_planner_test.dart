import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/domain/mindmap_sync_planner.dart';

void main() {
  test('saves remote changes and deletes locally unchanged remote deletes', () {
    final baseChanged = _node(
      id: 'shared',
      title: 'Shared',
      now: DateTime(2026, 6, 18, 9),
    );
    final baseDeleted = _node(
      id: 'deleted',
      title: 'Deleted remotely',
      now: DateTime(2026, 6, 18, 9),
    );
    final remoteChanged = baseChanged.copyWith(
      title: 'Shared from phone',
      updatedAt: DateTime(2026, 6, 18, 11),
    );

    final plan = const MindmapSyncPlanner().plan(
      localNodes: [baseChanged, baseDeleted],
      remoteNodes: [remoteChanged],
      baselineNodes: [baseChanged, baseDeleted],
    );

    expect(plan.hasBlockingConflicts, isFalse);
    expect(plan.nodesToSave.map((node) => node.id), ['shared']);
    expect(plan.nodesToSave.single.title, 'Shared from phone');
    expect(plan.nodeIdsToDelete, ['deleted']);
  });

  test(
    'detects a conflict when local and remote changed the same baseline',
    () {
      final baseline = _node(
        id: 'note-1',
        title: 'Original',
        now: DateTime(2026, 6, 18, 9),
      );
      final local = baseline.copyWith(
        title: 'Local edit',
        updatedAt: DateTime(2026, 6, 18, 10),
      );
      final remote = baseline.copyWith(
        title: 'Remote edit',
        updatedAt: DateTime(2026, 6, 18, 11),
      );

      final plan = const MindmapSyncPlanner().plan(
        localNodes: [local],
        remoteNodes: [remote],
        baselineNodes: [baseline],
      );

      expect(plan.nodesToSave, isEmpty);
      expect(plan.nodeIdsToDelete, isEmpty);
      expect(plan.hasBlockingConflicts, isTrue);
      expect(plan.conflicts.single.kind, SyncConflictKind.editEdit);
      expect(plan.conflicts.single.localNode, local);
      expect(plan.conflicts.single.remoteNode, remote);
      expect(plan.conflicts.single.baselineNode, baseline);
    },
  );

  test(
    'resolves edit conflicts by latest updated timestamp when requested',
    () {
      final baseline = _node(
        id: 'note-1',
        title: 'Original',
        now: DateTime(2026, 6, 18, 9),
      );
      final local = baseline.copyWith(
        title: 'Local edit',
        updatedAt: DateTime(2026, 6, 18, 10),
      );
      final remote = baseline.copyWith(
        title: 'Remote edit',
        updatedAt: DateTime(2026, 6, 18, 11),
      );

      final plan =
          const MindmapSyncPlanner(
            strategy: SyncConflictStrategy.latestUpdatedAt,
          ).plan(
            localNodes: [local],
            remoteNodes: [remote],
            baselineNodes: [baseline],
          );

      expect(plan.hasBlockingConflicts, isFalse);
      expect(
        plan.resolvedConflicts.single.resolution,
        SyncResolution.useRemote,
      );
      expect(plan.nodesToSave, [remote]);
    },
  );

  test('resolves selected conflicts with explicit per-node decisions', () {
    final remoteWinsBaseline = _node(
      id: 'remote-wins',
      title: 'Remote wins',
      now: DateTime(2026, 6, 18, 8),
    );
    final localWinsBaseline = _node(
      id: 'local-wins',
      title: 'Local wins',
      now: DateTime(2026, 6, 18, 8),
    );
    final remoteWinner = remoteWinsBaseline.copyWith(
      title: 'Remote selected',
      updatedAt: DateTime(2026, 6, 18, 11),
    );
    final localOlder = remoteWinsBaseline.copyWith(
      title: 'Local older',
      updatedAt: DateTime(2026, 6, 18, 10),
    );
    final localWinner = localWinsBaseline.copyWith(
      title: 'Local selected',
      updatedAt: DateTime(2026, 6, 18, 12),
    );
    final remoteOlder = localWinsBaseline.copyWith(
      title: 'Remote older',
      updatedAt: DateTime(2026, 6, 18, 9),
    );

    final plan =
        const MindmapSyncPlanner(
          conflictResolutions: {
            'remote-wins': SyncResolution.useRemote,
            'local-wins': SyncResolution.useLocal,
          },
        ).plan(
          localNodes: [localOlder, localWinner],
          remoteNodes: [remoteWinner, remoteOlder],
          baselineNodes: [remoteWinsBaseline, localWinsBaseline],
        );

    expect(plan.hasBlockingConflicts, isFalse);
    expect(plan.nodesToSave, [remoteWinner]);
    expect(plan.resolvedConflicts.map((conflict) => conflict.nodeId), [
      'local-wins',
      'remote-wins',
    ]);
    expect(plan.resolvedConflicts.map((conflict) => conflict.resolution), [
      SyncResolution.useLocal,
      SyncResolution.useRemote,
    ]);
  });

  test('leaves unselected conflicts blocking explicit partial decisions', () {
    final remoteWinsBaseline = _node(
      id: 'remote-wins',
      title: 'Remote wins',
      now: DateTime(2026, 6, 18, 8),
    );
    final localWinsBaseline = _node(
      id: 'local-wins',
      title: 'Local wins',
      now: DateTime(2026, 6, 18, 8),
    );
    final remoteWinner = remoteWinsBaseline.copyWith(
      title: 'Remote selected',
      updatedAt: DateTime(2026, 6, 18, 11),
    );
    final localOlder = remoteWinsBaseline.copyWith(
      title: 'Local older',
      updatedAt: DateTime(2026, 6, 18, 10),
    );
    final localWinner = localWinsBaseline.copyWith(
      title: 'Local selected',
      updatedAt: DateTime(2026, 6, 18, 12),
    );
    final remoteOlder = localWinsBaseline.copyWith(
      title: 'Remote older',
      updatedAt: DateTime(2026, 6, 18, 9),
    );

    final plan =
        const MindmapSyncPlanner(
          conflictResolutions: {'remote-wins': SyncResolution.useRemote},
        ).plan(
          localNodes: [localOlder, localWinner],
          remoteNodes: [remoteWinner, remoteOlder],
          baselineNodes: [remoteWinsBaseline, localWinsBaseline],
        );

    expect(plan.hasBlockingConflicts, isTrue);
    expect(plan.nodesToSave, [remoteWinner]);
    expect(plan.resolvedConflicts.single.nodeId, 'remote-wins');
    expect(plan.conflicts.single.nodeId, 'local-wins');
  });

  test('detects delete versus remote edit conflicts', () {
    final baseline = _node(
      id: 'note-1',
      title: 'Original',
      now: DateTime(2026, 6, 18, 9),
    );
    final remote = baseline.copyWith(
      title: 'Remote edit',
      updatedAt: DateTime(2026, 6, 18, 11),
    );

    final plan = const MindmapSyncPlanner().plan(
      localNodes: const [],
      remoteNodes: [remote],
      baselineNodes: [baseline],
    );

    expect(plan.hasBlockingConflicts, isTrue);
    expect(plan.conflicts.single.kind, SyncConflictKind.deleteEdit);
    expect(plan.conflicts.single.localNode, isNull);
    expect(plan.conflicts.single.remoteNode, remote);
  });
}

MindmapNode _node({
  required String id,
  required String title,
  required DateTime now,
}) {
  return MindmapNode.create(
    id: id,
    type: NodeType.note,
    title: title,
    day: DateTime(2026, 6, 18),
    now: now,
  );
}

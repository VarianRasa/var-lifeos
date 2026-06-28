import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/core/config/runtime_config.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/persistent_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/sembast_mindmap_node_database.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test(
    'nodesForDayProvider hides archived nodes from active day surfaces',
    () async {
      final today = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'active-task',
            type: NodeType.task,
            title: 'Active task',
            day: today,
            now: DateTime(2026, 6, 18, 8),
          ),
          MindmapNode.create(
            id: 'archived-note',
            type: NodeType.note,
            title: 'Archived note',
            day: today,
            isArchived: true,
            now: DateTime(2026, 6, 18, 9),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final activeDayNodes = await container.read(
        nodesForDayProvider(today).future,
      );
      final daySummary = await container.read(
        dayNodeSummaryProvider(today).future,
      );
      final allNodes = await container.read(allMindmapNodesProvider.future);

      expect(activeDayNodes.map((node) => node.id), ['active-task']);
      expect(daySummary.totalCount, 1);
      expect(allNodes.map((node) => node.id), ['active-task', 'archived-note']);
    },
  );

  test(
    'mindmapRepositoryProvider does not seed demo data by default',
    () async {
      final database = await databaseFactoryMemory.openDatabase('no-seed.db');
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [
          mindmapNodeDatabaseProvider.overrideWithValue(
            SembastMindmapNodeDatabase(database: database),
          ),
          mindmapNodeStoreProvider.overrideWithValue(_EmptyMindmapNodeStore()),
        ],
      );
      addTearDown(container.dispose);

      final nodes = await container.read(allMindmapNodesProvider.future);

      expect(nodes, isEmpty);
    },
  );

  test('mindmapRepositoryProvider seeds demo data when enabled', () async {
    final database = await databaseFactoryMemory.openDatabase('demo-seed.db');
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          const RuntimeConfig(demoSeedEnabled: true),
        ),
        mindmapNodeDatabaseProvider.overrideWithValue(
          SembastMindmapNodeDatabase(database: database),
        ),
        mindmapNodeStoreProvider.overrideWithValue(_EmptyMindmapNodeStore()),
      ],
    );
    addTearDown(container.dispose);

    final nodes = await container.read(allMindmapNodesProvider.future);

    expect(nodes.map((node) => node.id), contains('seed-task-plan-day'));
    expect(nodes.length, 5);
  });
}

final class _EmptyMindmapNodeStore implements MindmapNodeStore {
  @override
  Future<String?> readNodesJson() async => null;

  @override
  Future<void> writeNodesJson(String value) async {}
}

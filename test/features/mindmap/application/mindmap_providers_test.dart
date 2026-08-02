import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/core/config/runtime_config.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/canvas_board_repositories.dart';
import 'package:var_app/features/mindmap/data/canvas_board_template_repositories.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/persistent_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/sembast_mindmap_node_database.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_template.dart';
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

  test(
    'availableBoardTemplatesProvider uses overrides and refreshes live filtering',
    () async {
      final now = DateTime.utc(2026, 8, 2, 12);
      final boards = InMemoryCanvasBoardRepository();
      final templates = InMemoryCanvasBoardTemplateRepository();
      final source = CanvasBoard(
        id: 'source',
        kind: CanvasBoardKind.project,
        title: 'Source',
        workspaceName: 'Work',
        createdAt: now,
        updatedAt: now,
      );
      final template = CanvasBoardTemplate(
        id: 'template',
        name: 'Live source',
        sourceBoardId: source.id,
        createdAt: now,
        updatedAt: now,
      );
      await boards.saveBoard(source);
      await templates.saveTemplate(template);
      final container = ProviderContainer(
        overrides: [
          canvasBoardRepositoryProvider.overrideWithValue(boards),
          canvasBoardTemplateRepositoryProvider.overrideWithValue(templates),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(availableBoardTemplatesProvider('Work').future),
        <CanvasBoardTemplate>[template],
      );
      expect(
        await container.read(availableBoardTemplatesProvider('Other').future),
        isEmpty,
      );

      final subscription = container.listen(
        availableBoardTemplatesProvider('Work'),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await boards.saveBoard(source.copyWith(trashedAt: now));
      container.invalidate(workspaceBoardGraphProvider('Work'));

      expect(
        await container.read(availableBoardTemplatesProvider('Work').future),
        isEmpty,
      );

      await boards.saveBoard(source.copyWith(trashedAt: null));
      container.invalidate(workspaceBoardGraphProvider('Work'));
      expect(
        await container.read(availableBoardTemplatesProvider('Work').future),
        <CanvasBoardTemplate>[template],
      );

      await boards.deleteBoard(source.id);
      container.invalidate(workspaceBoardGraphProvider('Work'));
      expect(
        await container.read(availableBoardTemplatesProvider('Work').future),
        isEmpty,
      );
    },
  );
}

final class _EmptyMindmapNodeStore implements MindmapNodeStore {
  @override
  Future<String?> readNodesJson() async => null;

  @override
  Future<void> writeNodesJson(String value) async {}
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/workspace_context.dart';

void main() {
  test('workspaceContextsProvider groups nodes by project and area', () async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-launch',
          type: NodeType.task,
          title: 'Launch task',
          day: today,
          project: 'Launch App',
          area: 'Work',
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'note-launch',
          type: NodeType.note,
          title: 'Launch notes',
          day: today,
          project: 'Launch App',
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'habit-health',
          type: NodeType.habit,
          title: 'Workout',
          day: today,
          area: 'Health',
          now: DateTime(2026, 6, 18, 10),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final contexts = await container.read(workspaceContextsProvider.future);

    expect(
      contexts.contextFor(WorkspaceContextType.project, 'Launch App').nodeIds,
      ['task-launch', 'note-launch'],
    );
    expect(contexts.contextFor(WorkspaceContextType.area, 'Health').nodeIds, [
      'habit-health',
    ]);
  });
}

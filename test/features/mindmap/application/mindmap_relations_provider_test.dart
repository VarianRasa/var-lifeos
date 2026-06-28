import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('nodeRelationsProvider returns related nodes and backlinks', () async {
    final today = DateTime(2026, 6, 18);
    final tomorrow = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-1',
          type: NodeType.task,
          title: 'Launch task',
          day: today,
          relatedNodeIds: const ['note-1'],
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'note-1',
          type: NodeType.note,
          title: 'Release context',
          day: tomorrow,
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'goal-1',
          type: NodeType.goal,
          title: 'Ship v1',
          day: tomorrow,
          relatedNodeIds: const ['task-1'],
          now: DateTime(2026, 6, 18, 10),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final relations = await container.read(
      nodeRelationsProvider('task-1').future,
    );

    expect(relations.nodeId, 'task-1');
    expect(relations.relatedNodes.map((node) => node.id), ['note-1']);
    expect(relations.backlinks.map((node) => node.id), ['goal-1']);
  });

  test('nodeGraphProvider returns global relation graph', () async {
    final today = DateTime(2026, 6, 18);
    final tomorrow = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-1',
          type: NodeType.task,
          title: 'Launch task',
          day: today,
          relatedNodeIds: const ['note-1'],
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'note-1',
          type: NodeType.note,
          title: 'Release context',
          day: tomorrow,
          now: DateTime(2026, 6, 18, 9),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final graph = await container.read(nodeGraphProvider.future);

    expect(graph.nodes.map((node) => node.id), ['task-1', 'note-1']);
    expect(graph.edges.single.sourceId, 'task-1');
    expect(graph.edges.single.targetId, 'note-1');
    expect(graph.edges.single.isCrossDay, isTrue);
  });
}

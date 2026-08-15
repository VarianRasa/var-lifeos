import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_graph.dart';

void main() {
  test('NodeGraph builds cross-day edges and degree counts', () {
    final today = DateTime(2026, 6, 18);
    final tomorrow = DateTime(2026, 6, 19);
    final nodes = [
      MindmapNode.create(
        id: 'task-1',
        type: NodeType.task,
        title: 'Launch task',
        day: today,
        relatedNodeIds: const ['note-1', 'missing-node'],
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
    ];

    final graph = NodeGraph.fromNodes(nodes);

    expect(graph.nodes.map((node) => node.id), ['task-1', 'note-1', 'goal-1']);
    expect(graph.edges.map((edge) => '${edge.sourceId}->${edge.targetId}'), [
      'task-1->note-1',
      'goal-1->task-1',
    ]);
    expect(graph.edges.every((edge) => edge.isCrossDay), isTrue);
    expect(graph.nodeFor('task-1')?.outgoingCount, 1);
    expect(graph.nodeFor('task-1')?.incomingCount, 1);
    expect(graph.nodeFor('task-1')?.totalDegree, 2);
    expect(graph.neighborsFor('task-1').map((node) => node.id), [
      'note-1',
      'goal-1',
    ]);
    expect(graph.nodeFor('missing-node'), isNull);
  });

  test('NodeGraph.fromNodes extracts implicit wikilink edges from body', () {
    final today = DateTime(2026, 7, 24);
    final targetNode = MindmapNode.create(
      id: 'target-node-id',
      type: NodeType.note,
      title: 'Target Zettelkasten Note',
      day: today,
    );

    final sourceNode = MindmapNode.create(
      id: 'source-node-id',
      type: NodeType.journal,
      title: 'Source Daily Note',
      body: 'Today I referenced [[Target Zettelkasten Note]] in my thoughts.',
      day: today,
    );

    final graph = NodeGraph.fromNodes([targetNode, sourceNode]);

    expect(graph.edges, hasLength(1));
    final edge = graph.edges.first;
    expect(edge.sourceId, 'source-node-id');
    expect(edge.targetId, 'target-node-id');
    expect(edge.isWikilink, isTrue);
  });
}

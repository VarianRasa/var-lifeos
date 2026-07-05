import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/graph/domain/node_graph_explorer.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_graph.dart';

void main() {
  test(
    'filters visible graph by metadata query, node type, and cross-day scope',
    () {
      final graph = _buildExplorerGraph();

      final view = NodeGraphExplorerView.fromGraph(
        graph,
        query: const NodeGraphExplorerQuery(
          searchQuery: 'work',
          typeFilter: NodeType.task,
          crossDayOnly: true,
        ),
      );

      expect(view.activeFilterCount, 3);
      expect(view.matchingNodeCount, 1);
      expect(view.crossDayEdgeCount, 2);
      expect(view.visibleNodes.map((node) => node.id), [
        'task-1',
        'note-1',
        'goal-1',
      ]);
      expect(
        view.visibleEdges.map((edge) => '${edge.sourceId}->${edge.targetId}'),
        ['task-1->note-1', 'goal-1->task-1'],
      );
      expect(view.visibleHubs.map((node) => '${node.id}:${node.totalDegree}'), [
        'task-1:2',
        'goal-1:1',
        'note-1:1',
      ]);
    },
  );

  test(
    'focus narrows the graph to one node neighborhood and recomputes degrees',
    () {
      final graph = _buildExplorerGraph();

      final view = NodeGraphExplorerView.fromGraph(
        graph,
        query: const NodeGraphExplorerQuery(focusedNodeId: 'task-1'),
      );

      expect(view.focusedNode?.id, 'task-1');
      expect(view.visibleNodes.map((node) => node.id), [
        'task-1',
        'note-1',
        'habit-1',
        'goal-1',
      ]);
      expect(view.visibleHubs.first.id, 'task-1');
      expect(view.visibleHubs.first.totalDegree, 3);
      expect(
        view.visibleEdges.map((edge) => '${edge.sourceId}->${edge.targetId}'),
        ['task-1->habit-1', 'task-1->note-1', 'goal-1->task-1'],
      );

      final crossDayView = NodeGraphExplorerView.fromGraph(
        graph,
        query: const NodeGraphExplorerQuery(
          focusedNodeId: 'task-1',
          crossDayOnly: true,
        ),
      );

      expect(crossDayView.visibleNodes.map((node) => node.id), [
        'task-1',
        'note-1',
        'goal-1',
      ]);
      expect(crossDayView.visibleHubs.first.totalDegree, 2);
      expect(
        crossDayView.visibleEdges.map(
          (edge) => '${edge.sourceId}->${edge.targetId}',
        ),
        ['task-1->note-1', 'goal-1->task-1'],
      );
    },
  );

  test('focused graph view separates outgoing relations from backlinks', () {
    final graph = _buildExplorerGraph();

    final view = NodeGraphExplorerView.fromGraph(
      graph,
      query: const NodeGraphExplorerQuery(focusedNodeId: 'task-1'),
    );

    expect(view.focusedNeighborhood, isNotNull);
    expect(view.focusedNeighborhood!.focusedNode.id, 'task-1');
    expect(view.focusedNeighborhood!.relatedNodes.map((node) => node.id), [
      'habit-1',
      'note-1',
    ]);
    expect(view.focusedNeighborhood!.backlinkNodes.map((node) => node.id), [
      'goal-1',
    ]);
    expect(view.focusedNeighborhood!.relatedCount, 2);
    expect(view.focusedNeighborhood!.backlinkCount, 1);
    expect(view.focusedNeighborhood!.totalConnectionCount, 3);
  });

  test('filters graph by relation label metadata', () {
    final graph = _buildExplorerGraph();

    final view = NodeGraphExplorerView.fromGraph(
      graph,
      query: const NodeGraphExplorerQuery(relationLabelFilter: 'supports'),
    );

    expect(view.activeFilterCount, 1);
    expect(view.edgeCount, 1);
    expect(view.visibleNodes.map((node) => node.id), ['task-1', 'note-1']);
    expect(
      view.visibleEdges.map((edge) => '${edge.sourceId}->${edge.targetId}'),
      ['task-1->note-1'],
    );
  });

  test('filters graph by project, tag, status, and priority metadata', () {
    final graph = _buildExplorerGraph();

    final view = NodeGraphExplorerView.fromGraph(
      graph,
      query: const NodeGraphExplorerQuery(
        projectFilter: 'Launch App',
        tagFilter: 'work',
        statusFilter: NodeStatus.doing,
        priorityFilter: NodePriority.high,
      ),
    );

    expect(view.activeFilterCount, 4);
    expect(view.matchingNodeCount, 1);
    expect(view.visibleNodes.map((node) => node.id), [
      'task-1',
      'note-1',
      'habit-1',
      'goal-1',
    ]);
    expect(
      view.visibleEdges.map((edge) => '${edge.sourceId}->${edge.targetId}'),
      ['task-1->habit-1', 'task-1->note-1', 'goal-1->task-1'],
    );

    final areaView = NodeGraphExplorerView.fromGraph(
      graph,
      query: const NodeGraphExplorerQuery(areaFilter: 'Work'),
    );

    expect(areaView.matchingNodeCount, 2);
    expect(
      areaView.visibleEdges.map((edge) => '${edge.sourceId}->${edge.targetId}'),
      ['task-1->habit-1', 'task-1->note-1'],
    );
  });
}

NodeGraph _buildExplorerGraph() {
  final today = DateTime(2026, 6, 18);
  final tomorrow = DateTime(2026, 6, 19);
  final nodes = [
    MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Launch task',
      body: 'Coordinate release work',
      day: today,
      status: NodeStatus.doing,
      priority: NodePriority.high,
      project: 'Launch App',
      tags: const ['work', 'release'],
      relatedNodeIds: const ['note-1', 'habit-1'],
      data: const {
        'relations': [
          {'targetId': 'note-1', 'label': 'supports'},
          {'targetId': 'habit-1', 'label': 'blocks'},
        ],
      },
      now: DateTime(2026, 6, 18, 8),
    ),
    MindmapNode.create(
      id: 'note-1',
      type: NodeType.note,
      title: 'Release context',
      body: 'Launch checklist',
      day: tomorrow,
      area: 'Work',
      tags: const ['release'],
      now: DateTime(2026, 6, 18, 9),
    ),
    MindmapNode.create(
      id: 'habit-1',
      type: NodeType.habit,
      title: 'Daily standup',
      day: today,
      area: 'Work',
      now: DateTime(2026, 6, 18, 9, 30),
    ),
    MindmapNode.create(
      id: 'goal-1',
      type: NodeType.goal,
      title: 'Ship v1',
      day: tomorrow,
      relatedNodeIds: const ['task-1'],
      now: DateTime(2026, 6, 18, 10),
    ),
    MindmapNode.create(
      id: 'archive-1',
      type: NodeType.note,
      title: 'Archive idea',
      day: today,
      isArchived: true,
      now: DateTime(2026, 6, 18, 11),
    ),
  ];
  return NodeGraph.fromNodes(nodes);
}

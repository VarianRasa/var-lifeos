import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/graph/application/graph_overview.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_graph.dart';

void main() {
  test('summarizes graph totals and node categories', () {
    final graph = NodeGraph.fromNodes([
      _node('hub', relatedNodeIds: const ['a', 'b', 'c']),
      _node('a', priority: NodePriority.high),
      _node('b'),
      _node('c'),
      _node('isolated', updatedAt: DateTime(2026, 5, 1)),
    ]);

    final summary = buildGraphOverview(graph, now: DateTime(2026, 6, 18));

    expect(summary.totalNodes, 5);
    expect(summary.relationCount, 3);
    expect(summary.connectedNodes, 4);
    expect(summary.isolatedNodes, 1);
    expect(summary.hubNodes, 1);
    expect(summary.staleNodes, 1);
    expect(summary.highPriorityOpenNodes, 1);
    expect(summary.healthStatus, GraphHealthStatus.atRisk);
  });

  test('classifies sparse graph with no relations', () {
    final graph = NodeGraph.fromNodes([_node('one'), _node('two')]);

    final summary = buildGraphOverview(graph, now: DateTime(2026, 6, 18));

    expect(summary.hasNodes, isTrue);
    expect(summary.hasRelations, isFalse);
    expect(summary.healthStatus, GraphHealthStatus.sparse);
  });

  test('classifies healthy graph when balanced and current', () {
    final graph = NodeGraph.fromNodes([
      _node('a', relatedNodeIds: const ['b']),
      _node('b', relatedNodeIds: const ['c']),
      _node('c'),
    ]);

    final summary = buildGraphOverview(graph, now: DateTime(2026, 6, 18));

    expect(summary.healthStatus, GraphHealthStatus.healthy);
  });

  test('classifies crowded graph with dense relations', () {
    final graph = NodeGraph.fromNodes([
      _node('a', relatedNodeIds: const ['b', 'c', 'd']),
      _node('b', relatedNodeIds: const ['a', 'c', 'd']),
      _node('c', relatedNodeIds: const ['a', 'b', 'd']),
      _node('d'),
    ]);

    final summary = buildGraphOverview(graph, now: DateTime(2026, 6, 18));

    expect(summary.relationCount, 9);
    expect(summary.healthStatus, GraphHealthStatus.crowded);
  });
}

MindmapNode _node(
  String id, {
  List<String> relatedNodeIds = const [],
  NodePriority priority = NodePriority.none,
  DateTime? updatedAt,
}) {
  final createdAt = DateTime(2026, 6, 18, 9);
  return MindmapNode(
    id: id,
    type: NodeType.task,
    title: id,
    day: DateTime(2026, 6, 18),
    createdAt: createdAt,
    updatedAt: updatedAt ?? createdAt,
    priority: priority,
    relatedNodeIds: relatedNodeIds,
  );
}

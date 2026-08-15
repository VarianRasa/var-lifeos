/// Global relation graph derived from node links and backlinks.
library;

import '../../../core/utils/date_utils.dart';
import 'mindmap_node.dart';

final class NodeGraph {
  NodeGraph({
    required List<NodeGraphNode> nodes,
    required List<NodeGraphEdge> edges,
  }) : nodes = List.unmodifiable(nodes),
       edges = List.unmodifiable(edges),
       _nodesById = {for (final node in nodes) node.id: node};

  factory NodeGraph.fromNodes(List<MindmapNode> nodes) {
    final nodesById = {for (final node in nodes) node.id: node};
    final nodesByTitle = {
      for (final node in nodes)
        if (node.title.trim().isNotEmpty) node.title.trim().toLowerCase(): node,
    };
    final incomingCounts = {for (final node in nodes) node.id: 0};
    final outgoingCounts = {for (final node in nodes) node.id: 0};
    final edges = <NodeGraphEdge>[];
    final seenEdges = <String>{};

    final wikilinkRegex = RegExp(r'\[\[(.*?)\]\]');

    for (final source in nodes) {
      // 1. Explicit relations
      for (final targetId in source.relatedNodeIds) {
        final target = nodesById[targetId];
        if (target == null) continue;

        final edgeKey = '${source.id}->$targetId';
        if (!seenEdges.add(edgeKey)) continue;

        edges.add(
          NodeGraphEdge(
            sourceId: source.id,
            targetId: targetId,
            isCrossDay: !source.day.isSameDay(target.day),
            isWikilink: false,
          ),
        );
        outgoingCounts[source.id] = (outgoingCounts[source.id] ?? 0) + 1;
        incomingCounts[targetId] = (incomingCounts[targetId] ?? 0) + 1;
      }

      // 2. Implicit wikilinks parsing [[title]] or [[nodeId]] in body
      if (source.body.contains('[[')) {
        final matches = wikilinkRegex.allMatches(source.body);
        for (final match in matches) {
          final rawMatch = match.group(1)?.trim();
          if (rawMatch == null || rawMatch.isEmpty) continue;

          final targetNode =
              nodesById[rawMatch] ?? nodesByTitle[rawMatch.toLowerCase()];
          if (targetNode == null || targetNode.id == source.id) continue;

          final edgeKey = '${source.id}->${targetNode.id}';
          if (!seenEdges.add(edgeKey)) continue;

          edges.add(
            NodeGraphEdge(
              sourceId: source.id,
              targetId: targetNode.id,
              isCrossDay: !source.day.isSameDay(targetNode.day),
              isWikilink: true,
            ),
          );
          outgoingCounts[source.id] = (outgoingCounts[source.id] ?? 0) + 1;
          incomingCounts[targetNode.id] =
              (incomingCounts[targetNode.id] ?? 0) + 1;
        }
      }
    }

    return NodeGraph(
      nodes: [
        for (final node in nodes)
          NodeGraphNode(
            node: node,
            incomingCount: incomingCounts[node.id] ?? 0,
            outgoingCount: outgoingCounts[node.id] ?? 0,
          ),
      ],
      edges: edges,
    );
  }

  final List<NodeGraphNode> nodes;
  final List<NodeGraphEdge> edges;
  final Map<String, NodeGraphNode> _nodesById;

  bool get hasEdges => edges.isNotEmpty;
  int get edgeCount => edges.length;

  NodeGraphNode? nodeFor(String nodeId) => _nodesById[nodeId];

  List<NodeGraphEdge> edgesFor(String nodeId) {
    return [
      for (final edge in edges)
        if (edge.sourceId == nodeId || edge.targetId == nodeId) edge,
    ];
  }

  List<MindmapNode> neighborsFor(String nodeId) {
    final neighborIds = <String>{};
    for (final edge in edges) {
      if (edge.sourceId == nodeId) neighborIds.add(edge.targetId);
      if (edge.targetId == nodeId) neighborIds.add(edge.sourceId);
    }
    return [
      for (final neighborId in neighborIds) ?_nodesById[neighborId]?.node,
    ];
  }
}

final class NodeGraphNode {
  const NodeGraphNode({
    required this.node,
    required this.incomingCount,
    required this.outgoingCount,
  });

  final MindmapNode node;
  final int incomingCount;
  final int outgoingCount;

  String get id => node.id;
  int get totalDegree => incomingCount + outgoingCount;
}

final class NodeGraphEdge {
  const NodeGraphEdge({
    required this.sourceId,
    required this.targetId,
    required this.isCrossDay,
    this.isWikilink = false,
  });

  final String sourceId;
  final String targetId;
  final bool isCrossDay;
  final bool isWikilink;
}

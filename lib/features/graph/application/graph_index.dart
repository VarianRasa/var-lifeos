/// Precomputed graph adjacency for fast graph helpers.
library;

import '../../mindmap/domain/node_graph.dart';

final class GraphIndex {
  GraphIndex({
    required this.graph,
    required Map<String, List<NodeGraphEdge>> outgoingEdges,
    required Map<String, List<NodeGraphEdge>> incomingEdges,
    required Map<String, Set<String>> neighborIds,
  }) : outgoingEdges = _freezeEdgeMap(outgoingEdges),
       incomingEdges = _freezeEdgeMap(incomingEdges),
       neighborIds = _freezeSetMap(neighborIds);

  final NodeGraph graph;
  final Map<String, List<NodeGraphEdge>> outgoingEdges;
  final Map<String, List<NodeGraphEdge>> incomingEdges;
  final Map<String, Set<String>> neighborIds;

  List<NodeGraphEdge> outgoingFor(String nodeId) =>
      outgoingEdges[nodeId] ?? const [];
  List<NodeGraphEdge> incomingFor(String nodeId) =>
      incomingEdges[nodeId] ?? const [];
  Set<String> neighborsFor(String nodeId) => neighborIds[nodeId] ?? const {};
  bool isConnected(String nodeId) => neighborsFor(nodeId).isNotEmpty;
}

GraphIndex buildGraphIndex(NodeGraph graph) {
  final outgoing = <String, List<NodeGraphEdge>>{};
  final incoming = <String, List<NodeGraphEdge>>{};
  final neighbors = <String, Set<String>>{};
  for (final node in graph.nodes) {
    outgoing[node.id] = <NodeGraphEdge>[];
    incoming[node.id] = <NodeGraphEdge>[];
    neighbors[node.id] = <String>{};
  }
  for (final edge in graph.edges) {
    outgoing.putIfAbsent(edge.sourceId, () => <NodeGraphEdge>[]).add(edge);
    incoming.putIfAbsent(edge.targetId, () => <NodeGraphEdge>[]).add(edge);
    neighbors.putIfAbsent(edge.sourceId, () => <String>{}).add(edge.targetId);
    neighbors.putIfAbsent(edge.targetId, () => <String>{}).add(edge.sourceId);
  }
  return GraphIndex(
    graph: graph,
    outgoingEdges: outgoing,
    incomingEdges: incoming,
    neighborIds: neighbors,
  );
}

Map<String, List<NodeGraphEdge>> _freezeEdgeMap(
  Map<String, List<NodeGraphEdge>> source,
) {
  return Map.unmodifiable({
    for (final entry in source.entries)
      entry.key: List<NodeGraphEdge>.unmodifiable(entry.value),
  });
}

Map<String, Set<String>> _freezeSetMap(Map<String, Set<String>> source) {
  return Map.unmodifiable({
    for (final entry in source.entries)
      entry.key: Set<String>.unmodifiable(entry.value),
  });
}

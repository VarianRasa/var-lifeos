/// Mission-level health summary for the graph page.
library;

import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_graph.dart';

const int graphHubDegreeThreshold = 3;
const int graphStaleDayThreshold = 14;

final class GraphOverviewSummary {
  const GraphOverviewSummary({
    required this.totalNodes,
    required this.relationCount,
    required this.connectedNodes,
    required this.isolatedNodes,
    required this.hubNodes,
    required this.staleNodes,
    required this.highPriorityOpenNodes,
    required this.healthStatus,
  });

  final int totalNodes;
  final int relationCount;
  final int connectedNodes;
  final int isolatedNodes;
  final int hubNodes;
  final int staleNodes;
  final int highPriorityOpenNodes;
  final GraphHealthStatus healthStatus;

  bool get hasNodes => totalNodes > 0;
  bool get hasRelations => relationCount > 0;
}

enum GraphHealthStatus {
  healthy('Healthy'),
  sparse('Sparse'),
  crowded('Crowded'),
  atRisk('At risk');

  const GraphHealthStatus(this.label);

  final String label;
}

GraphOverviewSummary buildGraphOverview(
  NodeGraph graph, {
  DateTime? now,
  int hubDegreeThreshold = graphHubDegreeThreshold,
  int staleDayThreshold = graphStaleDayThreshold,
}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  var connectedNodes = 0;
  var hubNodes = 0;
  var staleNodes = 0;
  var highPriorityOpenNodes = 0;

  for (final graphNode in graph.nodes) {
    final node = graphNode.node;
    if (graphNode.totalDegree > 0) connectedNodes++;
    if (graphNode.totalDegree >= hubDegreeThreshold) hubNodes++;
    if (isGraphNodeStale(
      node,
      now: today,
      staleDayThreshold: staleDayThreshold,
    )) {
      staleNodes++;
    }
    if (!_isClosed(node.status) &&
        (node.priority == NodePriority.high ||
            node.priority == NodePriority.urgent)) {
      highPriorityOpenNodes++;
    }
  }

  final totalNodes = graph.nodes.length;
  final isolatedNodes = totalNodes - connectedNodes;

  return GraphOverviewSummary(
    totalNodes: totalNodes,
    relationCount: graph.edgeCount,
    connectedNodes: connectedNodes,
    isolatedNodes: isolatedNodes,
    hubNodes: hubNodes,
    staleNodes: staleNodes,
    highPriorityOpenNodes: highPriorityOpenNodes,
    healthStatus: _classifyHealth(
      totalNodes: totalNodes,
      relationCount: graph.edgeCount,
      isolatedNodes: isolatedNodes,
      staleNodes: staleNodes,
      highPriorityOpenNodes: highPriorityOpenNodes,
    ),
  );
}

GraphHealthStatus _classifyHealth({
  required int totalNodes,
  required int relationCount,
  required int isolatedNodes,
  required int staleNodes,
  required int highPriorityOpenNodes,
}) {
  if (totalNodes == 0 || relationCount == 0 || isolatedNodes > totalNodes / 2) {
    return GraphHealthStatus.sparse;
  }
  if (highPriorityOpenNodes > 0 || staleNodes > totalNodes / 2) {
    return GraphHealthStatus.atRisk;
  }
  if (relationCount > totalNodes * 2) return GraphHealthStatus.crowded;
  return GraphHealthStatus.healthy;
}

bool isGraphNodeStale(
  MindmapNode node, {
  DateTime? now,
  int staleDayThreshold = graphStaleDayThreshold,
}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  return today.difference(node.updatedAt).inDays >= staleDayThreshold;
}

bool _isClosed(NodeStatus status) => status == NodeStatus.done;

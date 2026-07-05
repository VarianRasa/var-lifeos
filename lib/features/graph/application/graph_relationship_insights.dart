/// Relationship diagnostics for the graph page.
library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_graph.dart';
import 'graph_overview.dart';

enum GraphRelationshipSeverity { info, warning, critical }

final class GraphRelationshipInsight {
  const GraphRelationshipInsight({
    required this.title,
    required this.description,
    required this.severity,
    required this.nodeIds,
  });

  final String title;
  final String description;
  final GraphRelationshipSeverity severity;
  final List<String> nodeIds;
}

List<GraphRelationshipInsight> buildGraphRelationshipInsights(
  NodeGraph graph, {
  DateTime? now,
}) {
  final insights = <GraphRelationshipInsight>[];
  final isolated = [
    for (final node in graph.nodes)
      if (node.totalDegree == 0) node,
  ];
  if (isolated.isNotEmpty) {
    insights.add(
      GraphRelationshipInsight(
        title: 'Orphan nodes',
        description: '${isolated.length} nodes have no graph relations.',
        severity: GraphRelationshipSeverity.warning,
        nodeIds: [for (final node in isolated) node.id],
      ),
    );
  }
  final highPriorityIsolated = isolated.where((node) {
    return node.node.type == NodeType.task &&
        node.node.status != NodeStatus.done &&
        (node.node.priority == NodePriority.high ||
            node.node.priority == NodePriority.urgent);
  }).toList();
  if (highPriorityIsolated.isNotEmpty) {
    insights.add(
      GraphRelationshipInsight(
        title: 'Isolated priority tasks',
        description:
            '${highPriorityIsolated.length} priority tasks need context.',
        severity: GraphRelationshipSeverity.critical,
        nodeIds: [for (final node in highPriorityIsolated) node.id],
      ),
    );
  }
  final hubs = [
    for (final node in graph.nodes)
      if (node.totalDegree >= graphHubDegreeThreshold) node,
  ];
  if (hubs.isNotEmpty) {
    insights.add(
      GraphRelationshipInsight(
        title: 'Hub nodes',
        description: '${hubs.length} nodes coordinate many relations.',
        severity: GraphRelationshipSeverity.info,
        nodeIds: [for (final node in hubs) node.id],
      ),
    );
  }
  final stale = [
    for (final node in graph.nodes)
      if (node.totalDegree > 0 && isGraphNodeStale(node.node, now: now)) node,
  ];
  if (stale.isNotEmpty) {
    insights.add(
      GraphRelationshipInsight(
        title: 'Stale clusters',
        description: '${stale.length} connected nodes have not moved recently.',
        severity: GraphRelationshipSeverity.warning,
        nodeIds: [for (final node in stale) node.id],
      ),
    );
  }
  final oneWay = graph.edges.where((edge) {
    return !graph.edges.any(
      (other) =>
          other.sourceId == edge.targetId && other.targetId == edge.sourceId,
    );
  }).toList();
  if (oneWay.length >= 3) {
    insights.add(
      GraphRelationshipInsight(
        title: 'One-way dependency chains',
        description: '${oneWay.length} links have no backlink confirmation.',
        severity: GraphRelationshipSeverity.info,
        nodeIds: {
          for (final edge in oneWay) ...[edge.sourceId, edge.targetId],
        }.toList(),
      ),
    );
  }
  final goalGaps = [
    for (final node in graph.nodes)
      if (node.node.type == NodeType.goal &&
          graph.neighborsFor(node.id).isEmpty)
        node,
  ];
  if (goalGaps.isNotEmpty) {
    insights.add(
      GraphRelationshipInsight(
        title: 'Goal relation gaps',
        description: '${goalGaps.length} goals need supporting tasks or notes.',
        severity: GraphRelationshipSeverity.critical,
        nodeIds: [for (final node in goalGaps) node.id],
      ),
    );
  }
  insights.sort((a, b) => b.severity.index.compareTo(a.severity.index));
  return insights;
}

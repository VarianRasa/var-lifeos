/// Risk badges derived from existing node data.
library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_graph.dart';
import 'graph_overview.dart';

enum GraphRiskSeverity { low, medium, high, critical }

final class GraphRiskBadge {
  const GraphRiskBadge({
    required this.nodeId,
    required this.label,
    required this.severity,
  });

  final String nodeId;
  final String label;
  final GraphRiskSeverity severity;
}

Map<String, List<GraphRiskBadge>> buildGraphRiskOverlay(
  NodeGraph graph, {
  DateTime? now,
}) {
  final result = <String, List<GraphRiskBadge>>{};
  for (final graphNode in graph.nodes) {
    final node = graphNode.node;
    final badges = <GraphRiskBadge>[];
    if (node.dueDate != null &&
        node.dueDate!.isBefore(_dateOnly(now ?? DateTime.now())) &&
        node.status != NodeStatus.done) {
      badges.add(_badge(node.id, 'Overdue', GraphRiskSeverity.critical));
    }
    if (node.priority == NodePriority.urgent) {
      badges.add(_badge(node.id, 'Urgent', GraphRiskSeverity.critical));
    } else if (node.priority == NodePriority.high) {
      badges.add(_badge(node.id, 'High priority', GraphRiskSeverity.high));
    }
    if (isGraphNodeStale(node, now: now)) {
      badges.add(_badge(node.id, 'Stale', GraphRiskSeverity.medium));
    }
    if (node.status == NodeStatus.waiting) {
      badges.add(_badge(node.id, 'Waiting', GraphRiskSeverity.medium));
    }
    if (graphNode.totalDegree == 0) {
      badges.add(_badge(node.id, 'No relations', GraphRiskSeverity.low));
    }
    if (node.type == NodeType.goal && !_hasNextAction(graph, node)) {
      badges.add(_badge(node.id, 'Needs next action', GraphRiskSeverity.high));
    }
    if (badges.isNotEmpty) {
      badges.sort((a, b) => b.severity.index.compareTo(a.severity.index));
      result[node.id] = List.unmodifiable(badges);
    }
  }
  return Map.unmodifiable(result);
}

GraphRiskBadge _badge(String id, String label, GraphRiskSeverity severity) {
  return GraphRiskBadge(nodeId: id, label: label, severity: severity);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _hasNextAction(NodeGraph graph, MindmapNode goal) {
  for (final neighbor in graph.neighborsFor(goal.id)) {
    if (neighbor.type == NodeType.task && neighbor.status != NodeStatus.done) {
      return true;
    }
  }
  return false;
}

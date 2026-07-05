/// Pure graph filter predicates.
library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_graph.dart';
import 'graph_overview.dart';

enum GraphRelationState {
  connected('Connected'),
  isolated('Isolated'),
  hub('Hub'),
  stale('Stale');

  const GraphRelationState(this.label);
  final String label;
}

final class GraphFilterState {
  const GraphFilterState({
    this.type,
    this.project,
    this.area,
    this.tag,
    this.priority,
    this.status,
    this.relationState,
    this.searchQuery = '',
  });

  final NodeType? type;
  final String? project;
  final String? area;
  final String? tag;
  final NodePriority? priority;
  final NodeStatus? status;
  final GraphRelationState? relationState;
  final String searchQuery;
}

bool matchesGraphFilter(
  NodeGraphNode graphNode,
  GraphFilterState filter, {
  DateTime? now,
}) {
  final node = graphNode.node;
  if (filter.type != null && node.type != filter.type) return false;
  if (filter.project != null && node.project != filter.project) return false;
  if (filter.area != null && node.area != filter.area) return false;
  if (filter.tag != null && !node.tags.contains(filter.tag)) return false;
  if (filter.priority != null && node.priority != filter.priority) return false;
  if (filter.status != null && node.status != filter.status) return false;
  if (!_matchesRelationState(graphNode, filter.relationState, now: now)) {
    return false;
  }
  final query = filter.searchQuery.trim().toLowerCase();
  if (query.isEmpty) return true;
  return [
    node.title,
    node.body,
    node.project,
    node.area,
    for (final tag in node.tags) tag,
  ].any((value) => value.toLowerCase().contains(query));
}

List<NodeGraphNode> filteredGraphNodes(
  Iterable<NodeGraphNode> nodes,
  GraphFilterState filter, {
  DateTime? now,
}) {
  return [
    for (final node in nodes)
      if (matchesGraphFilter(node, filter, now: now)) node,
  ]..sort((a, b) {
    final title = a.node.title.compareTo(b.node.title);
    if (title != 0) return title;
    return a.id.compareTo(b.id);
  });
}

bool _matchesRelationState(
  NodeGraphNode node,
  GraphRelationState? state, {
  DateTime? now,
}) {
  return switch (state) {
    null => true,
    GraphRelationState.connected => node.totalDegree > 0,
    GraphRelationState.isolated => node.totalDegree == 0,
    GraphRelationState.hub => node.totalDegree >= graphHubDegreeThreshold,
    GraphRelationState.stale => isGraphNodeStale(node.node, now: now),
  };
}

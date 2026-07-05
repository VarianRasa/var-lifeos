/// Query and projection helpers for the dedicated graph explorer.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_graph.dart';
import '../application/graph_filters.dart';

final class NodeGraphExplorerQuery {
  const NodeGraphExplorerQuery({
    this.searchQuery = '',
    this.typeFilter,
    this.statusFilter,
    this.priorityFilter,
    this.tagFilter,
    this.projectFilter,
    this.areaFilter,
    this.relationLabelFilter,
    this.relationState,
    this.crossDayOnly = false,
    this.focusedNodeId,
  });

  final String searchQuery;
  final NodeType? typeFilter;
  final NodeStatus? statusFilter;
  final NodePriority? priorityFilter;
  final String? tagFilter;
  final String? projectFilter;
  final String? areaFilter;
  final String? relationLabelFilter;
  final GraphRelationState? relationState;
  final bool crossDayOnly;
  final String? focusedNodeId;

  String get normalizedSearch => searchQuery.trim().toLowerCase();
  bool get hasSearch => normalizedSearch.isNotEmpty;
  bool get hasNodeFilter {
    return hasSearch ||
        typeFilter != null ||
        statusFilter != null ||
        priorityFilter != null ||
        _hasStringFilter(tagFilter) ||
        _hasStringFilter(projectFilter) ||
        _hasStringFilter(areaFilter);
  }

  bool get hasRelationFilter => _hasStringFilter(relationLabelFilter);

  bool get hasFocus => focusedNodeId != null && focusedNodeId!.isNotEmpty;

  int get activeFilterCount {
    return [
      hasSearch,
      typeFilter != null,
      statusFilter != null,
      priorityFilter != null,
      _hasStringFilter(tagFilter),
      _hasStringFilter(projectFilter),
      _hasStringFilter(areaFilter),
      hasRelationFilter,
      relationState != null,
      crossDayOnly,
      hasFocus,
    ].where((isActive) => isActive).length;
  }

  NodeGraphExplorerQuery copyWith({
    String? searchQuery,
    NodeType? typeFilter,
    bool clearTypeFilter = false,
    NodeStatus? statusFilter,
    bool clearStatusFilter = false,
    NodePriority? priorityFilter,
    bool clearPriorityFilter = false,
    String? tagFilter,
    bool clearTagFilter = false,
    String? projectFilter,
    bool clearProjectFilter = false,
    String? areaFilter,
    bool clearAreaFilter = false,
    String? relationLabelFilter,
    bool clearRelationLabelFilter = false,
    GraphRelationState? relationState,
    bool clearRelationState = false,
    bool? crossDayOnly,
    String? focusedNodeId,
    bool clearFocus = false,
  }) {
    return NodeGraphExplorerQuery(
      searchQuery: searchQuery ?? this.searchQuery,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
      statusFilter: clearStatusFilter
          ? null
          : (statusFilter ?? this.statusFilter),
      priorityFilter: clearPriorityFilter
          ? null
          : (priorityFilter ?? this.priorityFilter),
      tagFilter: clearTagFilter ? null : (tagFilter ?? this.tagFilter),
      projectFilter: clearProjectFilter
          ? null
          : (projectFilter ?? this.projectFilter),
      areaFilter: clearAreaFilter ? null : (areaFilter ?? this.areaFilter),
      relationLabelFilter: clearRelationLabelFilter
          ? null
          : (relationLabelFilter ?? this.relationLabelFilter),
      relationState: clearRelationState
          ? null
          : (relationState ?? this.relationState),
      crossDayOnly: crossDayOnly ?? this.crossDayOnly,
      focusedNodeId: clearFocus ? null : (focusedNodeId ?? this.focusedNodeId),
    );
  }

  bool matchesNode(MindmapNode node) {
    if (typeFilter != null && node.type != typeFilter) return false;
    if (statusFilter != null && node.status != statusFilter) return false;
    if (priorityFilter != null && node.priority != priorityFilter) {
      return false;
    }
    if (_hasStringFilter(tagFilter) && !node.tags.contains(tagFilter)) {
      return false;
    }
    if (_hasStringFilter(projectFilter) && node.project != projectFilter) {
      return false;
    }
    if (_hasStringFilter(areaFilter) && node.area != areaFilter) return false;
    if (!hasSearch) return true;
    return _matchesSearch(node, normalizedSearch);
  }
}

final class NodeGraphExplorerView {
  NodeGraphExplorerView._({
    required this.query,
    required List<NodeGraphNode> visibleNodes,
    required List<NodeGraphEdge> visibleEdges,
    required List<NodeGraphNode> visibleHubs,
    required this.matchingNodeCount,
    required this.focusedNode,
    required this.focusedNeighborhood,
  }) : visibleNodes = List.unmodifiable(visibleNodes),
       visibleEdges = List.unmodifiable(visibleEdges),
       visibleHubs = List.unmodifiable(visibleHubs);

  factory NodeGraphExplorerView.fromGraph(
    NodeGraph graph, {
    NodeGraphExplorerQuery query = const NodeGraphExplorerQuery(),
    int hubLimit = 8,
  }) {
    final matchingNodeIds = {
      for (final node in graph.nodes)
        if (query.matchesNode(node.node) &&
            matchesGraphFilter(
              node,
              GraphFilterState(relationState: query.relationState),
            ))
          node.id,
    };

    final visibleEdges = [
      for (final edge in graph.edges)
        if (_edgeMatches(graph, edge, query, matchingNodeIds)) edge,
    ]..sort((a, b) => _compareEdges(graph, a, b));

    final visibleNodeIds = <String>{};
    if (query.hasFocus) {
      final focusedId = query.focusedNodeId!;
      if (graph.nodeFor(focusedId) != null) visibleNodeIds.add(focusedId);
    } else if (!query.hasNodeFilter &&
        !query.hasRelationFilter &&
        query.relationState == null &&
        !query.crossDayOnly) {
      visibleNodeIds.addAll(graph.nodes.map((node) => node.id));
    } else if (query.hasNodeFilter) {
      visibleNodeIds.addAll(matchingNodeIds);
    }

    for (final edge in visibleEdges) {
      visibleNodeIds.add(edge.sourceId);
      visibleNodeIds.add(edge.targetId);
    }

    final degreeCounts = _degreeCountsFor(visibleEdges);
    final visibleNodes = [
      for (final node in graph.nodes)
        if (visibleNodeIds.contains(node.id))
          NodeGraphNode(
            node: node.node,
            incomingCount: degreeCounts[node.id]?.incoming ?? 0,
            outgoingCount: degreeCounts[node.id]?.outgoing ?? 0,
          ),
    ];

    final visibleHubs = [
      for (final node in visibleNodes)
        if (node.totalDegree > 0) node,
    ]..sort(_compareHubs);

    return NodeGraphExplorerView._(
      query: query,
      visibleNodes: visibleNodes,
      visibleEdges: visibleEdges,
      visibleHubs: visibleHubs.take(hubLimit).toList(growable: false),
      matchingNodeCount: query.hasFocus ? 1 : matchingNodeIds.length,
      focusedNode: query.hasFocus ? graph.nodeFor(query.focusedNodeId!) : null,
      focusedNeighborhood: query.hasFocus
          ? NodeGraphNeighborhood.fromGraph(graph, query.focusedNodeId!)
          : null,
    );
  }

  final NodeGraphExplorerQuery query;
  final List<NodeGraphNode> visibleNodes;
  final List<NodeGraphEdge> visibleEdges;
  final List<NodeGraphNode> visibleHubs;
  final int matchingNodeCount;
  final NodeGraphNode? focusedNode;
  final NodeGraphNeighborhood? focusedNeighborhood;

  int get activeFilterCount => query.activeFilterCount;
  int get edgeCount => visibleEdges.length;
  int get crossDayEdgeCount {
    return visibleEdges.where((edge) => edge.isCrossDay).length;
  }
}

final class NodeGraphNeighborhood {
  NodeGraphNeighborhood._({
    required this.focusedNode,
    required List<NodeGraphNode> relatedNodes,
    required List<NodeGraphNode> backlinkNodes,
  }) : relatedNodes = List.unmodifiable(relatedNodes),
       backlinkNodes = List.unmodifiable(backlinkNodes);

  static NodeGraphNeighborhood? fromGraph(NodeGraph graph, String nodeId) {
    final focusedNode = graph.nodeFor(nodeId);
    if (focusedNode == null) return null;

    final relatedNodes = <NodeGraphNode>[];
    final backlinkNodes = <NodeGraphNode>[];

    for (final edge in graph.edges) {
      if (edge.sourceId == nodeId) {
        final target = graph.nodeFor(edge.targetId);
        if (target != null) relatedNodes.add(target);
      } else if (edge.targetId == nodeId) {
        final source = graph.nodeFor(edge.sourceId);
        if (source != null) backlinkNodes.add(source);
      }
    }

    relatedNodes.sort(_compareGraphNodesByTitle);
    backlinkNodes.sort(_compareGraphNodesByTitle);

    return NodeGraphNeighborhood._(
      focusedNode: focusedNode,
      relatedNodes: relatedNodes,
      backlinkNodes: backlinkNodes,
    );
  }

  final NodeGraphNode focusedNode;
  final List<NodeGraphNode> relatedNodes;
  final List<NodeGraphNode> backlinkNodes;

  int get relatedCount => relatedNodes.length;
  int get backlinkCount => backlinkNodes.length;
  int get totalConnectionCount => relatedCount + backlinkCount;
}

final class _DegreeCount {
  const _DegreeCount({this.incoming = 0, this.outgoing = 0});

  final int incoming;
  final int outgoing;

  _DegreeCount addIncoming() {
    return _DegreeCount(incoming: incoming + 1, outgoing: outgoing);
  }

  _DegreeCount addOutgoing() {
    return _DegreeCount(incoming: incoming, outgoing: outgoing + 1);
  }
}

bool _edgeMatches(
  NodeGraph graph,
  NodeGraphEdge edge,
  NodeGraphExplorerQuery query,
  Set<String> matchingNodeIds,
) {
  if (query.crossDayOnly && !edge.isCrossDay) return false;
  if (query.hasRelationFilter &&
      _relationLabelFor(graph, edge) != query.relationLabelFilter) {
    return false;
  }
  if (query.hasFocus) {
    final focusedId = query.focusedNodeId!;
    if (edge.sourceId != focusedId && edge.targetId != focusedId) return false;
  }
  if (!query.hasNodeFilter) return true;
  return matchingNodeIds.contains(edge.sourceId) ||
      matchingNodeIds.contains(edge.targetId);
}

String _relationLabelFor(NodeGraph graph, NodeGraphEdge edge) {
  final source = graph.nodeFor(edge.sourceId)?.node;
  if (source == null) return 'relates to';
  final rawRelations = source.data['relations'];
  if (rawRelations is! List<Object?>) return 'relates to';
  for (final item in rawRelations) {
    if (item is! Map<Object?, Object?>) continue;
    if (item['targetId'] != edge.targetId) continue;
    final label = item['label'];
    if (label is String && label.trim().isNotEmpty) return label.trim();
  }
  return 'relates to';
}

Map<String, _DegreeCount> _degreeCountsFor(List<NodeGraphEdge> edges) {
  final counts = <String, _DegreeCount>{};
  for (final edge in edges) {
    counts[edge.sourceId] = (counts[edge.sourceId] ?? const _DegreeCount())
        .addOutgoing();
    counts[edge.targetId] = (counts[edge.targetId] ?? const _DegreeCount())
        .addIncoming();
  }
  return counts;
}

bool _matchesSearch(MindmapNode node, String query) {
  final values = [
    node.title,
    node.body,
    node.type.label,
    node.status.label,
    node.priority.label,
    node.project,
    node.area,
    dayKey(node.day),
    if (node.isPinned) 'pinned',
    if (node.isArchived) 'archived',
    for (final tag in node.tags) tag,
  ];
  return values.any((value) => value.toLowerCase().contains(query));
}

bool _hasStringFilter(String? value) {
  return value != null && value.trim().isNotEmpty;
}

int _compareEdges(NodeGraph graph, NodeGraphEdge a, NodeGraphEdge b) {
  final sourceA = graph.nodeFor(a.sourceId)?.node.title ?? a.sourceId;
  final sourceB = graph.nodeFor(b.sourceId)?.node.title ?? b.sourceId;
  final sourceCompare = sourceA.compareTo(sourceB);
  if (sourceCompare != 0) return sourceCompare;
  final targetA = graph.nodeFor(a.targetId)?.node.title ?? a.targetId;
  final targetB = graph.nodeFor(b.targetId)?.node.title ?? b.targetId;
  final targetCompare = targetA.compareTo(targetB);
  if (targetCompare != 0) return targetCompare;
  return '${a.sourceId}->${a.targetId}'.compareTo(
    '${b.sourceId}->${b.targetId}',
  );
}

int _compareHubs(NodeGraphNode a, NodeGraphNode b) {
  final degree = b.totalDegree.compareTo(a.totalDegree);
  if (degree != 0) return degree;
  final outgoing = b.outgoingCount.compareTo(a.outgoingCount);
  if (outgoing != 0) return outgoing;
  return a.node.title.compareTo(b.node.title);
}

int _compareGraphNodesByTitle(NodeGraphNode a, NodeGraphNode b) {
  final title = a.node.title.compareTo(b.node.title);
  if (title != 0) return title;
  return a.id.compareTo(b.id);
}

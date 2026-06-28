/// Dedicated graph view for node relations and backlinks.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/error_message.dart';
import '../../shared/widgets/search_field.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/node_graph.dart';
import '../mindmap/domain/workspace_context.dart';
import '../mindmap/presentation/mindmap_canvas.dart';
import 'domain/node_graph_explorer.dart';

class GraphPage extends ConsumerStatefulWidget {
  const GraphPage({super.key});

  @override
  ConsumerState<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends ConsumerState<GraphPage> {
  final _searchController = TextEditingController();
  NodeGraphExplorerQuery _query = const NodeGraphExplorerQuery();

  bool _initializedFilters = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedFilters) {
      _initializedFilters = true;
      try {
        final state = GoRouterState.of(context);
        final project = state.uri.queryParameters['project'];
        final area = state.uri.queryParameters['area'];
        if (project != null) {
          _query = _query.copyWith(projectFilter: project);
        } else if (area != null) {
          _query = _query.copyWith(areaFilter: area);
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(nodeGraphProvider);
    final isDesktop =
        MediaQuery.sizeOf(context).width >= LayoutConstants.desktopBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Graph'),
        actions: [
          SearchField(
            key: const ValueKey('graph-search-field'),
            controller: _searchController,
            hintText: 'Search graph...',
            onChanged: _changeSearchQuery,
          ),
          if (isDesktop)
            const SizedBox(width: 460)
          else
            const SizedBox(width: 16),
        ],
      ),
      body: graph.when(
        data: (value) {
          if (value.nodes.isEmpty) return const _GraphEmptyState();
          return _GraphBody(
            graph: value,
            view: NodeGraphExplorerView.fromGraph(value, query: _query),
            onTypeChanged: _changeTypeFilter,
            onStatusChanged: _changeStatusFilter,
            onPriorityChanged: _changePriorityFilter,
            onTagChanged: _changeTagFilter,
            onProjectChanged: _changeProjectFilter,
            onAreaChanged: _changeAreaFilter,
            onCrossDayChanged: _changeCrossDayOnly,
            onFocusNode: _focusNode,
            onClearFocus: _clearFocus,
            onClearFilters: _clearFilters,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorMessage(
          message: 'Unable to load graph',
          onRetry: () => ref.invalidate(allMindmapNodesProvider),
        ),
      ),
    );
  }

  void _changeSearchQuery(String value) {
    setState(() => _query = _query.copyWith(searchQuery: value));
  }

  void _changeTypeFilter(NodeType type) {
    setState(() {
      _query = _query.typeFilter == type
          ? _query.copyWith(clearTypeFilter: true)
          : _query.copyWith(typeFilter: type);
    });
  }

  void _changeStatusFilter(NodeStatus status) {
    setState(() {
      _query = _query.statusFilter == status
          ? _query.copyWith(clearStatusFilter: true)
          : _query.copyWith(statusFilter: status);
    });
  }

  void _changePriorityFilter(NodePriority priority) {
    setState(() {
      _query = _query.priorityFilter == priority
          ? _query.copyWith(clearPriorityFilter: true)
          : _query.copyWith(priorityFilter: priority);
    });
  }

  void _changeTagFilter(String tag) {
    setState(() {
      _query = _query.tagFilter == tag
          ? _query.copyWith(clearTagFilter: true)
          : _query.copyWith(tagFilter: tag);
    });
  }

  void _changeProjectFilter(String project) {
    setState(() {
      _query = _query.projectFilter == project
          ? _query.copyWith(clearProjectFilter: true)
          : _query.copyWith(projectFilter: project, clearAreaFilter: true);
    });
  }

  void _changeAreaFilter(String area) {
    setState(() {
      _query = _query.areaFilter == area
          ? _query.copyWith(clearAreaFilter: true)
          : _query.copyWith(areaFilter: area, clearProjectFilter: true);
    });
  }

  void _changeCrossDayOnly(bool value) {
    setState(() => _query = _query.copyWith(crossDayOnly: value));
  }

  void _focusNode(String nodeId) {
    setState(() => _query = _query.copyWith(focusedNodeId: nodeId));
  }

  void _clearFocus() {
    setState(() => _query = _query.copyWith(clearFocus: true));
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() => _query = const NodeGraphExplorerQuery());
  }
}

class _GraphBody extends StatelessWidget {
  const _GraphBody({
    required this.graph,
    required this.view,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onTagChanged,
    required this.onProjectChanged,
    required this.onAreaChanged,
    required this.onCrossDayChanged,
    required this.onFocusNode,
    required this.onClearFocus,
    required this.onClearFilters,
  });

  final NodeGraph graph;
  final NodeGraphExplorerView view;
  final ValueChanged<NodeType> onTypeChanged;
  final ValueChanged<NodeStatus> onStatusChanged;
  final ValueChanged<NodePriority> onPriorityChanged;
  final ValueChanged<String> onTagChanged;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onAreaChanged;
  final ValueChanged<bool> onCrossDayChanged;
  final ValueChanged<String> onFocusNode;
  final VoidCallback onClearFocus;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final spacing = MediaQuery.sizeOf(context).width < 720 ? 12.0 : 16.0;
    final nodes = [for (final node in graph.nodes) node.node];
    final tags = _availableTags(nodes);
    final workspaceContexts = WorkspaceContexts.fromNodes(nodes).contexts;

    return SingleChildScrollView(
      padding: EdgeInsets.all(spacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GraphFilterBand(
            query: view.query,
            focusedNode: view.focusedNode,
            tags: tags,
            workspaceContexts: workspaceContexts,
            onTypeChanged: onTypeChanged,
            onStatusChanged: onStatusChanged,
            onPriorityChanged: onPriorityChanged,
            onTagChanged: onTagChanged,
            onProjectChanged: onProjectChanged,
            onAreaChanged: onAreaChanged,
            onCrossDayChanged: onCrossDayChanged,
            onClearFocus: onClearFocus,
            onClearFilters: onClearFilters,
          ),
          SizedBox(height: spacing),
          _GraphMetricRail(
            children: [
              _GraphMetricPill(
                icon: Icons.hub_outlined,
                label: _countLabel(view.visibleNodes.length, 'node'),
              ),
              _GraphMetricPill(
                icon: Icons.link_outlined,
                label: _countLabel(view.edgeCount, 'link'),
              ),
              _GraphMetricPill(
                icon: Icons.calendar_month_outlined,
                label: '${view.crossDayEdgeCount} cross-day',
              ),
              if (view.activeFilterCount > 0)
                _GraphMetricPill(
                  icon: Icons.manage_search,
                  label: _countLabel(view.matchingNodeCount, 'match'),
                ),
              if (view.activeFilterCount > 0)
                _GraphMetricPill(
                  icon: Icons.filter_alt_outlined,
                  label: _countLabel(view.activeFilterCount, 'filter'),
                ),
            ],
          ),
          SizedBox(height: spacing),
          DefaultTabController(
            length: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.hub_outlined), text: 'Visual Network'),
                    Tab(
                      icon: Icon(Icons.list_alt_outlined),
                      text: 'Explorer List',
                    ),
                  ],
                ),
                SizedBox(height: spacing),
                SizedBox(
                  height: 600,
                  child: TabBarView(
                    children: [
                      VisualGraphView(
                        nodes: view.visibleNodes,
                        edges: view.visibleEdges,
                        onNodeTapped: (graphNode) {
                          goToDay(
                            context,
                            graphNode.node.day,
                            highlightNodeId: graphNode.id,
                          );
                        },
                      ),
                      SingleChildScrollView(
                        child: Column(
                          children: [
                            if (view.focusedNeighborhood != null) ...[
                              _GraphNeighborhoodPanel(
                                neighborhood: view.focusedNeighborhood!,
                              ),
                              SizedBox(height: spacing),
                            ],
                            _GraphSection(
                              title: 'Hubs',
                              child: view.visibleHubs.isEmpty
                                  ? const _GraphEmptyState(
                                      message: 'No connected hubs in this view',
                                    )
                                  : Column(
                                      children: [
                                        for (
                                          var index = 0;
                                          index < view.visibleHubs.length;
                                          index++
                                        ) ...[
                                          if (index > 0)
                                            const SizedBox(height: 8),
                                          _GraphHubTile(
                                            node: view.visibleHubs[index],
                                            onFocus: onFocusNode,
                                          ),
                                        ],
                                      ],
                                    ),
                            ),
                            SizedBox(height: spacing),
                            _GraphSection(
                              title: 'Links',
                              child: view.visibleEdges.isEmpty
                                  ? const _GraphEmptyState(
                                      message: 'No links in this view',
                                    )
                                  : Column(
                                      children: [
                                        for (
                                          var index = 0;
                                          index < view.visibleEdges.length;
                                          index++
                                        ) ...[
                                          if (index > 0)
                                            const SizedBox(height: 8),
                                          _GraphEdgeTile(
                                            graph: graph,
                                            edge: view.visibleEdges[index],
                                          ),
                                        ],
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphFilterBand extends StatelessWidget {
  const _GraphFilterBand({
    required this.query,
    required this.focusedNode,
    required this.tags,
    required this.workspaceContexts,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onTagChanged,
    required this.onProjectChanged,
    required this.onAreaChanged,
    required this.onCrossDayChanged,
    required this.onClearFocus,
    required this.onClearFilters,
  });

  final NodeGraphExplorerQuery query;
  final NodeGraphNode? focusedNode;
  final List<String> tags;
  final List<WorkspaceContext> workspaceContexts;
  final ValueChanged<NodeType> onTypeChanged;
  final ValueChanged<NodeStatus> onStatusChanged;
  final ValueChanged<NodePriority> onPriorityChanged;
  final ValueChanged<String> onTagChanged;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onAreaChanged;
  final ValueChanged<bool> onCrossDayChanged;
  final VoidCallback onClearFocus;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in NodeType.values)
                  FilterChip(
                    key: ValueKey('graph-type-${type.name}'),
                    label: Text(type.label),
                    selected: query.typeFilter == type,
                    onSelected: (_) => onTypeChanged(type),
                  ),
                FilterChip(
                  key: const ValueKey('graph-cross-day-only'),
                  label: const Text('Cross-day only'),
                  selected: query.crossDayOnly,
                  onSelected: onCrossDayChanged,
                ),
                for (final workspaceContext in workspaceContexts)
                  if (workspaceContext.type != WorkspaceContextType.daily)
                    FilterChip(
                      key: ValueKey(
                        'graph-${workspaceContext.type.name}-${workspaceContextKey(workspaceContext.name)}',
                      ),
                      label: Text(
                        '${workspaceContext.type.label} ${workspaceContext.name}',
                      ),
                      selected: switch (workspaceContext.type) {
                        WorkspaceContextType.project =>
                          query.projectFilter == workspaceContext.name,
                        WorkspaceContextType.area =>
                          query.areaFilter == workspaceContext.name,
                        WorkspaceContextType.daily => false,
                      },
                      onSelected: (_) {
                        switch (workspaceContext.type) {
                          case WorkspaceContextType.project:
                            onProjectChanged(workspaceContext.name);
                            break;
                          case WorkspaceContextType.area:
                            onAreaChanged(workspaceContext.name);
                            break;
                          case WorkspaceContextType.daily:
                            break;
                        }
                      },
                    ),
                for (final tag in tags)
                  FilterChip(
                    key: ValueKey('graph-tag-${workspaceContextKey(tag)}'),
                    label: Text('#$tag'),
                    selected: query.tagFilter == tag,
                    onSelected: (_) => onTagChanged(tag),
                  ),
                for (final priority in NodePriority.values)
                  if (priority != NodePriority.none)
                    FilterChip(
                      key: ValueKey('graph-priority-${priority.name}'),
                      label: Text('Priority ${priority.label}'),
                      selected: query.priorityFilter == priority,
                      onSelected: (_) => onPriorityChanged(priority),
                    ),
                for (final status in NodeStatus.values)
                  FilterChip(
                    key: ValueKey('graph-status-${status.name}'),
                    label: Text('Status ${status.label}'),
                    selected: query.statusFilter == status,
                    onSelected: (_) => onStatusChanged(status),
                  ),
                if (query.activeFilterCount > 0)
                  ActionChip(
                    key: const ValueKey('graph-clear-filters'),
                    avatar: const Icon(Icons.close, size: 16),
                    label: const Text('Clear'),
                    onPressed: onClearFilters,
                  ),
              ],
            ),
            if (focusedNode != null) ...[
              const SizedBox(height: 8),
              InputChip(
                key: const ValueKey('graph-focus-chip'),
                avatar: const Icon(Icons.center_focus_strong, size: 16),
                label: Text('Neighborhood: ${focusedNode!.node.title}'),
                onDeleted: onClearFocus,
                deleteIcon: const Icon(
                  Icons.close,
                  key: ValueKey('graph-clear-focus'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GraphSection extends StatelessWidget {
  const _GraphSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _GraphNeighborhoodPanel extends StatelessWidget {
  const _GraphNeighborhoodPanel({required this.neighborhood});

  final NodeGraphNeighborhood neighborhood;

  @override
  Widget build(BuildContext context) {
    return _GraphSection(
      title: 'Neighborhood',
      child: Column(
        key: const ValueKey('graph-neighborhood-panel'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(_nodeIcon(neighborhood.focusedNode.node.type)),
            title: Text(neighborhood.focusedNode.node.title),
            subtitle: Text(
              _countLabel(neighborhood.totalConnectionCount, 'connection'),
            ),
          ),
          const SizedBox(height: 8),
          _GraphNeighborhoodGroup(
            title: 'Related out',
            countLabel: _relationCountLabel(
              neighborhood.relatedCount,
              singular: 'related',
              plural: 'related',
            ),
            emptyMessage: 'No outgoing related nodes',
            keyPrefix: 'graph-neighborhood-related',
            nodes: neighborhood.relatedNodes,
          ),
          const SizedBox(height: 12),
          _GraphNeighborhoodGroup(
            title: 'Backlinks in',
            countLabel: _relationCountLabel(
              neighborhood.backlinkCount,
              singular: 'backlink',
              plural: 'backlinks',
            ),
            emptyMessage: 'No backlinks into this node',
            keyPrefix: 'graph-neighborhood-backlink',
            nodes: neighborhood.backlinkNodes,
          ),
        ],
      ),
    );
  }
}

class _GraphNeighborhoodGroup extends StatelessWidget {
  const _GraphNeighborhoodGroup({
    required this.title,
    required this.countLabel,
    required this.emptyMessage,
    required this.keyPrefix,
    required this.nodes,
  });

  final String title;
  final String countLabel;
  final String emptyMessage;
  final String keyPrefix;
  final List<NodeGraphNode> nodes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            Chip(label: Text(countLabel)),
          ],
        ),
        const SizedBox(height: 8),
        if (nodes.isEmpty)
          Text(emptyMessage, style: theme.textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final node in nodes)
                ActionChip(
                  key: ValueKey('$keyPrefix-${node.id}'),
                  avatar: Icon(_nodeIcon(node.node.type), size: 16),
                  label: Text(node.node.title),
                  onPressed: () =>
                      goToDay(context, node.node.day, highlightNodeId: node.id),
                ),
            ],
          ),
      ],
    );
  }
}

class _GraphHubTile extends StatelessWidget {
  const _GraphHubTile({required this.node, required this.onFocus});

  final NodeGraphNode node;
  final ValueChanged<String> onFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      key: ValueKey('graph-hub-${node.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        _nodeIcon(node.node.type),
        color: theme.colorScheme.primary,
      ),
      title: Text(
        node.node.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_countLabel(node.totalDegree, 'connection')),
          Text('${node.incomingCount} in - ${node.outgoingCount} out'),
        ],
      ),
      trailing: SizedBox(
        width: 96,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              key: ValueKey('graph-focus-node-${node.id}'),
              tooltip: 'Focus node',
              icon: const Icon(Icons.center_focus_strong),
              onPressed: () => onFocus(node.id),
            ),
            IconButton(
              tooltip: 'Open node',
              icon: const Icon(Icons.open_in_new),
              onPressed: () =>
                  goToDay(context, node.node.day, highlightNodeId: node.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphEdgeTile extends StatelessWidget {
  const _GraphEdgeTile({required this.graph, required this.edge});

  final NodeGraph graph;
  final NodeGraphEdge edge;

  @override
  Widget build(BuildContext context) {
    final source = graph.nodeFor(edge.sourceId)?.node;
    final target = graph.nodeFor(edge.targetId)?.node;
    final theme = Theme.of(context);
    if (source == null || target == null) return const SizedBox.shrink();

    return ListTile(
      key: ValueKey('graph-edge-${edge.sourceId}-${edge.targetId}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.account_tree_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        '${source.title} -> ${target.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${dayKey(source.day)} -> ${dayKey(target.day)}'),
      trailing: edge.isCrossDay
          ? const Chip(label: Text('Cross-day'))
          : const Chip(label: Text('Same day')),
      onTap: () => goToDay(context, target.day, highlightNodeId: target.id),
    );
  }
}

class _GraphMetricRail extends StatelessWidget {
  const _GraphMetricRail({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: 10),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _GraphMetricPill extends StatelessWidget {
  const _GraphMetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _GraphEmptyState extends StatelessWidget {
  const _GraphEmptyState({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text('No connections yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message ?? 'Create related nodes to build your graph',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

List<String> _availableTags(List<MindmapNode> nodes) {
  final tags = <String>{};
  for (final node in nodes) {
    tags.addAll(node.tags);
  }
  return tags.toList()..sort();
}

IconData _nodeIcon(NodeType type) => switch (type) {
  NodeType.task => Icons.check_circle_outline,
  NodeType.kanban => Icons.view_kanban_outlined,
  NodeType.plan => Icons.route_outlined,
  NodeType.note => Icons.notes_outlined,
  NodeType.journal => Icons.book_outlined,
  NodeType.habit => Icons.repeat_outlined,
  NodeType.goal => Icons.flag_outlined,
  NodeType.link => Icons.link_outlined,
  NodeType.empty => Icons.crop_square_outlined,
};

String _countLabel(int count, String singular) {
  if (singular == 'match') return '$count ${count == 1 ? 'match' : 'matches'}';
  return '$count $singular${count == 1 ? '' : 's'}';
}

String _relationCountLabel(
  int count, {
  required String singular,
  required String plural,
}) {
  return '$count ${count == 1 ? singular : plural}';
}

class VisualGraphView extends StatefulWidget {
  const VisualGraphView({
    required this.nodes,
    required this.edges,
    required this.onNodeTapped,
    super.key,
  });

  final List<NodeGraphNode> nodes;
  final List<NodeGraphEdge> edges;
  final ValueChanged<NodeGraphNode> onNodeTapped;

  @override
  State<VisualGraphView> createState() => _VisualGraphViewState();
}

class _VisualGraphViewState extends State<VisualGraphView> {
  final Map<String, Offset> _positions = {};
  final TransformationController _transformationController =
      TransformationController();
  String? _hoveredNodeId;

  @override
  void initState() {
    super.initState();
    _computeLayout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerGraph();
    });
  }

  @override
  void didUpdateWidget(covariant VisualGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodes.length != widget.nodes.length ||
        oldWidget.edges.length != widget.edges.length) {
      _computeLayout();
    }
  }

  void _centerGraph() {
    final viewportSize = context.size;
    if (viewportSize == null) return;

    final tx = (viewportSize.width - 1200.0) / 2;
    final ty = (viewportSize.height - 800.0) / 2;

    _transformationController.value = Matrix4.translationValues(tx, ty, 0);
  }

  void _computeLayout() {
    if (widget.nodes.isEmpty) return;

    final random = math.Random(42);

    const width = 1200.0;
    const height = 800.0;
    const center = Offset(width / 2, height / 2);
    final radius = math.min(width, height) * 0.35;

    for (var i = 0; i < widget.nodes.length; i++) {
      final node = widget.nodes[i];
      if (!_positions.containsKey(node.id)) {
        final angle = (i * 2.0 * math.pi) / widget.nodes.length;
        _positions[node.id] =
            center +
            Offset(
              radius * math.cos(angle) + (random.nextDouble() - 0.5) * 30,
              radius * math.sin(angle) + (random.nextDouble() - 0.5) * 30,
            );
      }
    }

    const iterations = 100;
    const area = width * height;
    final k = math.sqrt(area / widget.nodes.length) * 0.85;

    final currentPositions = Map<String, Offset>.from(_positions);

    for (var iter = 0; iter < iterations; iter++) {
      final forces = <String, Offset>{
        for (final node in widget.nodes) node.id: Offset.zero,
      };

      for (var i = 0; i < widget.nodes.length; i++) {
        final nodeA = widget.nodes[i];
        final posA = currentPositions[nodeA.id]!;

        for (var j = i + 1; j < widget.nodes.length; j++) {
          final nodeB = widget.nodes[j];
          final posB = currentPositions[nodeB.id]!;

          final delta = posA - posB;
          final distance = delta.distance;
          if (distance < 1.0) continue;

          final forceMag = (k * k) / distance;
          final forceVec = (delta / distance) * forceMag;

          forces[nodeA.id] = forces[nodeA.id]! + forceVec;
          forces[nodeB.id] = forces[nodeB.id]! - forceVec;
        }
      }

      for (final edge in widget.edges) {
        final posA = currentPositions[edge.sourceId];
        final posB = currentPositions[edge.targetId];
        if (posA == null || posB == null) continue;

        final delta = posA - posB;
        final distance = delta.distance;
        if (distance < 1.0) continue;

        final forceMag = (distance * distance) / k;
        final forceVec = (delta / distance) * forceMag;

        forces[edge.sourceId] = forces[edge.sourceId]! - forceVec;
        forces[edge.targetId] = forces[edge.targetId]! + forceVec;
      }

      final temp = (iterations - iter) / iterations * 20.0;
      for (final node in widget.nodes) {
        final force = forces[node.id]!;
        final forceDist = force.distance;
        if (forceDist < 0.1) continue;

        final cappedForce = (force / forceDist) * math.min(forceDist, temp);
        var newPos = currentPositions[node.id]! + cappedForce;

        newPos = Offset(
          newPos.dx.clamp(40.0, width - 40.0),
          newPos.dy.clamp(40.0, height - 40.0),
        );
        currentPositions[node.id] = newPos;
      }
    }

    _positions.addAll(currentPositions);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          InteractiveViewer(
            transformationController: _transformationController,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(400),
            minScale: 0.4,
            maxScale: 2.0,
            child: SizedBox(
              width: 1200,
              height: 800,
              child: GestureDetector(
                onTapUp: (details) {
                  final renderBox = context.findRenderObject() as RenderBox?;
                  if (renderBox != null) {
                    final localOffset = renderBox.globalToLocal(
                      details.globalPosition,
                    );
                    final sceneOffset = _transformationController.toScene(
                      localOffset,
                    );

                    for (final node in widget.nodes) {
                      final pos = _positions[node.id]!;
                      if ((sceneOffset - pos).distance <= 28.0) {
                        widget.onNodeTapped(node);
                        break;
                      }
                    }
                  }
                },
                child: MouseRegion(
                  onHover: (event) {
                    final sceneOffset = _transformationController.toScene(
                      event.localPosition,
                    );
                    String? newHoverId;
                    for (final node in widget.nodes) {
                      final pos = _positions[node.id]!;
                      if ((sceneOffset - pos).distance <= 28.0) {
                        newHoverId = node.id;
                        break;
                      }
                    }
                    if (newHoverId != _hoveredNodeId) {
                      setState(() {
                        _hoveredNodeId = newHoverId;
                      });
                    }
                  },
                  onExit: (_) {
                    setState(() {
                      _hoveredNodeId = null;
                    });
                  },
                  child: CustomPaint(
                    painter: _VisualGraphPainter(
                      nodes: widget.nodes,
                      edges: widget.edges,
                      positions: _positions,
                      hoveredNodeId: _hoveredNodeId,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Card(
              color: theme.colorScheme.surface.withValues(alpha: 0.8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Drag to pan, pinch to zoom, tap node to open',
                      style: TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisualGraphPainter extends CustomPainter {
  _VisualGraphPainter({
    required this.nodes,
    required this.edges,
    required this.positions,
    required this.hoveredNodeId,
  });

  final List<NodeGraphNode> nodes;
  final List<NodeGraphEdge> edges;
  final Map<String, Offset> positions;
  final String? hoveredNodeId;

  @override
  void paint(Canvas canvas, Size size) {
    final Map<String, NodeGraphNode> nodeMap = {for (final n in nodes) n.id: n};

    final Set<String> hoveredNeighbors = {};
    if (hoveredNodeId != null) {
      for (final edge in edges) {
        if (edge.sourceId == hoveredNodeId) hoveredNeighbors.add(edge.targetId);
        if (edge.targetId == hoveredNodeId) hoveredNeighbors.add(edge.sourceId);
      }
    }

    for (final edge in edges) {
      final pA = positions[edge.sourceId];
      final pB = positions[edge.targetId];
      if (pA == null || pB == null) continue;

      final nodeA = nodeMap[edge.sourceId];
      final nodeB = nodeMap[edge.targetId];
      if (nodeA == null || nodeB == null) continue;

      final isHighlighted =
          hoveredNodeId != null &&
          (edge.sourceId == hoveredNodeId || edge.targetId == hoveredNodeId);

      final colorA = nodeColor(nodeA.node.type);
      final colorB = nodeColor(nodeB.node.type);

      final baseAlpha = isHighlighted
          ? 0.9
          : (hoveredNodeId != null ? 0.05 : 0.4);

      final paint = Paint()
        ..strokeWidth = isHighlighted ? 2.5 : 1.2
        ..style = PaintingStyle.stroke;

      paint.shader = ui.Gradient.linear(pA, pB, [
        colorA.withValues(alpha: baseAlpha),
        colorB.withValues(alpha: baseAlpha),
      ]);

      if (edge.isCrossDay) {
        _drawDashedLine(canvas, pA, pB, paint);
      } else {
        canvas.drawLine(pA, pB, paint);
      }

      // Draw directed arrowhead pointing from A to B
      final direction = pB - pA;
      final distance = direction.distance;
      if (distance > 36.0) {
        final unitDir = direction / distance;
        final arrowPoint =
            pB - unitDir * 19.0; // just outside target node (radius 18)

        const arrowSize = 6.0;
        const angle = math.pi / 6; // 30 degrees
        final cosA = math.cos(angle);
        final sinA = math.sin(angle);

        final leftDir = Offset(
          unitDir.dx * cosA - unitDir.dy * sinA,
          unitDir.dx * sinA + unitDir.dy * cosA,
        );
        final rightDir = Offset(
          unitDir.dx * cosA - unitDir.dy * -sinA,
          unitDir.dx * -sinA + unitDir.dy * cosA,
        );

        final leftPoint = arrowPoint - leftDir * arrowSize;
        final rightPoint = arrowPoint - rightDir * arrowSize;

        final arrowPaint = Paint()
          ..color = colorB.withValues(
            alpha: isHighlighted ? 0.9 : (hoveredNodeId != null ? 0.05 : 0.4),
          )
          ..strokeWidth = isHighlighted ? 2.5 : 1.2
          ..style = PaintingStyle.stroke;

        canvas.drawLine(arrowPoint, leftPoint, arrowPaint);
        canvas.drawLine(arrowPoint, rightPoint, arrowPaint);
      }
    }

    for (final node in nodes) {
      final pos = positions[node.id];
      if (pos == null) continue;

      final isHovered = node.id == hoveredNodeId;
      final isNeighbor = hoveredNeighbors.contains(node.id);
      final fade = hoveredNodeId != null && !isHovered && !isNeighbor;
      final opacityMultiplier = fade ? 0.25 : 1.0;

      final color = nodeColor(node.node.type);

      if (isHovered) {
        canvas.drawCircle(
          pos,
          28.0,
          Paint()
            ..color = color.withValues(alpha: 0.4 * opacityMultiplier)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }

      canvas.drawCircle(
        pos,
        18.0,
        Paint()
          ..color = color.withValues(alpha: 0.8 * opacityMultiplier)
          ..style = PaintingStyle.fill,
      );

      canvas.drawCircle(
        pos,
        18.0,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7 * opacityMultiplier)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHovered ? 2.0 : 1.0,
      );

      final iconStr = String.fromCharCode(nodeIcon(node.node.type).codePoint);
      final iconPainter = TextPainter(
        text: TextSpan(
          text: iconStr,
          style: TextStyle(
            fontFamily: 'MaterialIcons',
            fontSize: 18.0,
            color: Colors.white.withValues(alpha: opacityMultiplier),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      iconPainter.paint(
        canvas,
        Offset(pos.dx - iconPainter.width / 2, pos.dy - iconPainter.height / 2),
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: node.node.title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: opacityMultiplier),
            fontSize: isHovered ? 12.0 : 10.0,
            fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: opacityMultiplier),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: 120);

      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2, pos.dy + 24.0),
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    final double dashCount = (distance / (dashWidth + dashSpace))
        .floorToDouble();
    if (dashCount <= 0) {
      canvas.drawLine(p1, p2, paint);
      return;
    }
    final xStep = dx / dashCount;
    final yStep = dy / dashCount;

    for (var i = 0; i < dashCount; i++) {
      final start = Offset(p1.dx + xStep * i, p1.dy + yStep * i);
      final end = Offset(
        p1.dx + xStep * i + (xStep * dashWidth / (dashWidth + dashSpace)),
        p1.dy + yStep * i + (yStep * dashWidth / (dashWidth + dashSpace)),
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VisualGraphPainter oldDelegate) {
    return oldDelegate.hoveredNodeId != hoveredNodeId ||
        oldDelegate.nodes.length != nodes.length ||
        oldDelegate.edges.length != edges.length;
  }
}

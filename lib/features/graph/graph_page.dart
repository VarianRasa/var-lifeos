/// Dedicated graph view for node relations and backlinks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/layout/adaptive_scaffold.dart';
import '../../shared/widgets/doodle_border.dart';
import '../../shared/widgets/error_message.dart';
import '../../shared/widgets/search_field.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/node_graph.dart';
import '../mindmap/domain/workspace_context.dart';
import '../mindmap/presentation/mindmap_canvas.dart';
import 'application/context_graph.dart';
import 'application/goal_dependency_graph.dart';
import 'application/graph_filters.dart';
import 'application/graph_markdown_export.dart';
import 'application/graph_overview.dart';
import 'application/graph_relation_suggestions.dart';
import 'application/graph_relationship_insights.dart';
import 'application/graph_risk_overlay.dart';
import 'domain/node_graph_explorer.dart';

class GraphPage extends ConsumerStatefulWidget {
  const GraphPage({super.key});

  @override
  ConsumerState<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends ConsumerState<GraphPage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  NodeGraphExplorerQuery _query = const NodeGraphExplorerQuery();
  ContextGraphMode _contextMode = ContextGraphMode.nodes;
  List<_GraphSavedFilter> _savedFilters = const [];

  Uri? _lastFilterUri;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedFilters());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final uri = GoRouterState.of(context).uri;
      if (_lastFilterUri == uri) return;
      _lastFilterUri = uri;
      final project = uri.queryParameters['project'];
      final area = uri.queryParameters['area'];
      _query = _query.copyWith(
        projectFilter: project,
        clearProjectFilter: project == null,
        areaFilter: project == null ? area : null,
        clearAreaFilter: project != null || area == null,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(nodeGraphProvider);
    return Scaffold(
      appBar: AppBar(
        title: const AppRouteChromeTabs(currentRoute: AppRoute.graph),
        actions: [
          SearchField(
            key: const ValueKey('graph-search-field'),
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: 'Search graph...',
            onChanged: _changeSearchQuery,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: graph.when(
        data: (value) {
          if (value.nodes.isEmpty) return const _GraphEmptyState();
          final view = NodeGraphExplorerView.fromGraph(value, query: _query);
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.slash): () {
                _searchFocusNode.requestFocus();
              },
              const SingleActivator(LogicalKeyboardKey.escape): _clearFilters,
              const SingleActivator(LogicalKeyboardKey.keyC): () {
                _changeRelationState(GraphRelationState.connected);
              },
              const SingleActivator(LogicalKeyboardKey.keyR): _clearFilters,
              const SingleActivator(LogicalKeyboardKey.keyF): () {
                if (view.visibleNodes.isNotEmpty) {
                  _focusNode(view.visibleNodes.first.id);
                }
              },
            },
            child: Focus(
              autofocus: true,
              child: _GraphBody(
                graph: value,
                view: view,
                onTypeChanged: _changeTypeFilter,
                onStatusChanged: _changeStatusFilter,
                onPriorityChanged: _changePriorityFilter,
                onTagChanged: _changeTagFilter,
                onProjectChanged: _changeProjectFilter,
                onAreaChanged: _changeAreaFilter,
                onRelationLabelChanged: _changeRelationLabelFilter,
                onCrossDayChanged: _changeCrossDayOnly,
                onRelationStateChanged: _changeRelationState,
                onContextModeChanged: _changeContextMode,
                onExportReport: _exportReport,
                contextMode: _contextMode,
                onFocusNode: _focusNode,
                onClearFocus: _clearFocus,
                onClearFilters: _clearFilters,
                onRelationLabelEdited: _editRelationLabel,
                savedFilters: _savedFilters,
                onSaveFilter: _saveCurrentFilter,
                onApplyFilter: _applySavedFilter,
                onDeleteFilter: _deleteSavedFilter,
                onRenameFilter: _renameSavedFilter,
                onDuplicateFilter: _duplicateSavedFilter,
                onExportFilters: _exportSavedFilters,
                onImportFilters: _importSavedFilters,
              ),
            ),
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

  Future<void> _loadSavedFilters() async {
    final raw = await _preferences.getString('graph_saved_filters');
    final pendingRaw = await _preferences.getString('graph_pending_filter');
    await _preferences.remove('graph_pending_filter');
    final pending = _GraphSavedFilter.fromRawQuery(pendingRaw);
    if (!mounted) return;
    setState(() {
      _savedFilters = _decodeGraphSavedFilters(raw);
      if (pending != null) {
        _query = pending.query;
        _searchController.text = pending.query.searchQuery;
      }
    });
  }

  Future<void> _persistSavedFilters(List<_GraphSavedFilter> filters) async {
    await _preferences.setString(
      'graph_saved_filters',
      jsonEncode([for (final filter in filters) filter.toJson()]),
    );
    if (mounted) setState(() => _savedFilters = filters);
  }

  Future<void> _saveCurrentFilter() async {
    final controller = TextEditingController(text: 'Graph view');
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save graph filter'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Filter name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.isEmpty) return;
    await _persistSavedFilters([
      ..._savedFilters,
      _GraphSavedFilter(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: label,
        query: _query,
      ),
    ]);
  }

  void _applySavedFilter(_GraphSavedFilter filter) {
    _searchController.text = filter.query.searchQuery;
    setState(() => _query = filter.query);
  }

  Future<void> _renameSavedFilter(_GraphSavedFilter filter) async {
    final controller = TextEditingController(text: filter.label);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename graph filter'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Filter name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.isEmpty) return;
    await _persistSavedFilters([
      for (final item in _savedFilters)
        item.id == filter.id
            ? _GraphSavedFilter(id: item.id, label: label, query: item.query)
            : item,
    ]);
  }

  Future<void> _duplicateSavedFilter(_GraphSavedFilter filter) async {
    await _persistSavedFilters([
      ..._savedFilters,
      _GraphSavedFilter(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: '${filter.label} copy',
        query: filter.query,
      ),
    ]);
  }

  Future<void> _deleteSavedFilter(String id) async {
    await _persistSavedFilters([
      for (final filter in _savedFilters)
        if (filter.id != id) filter,
    ]);
  }

  Future<void> _exportSavedFilters() async {
    await Clipboard.setData(
      ClipboardData(
        text: jsonEncode([for (final filter in _savedFilters) filter.toJson()]),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${_savedFilters.length} graph filters')),
    );
  }

  Future<void> _importSavedFilters() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import graph filters'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Graph filters JSON',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw == null || raw.isEmpty) return;
    try {
      final imported = _decodeGraphSavedFilters(raw);
      final merged = <String, _GraphSavedFilter>{
        for (final filter in _savedFilters) filter.id: filter,
        for (final filter in imported) filter.id: filter,
      };
      await _persistSavedFilters(merged.values.toList(growable: false));
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid graph filters JSON')),
      );
    }
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

  void _changeRelationLabelFilter(String label) {
    setState(() {
      _query = _query.relationLabelFilter == label
          ? _query.copyWith(clearRelationLabelFilter: true)
          : _query.copyWith(relationLabelFilter: label);
    });
  }

  void _changeCrossDayOnly(bool value) {
    setState(() => _query = _query.copyWith(crossDayOnly: value));
  }

  void _changeRelationState(GraphRelationState state) {
    setState(() {
      _query = _query.relationState == state
          ? _query.copyWith(clearRelationState: true)
          : _query.copyWith(relationState: state);
    });
  }

  void _changeContextMode(ContextGraphMode mode) {
    setState(() => _contextMode = mode);
  }

  Future<void> _exportReport(String markdown) async {
    await Clipboard.setData(ClipboardData(text: markdown));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Graph report copied')));
  }

  void _focusNode(String nodeId) {
    setState(() => _query = _query.copyWith(focusedNodeId: nodeId));
  }

  void _clearFocus() {
    setState(() => _query = _query.copyWith(clearFocus: true));
  }

  Future<void> _editRelationLabel(
    MindmapNode source,
    String targetId,
    String label,
  ) async {
    final relations = [
      for (final relation
          in source.data['relations'] as List<Object?>? ?? const [])
        if (relation case final Map<Object?, Object?> map)
          <String, Object?>{
            'targetId': map['targetId']?.toString() ?? '',
            'label': map['targetId']?.toString() == targetId
                ? label
                : map['label']?.toString() ?? 'relates to',
          },
    ];
    final hasRelation = relations.any(
      (relation) => relation['targetId'] == targetId,
    );
    if (!hasRelation) {
      relations.add(<String, Object?>{'targetId': targetId, 'label': label});
    }
    final updated = source.copyWith(
      data: <String, Object?>{...source.data, 'relations': relations},
      updatedAt: DateTime.now(),
    );
    await ref.read(mindmapRepositoryProvider).saveNode(updated);
    invalidateMindmapState(ref, day: source.day);
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() => _query = const NodeGraphExplorerQuery());
  }
}

final class _GraphSavedFilter {
  const _GraphSavedFilter({
    required this.id,
    required this.label,
    required this.query,
  });

  final String id;
  final String label;
  final NodeGraphExplorerQuery query;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'searchQuery': query.searchQuery,
    'typeFilter': query.typeFilter?.name,
    'statusFilter': query.statusFilter?.name,
    'priorityFilter': query.priorityFilter?.name,
    'tagFilter': query.tagFilter,
    'projectFilter': query.projectFilter,
    'areaFilter': query.areaFilter,
    'relationLabelFilter': query.relationLabelFilter,
    'relationState': query.relationState?.name,
    'crossDayOnly': query.crossDayOnly,
  };

  static _GraphSavedFilter? fromRawQuery(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      return _GraphSavedFilter.fromJson({
        'id': 'pending',
        'label': 'Pending',
        ...decoded,
      });
    } on FormatException {
      return null;
    }
  }

  static _GraphSavedFilter? fromJson(Object? value) {
    if (value case final Map<String, Object?> map) {
      final id = map['id']?.toString() ?? '';
      final label = map['label']?.toString() ?? '';
      if (id.isEmpty || label.isEmpty) return null;
      return _GraphSavedFilter(
        id: id,
        label: label,
        query: NodeGraphExplorerQuery(
          searchQuery: map['searchQuery']?.toString() ?? '',
          typeFilter: _enumByName(
            NodeType.values,
            map['typeFilter']?.toString(),
          ),
          statusFilter: _enumByName(
            NodeStatus.values,
            map['statusFilter']?.toString(),
          ),
          priorityFilter: _enumByName(
            NodePriority.values,
            map['priorityFilter']?.toString(),
          ),
          tagFilter: map['tagFilter']?.toString(),
          projectFilter: map['projectFilter']?.toString(),
          areaFilter: map['areaFilter']?.toString(),
          relationLabelFilter: map['relationLabelFilter']?.toString(),
          relationState: _enumByName(
            GraphRelationState.values,
            map['relationState']?.toString(),
          ),
          crossDayOnly: map['crossDayOnly'] == true,
        ),
      );
    }
    return null;
  }
}

List<_GraphSavedFilter> _decodeGraphSavedFilters(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) return const [];
    return decoded
        .map(_GraphSavedFilter.fromJson)
        .nonNulls
        .toList(growable: false);
  } on FormatException {
    return const [];
  }
}

T? _enumByName<T extends Enum>(Iterable<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
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
    required this.onRelationLabelChanged,
    required this.onCrossDayChanged,
    required this.onRelationStateChanged,
    required this.onContextModeChanged,
    required this.onExportReport,
    required this.contextMode,
    required this.onFocusNode,
    required this.onClearFocus,
    required this.onClearFilters,
    required this.onRelationLabelEdited,
    required this.savedFilters,
    required this.onSaveFilter,
    required this.onApplyFilter,
    required this.onDeleteFilter,
    required this.onRenameFilter,
    required this.onDuplicateFilter,
    required this.onExportFilters,
    required this.onImportFilters,
  });

  final NodeGraph graph;
  final NodeGraphExplorerView view;
  final ValueChanged<NodeType> onTypeChanged;
  final ValueChanged<NodeStatus> onStatusChanged;
  final ValueChanged<NodePriority> onPriorityChanged;
  final ValueChanged<String> onTagChanged;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onAreaChanged;
  final ValueChanged<String> onRelationLabelChanged;
  final ValueChanged<bool> onCrossDayChanged;
  final ValueChanged<GraphRelationState> onRelationStateChanged;
  final ValueChanged<ContextGraphMode> onContextModeChanged;
  final ValueChanged<String> onExportReport;
  final ContextGraphMode contextMode;
  final ValueChanged<String> onFocusNode;
  final VoidCallback onClearFocus;
  final VoidCallback onClearFilters;
  final Future<void> Function(MindmapNode source, String targetId, String label)
  onRelationLabelEdited;
  final List<_GraphSavedFilter> savedFilters;
  final Future<void> Function() onSaveFilter;
  final ValueChanged<_GraphSavedFilter> onApplyFilter;
  final Future<void> Function(String id) onDeleteFilter;
  final Future<void> Function(_GraphSavedFilter filter) onRenameFilter;
  final Future<void> Function(_GraphSavedFilter filter) onDuplicateFilter;
  final Future<void> Function() onExportFilters;
  final Future<void> Function() onImportFilters;

  @override
  Widget build(BuildContext context) {
    final spacing = MediaQuery.sizeOf(context).width < 720 ? 12.0 : 16.0;
    final nodes = [for (final node in graph.nodes) node.node];
    final tags = _availableTags(nodes);
    final relationLabels = _availableRelationLabels(nodes);
    final workspaceContexts = WorkspaceContexts.fromNodes(nodes).contexts;
    final overview = buildGraphOverview(graph);
    final contexts = buildContextGraphSummary(nodes, mode: contextMode);
    final goals = buildGoalDependencyMap(graph);
    final risks = buildGraphRiskOverlay(graph);
    final suggestions = buildGraphRelationSuggestions(graph);
    final insights = buildGraphRelationshipInsights(graph);
    final report = buildGraphMarkdownReport(
      graph: graph,
      overview: overview,
      contexts: contexts,
      goals: goals,
      risks: risks,
      suggestions: suggestions,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.all(spacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GraphDashboardPanelToggle(
            children: [_GraphOverviewHud(summary: overview)],
          ),
          SizedBox(height: spacing),
          _GraphFilterBand(
            query: view.query,
            focusedNode: view.focusedNode,
            tags: tags,
            relationLabels: relationLabels,
            workspaceContexts: workspaceContexts,
            onTypeChanged: onTypeChanged,
            onStatusChanged: onStatusChanged,
            onPriorityChanged: onPriorityChanged,
            onTagChanged: onTagChanged,
            onProjectChanged: onProjectChanged,
            onAreaChanged: onAreaChanged,
            onRelationLabelChanged: onRelationLabelChanged,
            onCrossDayChanged: onCrossDayChanged,
            onRelationStateChanged: onRelationStateChanged,
            onContextModeChanged: onContextModeChanged,
            onExportReport: () => onExportReport(report),
            contextMode: contextMode,
            onClearFocus: onClearFocus,
            onClearFilters: onClearFilters,
            savedFilters: savedFilters,
            onSaveFilter: onSaveFilter,
            onApplyFilter: onApplyFilter,
            onDeleteFilter: onDeleteFilter,
            onRenameFilter: onRenameFilter,
            onDuplicateFilter: onDuplicateFilter,
            onExportFilters: onExportFilters,
            onImportFilters: onImportFilters,
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
          _GraphGuidanceStrip(
            visibleNodeCount: view.visibleNodes.length,
            edgeCount: view.edgeCount,
            activeFilterCount: view.activeFilterCount,
            focusedNode: view.focusedNode?.node.title,
            onClearFilters: view.activeFilterCount > 0 ? onClearFilters : null,
            onClearFocus: view.focusedNode == null ? null : onClearFocus,
          ),
          SizedBox(height: spacing),
          _GraphDashboardPanelToggle(
            label: 'diagnostics',
            children: [
              _GraphDiagnosticsPanel(
                insights: insights,
                contexts: contexts,
                goals: goals,
                risks: risks,
                suggestions: suggestions,
                onFocusNode: onFocusNode,
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
                                            onRelationLabelEdited:
                                                onRelationLabelEdited,
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

class _GraphDashboardPanelToggle extends StatefulWidget {
  const _GraphDashboardPanelToggle({
    required this.children,
    this.label = 'overview',
  });

  final List<Widget> children;
  final String label;

  @override
  State<_GraphDashboardPanelToggle> createState() =>
      _GraphDashboardPanelToggleState();
}

class _GraphDashboardPanelToggleState
    extends State<_GraphDashboardPanelToggle> {
  bool _showPanels = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: ValueKey('graph-${widget.label}-panels-toggle'),
            onPressed: () => setState(() => _showPanels = !_showPanels),
            icon: Icon(
              _showPanels ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
            label: Text(
              _showPanels ? 'Hide ${widget.label}' : 'Show ${widget.label}',
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _showPanels
              ? Column(
                  key: ValueKey('graph-${widget.label}-panels'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [const SizedBox(height: 12), ...widget.children],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _GraphOverviewHud extends StatelessWidget {
  const _GraphOverviewHud({required this.summary});

  final GraphOverviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: DoodleShapeBorder(
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.22)),
          radius: 28,
          wobble: 2.6,
        ),
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.26),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radar_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Map overview',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Chip(
                  avatar: Icon(
                    _healthIcon(summary.healthStatus),
                    size: 18,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  label: Text(summary.healthStatus.label),
                  backgroundColor: colorScheme.primaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _GraphOverviewCard(
                  icon: Icons.hub_outlined,
                  label: 'Total nodes',
                  value: summary.totalNodes.toString(),
                ),
                _GraphOverviewCard(
                  icon: Icons.link_outlined,
                  label: 'Relations',
                  value: summary.relationCount.toString(),
                ),
                _GraphOverviewCard(
                  icon: Icons.device_hub_outlined,
                  label: 'Connected',
                  value: summary.connectedNodes.toString(),
                ),
                _GraphOverviewCard(
                  icon: Icons.blur_off_outlined,
                  label: 'Isolated',
                  value: summary.isolatedNodes.toString(),
                ),
                _GraphOverviewCard(
                  icon: Icons.account_tree_outlined,
                  label: 'Hubs',
                  value: summary.hubNodes.toString(),
                ),
                _GraphOverviewCard(
                  icon: Icons.history_toggle_off_outlined,
                  label: 'Stale',
                  value: summary.staleNodes.toString(),
                ),
                _GraphOverviewCard(
                  icon: Icons.priority_high_outlined,
                  label: 'High priority open',
                  value: summary.highPriorityOpenNodes.toString(),
                ),
              ],
            ),
            if (!summary.hasRelations) ...[
              const SizedBox(height: 12),
              Text(
                'No relations yet. Link related nodes to build a useful map.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GraphOverviewCard extends StatelessWidget {
  const _GraphOverviewCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      width: 156,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colorScheme.surface.withValues(alpha: 0.72),
          shape: DoodleShapeBorder(
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            radius: 18,
            wobble: 1.8,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _healthIcon(GraphHealthStatus status) {
  return switch (status) {
    GraphHealthStatus.healthy => Icons.verified_outlined,
    GraphHealthStatus.sparse => Icons.grain_outlined,
    GraphHealthStatus.crowded => Icons.blur_on_outlined,
    GraphHealthStatus.atRisk => Icons.warning_amber_outlined,
  };
}

class _GraphDiagnosticsPanel extends StatelessWidget {
  const _GraphDiagnosticsPanel({
    required this.insights,
    required this.contexts,
    required this.goals,
    required this.risks,
    required this.suggestions,
    required this.onFocusNode,
  });

  final List<GraphRelationshipInsight> insights;
  final ContextGraphSummary contexts;
  final GoalDependencyMap goals;
  final Map<String, List<GraphRiskBadge>> risks;
  final List<GraphRelationSuggestion> suggestions;
  final ValueChanged<String> onFocusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _GraphDiagnosticCard(
              title: 'Relationship intel',
              icon: Icons.psychology_alt_outlined,
              children: insights.isEmpty
                  ? const [Text('No graph issues detected')]
                  : [
                      for (final insight in insights.take(5))
                        _InsightRow(insight: insight, onFocusNode: onFocusNode),
                    ],
            ),
            _GraphDiagnosticCard(
              title: 'Context clusters',
              icon: Icons.workspaces_outline,
              children: contexts.clusters.isEmpty
                  ? const [Text('Switch to project/area/tag mode')]
                  : [
                      for (final cluster in contexts.clusters.take(6))
                        Text(
                          '${cluster.name}: ${cluster.nodeCount} nodes • ${cluster.openTasks} open • ${cluster.highPriority} priority',
                        ),
                    ],
            ),
            _GraphDiagnosticCard(
              title: 'Goal dependencies',
              icon: Icons.flag_outlined,
              children: goals.goals.isEmpty
                  ? const [Text('No goal anchors yet')]
                  : [
                      for (final goal in goals.goals.take(5))
                        Text(
                          '${goal.goal.title}: ${(goal.progress * 100).round()}% • ${goal.dependencies.length} deps${goal.missingNextAction ? ' • needs next action' : ''}',
                        ),
                    ],
            ),
            _GraphDiagnosticCard(
              title: 'Risk overlay',
              icon: Icons.warning_amber_outlined,
              children: risks.isEmpty
                  ? const [Text('No risk badges')]
                  : [
                      for (final entry in risks.entries.take(7))
                        ActionChip(
                          label: Text(
                            '${entry.key}: ${entry.value.map((badge) => badge.label).join(', ')}',
                          ),
                          onPressed: () => onFocusNode(entry.key),
                        ),
                    ],
            ),
            _GraphDiagnosticCard(
              title: 'Relation suggestions',
              icon: Icons.add_link_outlined,
              children: suggestions.isEmpty
                  ? const [Text('No strong suggestions')]
                  : [
                      for (final suggestion in suggestions.take(6))
                        Text(
                          '${suggestion.source.title} ↔ ${suggestion.target.title} (${suggestion.score})',
                        ),
                    ],
            ),
          ],
        ),
      ],
    );
  }
}

class _GraphDiagnosticCard extends StatelessWidget {
  const _GraphDiagnosticCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 320,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final child in children) ...[
                DefaultTextStyle.merge(
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  child: child,
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight, required this.onFocusNode});

  final GraphRelationshipInsight insight;
  final ValueChanged<String> onFocusNode;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(_insightIcon(insight.severity), size: 16),
      label: Text('${insight.title}: ${insight.description}'),
      onPressed: insight.nodeIds.isEmpty
          ? null
          : () => onFocusNode(insight.nodeIds.first),
    );
  }
}

IconData _insightIcon(GraphRelationshipSeverity severity) {
  return switch (severity) {
    GraphRelationshipSeverity.info => Icons.info_outline,
    GraphRelationshipSeverity.warning => Icons.warning_amber_outlined,
    GraphRelationshipSeverity.critical => Icons.error_outline,
  };
}

IconData _contextModeIcon(ContextGraphMode mode) {
  return switch (mode) {
    ContextGraphMode.nodes => Icons.hub_outlined,
    ContextGraphMode.projects => Icons.folder_copy_outlined,
    ContextGraphMode.areas => Icons.map_outlined,
    ContextGraphMode.tags => Icons.sell_outlined,
  };
}

String _contextModeLabel(ContextGraphMode mode) {
  return switch (mode) {
    ContextGraphMode.nodes => 'Nodes',
    ContextGraphMode.projects => 'Projects',
    ContextGraphMode.areas => 'Areas',
    ContextGraphMode.tags => 'Tags',
  };
}

class _GraphGuidanceStrip extends StatelessWidget {
  const _GraphGuidanceStrip({
    required this.visibleNodeCount,
    required this.edgeCount,
    required this.activeFilterCount,
    required this.focusedNode,
    required this.onClearFilters,
    required this.onClearFocus,
  });

  final int visibleNodeCount;
  final int edgeCount;
  final int activeFilterCount;
  final String? focusedNode;
  final VoidCallback? onClearFilters;
  final VoidCallback? onClearFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = focusedNode == null
        ? '$visibleNodeCount visible nodes • $edgeCount links'
        : 'Focused on $focusedNode • $visibleNodeCount neighbors';

    return DecoratedBox(
      key: const ValueKey('graph-guidance-strip'),
      decoration: ShapeDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.32,
        ),
        shape: DoodleShapeBorder(
          side: BorderSide(color: theme.colorScheme.outlineVariant),
          radius: 18,
          wobble: 1.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.account_tree_outlined, color: theme.colorScheme.primary),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Graph navigator', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (activeFilterCount > 0)
              ActionChip(
                avatar: const Icon(Icons.filter_alt_off_outlined, size: 16),
                label: Text('Clear $activeFilterCount filters'),
                onPressed: onClearFilters,
              ),
            if (focusedNode != null)
              ActionChip(
                avatar: const Icon(Icons.center_focus_weak_outlined, size: 16),
                label: const Text('Clear focus'),
                onPressed: onClearFocus,
              ),
          ],
        ),
      ),
    );
  }
}

class _GraphFilterBand extends StatefulWidget {
  const _GraphFilterBand({
    required this.query,
    required this.focusedNode,
    required this.tags,
    required this.relationLabels,
    required this.workspaceContexts,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onTagChanged,
    required this.onProjectChanged,
    required this.onAreaChanged,
    required this.onRelationLabelChanged,
    required this.onCrossDayChanged,
    required this.onRelationStateChanged,
    required this.onContextModeChanged,
    required this.onExportReport,
    required this.contextMode,
    required this.onClearFocus,
    required this.onClearFilters,
    required this.savedFilters,
    required this.onSaveFilter,
    required this.onApplyFilter,
    required this.onDeleteFilter,
    required this.onRenameFilter,
    required this.onDuplicateFilter,
    required this.onExportFilters,
    required this.onImportFilters,
  });

  final NodeGraphExplorerQuery query;
  final NodeGraphNode? focusedNode;
  final List<String> tags;
  final List<String> relationLabels;
  final List<WorkspaceContext> workspaceContexts;
  final ValueChanged<NodeType> onTypeChanged;
  final ValueChanged<NodeStatus> onStatusChanged;
  final ValueChanged<NodePriority> onPriorityChanged;
  final ValueChanged<String> onTagChanged;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onAreaChanged;
  final ValueChanged<String> onRelationLabelChanged;
  final ValueChanged<bool> onCrossDayChanged;
  final ValueChanged<GraphRelationState> onRelationStateChanged;
  final ValueChanged<ContextGraphMode> onContextModeChanged;
  final VoidCallback onExportReport;
  final ContextGraphMode contextMode;
  final VoidCallback onClearFocus;
  final VoidCallback onClearFilters;
  final List<_GraphSavedFilter> savedFilters;
  final Future<void> Function() onSaveFilter;
  final ValueChanged<_GraphSavedFilter> onApplyFilter;
  final Future<void> Function(String id) onDeleteFilter;
  final Future<void> Function(_GraphSavedFilter filter) onRenameFilter;
  final Future<void> Function(_GraphSavedFilter filter) onDuplicateFilter;
  final Future<void> Function() onExportFilters;
  final Future<void> Function() onImportFilters;

  @override
  State<_GraphFilterBand> createState() => _GraphFilterBandState();
}

class _GraphFilterBandState extends State<_GraphFilterBand> {
  bool _showFilters = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = widget.query;
    final focusedNode = widget.focusedNode;
    final tags = widget.tags;
    final relationLabels = widget.relationLabels;
    final workspaceContexts = widget.workspaceContexts;
    final savedFilters = widget.savedFilters;
    final contextMode = widget.contextMode;

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: DoodleShapeBorder(
          side: BorderSide(color: theme.dividerColor),
          radius: 8,
          wobble: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('graph-filter-band-toggle'),
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                  icon: Icon(
                    _showFilters
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                  label: Text(_showFilters ? 'Hide filters' : 'Show filters'),
                ),
                if (query.activeFilterCount > 0) ...[
                  const SizedBox(width: 8),
                  InputChip(
                    key: const ValueKey('graph-active-filters-chip'),
                    avatar: const Icon(Icons.filter_alt_outlined, size: 16),
                    label: Text(_countLabel(query.activeFilterCount, 'filter')),
                    onDeleted: widget.onClearFilters,
                  ),
                ],
                if (focusedNode != null) ...[
                  const SizedBox(width: 8),
                  InputChip(
                    avatar: const Icon(Icons.center_focus_strong, size: 16),
                    label: Text(focusedNode.node.title),
                    onDeleted: widget.onClearFocus,
                  ),
                ],
              ],
            ),
            if (_showFilters)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ActionChip(
                        avatar: const Icon(
                          Icons.bookmark_add_outlined,
                          size: 16,
                        ),
                        label: const Text('Save graph filter'),
                        onPressed: () => unawaited(widget.onSaveFilter()),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Graph filter import/export',
                        onSelected: (value) {
                          if (value == 'export') {
                            unawaited(widget.onExportFilters());
                          }
                          if (value == 'import') {
                            unawaited(widget.onImportFilters());
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'export',
                            child: Text('Export JSON'),
                          ),
                          PopupMenuItem(
                            value: 'import',
                            child: Text('Import JSON'),
                          ),
                        ],
                      ),
                      for (final filter in savedFilters)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InputChip(
                              avatar: const Icon(
                                Icons.bookmark_border,
                                size: 16,
                              ),
                              label: Text(filter.label),
                              onPressed: () => widget.onApplyFilter(filter),
                              onDeleted: () =>
                                  unawaited(widget.onDeleteFilter(filter.id)),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Graph filter actions',
                              onSelected: (value) {
                                if (value == 'rename') {
                                  unawaited(widget.onRenameFilter(filter));
                                }
                                if (value == 'duplicate') {
                                  unawaited(widget.onDuplicateFilter(filter));
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename'),
                                ),
                                PopupMenuItem(
                                  value: 'duplicate',
                                  child: Text('Duplicate'),
                                ),
                              ],
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in NodeType.values)
                        FilterChip(
                          key: ValueKey('graph-type-${type.name}'),
                          label: Text(type.label),
                          selected: query.typeFilter == type,
                          onSelected: (_) => widget.onTypeChanged(type),
                        ),
                      FilterChip(
                        key: const ValueKey('graph-cross-day-only'),
                        avatar: const Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                        ),
                        label: const Text('Cross-day only'),
                        selected: query.crossDayOnly,
                        onSelected: widget.onCrossDayChanged,
                      ),
                      for (final state in GraphRelationState.values)
                        FilterChip(
                          key: ValueKey('graph-relation-state-${state.name}'),
                          avatar: const Icon(Icons.radar_outlined, size: 18),
                          label: Text(state.label),
                          selected: query.relationState == state,
                          onSelected: (_) =>
                              widget.onRelationStateChanged(state),
                        ),
                      for (final mode in ContextGraphMode.values)
                        ChoiceChip(
                          key: ValueKey('graph-context-mode-${mode.name}'),
                          avatar: Icon(_contextModeIcon(mode), size: 18),
                          label: Text(_contextModeLabel(mode)),
                          selected: contextMode == mode,
                          onSelected: (_) => widget.onContextModeChanged(mode),
                        ),
                      ActionChip(
                        key: const ValueKey('graph-export-report'),
                        avatar: const Icon(
                          Icons.description_outlined,
                          size: 18,
                        ),
                        label: const Text('Copy report'),
                        onPressed: widget.onExportReport,
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
                                  widget.onProjectChanged(
                                    workspaceContext.name,
                                  );
                                  break;
                                case WorkspaceContextType.area:
                                  widget.onAreaChanged(workspaceContext.name);
                                  break;
                                case WorkspaceContextType.daily:
                                  break;
                              }
                            },
                          ),
                      for (final tag in tags)
                        FilterChip(
                          key: ValueKey(
                            'graph-tag-${workspaceContextKey(tag)}',
                          ),
                          label: Text('#$tag'),
                          selected: query.tagFilter == tag,
                          onSelected: (_) => widget.onTagChanged(tag),
                        ),
                      for (final label in relationLabels)
                        FilterChip(
                          key: ValueKey(
                            'graph-relation-${workspaceContextKey(label)}',
                          ),
                          label: Text('Relation $label'),
                          selected: query.relationLabelFilter == label,
                          onSelected: (_) =>
                              widget.onRelationLabelChanged(label),
                        ),
                      for (final priority in NodePriority.values)
                        if (priority != NodePriority.none)
                          FilterChip(
                            key: ValueKey('graph-priority-${priority.name}'),
                            label: Text('Priority ${priority.label}'),
                            selected: query.priorityFilter == priority,
                            onSelected: (_) =>
                                widget.onPriorityChanged(priority),
                          ),
                      for (final status in NodeStatus.values)
                        FilterChip(
                          key: ValueKey('graph-status-${status.name}'),
                          label: Text('Status ${status.label}'),
                          selected: query.statusFilter == status,
                          onSelected: (_) => widget.onStatusChanged(status),
                        ),
                      if (query.activeFilterCount > 0)
                        ActionChip(
                          key: const ValueKey('graph-clear-filters'),
                          avatar: const Icon(Icons.close, size: 16),
                          label: const Text('Clear'),
                          onPressed: widget.onClearFilters,
                        ),
                    ],
                  ),
                  if (focusedNode != null) ...[
                    const SizedBox(height: 8),
                    InputChip(
                      key: const ValueKey('graph-focus-chip'),
                      avatar: const Icon(Icons.center_focus_strong, size: 16),
                      label: Text('Neighborhood: ${focusedNode.node.title}'),
                      onDeleted: widget.onClearFocus,
                      deleteIcon: const Icon(
                        Icons.close,
                        key: ValueKey('graph-clear-focus'),
                      ),
                    ),
                  ],
                ],
              ),
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
      decoration: ShapeDecoration(
        shape: DoodleShapeBorder(
          side: BorderSide(color: theme.dividerColor),
          radius: 8,
          wobble: 1.2,
        ),
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
              '${neighborhood.focusedNode.node.type.label} • ${neighborhood.focusedNode.node.status.label} • ${neighborhood.focusedNode.node.priority.label} • ${_countLabel(neighborhood.totalConnectionCount, 'connection')}',
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.calendar_month_outlined, size: 16),
                label: const Text('Open day'),
                onPressed: () => goToDay(
                  context,
                  neighborhood.focusedNode.node.day,
                  highlightNodeId: neighborhood.focusedNode.id,
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.open_in_new_outlined, size: 16),
                label: const Text('Open node'),
                onPressed: () => context.go(
                  '/calendar/${dayKey(neighborhood.focusedNode.node.day)}/node/${neighborhood.focusedNode.id}',
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.insights_outlined, size: 16),
                label: const Text('Insights'),
                onPressed: () => context.go('/insights'),
              ),
              if (neighborhood.focusedNode.node.project.isNotEmpty)
                ActionChip(
                  avatar: const Icon(Icons.workspaces_outline, size: 16),
                  label: const Text('Workspace'),
                  onPressed: () => context.go(
                    '/workspaces/project/${Uri.encodeComponent(neighborhood.focusedNode.node.project)}',
                  ),
                ),
            ],
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
  const _GraphEdgeTile({
    required this.graph,
    required this.edge,
    required this.onRelationLabelEdited,
  });

  final NodeGraph graph;
  final NodeGraphEdge edge;
  final Future<void> Function(MindmapNode source, String targetId, String label)
  onRelationLabelEdited;

  @override
  Widget build(BuildContext context) {
    final source = graph.nodeFor(edge.sourceId)?.node;
    final target = graph.nodeFor(edge.targetId)?.node;
    final theme = Theme.of(context);
    if (source == null || target == null) return const SizedBox.shrink();
    final label = _relationLabelFor(source, target.id);

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
      subtitle: Text(
        '$label · ${dayKey(source.day)} -> ${dayKey(target.day)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Edit relation label',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _editLabel(context, source, target.id, label),
          ),
          edge.isCrossDay
              ? const Chip(label: Text('Cross-day'))
              : const Chip(label: Text('Same day')),
        ],
      ),
      onTap: () => goToDay(context, target.day, highlightNodeId: target.id),
    );
  }

  Future<void> _editLabel(
    BuildContext context,
    MindmapNode source,
    String targetId,
    String currentLabel,
  ) async {
    final controller = TextEditingController(text: currentLabel);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit relation label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Label'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.isEmpty) return;
    await onRelationLabelEdited(source, targetId, label);
  }

  String _relationLabelFor(MindmapNode source, String targetId) {
    final rawRelations = source.data['relations'];
    if (rawRelations is! List<Object?>) return 'relates to';
    for (final item in rawRelations) {
      if (item is! Map<Object?, Object?>) continue;
      if (item['targetId'] != targetId) continue;
      final label = item['label'];
      if (label is String && label.trim().isNotEmpty) return label.trim();
    }
    return 'relates to';
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

List<String> _availableRelationLabels(List<MindmapNode> nodes) {
  final labels = <String>{};
  for (final node in nodes) {
    final rawRelations = node.data['relations'];
    if (rawRelations is! List<Object?>) continue;
    for (final item in rawRelations) {
      if (item is! Map<Object?, Object?>) continue;
      final label = item['label'];
      if (label is String && label.trim().isNotEmpty) {
        labels.add(label.trim());
      }
    }
  }
  return labels.toList()..sort();
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
  _ => Icons.radio_button_unchecked,
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
    this.initialSelectedNodeId,
    super.key,
  });

  final List<NodeGraphNode> nodes;
  final List<NodeGraphEdge> edges;
  final ValueChanged<NodeGraphNode> onNodeTapped;
  final String? initialSelectedNodeId;

  @override
  State<VisualGraphView> createState() => _VisualGraphViewState();
}

class _VisualGraphViewState extends State<VisualGraphView> {
  final Map<String, Offset> _positions = {};
  final TransformationController _transformationController =
      TransformationController();
  String? _hoveredNodeId;
  String? _selectedNodeId;
  bool _showControls = false;

  @override
  void initState() {
    super.initState();
    _selectedNodeId = widget.initialSelectedNodeId;
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
    final selectedNode = _selectedNodeId == null
        ? null
        : widget.nodes.where((node) => node.id == _selectedNodeId).firstOrNull;

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
                        setState(() => _selectedNodeId = node.id);
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
          if (selectedNode != null)
            Positioned(
              left: 12,
              bottom: 12,
              child: _GraphNodeDetailDrawer(
                node: selectedNode,
                onClose: () => setState(() => _selectedNodeId = null),
                onOpen: () => widget.onNodeTapped(selectedNode),
              ),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: _showControls
                ? Card(
                    color: theme.colorScheme.surface.withValues(alpha: 0.86),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.info_outline, size: 14),
                          const SizedBox(width: 6),
                          const Text(
                            'Drag to pan, pinch to zoom, tap node for details',
                            style: TextStyle(fontSize: 10),
                          ),
                          IconButton(
                            tooltip: 'Zoom in',
                            icon: const Icon(Icons.add, size: 16),
                            onPressed: () {},
                          ),
                          IconButton(
                            tooltip: 'Hide graph controls',
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () =>
                                setState(() => _showControls = false),
                          ),
                        ],
                      ),
                    ),
                  )
                : IconButton.filledTonal(
                    tooltip: 'Show graph controls',
                    icon: const Icon(Icons.tune, size: 18),
                    onPressed: () => setState(() => _showControls = true),
                  ),
          ),
        ],
      ),
    );
  }
}

class _GraphNodeDetailDrawer extends StatelessWidget {
  const _GraphNodeDetailDrawer({
    required this.node,
    required this.onClose,
    required this.onOpen,
  });

  final NodeGraphNode node;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('graph-node-detail-drawer'),
      width: 280,
      child: Card(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_nodeIcon(node.node.type), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      node.node.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close node details',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(label: Text(node.node.type.label)),
                  Chip(label: Text(node.node.status.label)),
                  if (node.node.project.isNotEmpty)
                    Chip(label: Text('Project ${node.node.project}')),
                  if (node.totalDegree > 0)
                    Chip(label: Text(_countLabel(node.totalDegree, 'link'))),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('graph-node-detail-open-day'),
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open day'),
                ),
              ),
            ],
          ),
        ),
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

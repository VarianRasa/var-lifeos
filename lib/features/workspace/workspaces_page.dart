import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:var_app/features/workspace/data/workspace_sort_repository.dart';
import 'package:var_app/features/workspace/data/workspace_title_repository.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_design_tokens.dart';
import '../../core/theme/node_visuals.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/error_message.dart';
import '../../shared/widgets/search_field.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/workspace_context.dart';
import 'application/workspace_filters.dart';
import 'application/workspace_health.dart';
import 'application/workspace_overview.dart';

class WorkspacesPage extends ConsumerStatefulWidget {
  const WorkspacesPage({super.key});

  @override
  ConsumerState<WorkspacesPage> createState() => _WorkspacesPageState();
}

class _WorkspacesPageState extends ConsumerState<WorkspacesPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  WorkspaceFilterState _filter = const WorkspaceFilterState();
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const _filterPrefsKey = 'workspace_last_filter';
  bool _showStats = false;

  @override
  void initState() {
    super.initState();
    _loadFilter();
  }

  Future<void> _loadFilter() async {
    final raw = await _prefs.getString(_filterPrefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?> && mounted) {
        setState(() => _filter = workspaceFilterStateFromJson(decoded));
      }
    } on FormatException {
      // Ignore corrupt saved view.
    }
  }

  Future<void> _setFilter(WorkspaceFilterState filter) async {
    setState(() => _filter = filter);
    await _prefs.setString(
      _filterPrefsKey,
      jsonEncode(workspaceFilterStateToJson(filter)),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contexts = ref.watch(workspaceContextsProvider);
    final today = ref.watch(currentDateProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1): () {
          _setFilter(_filter.copyWith(type: WorkspaceContextType.project));
        },
        const SingleActivator(LogicalKeyboardKey.digit2): () {
          _setFilter(_filter.copyWith(type: WorkspaceContextType.area));
        },
        const SingleActivator(LogicalKeyboardKey.digit3): () {
          _setFilter(_filter.copyWith(type: WorkspaceContextType.daily));
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _clearSearch();
          _setFilter(const WorkspaceFilterState());
        },
        const SingleActivator(LogicalKeyboardKey.keyR): () {
          _clearSearch();
          _setFilter(const WorkspaceFilterState());
        },
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Workspaces'),
          actions: [
            IconButton(
              icon: Icon(
                _showStats ? Icons.query_stats : Icons.query_stats_outlined,
              ),
              tooltip: _showStats ? 'Hide stats' : 'Show stats',
              onPressed: () {
                setState(() {
                  _showStats = !_showStats;
                });
              },
            ),
            SearchField(
              controller: _searchController,
              hintText: 'Filter workspaces...',
              onChanged: (value) {
                setState(() => _searchQuery = value.trim().toLowerCase());
              },
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: contexts.when(
          data: (value) => value.contexts.isEmpty
              ? const _WorkspacesEmptyState()
              : _WorkspacesBody(
                  contexts: value,
                  today: today,
                  searchQuery: _searchQuery,
                  filter: _filter,
                  onFilterChanged: _setFilter,
                  onClearSearch: _clearSearch,
                  showStats: _showStats,
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorMessage(
            message: 'Unable to load workspaces',
            onRetry: () => ref.invalidate(workspaceContextsProvider),
          ),
        ),
      ),
    );
  }
}

class _WorkspacesEmptyState extends StatelessWidget {
  const _WorkspacesEmptyState();

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
              Icons.workspaces_outlined,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text('No workspaces yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Create nodes with projects and areas to see them organized here',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspacesBody extends ConsumerWidget {
  const _WorkspacesBody({
    required this.contexts,
    required this.today,
    required this.searchQuery,
    required this.filter,
    required this.onFilterChanged,
    required this.onClearSearch,
    required this.showStats,
  });

  final WorkspaceContexts contexts;
  final DateTime today;
  final String searchQuery;
  final WorkspaceFilterState filter;
  final ValueChanged<WorkspaceFilterState> onFilterChanged;
  final VoidCallback onClearSearch;
  final bool showStats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing =
        MediaQuery.sizeOf(context).width <= LayoutConstants.contentBreakpoint
        ? 12.0
        : 16.0;

    final sortState = ref.watch(workspaceSortProvider);
    final overview = buildWorkspaceOverview(contexts, today);

    final titleMap = ref.watch(workspaceTitleProvider);
    bool matchesSearch(WorkspaceContext w) {
      if (searchQuery.isEmpty) return true;
      final titleKey = '${w.type.name}_${w.name}';
      final customTitle = titleMap[titleKey] ?? '';
      return w.name.toLowerCase().contains(searchQuery) ||
          customTitle.toLowerCase().contains(searchQuery);
    }

    final filteredProjects = contexts.projects
        .where(matchesSearch)
        .where((w) => matchesWorkspaceFilter(w, filter, today))
        .toList();
    final filteredAreas = contexts.areas
        .where(matchesSearch)
        .where((w) => matchesWorkspaceFilter(w, filter, today))
        .toList();
    final filteredDailies = contexts.dailies
        .where(matchesSearch)
        .where((w) => matchesWorkspaceFilter(w, filter, today))
        .toList();

    final sortedProjects = sortFilteredWorkspaces(
      sortWorkspaces(filteredProjects, sortState.projectsOrder),
      filter.sortMode,
      today,
    );
    final sortedAreas = sortFilteredWorkspaces(
      sortWorkspaces(filteredAreas, sortState.areasOrder),
      filter.sortMode,
      today,
    );
    final sortedDailies = sortFilteredWorkspaces(
      filteredDailies,
      filter.sortMode,
      today,
    );
    final hasMatches =
        sortedProjects.isNotEmpty ||
        sortedAreas.isNotEmpty ||
        sortedDailies.isNotEmpty;

    return SingleChildScrollView(
      padding: EdgeInsets.all(spacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showStats) ...[
            _WorkspaceMetricRail(summary: overview),
            SizedBox(height: spacing),
          ],
          _WorkspaceFilterBar(
            filter: filter,
            onChanged: onFilterChanged,
            onClearSearch: onClearSearch,
          ),
          SizedBox(height: spacing),
          if (showStats) ...[
            _WorkspaceFocusStrip(
              contexts: contexts,
              visibleCount:
                  sortedProjects.length +
                  sortedAreas.length +
                  sortedDailies.length,
              hasSearch: searchQuery.isNotEmpty,
              today: today,
            ),
            SizedBox(height: spacing),
          ],
          if (!hasMatches)
            const _WorkspaceNoMatches()
          else ...[
            _WorkspaceSection(
              title: 'Projects',
              contexts: sortedProjects,
              today: today,
            ),
            SizedBox(height: spacing),
            _WorkspaceSection(
              title: 'Areas',
              contexts: sortedAreas,
              today: today,
            ),
            SizedBox(height: spacing),
          ],
          if (hasMatches && sortedDailies.isNotEmpty) ...[
            _WorkspaceSection(
              title: 'Dailies',
              contexts: sortedDailies,
              today: today,
            ),
            SizedBox(height: spacing),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceFilterBar extends StatefulWidget {
  const _WorkspaceFilterBar({
    required this.filter,
    required this.onChanged,
    required this.onClearSearch,
  });

  final WorkspaceFilterState filter;
  final ValueChanged<WorkspaceFilterState> onChanged;
  final VoidCallback onClearSearch;

  @override
  State<_WorkspaceFilterBar> createState() => _WorkspaceFilterBarState();
}

class _WorkspaceFilterBarState extends State<_WorkspaceFilterBar> {
  bool _expanded = false;

  bool get _hasActiveFilters => widget.filter.hasFilters;

  void _clearFilters() {
    widget.onClearSearch();
    widget.onChanged(const WorkspaceFilterState());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = widget.filter;
    return Semantics(
      label: 'Workspace filters and shortcuts',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: _expanded ? 0.22 : 0.12,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('workspace-filter-toggle'),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(
                        _expanded ? Icons.tune : Icons.tune_outlined,
                        size: 18,
                      ),
                      label: Text(
                        _expanded
                            ? 'Hide filters'
                            : _hasActiveFilters
                            ? 'Filters active'
                            : 'Show filters',
                      ),
                    ),
                  ),
                  if (_hasActiveFilters) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Clear workspace filters',
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.restart_alt),
                    ),
                  ],
                ],
              ),
              if (_hasActiveFilters) ...[
                const SizedBox(height: 8),
                _WorkspaceActiveFilterChips(
                  filter: filter,
                  onChanged: widget.onChanged,
                ),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _expanded
                    ? Padding(
                        key: const ValueKey('workspace-filter-panel'),
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            DropdownButton<WorkspaceContextType?>(
                              value: filter.type,
                              hint: const Text('Type'),
                              items: const [
                                DropdownMenuItem<WorkspaceContextType?>(
                                  value: null,
                                  child: Text('All types'),
                                ),
                                DropdownMenuItem(
                                  value: WorkspaceContextType.project,
                                  child: Text('Projects'),
                                ),
                                DropdownMenuItem(
                                  value: WorkspaceContextType.area,
                                  child: Text('Areas'),
                                ),
                                DropdownMenuItem(
                                  value: WorkspaceContextType.daily,
                                  child: Text('Dailies'),
                                ),
                              ],
                              onChanged: (value) => widget.onChanged(
                                filter.copyWith(
                                  type: value,
                                  clearType: value == null,
                                ),
                              ),
                            ),
                            DropdownButton<WorkspaceHealthStatus?>(
                              value: filter.health,
                              hint: const Text('Health'),
                              items: const [
                                DropdownMenuItem<WorkspaceHealthStatus?>(
                                  value: null,
                                  child: Text('All health'),
                                ),
                                DropdownMenuItem(
                                  value: WorkspaceHealthStatus.healthy,
                                  child: Text('Healthy'),
                                ),
                                DropdownMenuItem(
                                  value: WorkspaceHealthStatus.quiet,
                                  child: Text('Quiet'),
                                ),
                                DropdownMenuItem(
                                  value: WorkspaceHealthStatus.busy,
                                  child: Text('Busy'),
                                ),
                                DropdownMenuItem(
                                  value: WorkspaceHealthStatus.atRisk,
                                  child: Text('At risk'),
                                ),
                              ],
                              onChanged: (value) => widget.onChanged(
                                filter.copyWith(
                                  health: value,
                                  clearHealth: value == null,
                                ),
                              ),
                            ),
                            DropdownButton<WorkspaceSortMode>(
                              value: filter.sortMode,
                              items: const [
                                DropdownMenuItem(
                                  value: WorkspaceSortMode.manual,
                                  child: Text('Manual'),
                                ),
                                DropdownMenuItem(
                                  value: WorkspaceSortMode.name,
                                  child: Text('Name'),
                                ),
                                DropdownMenuItem(
                                  value: WorkspaceSortMode.activity,
                                  child: Text('Activity'),
                                ),
                                DropdownMenuItem(
                                  value: WorkspaceSortMode.risk,
                                  child: Text('Risk'),
                                ),
                                DropdownMenuItem(
                                  value: WorkspaceSortMode.progress,
                                  child: Text('Progress'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  widget.onChanged(
                                    filter.copyWith(sortMode: value),
                                  );
                                }
                              },
                            ),
                            FilterChip(
                              label: const Text('Overdue'),
                              selected: filter.overdueOnly,
                              onSelected: (value) => widget.onChanged(
                                filter.copyWith(overdueOnly: value),
                              ),
                            ),
                            FilterChip(
                              label: const Text('Stale'),
                              selected: filter.staleOnly,
                              onSelected: (value) => widget.onChanged(
                                filter.copyWith(staleOnly: value),
                              ),
                            ),
                            FilterChip(
                              label: const Text('Active'),
                              selected: filter.activeOnly,
                              onSelected: (value) => widget.onChanged(
                                filter.copyWith(activeOnly: value),
                              ),
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.restart_alt, size: 16),
                              label: const Text('Clear filters'),
                              onPressed: _clearFilters,
                            ),
                            const Chip(
                              label: Text('/ search - 1/2/3 type - R reset'),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceActiveFilterChips extends StatelessWidget {
  const _WorkspaceActiveFilterChips({
    required this.filter,
    required this.onChanged,
  });

  final WorkspaceFilterState filter;
  final ValueChanged<WorkspaceFilterState> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('workspace-active-filter-chips'),
      spacing: 6,
      runSpacing: 6,
      children: [
        if (filter.type != null)
          _WorkspaceFilterChip(
            icon: Icons.workspaces_outlined,
            label: 'Type: ${filter.type!.label}',
            onRemove: () => onChanged(filter.copyWith(clearType: true)),
          ),
        if (filter.health != null)
          _WorkspaceFilterChip(
            icon: Icons.health_and_safety_outlined,
            label: 'Health: ${filter.health!.label}',
            onRemove: () => onChanged(filter.copyWith(clearHealth: true)),
          ),
        if (filter.priority != null)
          _WorkspaceFilterChip(
            icon: Icons.priority_high_outlined,
            label: 'Priority: ${filter.priority!.label}',
            onRemove: () => onChanged(filter.copyWith(clearPriority: true)),
          ),
        if (filter.tag?.trim().isNotEmpty ?? false)
          _WorkspaceFilterChip(
            icon: Icons.tag_outlined,
            label: 'Tag: #${filter.tag}',
            onRemove: () => onChanged(filter.copyWith(clearTag: true)),
          ),
        if (filter.overdueOnly)
          _WorkspaceFilterChip(
            icon: Icons.warning_amber_outlined,
            label: 'Overdue',
            onRemove: () => onChanged(filter.copyWith(overdueOnly: false)),
          ),
        if (filter.staleOnly)
          _WorkspaceFilterChip(
            icon: Icons.history_toggle_off_outlined,
            label: 'Stale',
            onRemove: () => onChanged(filter.copyWith(staleOnly: false)),
          ),
        if (filter.activeOnly)
          _WorkspaceFilterChip(
            icon: Icons.bolt_outlined,
            label: 'Active',
            onRemove: () => onChanged(filter.copyWith(activeOnly: false)),
          ),
        if (filter.sortMode != WorkspaceSortMode.manual)
          _WorkspaceFilterChip(
            icon: Icons.sort_outlined,
            label: 'Sort: ${_workspaceSortLabel(filter.sortMode)}',
            onRemove: () =>
                onChanged(filter.copyWith(sortMode: WorkspaceSortMode.manual)),
          ),
      ],
    );
  }
}

class _WorkspaceFilterChip extends StatelessWidget {
  const _WorkspaceFilterChip({
    required this.icon,
    required this.label,
    required this.onRemove,
  });

  final IconData icon;
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(icon, size: 14),
      label: Text(label),
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close, size: 14),
      visualDensity: VisualDensity.compact,
    );
  }
}

String _workspaceSortLabel(WorkspaceSortMode mode) => switch (mode) {
  WorkspaceSortMode.manual => 'Manual',
  WorkspaceSortMode.name => 'Name',
  WorkspaceSortMode.activity => 'Activity',
  WorkspaceSortMode.risk => 'Risk',
  WorkspaceSortMode.progress => 'Progress',
};

class _WorkspaceFocusStrip extends StatelessWidget {
  const _WorkspaceFocusStrip({
    required this.contexts,
    required this.visibleCount,
    required this.hasSearch,
    required this.today,
  });

  final WorkspaceContexts contexts;
  final int visibleCount;
  final bool hasSearch;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = contexts.contexts.fold<int>(
      0,
      (total, workspace) => total + workspace.overdueCount(today),
    );
    final active = contexts.contexts.fold<int>(
      0,
      (total, workspace) => total + workspace.activeNodeCount,
    );

    return DecoratedBox(
      key: const ValueKey('workspace-focus-strip'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.32,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.dashboard_customize_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Workspace command center',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasSearch
                        ? '$visibleCount matching workspaces'
                        : '$active active nodes • $overdue overdue across workspaces',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceNoMatches extends StatelessWidget {
  const _WorkspaceNoMatches();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 220,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('No matching workspaces', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Try another project, area, daily title, or custom workspace title.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceMetricRail extends StatelessWidget {
  const _WorkspaceMetricRail({required this.summary});

  final WorkspaceOverviewSummary summary;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _WorkspaceMetricPill(
            icon: Icons.workspaces_outline,
            label: _countLabel(summary.totalWorkspaces, 'workspace'),
          ),
          const SizedBox(width: 10),
          _WorkspaceMetricPill(
            icon: Icons.account_tree_outlined,
            label: _countLabel(summary.projects, 'project'),
          ),
          const SizedBox(width: 10),
          _WorkspaceMetricPill(
            icon: Icons.category_outlined,
            label: _countLabel(summary.areas, 'area'),
          ),
          const SizedBox(width: 10),
          _WorkspaceMetricPill(
            icon: Icons.today_outlined,
            label: _countLabel(summary.dailies, 'daily'),
          ),
          const SizedBox(width: 10),
          _WorkspaceMetricPill(
            icon: Icons.radio_button_checked,
            label: '${summary.activeNodes} active',
          ),
          const SizedBox(width: 10),
          _WorkspaceMetricPill(
            icon: Icons.warning_amber_outlined,
            label: '${summary.overdueNodes} overdue total',
          ),
          const SizedBox(width: 10),
          _WorkspaceMetricPill(
            icon: Icons.priority_high_outlined,
            label: '${summary.highPriorityOpenNodes} high open',
          ),
          const SizedBox(width: 10),
          _WorkspaceMetricPill(
            icon: Icons.hourglass_empty_outlined,
            label: '${summary.staleWorkspaces} stale',
          ),
        ],
      ),
    );
  }
}

class _WorkspaceSection extends ConsumerWidget {
  const _WorkspaceSection({
    required this.title,
    required this.contexts,
    required this.today,
  });

  final String title;
  final List<WorkspaceContext> contexts;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        if (contexts.isEmpty)
          const _WorkspaceEmptyState()
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: contexts.length,
            onReorderItem: (oldIndex, newIndex) {
              final List<WorkspaceContext> updatedList = List.from(contexts);
              final item = updatedList.removeAt(oldIndex);
              updatedList.insert(newIndex, item);
              final newOrder = updatedList.map((e) => e.name).toList();
              if (title == 'Projects') {
                ref
                    .read(workspaceSortProvider.notifier)
                    .updateProjectsOrder(newOrder);
              } else if (title == 'Areas') {
                ref
                    .read(workspaceSortProvider.notifier)
                    .updateAreasOrder(newOrder);
              }
            },
            itemBuilder: (context, index) {
              final workspaceContext = contexts[index];
              return Padding(
                key: ValueKey(
                  'workspace-card-${workspaceContext.type.name}-${workspaceContext.name}',
                ),
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _WorkspaceContextCard(
                  contextSummary: workspaceContext,
                  today: today,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _WorkspaceContextCard extends ConsumerStatefulWidget {
  const _WorkspaceContextCard({
    required this.contextSummary,
    required this.today,
  });

  final WorkspaceContext contextSummary;
  final DateTime today;

  @override
  ConsumerState<_WorkspaceContextCard> createState() =>
      _WorkspaceContextCardState();
}

class _WorkspaceContextCardState extends ConsumerState<_WorkspaceContextCard> {
  bool _isHovered = false;
  bool _detailsExpanded = false;
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  void _showOverlay() {
    _hideOverlay();

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final overlay = Overlay.of(context);
    final overlayRenderBox = overlay.context.findRenderObject() as RenderBox?;
    final overlaySize = overlayRenderBox?.size ?? MediaQuery.sizeOf(context);

    final left = position.dx;
    final width = size.width;
    final bottom = overlaySize.height - position.dy + 4.0;

    final theme = Theme.of(context);
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          left: left,
          width: width,
          bottom: bottom,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 6 * (1 - value)),
                  child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
                );
              },
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.inverseSurface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Consumer(
                    builder: (context, ref, child) {
                      final titleMap = ref.watch(workspaceTitleProvider);
                      final titleKey =
                          '${widget.contextSummary.type.name}_${widget.contextSummary.name}';
                      final customTitle = titleMap[titleKey] ?? '';
                      if (customTitle.isEmpty) return const SizedBox.shrink();
                      return Text(
                        customTitle,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onHoverChange(bool isHovered) {
    if (_isHovered == isHovered) return;
    setState(() => _isHovered = isHovered);

    final titleMap = ref.read(workspaceTitleProvider);
    final titleKey =
        '${widget.contextSummary.type.name}_${widget.contextSummary.name}';
    final customTitle = titleMap[titleKey];
    final hasCustomTitle = customTitle != null && customTitle.isNotEmpty;

    if (isHovered && hasCustomTitle) {
      _showOverlay();
    } else {
      _hideOverlay();
    }
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    String currentTitle,
  ) async {
    var draft = currentTitle;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Workspace Title'),
        content: TextFormField(
          initialValue: currentTitle,
          decoration: const InputDecoration(
            hintText: 'Enter custom title',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onChanged: (value) => draft = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await ref
          .read(workspaceTitleProvider.notifier)
          .setTitle(
            widget.contextSummary.type,
            widget.contextSummary.name,
            result,
          );
      if (!mounted) return;
      // Refresh the overlay if it is active
      if (_isHovered && result.isNotEmpty) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final nextActions = widget.contextSummary.nextActions(widget.today);
    final completionPercent = (widget.contextSummary.completionRate * 100)
        .round();
    final progressPercent = (widget.contextSummary.averageProgress * 100)
        .round();
    final overdue = widget.contextSummary.overdueCount(widget.today);
    final health = classifyWorkspaceHealth(widget.contextSummary, widget.today);
    final healthSummary = buildWorkspaceHealth(
      widget.contextSummary,
      widget.today,
    );

    final titleMap = ref.watch(workspaceTitleProvider);
    final titleKey =
        '${widget.contextSummary.type.name}_${widget.contextSummary.name}';
    final customTitle = titleMap[titleKey];
    final hasCustomTitle = customTitle != null && customTitle.isNotEmpty;

    final container = AnimatedContainer(
      key: ValueKey(
        'workspace-context-${widget.contextSummary.type.name}-${workspaceContextKey(widget.contextSummary.name)}',
      ),
      duration: tokens.effectiveDuration(context, tokens.motionFast),
      curve: tokens.motionCurve,
      transformAlignment: Alignment.center,
      transform: Matrix4.translationValues(0.0, _isHovered ? -4.0 : 0.0, 0.0),
      decoration: ShapeDecoration(
        color: _isHovered
            ? theme.colorScheme.primary.withValues(alpha: 0.06)
            : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppDesignTokens.of(context).radiusContainer,
          ),
          side: BorderSide(
            color: _isHovered ? theme.colorScheme.primary : theme.dividerColor,
            width: _isHovered ? 1.8 : 1.0,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _workspaceIcon(widget.contextSummary.type),
                  size: 24,
                  color: _isHovered ? theme.colorScheme.primary : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Text(
                        hasCustomTitle
                            ? customTitle
                            : '${widget.contextSummary.type.label} ${widget.contextSummary.name}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: _isHovered ? FontWeight.bold : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_isHovered,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          tooltip: 'Rename',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              _showRenameDialog(context, customTitle ?? ''),
                        ),
                        IconButton(
                          icon: const Icon(Icons.bar_chart_outlined, size: 16),
                          tooltip: 'Go to Insights',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _hideOverlay();
                            final type = widget.contextSummary.type;
                            final name = widget.contextSummary.name;
                            context.go(
                              Uri(
                                path: '/insights',
                                queryParameters: {
                                  if (type == WorkspaceContextType.project)
                                    'project': name,
                                  if (type == WorkspaceContextType.area)
                                    'area': name,
                                },
                              ).toString(),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.hub_outlined, size: 16),
                          tooltip: 'Go to Graph',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _hideOverlay();
                            final type = widget.contextSummary.type;
                            final name = widget.contextSummary.name;
                            context.go(
                              Uri(
                                path: '/graph',
                                queryParameters: {
                                  if (type == WorkspaceContextType.project)
                                    'project': name,
                                  if (type == WorkspaceContextType.area)
                                    'area': name,
                                },
                              ).toString(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: widget.contextSummary.completionRate,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  widget.contextSummary.completionRate == 1.0
                      ? semantic.success
                      : semantic.accent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    '${widget.contextSummary.activeNodeCount} active',
                  ),
                  backgroundColor: _isHovered
                      ? theme.colorScheme.primaryContainer
                      : null,
                  side: BorderSide.none,
                ),
                Chip(
                  label: Text('$completionPercent% done'),
                  side: BorderSide.none,
                ),
                Chip(
                  label: Text(health.label),
                  backgroundColor: _healthColor(theme, semantic, health),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey(
                  'workspace-context-details-${widget.contextSummary.type.name}-${workspaceContextKey(widget.contextSummary.name)}',
                ),
                onPressed: () =>
                    setState(() => _detailsExpanded = !_detailsExpanded),
                icon: Icon(
                  _detailsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(_detailsExpanded ? 'Hide details' : 'Show details'),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _detailsExpanded
                  ? Column(
                      key: ValueKey(
                        'workspace-context-detail-panel-${widget.contextSummary.type.name}-${workspaceContextKey(widget.contextSummary.name)}',
                      ),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                              label: Text('$progressPercent% progress'),
                              side: BorderSide.none,
                            ),
                            if (overdue > 0)
                              Chip(
                                label: Text('$overdue overdue'),
                                backgroundColor:
                                    theme.colorScheme.errorContainer,
                                labelStyle: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                                side: BorderSide.none,
                              ),
                            if (isWorkspaceStale(
                              widget.contextSummary,
                              widget.today,
                            ))
                              const Chip(
                                label: Text('Stale'),
                                side: BorderSide.none,
                              ),
                            if (healthSummary.lastActivity != null)
                              Chip(
                                label: Text(
                                  workspaceLastActivityLabel(
                                    healthSummary.lastActivity,
                                    widget.today,
                                  ),
                                ),
                                side: BorderSide.none,
                              ),
                            for (final tag in healthSummary.tags.take(3))
                              Chip(label: Text('#$tag'), side: BorderSide.none),
                            if (widget.contextSummary.highPriorityCount > 0)
                              Chip(
                                label: Text(
                                  '${widget.contextSummary.highPriorityCount} high',
                                ),
                                backgroundColor:
                                    theme.colorScheme.tertiaryContainer,
                                labelStyle: TextStyle(
                                  color: theme.colorScheme.onTertiaryContainer,
                                ),
                                side: BorderSide.none,
                              ),
                          ],
                        ),
                        if (nextActions.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Next actions',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final node in nextActions) ...[
                            _WorkspaceActionTile(node: node),
                            if (node != nextActions.last)
                              const SizedBox(height: 6),
                          ],
                        ],
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );

    void openWorkspace() {
      _hideOverlay();
      final type = widget.contextSummary.type.name;
      final name = Uri.encodeComponent(widget.contextSummary.name);
      context.go('/workspaces/$type/$name');
    }

    return Semantics(
      button: true,
      label:
          '${widget.contextSummary.type.label} ${widget.contextSummary.name}, ${widget.contextSummary.activeNodeCount} active, $completionPercent percent done',
      onTap: openWorkspace,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): openWorkspace,
          const SingleActivator(LogicalKeyboardKey.space): openWorkspace,
        },
        child: Focus(
          child: MouseRegion(
            onEnter: (_) => _onHoverChange(true),
            onHover: (_) => _onHoverChange(true),
            onExit: (_) => _onHoverChange(false),
            cursor: SystemMouseCursors.click,
            child: Listener(
              onPointerHover: (_) => _onHoverChange(true),
              onPointerDown: (event) {
                // Fallback for right-click on web where onSecondaryTap might be swallowed
                if (event.buttons == 2) {
                  // 2 == kSecondaryButton
                  _showRenameDialog(context, customTitle ?? '');
                }
              },
              child: GestureDetector(
                onTap: openWorkspace,
                onSecondaryTap: () {
                  _showRenameDialog(context, customTitle ?? '');
                },
                onLongPress: () {
                  _showRenameDialog(context, customTitle ?? '');
                },
                child: container,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceActionTile extends StatelessWidget {
  const _WorkspaceActionTile({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: ValueKey('workspace-action-${node.id}'),
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () => goToDay(context, node.day, highlightNodeId: node.id),
        hoverColor: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Icon(
          NodeVisuals.icon(node.type),
          size: 20,
          color: NodeVisuals.color(context, node.type),
        ),
        title: Text(node.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_actionSubtitle(node)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      ),
    );
  }
}

class _WorkspaceMetricPill extends StatefulWidget {
  const _WorkspaceMetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  State<_WorkspaceMetricPill> createState() => _WorkspaceMetricPillState();
}

class _WorkspaceMetricPillState extends State<_WorkspaceMetricPill> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        transform: Matrix4.diagonal3Values(
          _isHovered ? 1.05 : 1.0,
          _isHovered ? 1.05 : 1.0,
          1.0,
        ),
        decoration: BoxDecoration(
          color: _isHovered
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
          border: Border.all(
            color: _isHovered ? theme.colorScheme.primary : theme.dividerColor,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: _isHovered
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: _isHovered
                      ? theme.colorScheme.onPrimaryContainer
                      : null,
                  fontWeight: _isHovered ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceEmptyState extends StatelessWidget {
  const _WorkspaceEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        'No contexts yet',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

String _actionSubtitle(MindmapNode node) {
  return [
    node.type.label,
    dayKey(node.day),
    if (node.dueDate != null) 'Due ${dayKey(node.dueDate!)}',
    if (node.priority != NodePriority.none) node.priority.label,
    if (node.status != NodeStatus.open) node.status.label,
  ].join(' - ');
}

Color _healthColor(
  ThemeData theme,
  AppSemanticColors semantic,
  WorkspaceHealthStatus health,
) {
  return switch (health) {
    WorkspaceHealthStatus.healthy => semantic.successMuted,
    WorkspaceHealthStatus.quiet => theme.colorScheme.surfaceContainerHighest,
    WorkspaceHealthStatus.busy => semantic.warningMuted,
    WorkspaceHealthStatus.atRisk => semantic.dangerMuted,
  };
}

IconData _workspaceIcon(WorkspaceContextType type) => switch (type) {
  WorkspaceContextType.project => Icons.account_tree_outlined,
  WorkspaceContextType.area => Icons.category_outlined,
  WorkspaceContextType.daily => Icons.today_outlined,
};

String _countLabel(int count, String singular) {
  return '$count $singular${count == 1 ? '' : 's'}';
}

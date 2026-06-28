import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:var_app/features/mindmap/domain/workspace_context.dart';
import 'package:var_app/features/workspace/data/workspace_sort_repository.dart';
import 'package:var_app/features/workspace/data/workspace_title_repository.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/error_message.dart';
import '../../shared/widgets/search_field.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/domain/mindmap_node.dart';

class WorkspacesPage extends ConsumerStatefulWidget {
  const WorkspacesPage({super.key});

  @override
  ConsumerState<WorkspacesPage> createState() => _WorkspacesPageState();
}

class _WorkspacesPageState extends ConsumerState<WorkspacesPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contexts = ref.watch(workspaceContextsProvider);
    final today = ref.watch(currentDateProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;

    final hasContexts = (contexts.valueOrNull?.contexts.isNotEmpty) ?? false;
    if (!hasContexts) {
      final theme = Theme.of(context);
      return Scaffold(
        appBar: AppBar(title: const Text('Workspaces')),
        body: Center(
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
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: isDesktop ? const Text('Workspaces') : const Text('Workspaces'),
        actions: [
          SearchField(
            controller: _searchController,
            hintText: 'Filter workspaces...',
            onChanged: (value) {
              setState(() => _searchQuery = value.trim().toLowerCase());
            },
          ),
          if (isDesktop)
            const SizedBox(width: 460)
          else
            const SizedBox(width: 16),
        ],
      ),
      body: contexts.when(
        data: (value) => _WorkspacesBody(
          contexts: value,
          today: today,
          searchQuery: _searchQuery,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorMessage(
          message: 'Unable to load workspaces',
          onRetry: () => ref.invalidate(workspaceContextsProvider),
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
  });

  final WorkspaceContexts contexts;
  final DateTime today;
  final String searchQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = MediaQuery.sizeOf(context).width < 720 ? 12.0 : 16.0;

    final sortState = ref.watch(workspaceSortProvider);

    final filteredProjects = contexts.projects.where((w) {
      if (searchQuery.isEmpty) return true;
      final nameMatches = w.name.toLowerCase().contains(searchQuery);
      final titleMap = ref.watch(workspaceTitleProvider);
      final titleKey = '${w.type.name}_${w.name}';
      final customTitle = titleMap[titleKey] ?? '';
      final titleMatches = customTitle.toLowerCase().contains(searchQuery);
      return nameMatches || titleMatches;
    }).toList();

    final filteredAreas = contexts.areas.where((w) {
      if (searchQuery.isEmpty) return true;
      final nameMatches = w.name.toLowerCase().contains(searchQuery);
      final titleMap = ref.watch(workspaceTitleProvider);
      final titleKey = '${w.type.name}_${w.name}';
      final customTitle = titleMap[titleKey] ?? '';
      final titleMatches = customTitle.toLowerCase().contains(searchQuery);
      return nameMatches || titleMatches;
    }).toList();

    final filteredDailies = contexts.dailies.where((w) {
      if (searchQuery.isEmpty) return true;
      final nameMatches = w.name.toLowerCase().contains(searchQuery);
      final titleMap = ref.watch(workspaceTitleProvider);
      final titleKey = '${w.type.name}_${w.name}';
      final customTitle = titleMap[titleKey] ?? '';
      final titleMatches = customTitle.toLowerCase().contains(searchQuery);
      return nameMatches || titleMatches;
    }).toList();

    final sortedProjects = sortWorkspaces(
      filteredProjects,
      sortState.projectsOrder,
    );
    final sortedAreas = sortWorkspaces(filteredAreas, sortState.areasOrder);

    return SingleChildScrollView(
      padding: EdgeInsets.all(spacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkspaceMetricRail(contexts: contexts, today: today),
          SizedBox(height: spacing),
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
          if (filteredDailies.isNotEmpty) ...[
            _WorkspaceSection(
              title: 'Dailies',
              contexts: filteredDailies,
              today: today,
            ),
            SizedBox(height: spacing),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceMetricRail extends StatelessWidget {
  const _WorkspaceMetricRail({required this.contexts, required this.today});

  final WorkspaceContexts contexts;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final activeNodes = contexts.contexts.fold<int>(
      0,
      (total, context) => total + context.activeNodeCount,
    );
    final overdue = contexts.contexts.fold<int>(
      0,
      (total, context) => total + context.overdueCount(today),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _WorkspaceMetricPill(
            icon: Icons.workspaces_outline,
            label: _countLabel(contexts.contexts.length, 'workspace'),
          ),
          const SizedBox(width: 10),
          _WorkspaceMetricPill(
            icon: Icons.account_tree_outlined,
            label: _countLabel(contexts.projects.length, 'project'),
          ),
          const SizedBox(width: 10),
          _WorkspaceMetricPill(
            icon: Icons.category_outlined,
            label: _countLabel(contexts.areas.length, 'area'),
          ),
          const SizedBox(width: 10),
          _WorkspaceMetricPill(
            icon: Icons.radio_button_checked,
            label: '$activeNodes active',
          ),
          const SizedBox(width: 10),
          _WorkspaceMetricPill(
            icon: Icons.warning_amber_outlined,
            label: '$overdue overdue total',
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
            onReorder: (oldIndex, newIndex) {
              if (oldIndex < newIndex) {
                newIndex -= 1;
              }
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
    final controller = TextEditingController(text: currentTitle);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Workspace Title'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter custom title',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (val) => Navigator.pop(context, val),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
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
    final nextActions = widget.contextSummary.nextActions(widget.today);
    final completionPercent = (widget.contextSummary.completionRate * 100)
        .round();
    final progressPercent = (widget.contextSummary.averageProgress * 100)
        .round();
    final overdue = widget.contextSummary.overdueCount(widget.today);

    final titleMap = ref.watch(workspaceTitleProvider);
    final titleKey =
        '${widget.contextSummary.type.name}_${widget.contextSummary.name}';
    final customTitle = titleMap[titleKey];
    final hasCustomTitle = customTitle != null && customTitle.isNotEmpty;

    final container = AnimatedContainer(
      key: ValueKey(
        'workspace-context-${widget.contextSummary.type.name}-${workspaceContextKey(widget.contextSummary.name)}',
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      transformAlignment: Alignment.center,
      transform: Matrix4.translationValues(0.0, _isHovered ? -6.0 : 0.0, 0.0)
        ..multiply(
          Matrix4.diagonal3Values(
            1.0 + (_isHovered ? 0.03 : 0.0),
            1.0 + (_isHovered ? 0.03 : 0.0),
            1.0,
          ),
        ),
      decoration: BoxDecoration(
        color: _isHovered ? null : theme.colorScheme.surface,
        gradient: _isHovered
            ? LinearGradient(
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.15),
                  theme.colorScheme.secondaryContainer.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        border: Border.all(
          color: _isHovered
              ? theme.colorScheme.primary.withValues(alpha: 0.6)
              : theme.dividerColor,
          width: _isHovered ? 2.0 : 1.0,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isHovered
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: 4,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                  blurRadius: 10,
                  spreadRadius: -2,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.0),
                  blurRadius: 24,
                  spreadRadius: 4,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.0),
                  blurRadius: 10,
                  spreadRadius: -2,
                  offset: const Offset(0, 4),
                ),
              ],
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
                  child: Text(
                    hasCustomTitle
                        ? customTitle
                        : '${widget.contextSummary.type.label} ${widget.contextSummary.name}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: _isHovered ? FontWeight.bold : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                      ? Colors.green
                      : theme.colorScheme.primary,
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
                  label: Text('$progressPercent% progress'),
                  side: BorderSide.none,
                ),
                if (overdue > 0)
                  Chip(
                    label: Text('$overdue overdue'),
                    backgroundColor: theme.colorScheme.errorContainer,
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    side: BorderSide.none,
                  ),
                if (widget.contextSummary.highPriorityCount > 0)
                  Chip(
                    label: Text(
                      '${widget.contextSummary.highPriorityCount} high',
                    ),
                    backgroundColor: theme.colorScheme.tertiaryContainer,
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
                if (node != nextActions.last) const SizedBox(height: 6),
              ],
            ],
          ],
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => _onHoverChange(true),
      onExit: (_) => _onHoverChange(false),
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: (event) {
          // Fallback for right-click on web where onSecondaryTap might be swallowed
          if (event.buttons == 2) {
            // 2 == kSecondaryButton
            _showRenameDialog(context, customTitle ?? '');
          }
        },
        child: GestureDetector(
          onTap: () {
            _hideOverlay();
            final type = widget.contextSummary.type.name;
            final name = Uri.encodeComponent(widget.contextSummary.name);
            context.go('/workspaces/$type/$name');
          },
          onSecondaryTap: () {
            _showRenameDialog(context, customTitle ?? '');
          },
          onLongPress: () {
            _showRenameDialog(context, customTitle ?? '');
          },
          child: container,
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
    return ListTile(
      key: ValueKey('workspace-action-${node.id}'),
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () => goToDay(context, node.day, highlightNodeId: node.id),
      hoverColor: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      leading: Icon(
        _nodeIcon(node.type),
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(node.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_actionSubtitle(node)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
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

IconData _workspaceIcon(WorkspaceContextType type) => switch (type) {
  WorkspaceContextType.project => Icons.account_tree_outlined,
  WorkspaceContextType.area => Icons.category_outlined,
  WorkspaceContextType.daily => Icons.today_outlined,
};

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
  return '$count $singular${count == 1 ? '' : 's'}';
}

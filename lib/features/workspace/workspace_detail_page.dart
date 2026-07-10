/// Workspace detail page with List, Kanban, and Gantt views.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/doodle_border.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/workspace_context.dart';
import 'application/workspace_goal_summary.dart';
import 'application/workspace_health.dart';
import 'application/workspace_markdown_export.dart';
import 'application/workspace_next_actions.dart';
import 'application/workspace_overview.dart';
import 'application/workspace_recommendations.dart';
import 'application/workspace_relationships.dart';
import 'application/workspace_timeline.dart';

/// View modes for the workspace detail page.
enum _WorkspaceView { list, kanban, gantt }

class WorkspaceDetailPage extends ConsumerStatefulWidget {
  const WorkspaceDetailPage({
    super.key,
    required this.typeName,
    required this.name,
  });

  final String typeName;
  final String name;

  @override
  ConsumerState<WorkspaceDetailPage> createState() =>
      _WorkspaceDetailPageState();
}

class _WorkspaceDetailPageState extends ConsumerState<WorkspaceDetailPage> {
  _WorkspaceView _view = _WorkspaceView.list;

  WorkspaceContextType get _type {
    for (final t in WorkspaceContextType.values) {
      if (t.name == widget.typeName) return t;
    }
    return WorkspaceContextType.project;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contextsFuture = ref.watch(workspaceContextsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/workspaces'),
        ),
        title: Text(
          '${_type.label} ${widget.name}',
          style: theme.textTheme.titleMedium,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SegmentedButton<_WorkspaceView>(
              segments: const [
                ButtonSegment(
                  value: _WorkspaceView.list,
                  label: Text('List'),
                  icon: Icon(Icons.view_list_outlined),
                ),
                ButtonSegment(
                  value: _WorkspaceView.kanban,
                  label: Text('Kanban'),
                  icon: Icon(Icons.view_kanban_outlined),
                ),
                ButtonSegment(
                  value: _WorkspaceView.gantt,
                  label: Text('Gantt'),
                  icon: Icon(Icons.waterfall_chart_outlined),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (selected) {
                setState(() => _view = selected.first);
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
      body: contextsFuture.when(
        data: (contexts) {
          final workspace = contexts.contextFor(_type, widget.name);
          final detailView = switch (_view) {
            _WorkspaceView.list => _WorkspaceListView(workspace: workspace),
            _WorkspaceView.kanban => _WorkspaceKanbanView(workspace: workspace),
            _WorkspaceView.gantt => _WorkspaceGanttView(workspace: workspace),
          };

          return Column(
            children: [
              if (_view != _WorkspaceView.list)
                _WorkspaceDetailHeader(workspace: workspace),
              Expanded(child: detailView),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text('Failed to load workspace'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => ref.invalidate(workspaceContextsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _workspaceTypeIcon(WorkspaceContextType type) {
  return switch (type) {
    WorkspaceContextType.project => Icons.account_tree_outlined,
    WorkspaceContextType.area => Icons.category_outlined,
    WorkspaceContextType.daily => Icons.today_outlined,
  };
}

class _WorkspaceDetailHeader extends ConsumerWidget {
  const _WorkspaceDetailHeader({required this.workspace});

  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final health = buildWorkspaceHealth(workspace, today);
    final timeline = buildWorkspaceTimeline(workspace, today);
    final goals = buildWorkspaceGoalSummary(workspace, today);
    final relationships = buildWorkspaceRelationshipSummary(
      workspace,
      workspace.nodes,
    );
    final nextActions = buildWorkspaceNextActions(workspace, today);
    final recommendations = buildWorkspaceRecommendations(
      workspace,
      today,
      relationships,
    );
    final completion = (workspace.completionRate * 100).round();
    final progress = (health.progress * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.colorScheme.surface,
          shape: DoodleShapeBorder(
            side: BorderSide(color: theme.dividerColor),
            radius: 20,
            wobble: 1.2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _workspaceTypeIcon(workspace.type),
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  _HeaderChip(
                    icon: Icons.monitor_heart_outlined,
                    label: health.status.label,
                  ),
                  const SizedBox(width: 8),
                  _HeaderChip(
                    icon: Icons.schedule_outlined,
                    label: workspaceLastActivityLabel(
                      health.lastActivity,
                      today,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeaderChip(
                    icon: Icons.radio_button_checked,
                    label: '${health.active} active',
                  ),
                  _HeaderChip(
                    icon: Icons.check_circle_outline,
                    label: '${health.done} done',
                  ),
                  _HeaderChip(
                    icon: Icons.warning_amber_outlined,
                    label: '${health.overdue} overdue',
                  ),
                  _HeaderChip(
                    icon: Icons.priority_high_outlined,
                    label: '${health.highPriority} high',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: health.progress.clamp(0, 1).toDouble(),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$completion% complete • $progress% average progress',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go(_graphUrl(workspace)),
                    icon: const Icon(Icons.hub_outlined, size: 16),
                    label: const Text('Graph'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go(_insightsUrl(workspace)),
                    icon: const Icon(Icons.bar_chart_outlined, size: 16),
                    label: const Text('Insights'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final markdown = exportWorkspaceMarkdown(
                        workspace: workspace,
                        today: today,
                        health: health,
                        timeline: timeline,
                        goals: goals,
                        relationships: relationships,
                        nextActions: nextActions,
                        recommendations: recommendations,
                      );
                      await Clipboard.setData(ClipboardData(text: markdown));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Workspace report copied'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined, size: 16),
                    label: const Text('Copy report'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _graphUrl(WorkspaceContext workspace) {
  return Uri(
    path: '/graph',
    queryParameters: {
      if (workspace.type == WorkspaceContextType.project)
        'project': workspace.name,
      if (workspace.type == WorkspaceContextType.area) 'area': workspace.name,
    },
  ).toString();
}

String _insightsUrl(WorkspaceContext workspace) {
  return Uri(
    path: '/insights',
    queryParameters: {
      if (workspace.type == WorkspaceContextType.project)
        'project': workspace.name,
      if (workspace.type == WorkspaceContextType.area) 'area': workspace.name,
    },
  ).toString();
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      backgroundColor: theme.colorScheme.surface,
      side: BorderSide(color: theme.colorScheme.outlineVariant),
    );
  }
}

// ---------------------------------------------------------------------------
// LIST VIEW
// ---------------------------------------------------------------------------

class _WorkspaceListView extends StatelessWidget {
  const _WorkspaceListView({required this.workspace});
  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = workspace.activeNodes
        .where((n) => !n.isDone && n.status != NodeStatus.done)
        .toList();
    final completed = workspace.activeNodes
        .where((n) => n.isDone || n.status == NodeStatus.done)
        .toList();

    if (workspace.nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text('No tasks yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Add tasks to this workspace from the calendar',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats row
        _StatsRow(workspace: workspace),
        const SizedBox(height: 20),

        if (completed.isNotEmpty) ...[
          Text(
            'Completed (${completed.length})',
            style: theme.textTheme.titleSmall?.copyWith(color: Colors.green),
          ),
          const SizedBox(height: 8),
          ...completed.map((node) => _TaskListTile(node: node)),
          const SizedBox(height: 20),
        ],

        if (active.isNotEmpty) ...[
          Text(
            'Active (${active.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...active.map((node) => _TaskListTile(node: node)),
        ],

        const SizedBox(height: 20),
        _WorkspaceDrillPanels(workspace: workspace),
      ],
    );
  }
}

class _WorkspaceDrillPanels extends StatelessWidget {
  const _WorkspaceDrillPanels({required this.workspace});

  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final overdue = workspace.activeNodes
        .where((node) {
          final due = node.dueDate;
          return due != null &&
              due.dateOnly.isBefore(today.dateOnly) &&
              !node.isDone &&
              node.status != NodeStatus.done;
        })
        .toList(growable: false);
    final high = workspace.activeNodes
        .where(
          (node) =>
              node.priority.index >= NodePriority.high.index &&
              !node.isDone &&
              node.status != NodeStatus.done,
        )
        .toList(growable: false);
    final waiting = workspace.activeNodes
        .where((node) => node.status == NodeStatus.waiting)
        .toList(growable: false);
    final goals = workspace.activeNodes
        .where((node) => node.type == NodeType.goal)
        .toList(growable: false);

    return Column(
      children: [
        _DrillExpansion(title: 'Overdue nodes', nodes: overdue),
        _DrillExpansion(title: 'High-priority nodes', nodes: high),
        _DrillExpansion(title: 'Waiting / blocked nodes', nodes: waiting),
        _DrillExpansion(title: 'Goals', nodes: goals),
      ],
    );
  }
}

class _DrillExpansion extends StatelessWidget {
  const _DrillExpansion({required this.title, required this.nodes});

  final String title;
  final List<MindmapNode> nodes;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      title: Text('$title (${nodes.length})'),
      children: nodes.isEmpty
          ? [const ListTile(dense: true, title: Text('No items'))]
          : [for (final node in nodes) _TaskListTile(node: node)],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.workspace});
  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context) {
    final completion = (workspace.completionRate * 100).round();
    final progress = (workspace.averageProgress * 100).round();

    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.colorScheme.surface,
        shape: DoodleShapeBorder(
          side: BorderSide(color: theme.dividerColor),
          radius: 12,
          wobble: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(
              label: 'Total',
              value: '${workspace.nodes.length}',
              icon: Icons.layers_outlined,
            ),
            _StatItem(
              label: 'Active',
              value: '${workspace.activeNodeCount}',
              icon: Icons.radio_button_checked,
            ),
            _StatItem(
              label: 'Done',
              value: '$completion%',
              icon: Icons.check_circle_outlined,
            ),
            _StatItem(
              label: 'Progress',
              value: '$progress%',
              icon: Icons.trending_up_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _TaskListTile extends StatelessWidget {
  const _TaskListTile({required this.node});
  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = node.isDone || node.status == NodeStatus.done;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          isDone ? Icons.check_circle : _statusIcon(node.status),
          color: isDone ? Colors.green : _statusColor(node.status, theme),
          size: 20,
        ),
        title: Text(
          node.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: isDone
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: Text(
          [
            node.type.label,
            dayKey(node.day),
            if (node.dueDate != null) 'Due ${dayKey(node.dueDate!)}',
            if (node.priority != NodePriority.none) node.priority.label,
          ].join(' Â· '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: node.priority.index >= NodePriority.high.index
            ? Icon(Icons.flag, size: 16, color: theme.colorScheme.error)
            : null,
        onTap: () => goToDay(context, node.day, highlightNodeId: node.id),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KANBAN VIEW
// ---------------------------------------------------------------------------

/// Column definitions for the Kanban board.
enum _KanbanColumn {
  open('To Do', NodeStatus.open, Icons.radio_button_unchecked),
  planned('Planned', NodeStatus.planned, Icons.event_outlined),
  doing('In Progress', NodeStatus.doing, Icons.sync_outlined),
  waiting('Waiting', NodeStatus.waiting, Icons.hourglass_empty_outlined),
  done('Done', NodeStatus.done, Icons.check_circle_outlined);

  const _KanbanColumn(this.label, this.targetStatus, this.icon);
  final String label;
  final NodeStatus targetStatus;
  final IconData icon;
}

class _WorkspaceKanbanView extends ConsumerWidget {
  const _WorkspaceKanbanView({required this.workspace});
  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = workspace.activeNodes;

    // Bucket nodes into columns
    final buckets = <_KanbanColumn, List<MindmapNode>>{
      for (final col in _KanbanColumn.values) col: [],
    };

    for (final node in active) {
      if (node.isDone || node.status == NodeStatus.done) {
        buckets[_KanbanColumn.done]!.add(node);
      } else {
        final column = _KanbanColumn.values.firstWhere(
          (item) => item.targetStatus == node.status,
          orElse: () => _KanbanColumn.open,
        );
        buckets[column]!.add(node);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = math.max(240.0, (constraints.maxWidth - 72) / 5);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final col in _KanbanColumn.values) ...[
                _KanbanColumnWidget(
                  column: col,
                  nodes: buckets[col]!,
                  width: columnWidth,
                ),
                if (col != _KanbanColumn.done) const SizedBox(width: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _KanbanColumnWidget extends ConsumerWidget {
  const _KanbanColumnWidget({
    required this.column,
    required this.nodes,
    required this.width,
  });

  final _KanbanColumn column;
  final List<MindmapNode> nodes;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) async {
        final nodeId = details.data;
        final repo = ref.read(mindmapRepositoryProvider);
        final allNodes = await repo.listNodes();
        final node = allNodes.firstWhere(
          (n) => n.id == nodeId,
          orElse: () => throw StateError('Node $nodeId not found'),
        );

        final newStatus = column.targetStatus;
        final isDone = newStatus == NodeStatus.done;

        final updated = node.copyWith(
          status: newStatus,
          isDone: isDone,
          progress: isDone
              ? 1.0
              : (newStatus == NodeStatus.doing
                    ? math.max(node.progress, 0.1)
                    : node.progress),
          updatedAt: DateTime.now(),
        );

        await repo.saveNode(updated);
        invalidateMindmapState(ref, day: node.day);
      },
      builder: (context, candidateData, rejectedData) {
        final isAccepting = candidateData.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: width,
          decoration: BoxDecoration(
            color: isAccepting
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAccepting
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
              width: isAccepting ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Column header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _columnHeaderColor(
                    column,
                    theme,
                  ).withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      column.icon,
                      size: 18,
                      color: _columnHeaderColor(column, theme),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        column.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _columnHeaderColor(column, theme),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _columnHeaderColor(
                          column,
                          theme,
                        ).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${nodes.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _columnHeaderColor(column, theme),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Cards
              if (nodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Drop tasks here',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      for (final node in nodes) ...[
                        _KanbanCard(node: node, column: column),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({required this.node, required this.column});

  final MindmapNode node;
  final _KanbanColumn column;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final card = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => goToDay(context, node.day, highlightNodeId: node.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _nodeTypeIcon(node.type),
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      node.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: column == _KanbanColumn.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (node.priority.index >= NodePriority.high.index)
                    Icon(Icons.flag, size: 14, color: theme.colorScheme.error),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    dayKey(node.day),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (node.dueDate != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_outlined,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          dayKey(node.dueDate!),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (node.checklist.isNotEmpty) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: node.checklistProgress,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return LongPressDraggable<String>(
      data: node.id,
      delay: const Duration(milliseconds: 150),
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 250, child: Opacity(opacity: 0.85, child: card)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }
}

// ---------------------------------------------------------------------------
// GANTT VIEW
// ---------------------------------------------------------------------------

class _WorkspaceGanttView extends StatelessWidget {
  const _WorkspaceGanttView({required this.workspace});
  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = workspace.activeNodes;

    if (active.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.waterfall_chart_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text('No tasks to visualize', style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    // Compute timeline range
    DateTime earliest = active.first.day;
    DateTime latest = active.first.day;
    for (final node in active) {
      if (node.day.isBefore(earliest)) earliest = node.day;
      final end = node.dueDate ?? node.day;
      if (end.isAfter(latest)) latest = end;
    }
    // Add padding
    earliest = earliest.subtract(const Duration(days: 7));
    latest = latest.add(const Duration(days: 14));

    final totalDays = latest.difference(earliest).inDays + 1;
    const dayWidth = 40.0;
    const rowHeight = 40.0;
    const labelWidth = 180.0;
    final today = DateTime.now().dateOnly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _GanttLegendItem(
                color: theme.colorScheme.primary,
                label: 'Active',
              ),
              _GanttLegendItem(
                color: Colors.orange.shade400,
                label: 'In Progress',
              ),
              const _GanttLegendItem(color: Colors.green, label: 'Done'),
              _GanttLegendItem(
                color: theme.colorScheme.error,
                label: 'Overdue',
              ),
            ],
          ),
        ),

        // Chart area
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: labelWidth + (totalDays * dayWidth),
                height: (active.length * rowHeight) + 32,
                child: CustomPaint(
                  painter: _GanttChartPainter(
                    nodes: active,
                    earliest: earliest,
                    totalDays: totalDays,
                    dayWidth: dayWidth,
                    rowHeight: rowHeight,
                    labelWidth: labelWidth,
                    today: today,
                    theme: theme,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GanttLegendItem extends StatelessWidget {
  const _GanttLegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _GanttChartPainter extends CustomPainter {
  _GanttChartPainter({
    required this.nodes,
    required this.earliest,
    required this.totalDays,
    required this.dayWidth,
    required this.rowHeight,
    required this.labelWidth,
    required this.today,
    required this.theme,
  });

  final List<MindmapNode> nodes;
  final DateTime earliest;
  final int totalDays;
  final double dayWidth;
  final double rowHeight;
  final double labelWidth;
  final DateTime today;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    const headerHeight = 28.0;
    const chartTop = headerHeight;

    // Draw day headers
    final todayPaint = Paint()
      ..color = theme.colorScheme.primary.withValues(alpha: 0.1);
    final gridPaint = Paint()
      ..color = theme.dividerColor.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;

    for (var i = 0; i < totalDays; i++) {
      final day = earliest.add(Duration(days: i));
      final x = labelWidth + (i * dayWidth);

      // Today highlight
      if (day.year == today.year &&
          day.month == today.month &&
          day.day == today.day) {
        canvas.drawRect(Rect.fromLTWH(x, 0, dayWidth, size.height), todayPaint);
      }

      // Vertical grid line
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);

      // Day label (only show for start-of-week or every 3rd day)
      if (day.weekday == DateTime.monday || i % 3 == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${day.day}/${day.month}',
            style: TextStyle(
              fontSize: 9,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: dayWidth);
        tp.paint(canvas, Offset(x + 2, 4));
      }
    }

    // Horizontal separator under header
    canvas.drawLine(
      const Offset(0, headerHeight),
      Offset(size.width, headerHeight),
      Paint()..color = theme.dividerColor,
    );

    // Draw task rows
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final y = chartTop + (i * rowHeight);

      // Row separator
      if (i > 0) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }

      // Alternating row background
      if (i.isEven) {
        canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, rowHeight),
          Paint()
            ..color = theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.15,
            ),
        );
      }

      // Title label (truncated)
      final title = node.title.length > 22
          ? '${node.title.substring(0, 20)}â€¦'
          : node.title;
      final tp = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: 'â€¦',
      )..layout(maxWidth: labelWidth - 16);
      tp.paint(canvas, Offset(8, y + (rowHeight - tp.height) / 2));

      // Bar
      final start = node.day;
      final end = node.dueDate ?? node.day;
      final startOffset = start.difference(earliest).inDays;
      final duration = math.max(1, end.difference(start).inDays + 1);

      final barX = labelWidth + (startOffset * dayWidth) + 2;
      final barWidth = (duration * dayWidth) - 4;
      final barY = y + 8;
      final barHeight = rowHeight - 16;

      final barColor = _barColor(node);
      final barPaint = Paint()..color = barColor;
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(barX, barY, barWidth, barHeight),
        const Radius.circular(6),
      );
      canvas.drawRRect(barRect, barPaint);

      // Bar label
      if (barWidth > 30) {
        final barLabel = TextPainter(
          text: TextSpan(
            text: '${(node.progress * 100).round()}%',
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: barWidth - 8);
        barLabel.paint(
          canvas,
          Offset(barX + 4, barY + (barHeight - barLabel.height) / 2),
        );
      }
    }

    // Today indicator line
    final todayOffset = today.difference(earliest).inDays;
    if (todayOffset >= 0 && todayOffset < totalDays) {
      final todayX = labelWidth + (todayOffset * dayWidth) + (dayWidth / 2);
      canvas.drawLine(
        Offset(todayX, 0),
        Offset(todayX, size.height),
        Paint()
          ..color = theme.colorScheme.primary
          ..strokeWidth = 2,
      );
    }
  }

  Color _barColor(MindmapNode node) {
    if (node.isDone || node.status == NodeStatus.done) return Colors.green;
    if (node.dueDate != null && node.dueDate!.isBefore(today) && !node.isDone) {
      return theme.colorScheme.error;
    }
    if (node.status == NodeStatus.doing) return Colors.orange.shade400;
    return theme.colorScheme.primary;
  }

  @override
  bool shouldRepaint(covariant _GanttChartPainter oldDelegate) {
    return nodes != oldDelegate.nodes || today != oldDelegate.today;
  }
}

// ---------------------------------------------------------------------------
// SHARED HELPERS
// ---------------------------------------------------------------------------

IconData _statusIcon(NodeStatus status) => switch (status) {
  NodeStatus.open => Icons.radio_button_unchecked,
  NodeStatus.planned => Icons.event_outlined,
  NodeStatus.doing => Icons.sync_outlined,
  NodeStatus.waiting => Icons.hourglass_empty_outlined,
  NodeStatus.done => Icons.check_circle,
};

Color _statusColor(NodeStatus status, ThemeData theme) => switch (status) {
  NodeStatus.open => theme.colorScheme.onSurfaceVariant,
  NodeStatus.planned => theme.colorScheme.tertiary,
  NodeStatus.doing => Colors.orange.shade400,
  NodeStatus.waiting => theme.colorScheme.secondary,
  NodeStatus.done => Colors.green,
};

Color _columnHeaderColor(_KanbanColumn column, ThemeData theme) =>
    switch (column) {
      _KanbanColumn.open => theme.colorScheme.primary,
      _KanbanColumn.planned => theme.colorScheme.tertiary,
      _KanbanColumn.doing => Colors.orange.shade400,
      _KanbanColumn.waiting => theme.colorScheme.secondary,
      _KanbanColumn.done => Colors.green,
    };

IconData _nodeTypeIcon(NodeType type) => switch (type) {
  NodeType.task => Icons.check_circle_outline,
  NodeType.kanban => Icons.view_kanban_outlined,
  NodeType.plan => Icons.route_outlined,
  NodeType.note => Icons.notes_outlined,
  NodeType.journal => Icons.book_outlined,
  NodeType.habit => Icons.repeat_outlined,
  NodeType.goal => Icons.flag_outlined,
  NodeType.link => Icons.link_outlined,
  NodeType.event => Icons.event_outlined,
  NodeType.decision => Icons.rule_outlined,
  NodeType.resource => Icons.inventory_2_outlined,
  NodeType.idea => Icons.lightbulb_outline,
  NodeType.question => Icons.help_outline,
  NodeType.contact => Icons.person_outline,
  NodeType.metric => Icons.query_stats_outlined,
  NodeType.expense => Icons.payments_outlined,
  NodeType.bookmark => Icons.bookmark_border,
  NodeType.routine => Icons.repeat_on_outlined,
  NodeType.mood => Icons.mood,
  NodeType.timer => Icons.timer_outlined,
  NodeType.quote => Icons.format_quote_outlined,
  NodeType.audio => Icons.mic_none_outlined,
  NodeType.checklist => Icons.checklist_rtl_outlined,
  NodeType.canvas => Icons.gesture_outlined,
  NodeType.weather => Icons.wb_sunny_outlined,
  NodeType.fit => Icons.directions_run_outlined,
  NodeType.empty => Icons.crop_square_outlined,
};

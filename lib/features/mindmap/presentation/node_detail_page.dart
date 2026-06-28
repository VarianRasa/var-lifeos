import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../application/mindmap_providers.dart';
import '../domain/goal_progress.dart';
import '../domain/habit_completion.dart';
import '../domain/kanban_board.dart';
import '../domain/mindmap_node.dart';
import '../domain/plan_progress.dart';
import 'mindmap_canvas.dart'; // for nodeColor, nodeIcon
import 'node_editor_panel.dart';

class NodeDetailPage extends ConsumerWidget {
  const NodeDetailPage({required this.date, required this.nodeId, super.key});

  final DateTime date;
  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allNodesAsync = ref.watch(allMindmapNodesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to Mindmap',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            goToDay(context, date, highlightNodeId: nodeId);
          },
        ),
        title: const Text('Node Details'),
      ),
      body: allNodesAsync.when(
        data: (nodes) {
          final node = nodes.where((n) => n.id == nodeId).firstOrNull;
          if (node == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Node not found or has been deleted.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go(AppRoute.calendar.path),
                    child: const Text('Go to Calendar'),
                  ),
                ],
              ),
            );
          }

          // Calculate related/backlink nodes
          final relatedNodes = nodes.where((n) {
            return n.id != node.id &&
                (node.relatedNodeIds.contains(n.id) ||
                    n.relatedNodeIds.contains(node.id));
          }).toList();

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Layout: Grid-like split for large screens, linear for small screens
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 700;
                        final leftPanel = _buildLeftPanel(context, ref, node);
                        final rightPanel = _buildRightPanel(
                          context,
                          ref,
                          node,
                          relatedNodes,
                        );

                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 4, child: leftPanel),
                              const SizedBox(width: 24),
                              Expanded(flex: 5, child: rightPanel),
                            ],
                          );
                        } else {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              leftPanel,
                              const SizedBox(height: 24),
                              rightPanel,
                            ],
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildLeftPanel(
    BuildContext context,
    WidgetRef ref,
    MindmapNode node,
  ) {
    final theme = Theme.of(context);
    final color = nodeColor(node.type);
    final icon = nodeIcon(node.type);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category/Header Badge Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  avatar: Icon(icon, color: color, size: 16),
                  label: Text(
                    node.type.label,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: color.withValues(alpha: 0.1),
                  side: BorderSide(color: color.withValues(alpha: 0.2)),
                ),
                if (node.isPinned)
                  Icon(
                    Icons.push_pin,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Title
            Text(
              node.title.isEmpty ? 'Untitled ${node.type.name}' : node.title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // Metadata chips (Status, Priority, Project, Area, Date)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (node.status != NodeStatus.open ||
                    node.type == NodeType.task)
                  _buildMetaChip(
                    context,
                    Icons.lens,
                    node.status.label,
                    node.status == NodeStatus.done
                        ? Colors.green
                        : (node.status == NodeStatus.doing
                              ? Colors.blue
                              : Colors.orange),
                  ),
                if (node.priority != NodePriority.none)
                  _buildMetaChip(
                    context,
                    Icons.priority_high,
                    node.priority.label,
                    node.priority == NodePriority.high
                        ? Colors.red
                        : (node.priority == NodePriority.medium
                              ? Colors.orange
                              : Colors.grey),
                  ),
                if (node.project.isNotEmpty)
                  _buildMetaChip(
                    context,
                    Icons.folder_outlined,
                    'Proj: ${node.project}',
                    theme.colorScheme.primary,
                  ),
                if (node.area.isNotEmpty)
                  _buildMetaChip(
                    context,
                    Icons.category_outlined,
                    'Area: ${node.area}',
                    theme.colorScheme.secondary,
                  ),
                if (node.dueDate != null)
                  _buildMetaChip(
                    context,
                    Icons.event_outlined,
                    'Due: ${DateFormat('yyyy-MM-dd').format(node.dueDate!)}',
                    node.dueDate!.isBefore(DateTime.now().dateOnly)
                        ? Colors.red
                        : Colors.green,
                  ),
              ],
            ),
            const Divider(height: 32),
            // Body / Description
            Text('Description', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                node.body.isEmpty ? 'No description provided.' : node.body,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: node.body.isEmpty ? theme.hintColor : null,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Created/Updated Dates
            Text(
              'Created: ${DateFormat('yyyy-MM-dd HH:mm').format(node.createdAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
            Text(
              'Updated: ${DateFormat('yyyy-MM-dd HH:mm').format(node.updatedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
            const Divider(height: 32),
            // Quick Actions Button Row
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _editNode(context, ref, node),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: node.isPinned ? 'Unpin' : 'Pin',
                  icon: Icon(
                    node.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  onPressed: () => _togglePin(ref, node),
                ),
                IconButton.filledTonal(
                  tooltip: node.isArchived ? 'Unarchive' : 'Archive',
                  icon: Icon(
                    node.isArchived ? Icons.unarchive : Icons.archive_outlined,
                  ),
                  onPressed: () => _toggleArchive(ref, node),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref, node),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(
    BuildContext context,
    WidgetRef ref,
    MindmapNode node,
    List<MindmapNode> relatedNodes,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Type-Specific Feature Container
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Content & Progress',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (node.progress > 0)
                      Text(
                        '${(node.progress * 100).round()}% Completed',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                if (node.progress > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: node.progress,
                      minHeight: 8,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
                const Divider(height: 32),
                _buildTypeSpecificDashboard(context, ref, node),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Related / Connected Nodes
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.device_hub,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text('Connected Nodes', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 16),
                if (relatedNodes.isEmpty)
                  Text(
                    'No other nodes are linked to this node.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2.8,
                        ),
                    itemCount: relatedNodes.length,
                    itemBuilder: (context, index) {
                      final rel = relatedNodes[index];
                      final col = nodeColor(rel.type);
                      return InkWell(
                        onTap: () {
                          // Navigate to related node detail
                          context.go(
                            '/calendar/${dayKey(rel.day)}/node/${rel.id}',
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.dividerColor.withValues(alpha: 0.6),
                            ),
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: col.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  nodeIcon(rel.type),
                                  color: col,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      rel.title.isEmpty
                                          ? 'Untitled ${rel.type.name}'
                                          : rel.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    Text(
                                      dayKey(rel.day),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: theme.hintColor),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: theme.hintColor,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeSpecificDashboard(
    BuildContext context,
    WidgetRef ref,
    MindmapNode node,
  ) {
    switch (node.type) {
      case NodeType.task:
        return _buildTaskDashboard(ref, node);
      case NodeType.kanban:
        return _buildKanbanDashboard(ref, node);
      case NodeType.plan:
        return _buildPlanDashboard(ref, node);
      case NodeType.goal:
        return _buildGoalDashboard(ref, node);
      case NodeType.habit:
        return _buildHabitDashboard(context, ref, node);
      case NodeType.journal:
        return _buildJournalDashboard(ref, node);
      case NodeType.note:
        return _buildNoteDashboard(context, node);
      case NodeType.link:
        return _buildLinkDashboard(context, node);
      case NodeType.empty:
        return const Text('Empty Node.');
    }
  }

  // TASK DASHBOARD
  Widget _buildTaskDashboard(WidgetRef ref, MindmapNode node) {
    if (node.checklist.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'This task has no checklist items. Edit the node to add some!',
        ),
      );
    }

    return Column(
      children: node.checklist.map((item) {
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            item.title,
            style: TextStyle(
              decoration: item.isDone ? TextDecoration.lineThrough : null,
              color: item.isDone ? Colors.grey : null,
            ),
          ),
          value: item.isDone,
          onChanged: (val) {
            if (val != null) {
              _toggleChecklistItem(ref, node, item.id, val);
            }
          },
        );
      }).toList(),
    );
  }

  // KANBAN DASHBOARD
  Widget _buildKanbanDashboard(WidgetRef ref, MindmapNode node) {
    final board = KanbanBoard.fromNodeData(node.data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Grid columns
        for (final col in KanbanColumn.values) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      col.label.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${board.cardsFor(col).length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (board.cardsFor(col).isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        'No cards here',
                        style: TextStyle(
                          color: Colors.grey.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                else
                  ...board.cardsFor(col).map((card) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                card.title,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            if (col.next != null)
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.arrow_forward_outlined,
                                  size: 18,
                                ),
                                onPressed: () {
                                  _moveKanbanCard(ref, node, board, card.id);
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // PLAN DASHBOARD
  Widget _buildPlanDashboard(WidgetRef ref, MindmapNode node) {
    final steps = planSteps(node);
    if (steps.isEmpty) {
      return const Text('This plan has no steps. Edit the node to add some!');
    }

    final completed = completedPlanSteps(node);
    return Column(
      children: steps.map((step) {
        final isDone = completed.contains(step);
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            step,
            style: TextStyle(
              decoration: isDone ? TextDecoration.lineThrough : null,
              color: isDone ? Colors.grey : null,
            ),
          ),
          value: isDone,
          onChanged: (val) {
            if (val != null) {
              _togglePlanStepItem(ref, node, step, val);
            }
          },
        );
      }).toList(),
    );
  }

  // GOAL DASHBOARD
  Widget _buildGoalDashboard(WidgetRef ref, MindmapNode node) {
    final milestones = goalMilestones(node);
    if (milestones.isEmpty) {
      return const Text(
        'This goal has no milestones. Edit the node to add some!',
      );
    }

    final completed = completedGoalMilestones(node);
    return Column(
      children: milestones.map((milestone) {
        final isDone = completed.contains(milestone);
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            milestone,
            style: TextStyle(
              decoration: isDone ? TextDecoration.lineThrough : null,
              color: isDone ? Colors.grey : null,
            ),
          ),
          value: isDone,
          onChanged: (val) {
            if (val != null) {
              _toggleGoalMilestoneItem(ref, node, milestone, val);
            }
          },
        );
      }).toList(),
    );
  }

  // HABIT DASHBOARD
  Widget _buildHabitDashboard(
    BuildContext context,
    WidgetRef ref,
    MindmapNode node,
  ) {
    final completions = habitCompletionKeys(node);
    final currentStreak = calculateCurrentStreak(node);
    final maxStreak = calculateMaxStreak(node);
    final theme = Theme.of(context);

    // We render the past 14 days completion tracker
    final List<DateTime> pastDays = List.generate(14, (index) {
      return DateTime.now().dateOnly.subtract(Duration(days: 13 - index));
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Streak Tracker',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (currentStreak > 0) ...[
                  Text(
                    '🔥 $currentStreak day streak',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(max: $maxStreak)',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  '${completions.length} total completions',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: pastDays.map((day) {
            final isDone = completions.contains(dayKey(day));
            final isToday = day.isSameDay(DateTime.now());

            return InkWell(
              onTap: () => _toggleHabitDay(ref, node, day, !isDone),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isDone
                      ? Colors.green.withValues(alpha: 0.15)
                      : (isToday
                            ? Colors.blue.withValues(alpha: 0.05)
                            : Colors.transparent),
                  border: Border.all(
                    color: isDone
                        ? Colors.green
                        : (isToday
                              ? Colors.blue
                              : Colors.grey.withValues(alpha: 0.3)),
                    width: isToday ? 2.0 : 1.0,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('E').format(day).substring(0, 2),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isDone
                            ? Colors.green
                            : (isToday ? Colors.blue : Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDone
                            ? Colors.green
                            : (isToday ? Colors.blue : null),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text(
          '* Tap any day above to toggle completion state for that day.',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: Colors.grey,
          ),
        ),
        const Divider(height: 32),
        _HabitHeatmap(node: node),
      ],
    );
  }

  // JOURNAL DASHBOARD
  Widget _buildJournalDashboard(WidgetRef ref, MindmapNode node) {
    final theme = Theme.of(ref.context);
    final journal = node.data['journal'] as Map?;
    if (journal == null) {
      return const Text('This journal entry has no details yet.');
    }

    final mood = journal['mood'] as int?;
    final energy = journal['energy'] as int?;
    final prompt = journal['prompt'] as String?;
    final gratitudes = (journal['gratitude'] as List?)?.cast<String>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mood != null || energy != null) ...[
          Row(
            children: [
              if (mood != null)
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.2,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.wb_sunny_outlined,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text('Mood', style: theme.textTheme.labelSmall),
                          Text(
                            '$mood/10',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (mood != null && energy != null) const SizedBox(width: 8),
              if (energy != null)
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.2,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.bolt,
                            color: Colors.yellow,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text('Energy', style: theme.textTheme.labelSmall),
                          Text(
                            '$energy/10',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (prompt != null && prompt.trim().isNotEmpty) ...[
          Text('Daily Reflection Prompt', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(prompt, style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
        ],
        if (gratitudes.isNotEmpty) ...[
          Text('Gratitude List', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          ...gratitudes.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.favorite,
                    size: 14,
                    color: Colors.red.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(g)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // NOTE DASHBOARD
  Widget _buildNoteDashboard(BuildContext context, MindmapNode node) {
    final noteData = node.data['note'] as Map?;
    final source = noteData?['source'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (source.isNotEmpty) ...[
          const Text(
            'Note Source:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: source));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Source link copied to clipboard'),
                ),
              );
            },
            child: Text(
              source,
              style: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const Text(
          'Notes are formatted in simple text block. Use Edit button to add or change details.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  // LINK DASHBOARD
  Widget _buildLinkDashboard(BuildContext context, MindmapNode node) {
    final linkData = node.data['link'] as Map?;
    final url = linkData?['url'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url.isEmpty)
          const Text('No URL link has been configured.')
        else ...[
          const Text('URL Link', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
              color: Colors.blue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    url,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy Link',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied URL link to clipboard'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // STATE HELPERS
  void _toggleChecklistItem(
    WidgetRef ref,
    MindmapNode node,
    String itemId,
    bool isDone,
  ) async {
    final updatedChecklist = node.checklist.map((item) {
      return item.id == itemId ? item.copyWith(isDone: isDone) : item;
    }).toList();

    final doneCount = updatedChecklist.where((item) => item.isDone).length;
    final progress = updatedChecklist.isEmpty
        ? 0.0
        : doneCount / updatedChecklist.length;
    final allDone =
        doneCount == updatedChecklist.length && updatedChecklist.isNotEmpty;

    final updatedNode = node.copyWith(
      checklist: updatedChecklist,
      progress: progress,
      isDone: allDone,
      status: allDone
          ? NodeStatus.done
          : (progress > 0 ? NodeStatus.doing : NodeStatus.open),
      updatedAt: DateTime.now(),
    );

    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _moveKanbanCard(
    WidgetRef ref,
    MindmapNode node,
    KanbanBoard board,
    String cardId,
  ) async {
    final updatedBoard = board.moveCardToNextColumn(cardId);
    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(
      node.copyWith(
        data: {...node.data, 'kanban': updatedBoard.toJson()},
        updatedAt: DateTime.now(),
      ),
    );
    invalidateMindmapState(ref, day: node.day);
  }

  void _togglePlanStepItem(
    WidgetRef ref,
    MindmapNode node,
    String step,
    bool isDone,
  ) async {
    final completed = completedPlanSteps(node).toList();
    if (isDone) {
      if (!completed.contains(step)) completed.add(step);
    } else {
      completed.remove(step);
    }
    completed.sort();

    final steps = planSteps(node);
    final completedCount = completed.length;
    final progress = steps.isEmpty ? 0.0 : completedCount / steps.length;
    final isComplete = completedCount == steps.length && steps.isNotEmpty;

    final updatedNode = node.copyWith(
      data: {
        ...node.data,
        'plan': {
          ...(node.data['plan'] as Map? ?? {}),
          'steps': steps,
          'completedSteps': completed,
        },
      },
      progress: progress,
      status: isComplete
          ? NodeStatus.done
          : (progress > 0 ? NodeStatus.doing : NodeStatus.open),
      isDone: isComplete,
      updatedAt: DateTime.now(),
    );

    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _toggleGoalMilestoneItem(
    WidgetRef ref,
    MindmapNode node,
    String milestone,
    bool isDone,
  ) async {
    final completed = completedGoalMilestones(node).toList();
    if (isDone) {
      if (!completed.contains(milestone)) completed.add(milestone);
    } else {
      completed.remove(milestone);
    }
    completed.sort();

    final milestones = goalMilestones(node);
    final completedCount = completed.length;
    final progress = milestones.isEmpty
        ? 0.0
        : completedCount / milestones.length;

    final updatedNode = node.copyWith(
      data: {
        ...node.data,
        'goal': {
          ...(node.data['goal'] as Map? ?? {}),
          'milestones': milestones,
          'completedMilestones': completed,
        },
      },
      progress: progress,
      updatedAt: DateTime.now(),
    );

    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _toggleHabitDay(
    WidgetRef ref,
    MindmapNode node,
    DateTime day,
    bool isDone,
  ) async {
    final keys = habitCompletionKeys(node).toList();
    final dayStr = dayKey(day.dateOnly);
    if (isDone) {
      if (!keys.contains(dayStr)) keys.add(dayStr);
    } else {
      keys.remove(dayStr);
    }
    keys.sort();

    final updatedNode = node.copyWith(
      data: {
        ...node.data,
        'habit': {...(node.data['habit'] as Map? ?? {}), 'completions': keys},
      },
      updatedAt: DateTime.now(),
    );

    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _togglePin(WidgetRef ref, MindmapNode node) async {
    final updatedNode = node.copyWith(
      isPinned: !node.isPinned,
      updatedAt: DateTime.now(),
    );
    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _toggleArchive(WidgetRef ref, MindmapNode node) async {
    final updatedNode = node.copyWith(
      isArchived: !node.isArchived,
      updatedAt: DateTime.now(),
    );
    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _editNode(BuildContext context, WidgetRef ref, MindmapNode node) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: NodeEditorPanel(
                node: node,
                onSave: (updated) async {
                  final repository = ref.read(mindmapRepositoryProvider);
                  await repository.saveNode(updated);
                  invalidateMindmapState(
                    ref,
                    day: node.day,
                    extraDay: updated.day,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                onClose: () => Navigator.pop(context),
                onDelete: () async {
                  final repository = ref.read(mindmapRepositoryProvider);
                  await repository.deleteNode(node.id);
                  invalidateMindmapState(ref, day: node.day);
                  if (context.mounted) {
                    Navigator.pop(context); // Close bottom sheet
                    goToDay(context, node.day); // Redirect back to day page
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, MindmapNode node) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Node'),
        content: Text(
          'Are you sure you want to delete "${node.title.isEmpty ? 'Untitled' : node.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              final repository = ref.read(mindmapRepositoryProvider);
              await repository.deleteNode(node.id);
              invalidateMindmapState(ref, day: node.day);
              if (context.mounted) {
                Navigator.pop(context); // Close dialog
                goToDay(context, node.day); // Redirect to day page
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _HabitHeatmap extends StatelessWidget {
  const _HabitHeatmap({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completions = habitCompletionKeys(node);
    final today = DateTime.now().dateOnly;
    final offsetDays = today.weekday % 7;
    final startDate = today.subtract(Duration(days: 52 * 7 + offsetDays));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Completions Heatmap',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(53, (weekIndex) {
                  return Column(
                    children: List.generate(7, (dayIndex) {
                      final day = startDate.add(
                        Duration(days: weekIndex * 7 + dayIndex),
                      );
                      final key = dayKey(day);
                      final isDone = completions.contains(key);
                      final isFuture = day.isAfter(today);
                      final isToday = day.isSameDay(today);

                      Color cellColor;
                      if (isFuture) {
                        cellColor = theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.1);
                      } else if (isDone) {
                        cellColor = NodeColors.habit;
                      } else if (isToday) {
                        cellColor = NodeColors.habit.withValues(alpha: 0.15);
                      } else {
                        cellColor = theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4);
                      }

                      BorderSide borderSide;
                      if (isToday) {
                        borderSide = const BorderSide(
                          color: NodeColors.habit,
                          width: 1.5,
                        );
                      } else {
                        borderSide = BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.25,
                          ),
                          width: 0.75,
                        );
                      }

                      final formattedDate = DateFormat(
                        'EEEE, MMM d, yyyy',
                      ).format(day);
                      final statusText = isDone
                          ? 'Completed'
                          : (isFuture ? 'Future' : 'Not completed');

                      return Tooltip(
                        message: '$formattedDate: $statusText',
                        child: Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.all(2.0),
                          decoration: BoxDecoration(
                            color: cellColor,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.fromBorderSide(borderSide),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

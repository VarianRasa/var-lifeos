/// Dedicated Life OS hub for Goals, Milestones, Habits, and Streaks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/node_visuals.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/error_message.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/domain/mindmap_node.dart';

class GoalsHabitsPage extends ConsumerStatefulWidget {
  const GoalsHabitsPage({super.key});

  @override
  ConsumerState<GoalsHabitsPage> createState() => _GoalsHabitsPageState();
}

class _GoalsHabitsPageState extends ConsumerState<GoalsHabitsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodesAsync = ref.watch(allMindmapNodesProvider);

    return Scaffold(
      body: nodesAsync.when(
        data: (nodes) {
          final goals = nodes
              .where((n) => n.type == NodeType.goal && !n.isArchived)
              .toList();
          final habits = nodes
              .where((n) => n.type == NodeType.habit && !n.isArchived)
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.track_changes_rounded,
                      size: 28,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Goals & Habits Hub',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Track long-term objectives, milestones, and habit consistency.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: theme.colorScheme.primary,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    text: 'Goals (${goals.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.repeat_outlined, size: 18),
                    text: 'Habits (${habits.length})',
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _GoalsView(goals: goals),
                    _HabitsView(habits: habits),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => ErrorMessage(
          message: 'Failed to load goals & habits',
          onRetry: () => ref.invalidate(allMindmapNodesProvider),
        ),
      ),
    );
  }
}

class _GoalsView extends StatelessWidget {
  const _GoalsView({required this.goals});
  final List<MindmapNode> goals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final goalColor = NodeVisuals.color(context, NodeType.goal);

    if (goals.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flag_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('No goals defined yet', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Add Goal nodes on any day canvas to see them here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: goals.length,
      itemBuilder: (context, index) {
        final goal = goals[index];
        final progress = goal.progress;
        final isDone = goal.isDone || goal.status == NodeStatus.done;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isDone ? Icons.check_circle : Icons.flag_rounded,
                      color: isDone ? semantic.success : goalColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        goal.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      tooltip: 'Open in Calendar',
                      onPressed: () =>
                          goToDay(context, goal.day, highlightNodeId: goal.id),
                    ),
                  ],
                ),
                if (goal.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    goal.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          color: isDone ? semantic.success : goalColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(progress * 100).round()}%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (goal.checklist.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final item in goal.checklist)
                        Chip(
                          avatar: Icon(
                            item.isDone
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 14,
                            color: item.isDone ? semantic.success : null,
                          ),
                          label: Text(
                            item.title,
                            style: TextStyle(
                              decoration: item.isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HabitsView extends StatelessWidget {
  const _HabitsView({required this.habits});
  final List<MindmapNode> habits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final habitColor = NodeVisuals.color(context, NodeType.habit);

    if (habits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.repeat_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('No habits tracked yet', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Add Habit nodes on any day canvas to track consistency.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: habits.length,
      itemBuilder: (context, index) {
        final habit = habits[index];
        final isDone = habit.isDone || habit.status == NodeStatus.done;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDone
                        ? semantic.successMuted
                        : habitColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.repeat,
                    color: isDone ? semantic.success : habitColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Created on ${dayKey(habit.day)} · ${isDone ? 'Completed today' : 'Open'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  tooltip: 'Open in Calendar',
                  onPressed: () =>
                      goToDay(context, habit.day, highlightNodeId: habit.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

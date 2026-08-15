import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../calendar/application/focus_session.dart';
import '../../application/mindmap_providers.dart';
import '../../domain/habit_completion.dart';
import '../../domain/hybrid_timer.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_type_payloads.dart';
import '../../domain/project_plan.dart';
import 'node_mini_app_common.dart';

class NodeAnalyticsTab extends ConsumerWidget {
  const NodeAnalyticsTab({required this.node, super.key});

  final MindmapNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiniAppSection(
                title: '${node.type.label} analytics',
                subtitle: 'Metrics derived from persisted node data.',
                icon: Icons.analytics_outlined,
                child: _typeAnalytics(context, ref),
              ),
              const SizedBox(height: 16),
              MiniAppSection(
                title: 'Node information',
                icon: Icons.info_outline,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    MiniAppStat(
                      label: 'Progress',
                      value: '${(node.progress * 100).round()}%',
                      icon: Icons.donut_large,
                    ),
                    MiniAppStat(
                      label: 'Status',
                      value: node.status.label,
                      icon: Icons.flag_outlined,
                    ),
                    MiniAppStat(
                      label: 'Relations',
                      value: '${node.relatedNodeIds.length}',
                      icon: Icons.hub_outlined,
                    ),
                    MiniAppStat(
                      label: 'Payload keys',
                      value: '${node.data.length}',
                      icon: Icons.data_object,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _typeAnalytics(BuildContext context, WidgetRef ref) =>
      switch (node.type) {
        NodeType.task => _taskAnalytics(context),
        NodeType.kanban => _kanbanAnalytics(context),
        NodeType.plan => _planAnalytics(context),
        NodeType.timer => _timerAnalytics(context),
        NodeType.note => _noteAnalytics(context),
        NodeType.journal => _journalAnalytics(context, ref),
        NodeType.decision => _decisionAnalytics(context),
        NodeType.idea => _ideaAnalytics(context),
        NodeType.canvas => _canvasAnalytics(context),
        NodeType.habit || NodeType.routine => _habitAnalytics(context),
        NodeType.fit => _fitnessAnalytics(context),
        NodeType.expense => _expenseAnalytics(context),
        NodeType.itinerary => _itineraryAnalytics(context),
        _ => MiniAppProgressMeter(label: 'Completion', value: node.progress),
      };

  Widget _taskAnalytics(BuildContext context) => Column(
    children: [
      MiniAppProgressMeter(
        label: 'Subtask completion',
        value: node.checklist.isEmpty ? node.progress : node.checklistProgress,
        detail: node.checklist.isEmpty
            ? '${(node.progress * 100).round()}%'
            : '${node.completedChecklistCount}/${node.checklist.length}',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          MiniAppStat(
            label: 'Focus time',
            value: '${totalFocusMinutes(node)} min',
            icon: Icons.timer_outlined,
          ),
          MiniAppStat(
            label: 'Blockers',
            value: '${node.blockedByNodeIds.length}',
            icon: Icons.account_tree_outlined,
          ),
        ],
      ),
    ],
  );

  Widget _kanbanAnalytics(BuildContext context) {
    final payload = KanbanPayload.fromNode(node);
    return Column(
      children: [
        for (final column in payload.columns) ...[
          MiniAppProgressMeter(
            label: column.title,
            value: payload.cards.isEmpty
                ? 0
                : payload.cards
                          .where((card) => card.columnId == column.id)
                          .length /
                      payload.cards.length,
            detail:
                '${payload.cards.where((card) => card.columnId == column.id).length} cards',
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _planAnalytics(BuildContext context) {
    final tasks = PlanPayload.fromNode(node).project.tasks;
    final done = tasks
        .where((task) => task.status == ProjectTaskStatus.done)
        .length;
    final estimate = tasks.fold<int>(
      0,
      (sum, task) => sum + (task.estimatedMinutes ?? 0),
    );
    final actual = tasks.fold<int>(
      0,
      (sum, task) => sum + (task.actualMinutes ?? 0),
    );
    return Column(
      children: [
        MiniAppProgressMeter(
          label: 'Project tasks',
          value: tasks.isEmpty ? 0 : done / tasks.length,
          detail: '$done/${tasks.length}',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          children: [
            MiniAppStat(
              label: 'Estimate',
              value: '$estimate min',
              icon: Icons.hourglass_top,
            ),
            MiniAppStat(
              label: 'Actual',
              value: '$actual min',
              icon: Icons.timer,
            ),
          ],
        ),
      ],
    );
  }

  Widget _timerAnalytics(BuildContext context) {
    final timer = TimerPayload.fromNode(node).timer;
    final focus = timer.history.where(
      (item) => item.segment == FocusSegment.focus,
    );
    final focusSeconds = focus.fold<int>(
      0,
      (sum, item) => sum + item.actualSeconds,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(const Duration(days: 6));
    final todaySeconds = focus
        .where((item) => DateUtils.isSameDay(item.completedAt.toLocal(), today))
        .fold<int>(0, (sum, item) => sum + item.actualSeconds);
    final weekSeconds = focus
        .where(
          (item) => !DateTime(
            item.completedAt.year,
            item.completedAt.month,
            item.completedAt.day,
          ).isBefore(weekStart),
        )
        .fold<int>(0, (sum, item) => sum + item.actualSeconds);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        MiniAppStat(
          label: 'Sessions',
          value: '${timer.history.length}',
          icon: Icons.repeat,
        ),
        MiniAppStat(
          label: 'Focus time',
          value: '${focusSeconds ~/ 60} min',
          icon: Icons.center_focus_strong,
        ),
        MiniAppStat(
          label: 'Today',
          value: '${todaySeconds ~/ 60} min',
          icon: Icons.today_outlined,
        ),
        MiniAppStat(
          label: 'Last 7 days',
          value: '${weekSeconds ~/ 60} min',
          icon: Icons.date_range_outlined,
        ),
        MiniAppStat(
          label: 'Cycles',
          value: '${timer.completedCycles}',
          icon: Icons.loop,
        ),
      ],
    );
  }

  Widget _noteAnalytics(BuildContext context) {
    final words = RegExp(r'\S+').allMatches(node.body).length;
    final headings = node.body
        .split('\n')
        .where((line) => RegExp(r'^#{1,6}\s+').hasMatch(line.trim()))
        .length;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        MiniAppStat(label: 'Words', value: '$words', icon: Icons.notes),
        MiniAppStat(
          label: 'Reading time',
          value: '${words == 0 ? 0 : (words / 200).ceil()} min',
          icon: Icons.schedule,
        ),
        MiniAppStat(
          label: 'Headings',
          value: '$headings',
          icon: Icons.format_size,
        ),
      ],
    );
  }

  Widget _journalAnalytics(BuildContext context, WidgetRef ref) {
    final payload = JournalPayload.fromNode(node);
    final journals =
        (ref.watch(allMindmapNodesProvider).valueOrNull ?? const [])
            .where((item) => item.type == NodeType.journal && !item.isArchived)
            .map(JournalPayload.fromNode)
            .toList();
    final recent = journals
        .where(
          (item) => !item.date.isBefore(
            DateTime.now().subtract(const Duration(days: 29)),
          ),
        )
        .toList();
    double average(Iterable<int?> values) {
      final available = values.whereType<int>().toList();
      return available.isEmpty
          ? 0
          : available.fold<int>(0, (sum, value) => sum + value) /
                available.length;
    }

    return Column(
      children: [
        MiniAppProgressMeter(
          label: 'Mood',
          value: (payload.mood ?? 0) / 10,
          detail: payload.mood == null ? 'Unset' : '${payload.mood}/10',
        ),
        const SizedBox(height: 12),
        MiniAppProgressMeter(
          label: 'Energy',
          value: (payload.energy ?? 0) / 10,
          detail: payload.energy == null ? 'Unset' : '${payload.energy}/10',
          color: Theme.of(context).colorScheme.tertiary,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            MiniAppStat(
              label: '30-day mood',
              value: average(
                recent.map((item) => item.mood),
              ).toStringAsFixed(1),
              icon: Icons.mood,
            ),
            MiniAppStat(
              label: '30-day energy',
              value: average(
                recent.map((item) => item.energy),
              ).toStringAsFixed(1),
              icon: Icons.bolt,
            ),
          ],
        ),
      ],
    );
  }

  Widget _decisionAnalytics(BuildContext context) {
    final payload = DecisionPayload.fromNode(node);
    return Column(
      children: [
        MiniAppProgressMeter(
          label: 'Decision readiness',
          value: payload.decisionCompleted / 5,
          detail: '${payload.decisionCompleted}/5 checks',
        ),
        const SizedBox(height: 12),
        MiniAppStat(
          label: 'Options',
          value: '${payload.options.length}',
          icon: Icons.alt_route,
        ),
      ],
    );
  }

  Widget _ideaAnalytics(BuildContext context) {
    final payload = IdeaPayload.fromNode(node);
    return Column(
      children: [
        MiniAppProgressMeter(
          label: 'Validation',
          value: payload.validationCompleted / 3,
          detail: '${payload.validationCompleted}/3 signals',
        ),
        const SizedBox(height: 12),
        MiniAppProgressMeter(
          label: 'Confidence',
          value: payload.confidence / 100,
          detail: '${payload.confidence}%',
        ),
      ],
    );
  }

  Widget _canvasAnalytics(BuildContext context) {
    final payload = CanvasPayload.fromNode(node);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        MiniAppStat(
          label: 'Elements',
          value: '${payload.elements.length}',
          icon: Icons.layers,
        ),
        MiniAppStat(
          label: 'Strokes',
          value: '${payload.drawingCount}',
          icon: Icons.gesture,
        ),
        MiniAppStat(
          label: 'Text',
          value: '${payload.textCount}',
          icon: Icons.text_fields,
        ),
      ],
    );
  }

  Widget _habitAnalytics(BuildContext context) {
    final stats = calculateHabitStreakStats(node, DateTime.now());
    return Column(
      children: [
        MiniAppProgressMeter(
          label: '30-day consistency',
          value: stats.completionRate30Days,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          children: [
            MiniAppStat(
              label: 'Current streak',
              value: '${stats.currentStreak}',
              icon: Icons.local_fire_department,
            ),
            MiniAppStat(
              label: 'Best streak',
              value: '${stats.maxStreak}',
              icon: Icons.emoji_events,
            ),
          ],
        ),
      ],
    );
  }

  Widget _fitnessAnalytics(BuildContext context) {
    final fit = FitPayload.fromNode(node);
    return Column(
      children: [
        MiniAppProgressMeter(
          label: 'Steps',
          value: (fit.steps ?? 0) / fit.stepGoal,
          detail: '${(fit.steps ?? 0).round()}/${fit.stepGoal.round()}',
        ),
        const SizedBox(height: 12),
        MiniAppProgressMeter(
          label: 'Active minutes',
          value: (fit.durationMinutes ?? 0) / fit.durationGoalMinutes,
          detail:
              '${(fit.durationMinutes ?? 0).round()}/${fit.durationGoalMinutes.round()} min',
        ),
      ],
    );
  }

  Widget _expenseAnalytics(BuildContext context) {
    final expense = ExpensePayload.fromNode(node);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        MiniAppStat(
          label: 'Amount',
          value:
              '${expense.currency.isEmpty ? 'USD' : expense.currency} ${(expense.amount ?? 0).toStringAsFixed(2)}',
          icon: Icons.payments,
        ),
        MiniAppStat(
          label: 'Category',
          value: expense.category.isEmpty ? 'Uncategorized' : expense.category,
          icon: Icons.category,
        ),
        MiniAppStat(
          label: 'Receipts',
          value: '${expense.receipts.length}',
          icon: Icons.receipt_long,
        ),
      ],
    );
  }

  Widget _itineraryAnalytics(BuildContext context) {
    final payload = ItineraryPayload.fromNode(node);
    final insights = ItineraryInsights.fromPayload(payload);
    return Column(
      children: [
        MiniAppProgressMeter(
          label: 'Readiness',
          value: insights.readinessScore / 100,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            MiniAppStat(
              label: 'Conflicts',
              value: '${insights.agendaConflicts.length}',
              icon: Icons.warning_amber,
            ),
            MiniAppStat(
              label: 'Pending bookings',
              value: '${insights.pendingBookings}',
              icon: Icons.confirmation_number_outlined,
            ),
            MiniAppStat(
              label: 'Essential unpacked',
              value: '${insights.pendingEssentialItems}',
              icon: Icons.luggage,
            ),
          ],
        ),
      ],
    );
  }
}

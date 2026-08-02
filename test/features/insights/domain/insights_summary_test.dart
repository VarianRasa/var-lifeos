import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/insights/domain/insights_summary.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('InsightsSummary calculates dashboard analytics from nodes', () {
    final today = DateTime(2026, 6, 18);
    final yesterday = today.addDays(-1);
    final twoDaysAgo = today.addDays(-2);
    final nodes = [
      MindmapNode.create(
        id: 'done-task',
        type: NodeType.task,
        title: 'Done task',
        day: today,
        status: NodeStatus.done,
        dueDate: today,
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'overdue-task',
        type: NodeType.task,
        title: 'Overdue task',
        day: yesterday,
        status: NodeStatus.doing,
        dueDate: yesterday,
        now: DateTime(2026, 6, 18, 9),
      ),
      MindmapNode.create(
        id: 'future-task',
        type: NodeType.task,
        title: 'Future task',
        day: today,
        dueDate: today.addDays(1),
        now: DateTime(2026, 6, 18, 10),
      ),
      MindmapNode.create(
        id: 'habit',
        type: NodeType.habit,
        title: 'Workout',
        day: today,
        data: const {
          'habit': {
            'completions': [
              '2026-06-14',
              '2026-06-15',
              '2026-06-16',
              '2026-06-17',
              '2026-06-18',
            ],
          },
        },
        now: DateTime(2026, 6, 18, 11),
      ),
      MindmapNode.create(
        id: 'goal',
        type: NodeType.goal,
        title: 'Launch v1',
        day: yesterday,
        data: const {
          'goal': {
            'milestones': ['Prototype', 'Beta'],
            'completedMilestones': ['Prototype'],
          },
        },
        now: DateTime(2026, 6, 18, 12),
      ),
      MindmapNode.create(
        id: 'weekly-journal',
        type: NodeType.journal,
        title: 'Weekly review',
        day: today,
        data: const {
          'journal': {'isWeeklyReview': true},
        },
        now: DateTime(2026, 6, 18, 13),
      ),
      MindmapNode.create(
        id: 'monthly-journal',
        type: NodeType.journal,
        title: 'Monthly review',
        day: twoDaysAgo,
        data: const {
          'journal': {'isMonthlyReview': true},
        },
        now: DateTime(2026, 6, 18, 14),
      ),
    ];

    final summary = InsightsSummary.fromNodes(today: today, nodes: nodes);

    expect(summary.totalNodeCount, 7);
    expect(summary.activeDayCount, 3);
    expect(summary.averageNodesPerActiveDay, closeTo(2.33, 0.01));
    expect(summary.busiestDay, today);
    expect(summary.busiestDayNodeCount, 4);
    expect(summary.taskCount, 3);
    expect(summary.completedTaskCount, 1);
    expect(summary.taskCompletionRate, closeTo(1 / 3, 0.001));
    expect(summary.overdueCount, 1);
    expect(summary.productiveDayCount, 3);
    expect(summary.habitConsistency, closeTo(5 / 7, 0.001));
    expect(summary.averageGoalProgress, 0.5);
    expect(summary.weeklyReviewCount, 1);
    expect(summary.monthlyReviewCount, 1);
  });

  test('InsightsWeeklyPulse summarizes recent activity and upcoming load', () {
    final today = DateTime(2026, 6, 18);
    final nodes = [
      MindmapNode.create(
        id: 'done-task',
        type: NodeType.task,
        title: 'Done task',
        day: today,
        status: NodeStatus.done,
        dueDate: today,
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'upcoming-task',
        type: NodeType.task,
        title: 'Upcoming task',
        day: today,
        dueDate: today.addDays(2),
        now: DateTime(2026, 6, 18, 9),
      ),
      MindmapNode.create(
        id: 'today-note',
        type: NodeType.note,
        title: 'Today note',
        day: today,
        now: DateTime(2026, 6, 18, 10),
      ),
      MindmapNode.create(
        id: 'yesterday-habit',
        type: NodeType.habit,
        title: 'Workout',
        day: today.addDays(-1),
        now: DateTime(2026, 6, 17, 8),
      ),
      MindmapNode.create(
        id: 'week-task',
        type: NodeType.task,
        title: 'Week task',
        day: today.addDays(-2),
        status: NodeStatus.doing,
        dueDate: today.addDays(-2),
        now: DateTime(2026, 6, 16, 8),
      ),
      MindmapNode.create(
        id: 'week-journal',
        type: NodeType.journal,
        title: 'Week journal',
        day: today.addDays(-2),
        now: DateTime(2026, 6, 16, 9),
      ),
      MindmapNode.create(
        id: 'older-note',
        type: NodeType.note,
        title: 'Older note',
        day: today.addDays(-4),
        now: DateTime(2026, 6, 14, 8),
      ),
      MindmapNode.create(
        id: 'outside-window',
        type: NodeType.note,
        title: 'Outside window',
        day: today.addDays(-8),
        now: DateTime(2026, 6, 10, 8),
      ),
    ];

    final pulse = InsightsWeeklyPulse.fromNodes(today: today, nodes: nodes);

    expect(pulse.days, hasLength(4));
    expect(pulse.activeDayCount, 3);
    expect(pulse.quietDayCount, 1);
    expect(pulse.busiestDay, today);
    expect(pulse.busiestDayNodeCount, 3);
    expect(pulse.taskCount, 3);
    expect(pulse.completedTaskCount, 1);
    expect(pulse.taskCompletionRate, closeTo(1 / 3, 0.001));
    expect(pulse.upcomingTaskCount, 1);
    expect(pulse.days.last.nodeCount, 3);
  });

  test('weekly review uses explicit range and updatedAt for wins', () {
    final start = DateTime(2026, 7, 20);
    final end = DateTime(2026, 7, 22);
    final nodes = [
      MindmapNode.create(
        id: 'win',
        type: NodeType.task,
        title: 'Finished old task',
        day: DateTime(2026, 7, 1),
        progress: 1,
        now: DateTime(2026, 7, 21),
      ),
      MindmapNode.create(
        id: 'old-win',
        type: NodeType.task,
        title: 'Finished before range',
        day: start,
        status: NodeStatus.done,
        now: DateTime(2026, 7, 19),
      ),
      MindmapNode.create(
        id: 'late',
        type: NodeType.task,
        title: 'Late at period end',
        day: start,
        dueDate: DateTime(2026, 7, 21),
        now: start,
      ),
      MindmapNode.create(
        id: 'archived-late',
        type: NodeType.task,
        title: 'Archived late',
        day: start,
        dueDate: DateTime(2026, 7, 21),
        isArchived: true,
        now: start,
      ),
    ];

    final review = InsightsWeeklyReview.fromNodes(today: end, nodes: nodes);

    expect(review.completedTasks.map((node) => node.id), ['win']);
    expect(review.overdueTasks.map((node) => node.id), ['late']);
  });
}

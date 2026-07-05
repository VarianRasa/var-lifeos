import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/insights/application/insights_summary.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('InsightsWindow creates matching previous windows', () {
    final today = DateTime(2026, 6, 18);

    final todayWindow = InsightsWindow.today(today);
    final weekWindow = InsightsWindow.week(today);
    final monthWindow = InsightsWindow.month(today);

    expect(todayWindow.start, DateTime(2026, 6, 18));
    expect(todayWindow.end, DateTime(2026, 6, 18));
    expect(todayWindow.previous.start, DateTime(2026, 6, 17));
    expect(todayWindow.previous.end, DateTime(2026, 6, 17));

    expect(weekWindow.start, DateTime(2026, 6, 15));
    expect(weekWindow.end, DateTime(2026, 6, 18));
    expect(weekWindow.previous.start, DateTime(2026, 6, 11));
    expect(weekWindow.previous.end, DateTime(2026, 6, 14));

    expect(monthWindow.start, DateTime(2026, 6));
    expect(monthWindow.end, DateTime(2026, 6, 18));
    expect(monthWindow.previous.start, DateTime(2026, 5, 14));
    expect(monthWindow.previous.end, DateTime(2026, 5, 31));
  });

  test('buildInsightsSummary totals current and previous windows', () {
    final today = DateTime(2026, 6, 18);
    final yesterday = today.addDays(-1);
    final previousWeekDay = DateTime(2026, 6, 13);
    final nodes = [
      MindmapNode.create(
        id: 'open',
        type: NodeType.task,
        title: 'Open task',
        day: today,
        dueDate: today,
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'done',
        type: NodeType.task,
        title: 'Done task',
        day: today,
        status: NodeStatus.done,
        now: DateTime(2026, 6, 18, 9),
      ),
      MindmapNode.create(
        id: 'overdue',
        type: NodeType.task,
        title: 'Overdue task',
        day: yesterday,
        dueDate: yesterday,
        priority: NodePriority.urgent,
        now: DateTime(2026, 6, 17, 9),
      ),
      MindmapNode.create(
        id: 'focus',
        type: NodeType.journal,
        title: 'Deep work review',
        day: today,
        data: const {
          'focus_sessions': [
            {'duration_mins': 25},
            {'duration_mins': 35},
          ],
          'journal': {'isWeeklyReview': true},
        },
        now: DateTime(2026, 6, 18, 10),
      ),
      MindmapNode.create(
        id: 'habit',
        type: NodeType.habit,
        title: 'Workout',
        day: today,
        data: const {
          'habit': {
            'completions': ['2026-06-18'],
          },
        },
        now: DateTime(2026, 6, 18, 11),
      ),
      MindmapNode.create(
        id: 'previous-done',
        type: NodeType.task,
        title: 'Previous done',
        day: previousWeekDay,
        status: NodeStatus.done,
        now: DateTime(2026, 6, 13, 8),
      ),
    ];

    final summaries = buildInsightsSummary(today: today, nodes: nodes);
    final todaySummary = summaries.singleWhere(
      (summary) => summary.window.kind == InsightsWindowKind.today,
    );
    final weekSummary = summaries.singleWhere(
      (summary) => summary.window.kind == InsightsWindowKind.week,
    );

    expect(todaySummary.current.openTasks, 1);
    expect(todaySummary.current.completedTasks, 1);
    expect(todaySummary.current.overdueTasks, 0);
    expect(todaySummary.current.focusMinutes, 60);
    expect(todaySummary.current.reviewCount, 1);
    expect(todaySummary.current.habitCompletionRate, 1);

    expect(weekSummary.current.openTasks, 2);
    expect(weekSummary.current.completedTasks, 1);
    expect(weekSummary.current.overdueTasks, 1);
    expect(weekSummary.current.highPriorityOpenTasks, 1);
    expect(weekSummary.previous.completedTasks, 1);
    expect(weekSummary.completedTaskDelta, 0);
  });

  test(
    'classifyInsightMissionStatus detects stable/improving/risk/critical',
    () {
      const empty = InsightMissionMetrics(
        openTasks: 0,
        completedTasks: 0,
        overdueTasks: 0,
        highPriorityOpenTasks: 0,
        focusMinutes: 0,
        habitCompletionRate: 0,
        reviewCount: 0,
      );

      expect(
        classifyInsightMissionStatus(current: empty, previous: empty),
        InsightMissionStatus.stable,
      );
      expect(
        classifyInsightMissionStatus(
          current: const InsightMissionMetrics(
            openTasks: 1,
            completedTasks: 3,
            overdueTasks: 0,
            highPriorityOpenTasks: 0,
            focusMinutes: 20,
            habitCompletionRate: 0,
            reviewCount: 0,
          ),
          previous: empty,
        ),
        InsightMissionStatus.improving,
      );
      expect(
        classifyInsightMissionStatus(
          current: const InsightMissionMetrics(
            openTasks: 2,
            completedTasks: 0,
            overdueTasks: 2,
            highPriorityOpenTasks: 0,
            focusMinutes: 0,
            habitCompletionRate: 0,
            reviewCount: 0,
          ),
          previous: empty,
        ),
        InsightMissionStatus.atRisk,
      );
      expect(
        classifyInsightMissionStatus(
          current: const InsightMissionMetrics(
            openTasks: 8,
            completedTasks: 0,
            overdueTasks: 5,
            highPriorityOpenTasks: 8,
            focusMinutes: 0,
            habitCompletionRate: 0,
            reviewCount: 0,
          ),
          previous: empty,
        ),
        InsightMissionStatus.critical,
      );
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/insights/application/context_health.dart';
import 'package:var_app/features/insights/application/focus_insights.dart';
import 'package:var_app/features/insights/application/goal_insights.dart';
import 'package:var_app/features/insights/application/habit_insights.dart';
import 'package:var_app/features/insights/application/insight_recommendations.dart';
import 'package:var_app/features/insights/application/insight_risk_engine.dart';
import 'package:var_app/features/insights/application/insights_markdown_export.dart';
import 'package:var_app/features/insights/application/insights_summary.dart';
import 'package:var_app/features/insights/application/insights_trends.dart';
import 'package:var_app/features/insights/application/review_insights.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('buildInsightsMarkdownReport includes expected sections', () {
    final today = DateTime(2026, 7, 2, 10, 30);
    final yesterday = DateTime(2026, 7, 1);
    final nodes = [
      MindmapNode.create(
        id: 'done',
        type: NodeType.task,
        title: 'Ship dashboard',
        day: today,
        status: NodeStatus.done,
        project: 'Var',
        tags: const ['release'],
        now: today,
      ),
      MindmapNode.create(
        id: 'late',
        type: NodeType.task,
        title: 'Fix overdue task',
        day: yesterday,
        priority: NodePriority.high,
        dueDate: yesterday,
        now: yesterday,
      ),
    ];

    final report = buildInsightsMarkdownReport(
      InsightsMarkdownReportInput(
        generatedAt: today,
        rangeStart: yesterday,
        rangeEnd: today,
        nodes: nodes,
        missionSummaries: buildInsightsSummary(today: today, nodes: nodes),
        completionTrend: buildCompletionTrend(
          start: yesterday,
          end: today,
          today: today,
          nodes: nodes,
        ),
        risks: const [
          InsightRisk(
            id: 'overdue-cluster',
            title: 'Overdue cluster',
            message: 'Tasks are past due.',
            severity: InsightRiskSeverity.high,
            actionType: InsightRiskActionType.scheduleOverdue,
            count: 3,
          ),
        ],
        recommendations: const [
          InsightRecommendation(
            id: 'schedule-overdue',
            title: 'Schedule overdue tasks',
            message: 'Move overdue work.',
            action: InsightRecommendationAction.scheduleOverdueTasks,
            priority: 80,
          ),
        ],
        contextHealth: buildContextHealthSummary(today: today, nodes: nodes),
        focusSummary: buildFocusInsightSummary(
          start: yesterday,
          end: today,
          nodes: nodes,
        ),
        habitSummary: buildHabitInsightSummary(
          start: yesterday,
          end: today,
          today: today,
          nodes: nodes,
        ),
        reviewSummary: buildReviewInsightSummary(
          start: yesterday,
          end: today,
          today: today,
          nodes: nodes,
        ),
        goalSummary: buildGoalInsightSummary(today: today, nodes: nodes),
      ),
    );

    expect(report, contains('# Var insights report'));
    expect(report, contains('## Summary metrics'));
    expect(report, contains('## Trend highlights'));
    expect(report, contains('## Risks'));
    expect(report, contains('Overdue cluster'));
    expect(report, contains('## Recommendations'));
    expect(report, contains('Schedule overdue tasks'));
    expect(report, contains('## Completed tasks'));
    expect(report, contains('Ship dashboard'));
    expect(report, contains('## Overdue tasks'));
    expect(report, contains('Fix overdue task'));
  });

  test('buildInsightsMarkdownReport is deterministic for empty data', () {
    final today = DateTime(2026, 7, 2, 10, 30);
    final report = buildInsightsMarkdownReport(
      InsightsMarkdownReportInput(
        generatedAt: today,
        rangeStart: today,
        rangeEnd: today,
        nodes: const [],
        missionSummaries: const [],
        completionTrend: const InsightTrendSeries(
          points: [],
          completionDirection: InsightTrendDirection.flat,
          openWorkDirection: InsightTrendDirection.flat,
          overdueDirection: InsightTrendDirection.flat,
          highPriorityDirection: InsightTrendDirection.flat,
        ),
        risks: const [],
        recommendations: const [],
        contextHealth: const ContextHealthSummary(
          items: [],
          neglectedContexts: [],
          hotContexts: [],
        ),
        focusSummary: const FocusInsightSummary(
          totalMinutes: 0,
          minutesByDay: [],
          minutesByProject: [],
          minutesByArea: [],
          minutesByTag: [],
          bestFocusDay: null,
          bestFocusMinutes: 0,
          plannedOpenTasks: 0,
          hasLowFocusWarning: false,
        ),
        habitSummary: const HabitInsightSummary(
          habitCount: 0,
          completionRate: 0,
          completedCount: 0,
          expectedCount: 0,
          missedHabits: [],
          streaks: [],
          mostConsistentHabit: null,
          streakAtRisk: null,
        ),
        reviewSummary: const ReviewInsightSummary(
          journalCount: 0,
          reviewCount: 0,
          lastReviewDate: null,
          currentReflectionStreak: 0,
          longestReflectionStreak: 0,
          reviewGaps: [],
          keywordBuckets: {},
          hasReviewThisWeek: false,
        ),
        goalSummary: const GoalInsightSummary(
          goalCount: 0,
          averageProgress: 0,
          notStartedCount: 0,
          inProgressCount: 0,
          completedCount: 0,
          stalledGoals: [],
          recentlyProgressedGoals: [],
          needsNextActionGoals: [],
          milestoneMomentumCount: 0,
          items: [],
        ),
      ),
    );

    expect(report, contains('- No active risks.'));
    expect(report, contains('- No recommended actions.'));
    expect(report, contains('- No completed tasks.'));
    expect(report, contains('- No overdue tasks.'));
  });
}

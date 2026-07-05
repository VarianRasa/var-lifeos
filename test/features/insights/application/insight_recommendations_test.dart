import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/insights/application/insight_recommendations.dart';
import 'package:var_app/features/insights/application/insight_risk_engine.dart';

void main() {
  test('buildInsightRecommendations prioritizes critical risks first', () {
    final items = buildInsightRecommendations(
      risks: const [
        InsightRisk(
          id: 'watch',
          title: 'Watch risk',
          message: 'Watch',
          severity: InsightRiskSeverity.watch,
          actionType: InsightRiskActionType.createWeeklyReview,
          count: 1,
        ),
        InsightRisk(
          id: 'critical',
          title: 'Critical risk',
          message: 'Critical',
          severity: InsightRiskSeverity.critical,
          actionType: InsightRiskActionType.scheduleOverdue,
          count: 1,
        ),
      ],
      reviewCount: 1,
      hasContextFilter: true,
    );

    expect(items.first.id, 'risk-critical');
    expect(
      items.first.action,
      InsightRecommendationAction.scheduleOverdueTasks,
    );
  });

  test('buildInsightRecommendations adds fallback actions', () {
    final items = buildInsightRecommendations(
      risks: const [],
      overdueCount: 2,
      openTaskCount: 7,
      reviewCount: 0,
    );

    expect(items.map((item) => item.id), contains('schedule-overdue-tasks'));
    expect(items.map((item) => item.id), contains('balance-workload'));
    expect(items.map((item) => item.id), contains('create-weekly-review'));
    expect(items.map((item) => item.id), contains('export-report'));
  });

  test(
    'buildInsightRecommendations uses stable ordering for equal priority',
    () {
      final items = buildInsightRecommendations(
        risks: const [
          InsightRisk(
            id: 'b-risk',
            title: 'B',
            message: 'B',
            severity: InsightRiskSeverity.watch,
            actionType: InsightRiskActionType.openCalendar,
          ),
          InsightRisk(
            id: 'a-risk',
            title: 'A',
            message: 'A',
            severity: InsightRiskSeverity.watch,
            actionType: InsightRiskActionType.openCalendar,
          ),
        ],
        reviewCount: 1,
        hasContextFilter: true,
      );

      expect(items.map((item) => item.id).take(2), [
        'risk-a-risk',
        'risk-b-risk',
      ]);
    },
  );
}

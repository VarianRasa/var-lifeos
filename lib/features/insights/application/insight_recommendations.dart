/// Converts insight signals into ordered next-action recommendations.
library;

import 'insight_risk_engine.dart';

enum InsightRecommendationAction {
  openCalendar,
  openDayReview,
  filterContext,
  createWeeklyReview,
  scheduleOverdueTasks,
  applyDayTemplate,
  balanceWorkload,
  exportReport,
}

final class InsightRecommendation {
  const InsightRecommendation({
    required this.id,
    required this.title,
    required this.message,
    required this.action,
    required this.priority,
    this.contextName,
  });

  final String id;
  final String title;
  final String message;
  final InsightRecommendationAction action;
  final int priority;
  final String? contextName;
}

List<InsightRecommendation> buildInsightRecommendations({
  required Iterable<InsightRisk> risks,
  int overdueCount = 0,
  int openTaskCount = 0,
  int reviewCount = 0,
  bool hasContextFilter = false,
}) {
  final byId = <String, InsightRecommendation>{};

  for (final risk in risks) {
    final recommendation = _fromRisk(risk);
    byId.putIfAbsent(recommendation.id, () => recommendation);
  }

  if (overdueCount > 0) {
    byId.putIfAbsent(
      'schedule-overdue-tasks',
      () => InsightRecommendation(
        id: 'schedule-overdue-tasks',
        title: 'Schedule overdue tasks',
        message: 'Move or complete $overdueCount overdue tasks.',
        action: InsightRecommendationAction.scheduleOverdueTasks,
        priority: 80 + overdueCount,
      ),
    );
  }

  if (reviewCount == 0) {
    byId.putIfAbsent(
      'create-weekly-review',
      () => const InsightRecommendation(
        id: 'create-weekly-review',
        title: 'Create weekly review',
        message: 'Add a review node to close the loop.',
        action: InsightRecommendationAction.createWeeklyReview,
        priority: 70,
      ),
    );
  }

  if (openTaskCount >= 6) {
    byId.putIfAbsent(
      'balance-workload',
      () => InsightRecommendation(
        id: 'balance-workload',
        title: 'Balance workload',
        message: '$openTaskCount open tasks need triage.',
        action: InsightRecommendationAction.balanceWorkload,
        priority: 65 + openTaskCount,
      ),
    );
  }

  if (!hasContextFilter) {
    byId.putIfAbsent(
      'export-report',
      () => const InsightRecommendation(
        id: 'export-report',
        title: 'Export report',
        message: 'Capture the current dashboard as a markdown report.',
        action: InsightRecommendationAction.exportReport,
        priority: 10,
      ),
    );
  }

  final items = byId.values.toList()
    ..sort((a, b) {
      final priorityCompare = b.priority.compareTo(a.priority);
      if (priorityCompare != 0) return priorityCompare;
      return a.id.compareTo(b.id);
    });
  return List.unmodifiable(items.take(6));
}

InsightRecommendation _fromRisk(InsightRisk risk) {
  return InsightRecommendation(
    id: 'risk-${risk.id}',
    title: risk.title,
    message: risk.message,
    action: _actionFromRisk(risk.actionType),
    priority: _severityPriority(risk.severity) + risk.count,
    contextName: risk.contextName,
  );
}

InsightRecommendationAction _actionFromRisk(InsightRiskActionType actionType) {
  switch (actionType) {
    case InsightRiskActionType.openCalendar:
      return InsightRecommendationAction.openCalendar;
    case InsightRiskActionType.openDayReview:
      return InsightRecommendationAction.openDayReview;
    case InsightRiskActionType.filterContext:
      return InsightRecommendationAction.filterContext;
    case InsightRiskActionType.createWeeklyReview:
      return InsightRecommendationAction.createWeeklyReview;
    case InsightRiskActionType.scheduleOverdue:
      return InsightRecommendationAction.scheduleOverdueTasks;
    case InsightRiskActionType.balanceWorkload:
      return InsightRecommendationAction.balanceWorkload;
  }
}

int _severityPriority(InsightRiskSeverity severity) {
  switch (severity) {
    case InsightRiskSeverity.info:
      return 20;
    case InsightRiskSeverity.watch:
      return 50;
    case InsightRiskSeverity.high:
      return 80;
    case InsightRiskSeverity.critical:
      return 100;
  }
}

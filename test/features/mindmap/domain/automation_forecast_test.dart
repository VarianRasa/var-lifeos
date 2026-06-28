import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/automation_forecast.dart';
import 'package:var_app/features/mindmap/domain/automation_rule.dart';
import 'package:var_app/features/mindmap/domain/recurring_routine.dart';

void main() {
  test('forecasts enabled routines and paused automation rules', () {
    final today = DateTime(2026, 6, 23);
    final activeDailyRule = createAutomationRuleNode(
      id: 'daily-research',
      label: 'Daily research',
      templateId: 'research-note',
      rule: RecurringRule.daily(),
      day: today,
      now: DateTime(2026, 6, 23, 8),
    );
    final activeFridayRule = createAutomationRuleNode(
      id: 'project-review',
      label: 'Project review',
      templateId: 'sprint-board',
      rule: RecurringRule.weekly(weekday: DateTime.friday),
      day: today,
      now: DateTime(2026, 6, 23, 8),
    );
    final pausedRule = createAutomationRuleNode(
      id: 'paused-research',
      label: 'Paused research',
      templateId: 'research-note',
      rule: RecurringRule.daily(),
      enabled: false,
      day: today,
      now: DateTime(2026, 6, 23, 8),
    );

    final forecast = AutomationForecast.fromNodes(
      today: today,
      nodes: [activeDailyRule, activeFridayRule, pausedRule],
    );

    expect(forecast.tomorrowCount, 4);
    expect(forecast.weekCount, 6);
    expect(forecast.pausedCount, 1);
    expect(forecast.tomorrowItems.map((item) => item.title), [
      'Daily plan',
      'Daily journal',
      'Workout habit',
      'Daily research',
    ]);

    final projectReview = forecast.weekItems.singleWhere(
      (item) => item.title == 'Project review',
    );
    expect(projectReview.day, DateTime(2026, 6, 26));
    expect(projectReview.dayLabel, '2026-06-26');
    expect(forecast.pausedRules.single.label, 'Paused research');
  });
}

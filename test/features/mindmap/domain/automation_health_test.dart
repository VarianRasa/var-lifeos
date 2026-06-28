import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/automation_health.dart';
import 'package:var_app/features/mindmap/domain/automation_rule.dart';
import 'package:var_app/features/mindmap/domain/recurring_routine.dart';

void main() {
  test('detects active automation rules that duplicate the same schedule', () {
    final today = DateTime(2026, 6, 24);
    final duplicateDefaultRule = createAutomationRuleNode(
      id: 'daily-startup-copy',
      label: 'Daily startup copy',
      templateId: 'daily-plan',
      rule: RecurringRule.daily(),
      day: today,
      now: DateTime(2026, 6, 24, 8),
    );
    final secondDuplicateRule = createAutomationRuleNode(
      id: 'daily-plan-second',
      label: 'Second daily plan',
      templateId: 'daily-plan',
      rule: RecurringRule.daily(),
      day: today,
      now: DateTime(2026, 6, 24, 8),
    );
    final pausedDuplicateRule = createAutomationRuleNode(
      id: 'paused-startup',
      label: 'Paused startup',
      templateId: 'daily-plan',
      rule: RecurringRule.daily(),
      enabled: false,
      day: today,
      now: DateTime(2026, 6, 24, 8),
    );

    final health = AutomationHealth.fromNodes(
      nodes: [duplicateDefaultRule, secondDuplicateRule, pausedDuplicateRule],
    );

    expect(health.hasIssues, isTrue);
    expect(health.conflictCount, 1);
    expect(health.issues, hasLength(1));

    final issue = health.issues.single;
    expect(issue.type, AutomationHealthIssueType.duplicateSchedule);
    expect(issue.severity, AutomationHealthIssueSeverity.warning);
    expect(issue.title, 'Duplicate Daily plan automation');
    expect(issue.cadenceLabel, 'Daily');
    expect(issue.affectedLabels, [
      'Daily plan',
      'Daily startup copy',
      'Second daily plan',
    ]);
    expect(issue.pausableRuleNodeIds, [
      'automation-rule-daily-startup-copy',
      'automation-rule-daily-plan-second',
    ]);
    expect(issue.canPauseRules, isTrue);
    expect(
      issue.message,
      'Daily plan, Daily startup copy, Second daily plan all create Daily plan on Daily. Keep one active rule to avoid duplicate nodes.',
    );
  });

  test('keeps one custom rule active when no default routine is involved', () {
    final today = DateTime(2026, 6, 24);
    final firstCustomRule = createAutomationRuleNode(
      id: 'research-a',
      label: 'Research A',
      templateId: 'research-note',
      rule: RecurringRule.daily(),
      day: today,
      now: DateTime(2026, 6, 24, 8),
    );
    final secondCustomRule = createAutomationRuleNode(
      id: 'research-b',
      label: 'Research B',
      templateId: 'research-note',
      rule: RecurringRule.daily(),
      day: today,
      now: DateTime(2026, 6, 24, 8),
    );

    final health = AutomationHealth.fromNodes(
      nodes: [firstCustomRule, secondCustomRule],
    );

    expect(health.conflictCount, 1);
    expect(health.issues.single.affectedLabels, ['Research A', 'Research B']);
    expect(health.issues.single.pausableRuleNodeIds, [
      'automation-rule-research-b',
    ]);
  });
}

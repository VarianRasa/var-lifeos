import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/automation_rule.dart';
import 'package:var_app/features/mindmap/domain/recurring_routine.dart';

void main() {
  test('automation rule presets cover common workflows', () {
    expect(defaultAutomationRulePresets.map((preset) => preset.id), [
      'daily-startup',
      'weekly-review',
      'habit-check-in',
      'project-review',
    ]);

    final weeklyReview = defaultAutomationRulePresets.singleWhere(
      (preset) => preset.id == 'weekly-review',
    );
    final projectReview = defaultAutomationRulePresets.singleWhere(
      (preset) => preset.id == 'project-review',
    );

    expect(weeklyReview.label, 'Weekly review');
    expect(weeklyReview.templateId, 'weekly-review');
    expect(weeklyReview.rule.isDueOn(DateTime(2026, 6, 22)), isTrue);
    expect(projectReview.label, 'Project review');
    expect(projectReview.templateId, 'sprint-board');
    expect(projectReview.rule.isDueOn(DateTime(2026, 6, 26)), isTrue);
  });

  test('automation rule presets create hidden rule nodes', () {
    final preset = defaultAutomationRulePresets.singleWhere(
      (preset) => preset.id == 'daily-startup',
    );
    final ruleNode = createAutomationRuleNodeFromPreset(
      id: 'custom-startup',
      preset: preset,
      day: DateTime(2026, 6, 24),
      now: DateTime(2026, 6, 24, 8),
    );

    expect(ruleNode.id, 'automation-rule-custom-startup');
    expect(ruleNode.data['automationRule'], {
      'id': 'custom-startup',
      'label': 'Daily startup',
      'templateId': 'daily-plan',
      'frequency': 'daily',
      'enabled': true,
    });
  });

  test('custom automation rule nodes become recurring routines', () {
    final ruleNode = createAutomationRuleNode(
      id: 'custom-research',
      label: 'Daily research',
      templateId: 'research-note',
      rule: RecurringRule.daily(),
      day: DateTime(2026, 6, 23),
      now: DateTime(2026, 6, 23, 8),
    );

    expect(ruleNode.type, NodeType.note);
    expect(ruleNode.isArchived, isTrue);
    expect(ruleNode.tags, containsAll(['routine', 'automation-rule']));
    expect(ruleNode.data['automationRule'], {
      'id': 'custom-research',
      'label': 'Daily research',
      'templateId': 'research-note',
      'frequency': 'daily',
      'enabled': true,
    });

    final routines = customRecurringRoutinesFromNodes([ruleNode]);

    expect(routines, hasLength(1));
    expect(routines.single.id, 'custom-research');
    expect(routines.single.label, 'Daily research');
    expect(routines.single.nodeTitle, 'Daily research');
    expect(routines.single.template.id, 'research-note');
    expect(routines.single.rule.isDueOn(DateTime(2026, 6, 24)), isTrue);
  });

  test('disabled automation rule nodes are not exposed as routines', () {
    final ruleNode = createAutomationRuleNode(
      id: 'disabled-review',
      label: 'Disabled review',
      templateId: 'weekly-review',
      rule: RecurringRule.weekly(weekday: DateTime.monday),
      enabled: false,
      day: DateTime(2026, 6, 23),
      now: DateTime(2026, 6, 23, 8),
    );

    expect(customRecurringRoutinesFromNodes([ruleNode]), isEmpty);
  });

  test('automation rule nodes can be listed and updated', () {
    final createdAt = DateTime(2026, 6, 23, 8);
    final updatedAt = DateTime(2026, 6, 23, 9);
    final ruleNode = createAutomationRuleNode(
      id: 'custom-research',
      label: 'Daily research',
      templateId: 'research-note',
      rule: RecurringRule.daily(),
      day: DateTime(2026, 6, 23),
      now: createdAt,
    );

    final listed = automationRulesFromNodes([ruleNode]);

    expect(listed, hasLength(1));
    expect(listed.single.nodeId, ruleNode.id);
    expect(listed.single.id, 'custom-research');
    expect(listed.single.label, 'Daily research');
    expect(listed.single.templateId, 'research-note');
    expect(listed.single.enabled, isTrue);

    final updated = updateAutomationRuleNode(
      node: ruleNode,
      label: 'Weekly research',
      templateId: 'weekly-review',
      rule: RecurringRule.weekly(weekday: DateTime.friday),
      enabled: false,
      now: updatedAt,
    );

    expect(updated.id, ruleNode.id);
    expect(updated.updatedAt, updatedAt);
    expect(updated.title, 'Automation rule: Weekly research');
    expect(updated.data['automationRule'], {
      'id': 'custom-research',
      'label': 'Weekly research',
      'templateId': 'weekly-review',
      'frequency': 'weekly',
      'weekday': DateTime.friday,
      'enabled': false,
    });
    expect(customRecurringRoutinesFromNodes([updated]), isEmpty);

    final disabled = automationRulesFromNodes([updated]);
    expect(disabled.single.label, 'Weekly research');
    expect(disabled.single.enabled, isFalse);
    expect(disabled.single.rule.isDueOn(DateTime(2026, 6, 26)), isTrue);
  });

  test(
    'AutomationRuleRecord serializes and deserializes trigger and action fields',
    () {
      final now = DateTime(2026, 7, 24);
      final node = createAutomationRuleNode(
        id: 'rule-1',
        label: 'Auto Tag Review',
        templateId: 'daily-plan',
        rule: RecurringRule.daily(),
        day: now,
        enabled: true,
        now: now,
      );

      final updatedData = Map<String, Object?>.from(node.data);
      final ruleMap = Map<String, Object?>.from(
        (updatedData[automationRuleDataKey] as Map).cast<String, Object?>(),
      );

      ruleMap['triggerType'] = AutomationTriggerType.taskCompleted.name;
      ruleMap['actionType'] = AutomationActionType.autoTag.name;
      ruleMap['actionTag'] = 'done-review';

      updatedData[automationRuleDataKey] = ruleMap;
      final finalNode = node.copyWith(data: updatedData);

      final parsedRule = automationRuleFromNode(finalNode);

      expect(parsedRule, isNotNull);
      expect(parsedRule!.label, 'Auto Tag Review');
      expect(parsedRule.triggerType, AutomationTriggerType.taskCompleted);
      expect(parsedRule.actionType, AutomationActionType.autoTag);
      expect(parsedRule.actionTag, 'done-review');
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/automation_rule.dart';
import 'package:var_app/features/mindmap/domain/automation_trigger_engine.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/recurring_routine.dart';

void main() {
  group('AutomationTriggerEngine', () {
    final today = DateTime(2026, 8, 7);

    test('triggers autoTag action when task is completed', () {
      final task = MindmapNode.create(
        id: 't1',
        type: NodeType.task,
        title: 'Task 1',
        isDone: true,
        status: NodeStatus.done,
        day: today,
      );

      final rule = AutomationRuleRecord(
        nodeId: 'rule-node-1',
        id: 'rule-1',
        label: 'Auto Tag Completed',
        templateId: 'daily-plan',
        rule: RecurringRule.daily(),
        enabled: true,
        triggerType: AutomationTriggerType.taskCompleted,
        actionType: AutomationActionType.autoTag,
        actionTag: 'verified-done',
      );

      final result = evaluateAutomationTriggers(
        mutatedNode: task,
        activeRules: [rule],
        today: today,
      );

      expect(result.updatedNode.tags, contains('verified-done'));
      expect(result.recordedEvents.length, equals(1));
    });

    test(
      'triggers createFollowupTask action when node created with specific tag',
      () {
        final node = MindmapNode.create(
          id: 'n1',
          type: NodeType.note,
          title: 'Project Notes',
          tags: const ['needs-followup'],
          day: today,
        );

        final rule = AutomationRuleRecord(
          nodeId: 'rule-node-2',
          id: 'rule-2',
          label: 'Followup Generator',
          templateId: 'daily-plan',
          rule: RecurringRule.daily(),
          enabled: true,
          triggerType: AutomationTriggerType.nodeCreatedWithTag,
          triggerTag: 'needs-followup',
          actionType: AutomationActionType.createFollowupTask,
          followupTitle: 'Action: Review Project Notes',
        );

        final result = evaluateAutomationTriggers(
          mutatedNode: node,
          activeRules: [rule],
          today: today,
        );

        expect(result.createdNodes.length, equals(1));
        expect(
          result.createdNodes.first.title,
          equals('Action: Review Project Notes'),
        );
      },
    );
  });
}

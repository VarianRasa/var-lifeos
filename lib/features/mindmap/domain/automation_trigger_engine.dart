/// Event-driven automation execution engine.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import 'automation_event.dart';
import 'automation_rule.dart';
import 'habit_completion.dart';
import 'mindmap_node.dart';

final class AutomationTriggerResult {
  const AutomationTriggerResult({
    required this.updatedNode,
    this.createdNodes = const [],
    this.recordedEvents = const [],
  });

  final MindmapNode updatedNode;
  final List<MindmapNode> createdNodes;
  final List<AutomationEventRecord> recordedEvents;
}

AutomationTriggerResult evaluateAutomationTriggers({
  required MindmapNode mutatedNode,
  required Iterable<AutomationRuleRecord> activeRules,
  required DateTime today,
}) {
  var currentNode = mutatedNode;
  final created = <MindmapNode>[];
  final events = <AutomationEventRecord>[];

  final now = DateTime.now();

  for (final rule in activeRules) {
    if (!rule.enabled) continue;

    bool isMatch = false;

    switch (rule.triggerType) {
      case AutomationTriggerType.taskCompleted:
        if (mutatedNode.type == NodeType.task &&
            (mutatedNode.isDone || mutatedNode.status == NodeStatus.done)) {
          isMatch = true;
        }
      case AutomationTriggerType.habitChecked:
        if (mutatedNode.type == NodeType.habit &&
            hasHabitCompletionOn(mutatedNode, today)) {
          isMatch = true;
        }
      case AutomationTriggerType.nodeCreatedWithTag:
        final targetTag = rule.triggerTag?.trim().toLowerCase() ?? '';
        if (targetTag.isNotEmpty &&
            mutatedNode.tags.any((t) => t.toLowerCase() == targetTag)) {
          isMatch = true;
        }
      case AutomationTriggerType.scheduled:
        break;
    }

    if (!isMatch) continue;

    // Execute Action
    switch (rule.actionType) {
      case AutomationActionType.autoTag:
        final addTag = rule.actionTag?.trim();
        if (addTag != null &&
            addTag.isNotEmpty &&
            !currentNode.tags.contains(addTag)) {
          currentNode = currentNode.copyWith(
            tags: [...currentNode.tags, addTag],
            updatedAt: now,
          );
        }
      case AutomationActionType.createFollowupTask:
        final title =
            rule.followupTitle?.trim() ?? 'Follow-up: ${mutatedNode.title}';
        final followupNode = MindmapNode.create(
          id: 'auto-followup-${now.microsecondsSinceEpoch}',
          type: NodeType.task,
          title: title,
          day: today.dateOnly,
          project: mutatedNode.project,
          area: mutatedNode.area,
          tags: ['automation-followup'],
          relatedNodeIds: [mutatedNode.id],
        );
        created.add(followupNode);
      case AutomationActionType.logHabitCompletion:
        if (rule.targetHabitId != null &&
            currentNode.id == rule.targetHabitId) {
          currentNode = logHabitCompletion(currentNode, today, now: now);
        }
      case AutomationActionType.createFromTemplate:
        break;
    }

    events.add(
      AutomationEventRecord(
        nodeId: 'evt-node-${now.microsecondsSinceEpoch}',
        id: 'evt-${now.microsecondsSinceEpoch}',
        type: AutomationEventType.applyRoutines,
        title: 'Automation Triggered: ${rule.label}',
        message: 'Executed ${rule.actionType.label} for ${mutatedNode.title}',
        day: today.dateOnly,
        occurredAt: now,
        affectedRuleNodeIds: [rule.nodeId],
        affectedLabels: [rule.label],
      ),
    );
  }

  return AutomationTriggerResult(
    updatedNode: currentNode,
    createdNodes: created,
    recordedEvents: events,
  );
}

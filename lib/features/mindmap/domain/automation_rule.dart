/// User-defined automation rules stored as hidden mindmap nodes.
library;

import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';
import 'node_template.dart';
import 'recurring_routine.dart';

const automationRuleDataKey = 'automationRule';

enum AutomationTriggerType {
  scheduled('Sesuai Jadwal'),
  taskCompleted('Task Selesai'),
  habitChecked('Habit Dicentang'),
  nodeCreatedWithTag('Node Baru dengan Tag');

  const AutomationTriggerType(this.label);
  final String label;
}

enum AutomationActionType {
  createFromTemplate('Buat Node dari Template'),
  autoTag('Otomatis Tambah Tag'),
  createFollowupTask('Buat Task Lanjutan'),
  logHabitCompletion('Log Progres Habit');

  const AutomationActionType(this.label);
  final String label;
}

final class AutomationRuleRecord {
  const AutomationRuleRecord({
    required this.nodeId,
    required this.id,
    required this.label,
    required this.templateId,
    required this.rule,
    required this.enabled,
    this.triggerType = AutomationTriggerType.scheduled,
    this.triggerTag,
    this.actionType = AutomationActionType.createFromTemplate,
    this.actionTag,
    this.followupTitle,
    this.targetHabitId,
  });

  final String nodeId;
  final String id;
  final String label;
  final String templateId;
  final RecurringRule rule;
  final bool enabled;
  final AutomationTriggerType triggerType;
  final String? triggerTag;
  final AutomationActionType actionType;
  final String? actionTag;
  final String? followupTitle;
  final String? targetHabitId;
}

final class AutomationRulePreset {
  const AutomationRulePreset({
    required this.id,
    required this.label,
    required this.templateId,
    required this.rule,
  });

  final String id;
  final String label;
  final String templateId;
  final RecurringRule rule;
}

final defaultAutomationRulePresets = List<AutomationRulePreset>.unmodifiable([
  AutomationRulePreset(
    id: 'daily-startup',
    label: 'Daily startup',
    templateId: 'daily-plan',
    rule: RecurringRule.daily(),
  ),
  AutomationRulePreset(
    id: 'weekly-review',
    label: 'Weekly review',
    templateId: 'weekly-review',
    rule: RecurringRule.weekly(weekday: DateTime.monday),
  ),
  AutomationRulePreset(
    id: 'habit-check-in',
    label: 'Habit check-in',
    templateId: 'workout-habit',
    rule: RecurringRule.daily(),
  ),
  AutomationRulePreset(
    id: 'project-review',
    label: 'Project review',
    templateId: 'sprint-board',
    rule: RecurringRule.weekly(weekday: DateTime.friday),
  ),
]);

MindmapNode createAutomationRuleNode({
  required String id,
  required String label,
  required String templateId,
  required RecurringRule rule,
  required DateTime day,
  bool enabled = true,
  DateTime? now,
}) {
  final trimmedLabel = label.trim();
  final normalizedLabel = trimmedLabel.isEmpty
      ? 'Automation rule'
      : trimmedLabel;

  return MindmapNode.create(
    id: 'automation-rule-$id',
    type: NodeType.note,
    title: 'Automation rule: $normalizedLabel',
    body: 'Creates $normalizedLabel from the $templateId template.',
    day: day,
    tags: const ['routine', 'automation-rule'],
    isArchived: true,
    data: {
      automationRuleDataKey: {
        'id': id,
        'label': normalizedLabel,
        'templateId': templateId,
        'frequency': rule.frequency.name,
        if (rule.weekday != null) 'weekday': rule.weekday,
        if (rule.dayOfMonth != null) 'dayOfMonth': rule.dayOfMonth,
        'enabled': enabled,
      },
    },
    now: now,
  );
}

MindmapNode createAutomationRuleNodeFromPreset({
  required String id,
  required AutomationRulePreset preset,
  required DateTime day,
  bool enabled = true,
  DateTime? now,
}) {
  return createAutomationRuleNode(
    id: id,
    label: preset.label,
    templateId: preset.templateId,
    rule: preset.rule,
    day: day,
    enabled: enabled,
    now: now,
  );
}

MindmapNode updateAutomationRuleNode({
  required MindmapNode node,
  required String label,
  required String templateId,
  required RecurringRule rule,
  required bool enabled,
  DateTime? now,
}) {
  final existingRule = automationRuleFromNode(node);
  final ruleId =
      existingRule?.id ?? node.id.replaceFirst('automation-rule-', '');
  final timestamp = now ?? DateTime.now();
  final trimmedLabel = label.trim();
  final normalizedLabel = trimmedLabel.isEmpty
      ? 'Automation rule'
      : trimmedLabel;

  return node.copyWith(
    title: 'Automation rule: $normalizedLabel',
    body: 'Creates $normalizedLabel from the $templateId template.',
    tags: const ['routine', 'automation-rule'],
    isArchived: true,
    updatedAt: timestamp,
    data: {
      automationRuleDataKey: {
        'id': ruleId,
        'label': normalizedLabel,
        'templateId': templateId,
        'frequency': rule.frequency.name,
        if (rule.weekday != null) 'weekday': rule.weekday,
        if (rule.dayOfMonth != null) 'dayOfMonth': rule.dayOfMonth,
        'enabled': enabled,
      },
    },
  );
}

List<AutomationRuleRecord> automationRulesFromNodes(
  Iterable<MindmapNode> nodes,
) {
  final rules = <AutomationRuleRecord>[];

  for (final node in nodes) {
    final rule = automationRuleFromNode(node);
    if (rule != null) rules.add(rule);
  }

  return List.unmodifiable(rules);
}

AutomationRuleRecord? automationRuleFromNode(MindmapNode node) {
  final data = node.data[automationRuleDataKey];
  if (data is! Map) return null;
  final ruleData = data.cast<String, Object?>();

  final id = _stringValue(ruleData['id']);
  final label = _stringValue(ruleData['label']);
  final templateId = _stringValue(ruleData['templateId']);
  if (id == null || label == null || templateId == null) return null;

  final template = _templateByIdOrNull(templateId);
  final rule = _recurringRuleFromData(ruleData);
  if (template == null || rule == null) return null;

  final triggerTypeStr = _stringValue(ruleData['triggerType']);
  final triggerType = AutomationTriggerType.values.firstWhere(
    (e) => e.name == triggerTypeStr,
    orElse: () => AutomationTriggerType.scheduled,
  );
  final actionTypeStr = _stringValue(ruleData['actionType']);
  final actionType = AutomationActionType.values.firstWhere(
    (e) => e.name == actionTypeStr,
    orElse: () => AutomationActionType.createFromTemplate,
  );

  return AutomationRuleRecord(
    nodeId: node.id,
    id: id,
    label: label,
    templateId: template.id,
    rule: rule,
    enabled: ruleData['enabled'] != false,
    triggerType: triggerType,
    triggerTag: _stringValue(ruleData['triggerTag']),
    actionType: actionType,
    actionTag: _stringValue(ruleData['actionTag']),
    followupTitle: _stringValue(ruleData['followupTitle']),
    targetHabitId: _stringValue(ruleData['targetHabitId']),
  );
}

List<RecurringNodeRoutine> allRecurringRoutinesFromNodes(
  Iterable<MindmapNode> nodes,
) {
  return List.unmodifiable([
    ...defaultRecurringRoutines,
    ...customRecurringRoutinesFromNodes(nodes),
  ]);
}

List<RecurringNodeRoutine> customRecurringRoutinesFromNodes(
  Iterable<MindmapNode> nodes,
) {
  final routines = <RecurringNodeRoutine>[];

  for (final node in nodes) {
    final routine = _customRecurringRoutineFromNode(node);
    if (routine != null) routines.add(routine);
  }

  return List.unmodifiable(routines);
}

RecurringNodeRoutine? _customRecurringRoutineFromNode(MindmapNode node) {
  final ruleRecord = automationRuleFromNode(node);
  if (ruleRecord == null || !ruleRecord.enabled) return null;
  final template = _templateByIdOrNull(ruleRecord.templateId);
  if (template == null) return null;

  return RecurringNodeRoutine(
    id: ruleRecord.id,
    label: ruleRecord.label,
    nodeTitle: ruleRecord.label,
    template: template,
    rule: ruleRecord.rule,
  );
}

RecurringRule? _recurringRuleFromData(Map<String, Object?> data) {
  final frequency = data['frequency'];
  if (frequency is! String) return null;

  return switch (frequency) {
    'daily' => RecurringRule.daily(),
    'weekly' => RecurringRule.weekly(
      weekday: _intInRange(data['weekday'], min: 1, max: 7) ?? DateTime.monday,
    ),
    'monthly' => RecurringRule.monthly(
      dayOfMonth: _intInRange(data['dayOfMonth'], min: 1, max: 31) ?? 1,
    ),
    _ => null,
  };
}

NodeTemplate? _templateByIdOrNull(String id) {
  for (final template in defaultNodeTemplates) {
    if (template.id == id) return template;
  }
  return null;
}

String? _stringValue(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _intInRange(Object? value, {required int min, required int max}) {
  if (value is! int) return null;
  if (value < min || value > max) return null;
  return value;
}

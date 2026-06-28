/// Automation health checks for recurring routines and custom rules.
library;

import 'automation_rule.dart';
import 'mindmap_node.dart';
import 'node_template.dart';
import 'recurring_routine.dart';

enum AutomationHealthIssueType { duplicateSchedule }

enum AutomationHealthIssueSeverity { warning }

final class AutomationHealth {
  AutomationHealth({required List<AutomationHealthIssue> issues})
    : issues = List.unmodifiable(issues);

  factory AutomationHealth.fromNodes({required Iterable<MindmapNode> nodes}) {
    final nodeList = nodes.toList(growable: false);
    final entries = [
      for (final routine in defaultRecurringRoutines)
        _AutomationEntry.fromRoutine(routine),
      for (final rule in automationRulesFromNodes(nodeList))
        if (rule.enabled) _AutomationEntry.fromRule(rule),
    ];

    final groupedEntries = <String, List<_AutomationEntry>>{};
    for (final entry in entries) {
      groupedEntries.putIfAbsent(entry.scheduleKey, () => []).add(entry);
    }

    final issues = <AutomationHealthIssue>[];
    for (final group in groupedEntries.values) {
      if (group.length < 2) continue;
      final first = group.first;
      final labels = [for (final entry in group) entry.label];
      final affectedLabels = labels.join(', ');
      final pausableRuleNodeIds = _pausableRuleNodeIds(group);
      issues.add(
        AutomationHealthIssue(
          id: 'duplicate-${first.scheduleKey}',
          type: AutomationHealthIssueType.duplicateSchedule,
          severity: AutomationHealthIssueSeverity.warning,
          title: 'Duplicate ${first.templateLabel} automation',
          message:
              '$affectedLabels all create ${first.templateLabel} on ${first.cadenceLabel}. Keep one active rule to avoid duplicate nodes.',
          cadenceLabel: first.cadenceLabel,
          affectedLabels: labels,
          pausableRuleNodeIds: pausableRuleNodeIds,
        ),
      );
    }

    return AutomationHealth(issues: issues);
  }

  final List<AutomationHealthIssue> issues;

  int get conflictCount => issues.length;

  bool get hasIssues => issues.isNotEmpty;
}

final class AutomationHealthIssue {
  AutomationHealthIssue({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    required this.cadenceLabel,
    required this.affectedLabels,
    required List<String> pausableRuleNodeIds,
  }) : pausableRuleNodeIds = List.unmodifiable(pausableRuleNodeIds);

  final String id;
  final AutomationHealthIssueType type;
  final AutomationHealthIssueSeverity severity;
  final String title;
  final String message;
  final String cadenceLabel;
  final List<String> affectedLabels;
  final List<String> pausableRuleNodeIds;

  bool get canPauseRules => pausableRuleNodeIds.isNotEmpty;
}

final class _AutomationEntry {
  const _AutomationEntry({
    required this.label,
    required this.templateId,
    required this.templateLabel,
    required this.rule,
    required this.ruleNodeId,
    required this.isDefaultRoutine,
  });

  factory _AutomationEntry.fromRoutine(RecurringNodeRoutine routine) {
    return _AutomationEntry(
      label: routine.label,
      templateId: routine.template.id,
      templateLabel: routine.template.label,
      rule: routine.rule,
      ruleNodeId: null,
      isDefaultRoutine: true,
    );
  }

  factory _AutomationEntry.fromRule(AutomationRuleRecord rule) {
    final template = nodeTemplateById(rule.templateId);
    return _AutomationEntry(
      label: rule.label,
      templateId: template.id,
      templateLabel: template.label,
      rule: rule.rule,
      ruleNodeId: rule.nodeId,
      isDefaultRoutine: false,
    );
  }

  final String label;
  final String templateId;
  final String templateLabel;
  final RecurringRule rule;
  final String? ruleNodeId;
  final bool isDefaultRoutine;

  String get cadenceLabel => _cadenceLabel(rule);

  String get scheduleKey {
    return [
      templateId,
      rule.frequency.name,
      rule.weekday?.toString() ?? '',
      rule.dayOfMonth?.toString() ?? '',
    ].join('|');
  }
}

List<String> _pausableRuleNodeIds(List<_AutomationEntry> group) {
  final customRuleNodeIds = [
    for (final entry in group)
      if (!entry.isDefaultRoutine && entry.ruleNodeId != null)
        entry.ruleNodeId!,
  ];
  if (customRuleNodeIds.isEmpty) return const [];

  final hasDefaultRoutine = group.any((entry) => entry.isDefaultRoutine);
  if (hasDefaultRoutine) return customRuleNodeIds;

  return customRuleNodeIds.skip(1).toList(growable: false);
}

String _cadenceLabel(RecurringRule rule) {
  return switch (rule.frequency) {
    RecurringFrequency.daily => 'Daily',
    RecurringFrequency.weekly => 'Weekly ${_weekdayLabel(rule.weekday)}',
    RecurringFrequency.monthly => 'Monthly day ${rule.dayOfMonth}',
  };
}

String _weekdayLabel(int? weekday) {
  return switch (weekday) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => 'weekly',
  };
}

/// Deterministic smart risk detection for Insights.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/automation_event.dart';
import '../../mindmap/domain/habit_completion.dart';
import '../../mindmap/domain/mindmap_node.dart';

enum InsightRiskSeverity { info, watch, high, critical }

enum InsightRiskActionType {
  openCalendar,
  openDayReview,
  filterContext,
  createWeeklyReview,
  scheduleOverdue,
  balanceWorkload,
}

final class InsightRisk {
  const InsightRisk({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.actionType,
    this.count = 0,
    this.contextName,
  });

  final String id;
  final String title;
  final String message;
  final InsightRiskSeverity severity;
  final InsightRiskActionType actionType;
  final int count;
  final String? contextName;
}

List<InsightRisk> buildInsightRisks({
  required DateTime today,
  required Iterable<MindmapNode> nodes,
}) {
  final normalizedToday = today.dateOnly;
  final activeNodes = [
    for (final node in nodes)
      if (!node.isArchived) node,
  ];
  final risks = <InsightRisk>[];

  risks.addAll(_overdueClusterRisks(activeNodes, normalizedToday));
  risks.addAll(_highPriorityOverloadRisks(activeNodes));
  risks.addAll(_weeklyReviewRisks(activeNodes, normalizedToday));
  risks.addAll(_habitStreakRisks(activeNodes, normalizedToday));
  risks.addAll(_staleProjectRisks(activeNodes, normalizedToday));
  risks.addAll(_unscheduledTaskRisks(activeNodes));
  risks.addAll(_snoozeRisks(nodes.toList(growable: false), normalizedToday));
  risks.addAll(_workloadCompletionRisks(activeNodes, normalizedToday));

  risks.sort((a, b) {
    final severityCompare = b.severity.index.compareTo(a.severity.index);
    if (severityCompare != 0) return severityCompare;
    final countCompare = b.count.compareTo(a.count);
    if (countCompare != 0) return countCompare;
    return a.id.compareTo(b.id);
  });
  return List.unmodifiable(risks);
}

List<InsightRisk> _overdueClusterRisks(
  List<MindmapNode> nodes,
  DateTime today,
) {
  final overdue = nodes.where((node) {
    return node.type == NodeType.task &&
        !_isComplete(node) &&
        node.dueDate != null &&
        node.dueDate!.dateOnly.isBefore(today);
  }).toList();
  if (overdue.length < 3) return const [];
  return [
    InsightRisk(
      id: 'overdue-cluster',
      title: 'Overdue cluster',
      message:
          '${overdue.length} tasks are past due. Schedule or close the oldest items.',
      severity: overdue.length >= 6
          ? InsightRiskSeverity.critical
          : InsightRiskSeverity.high,
      actionType: InsightRiskActionType.scheduleOverdue,
      count: overdue.length,
    ),
  ];
}

List<InsightRisk> _highPriorityOverloadRisks(List<MindmapNode> nodes) {
  final high = nodes.where((node) {
    return node.type == NodeType.task &&
        !_isComplete(node) &&
        node.priority.index >= NodePriority.high.index;
  }).length;
  if (high < 5) return const [];
  return [
    InsightRisk(
      id: 'high-priority-overload',
      title: 'High-priority overload',
      message: '$high high-priority tasks are open. Pick the true top 3.',
      severity: high >= 9
          ? InsightRiskSeverity.critical
          : InsightRiskSeverity.high,
      actionType: InsightRiskActionType.balanceWorkload,
      count: high,
    ),
  ];
}

List<InsightRisk> _weeklyReviewRisks(List<MindmapNode> nodes, DateTime today) {
  final weekStart = today.startOfWeek;
  final hasReview = nodes.any((node) {
    return _isReview(node) &&
        !node.day.dateOnly.isBefore(weekStart) &&
        !node.day.dateOnly.isAfter(today);
  });
  if (hasReview) return const [];
  return const [
    InsightRisk(
      id: 'no-review-this-week',
      title: 'No review this week',
      message: 'Reflection cadence is missing. Create a weekly review node.',
      severity: InsightRiskSeverity.watch,
      actionType: InsightRiskActionType.createWeeklyReview,
    ),
  ];
}

List<InsightRisk> _habitStreakRisks(List<MindmapNode> nodes, DateTime today) {
  final atRisk = nodes.where((node) {
    if (node.type != NodeType.habit) return false;
    final keys = habitCompletionKeys(node).toSet();
    return !keys.contains(dayKey(today)) &&
        keys.contains(dayKey(today.addDays(-1)));
  }).toList();
  if (atRisk.isEmpty) return const [];
  return [
    InsightRisk(
      id: 'habit-streak-at-risk',
      title: 'Habit streak at risk',
      message: '${atRisk.first.title} is not completed today.',
      severity: InsightRiskSeverity.watch,
      actionType: InsightRiskActionType.openCalendar,
      count: atRisk.length,
    ),
  ];
}

List<InsightRisk> _staleProjectRisks(List<MindmapNode> nodes, DateTime today) {
  final byProject = <String, List<MindmapNode>>{};
  for (final node in nodes) {
    if (node.project.isEmpty) continue;
    (byProject[node.project] ??= []).add(node);
  }
  final risks = <InsightRisk>[];
  for (final entry in byProject.entries) {
    final openTasks = entry.value
        .where((node) => node.type == NodeType.task && !_isComplete(node))
        .length;
    if (openTasks == 0) continue;
    final lastActivity = entry.value
        .map((node) => node.updatedAt.dateOnly)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    if (today.difference(lastActivity).inDays >= 14) {
      risks.add(
        InsightRisk(
          id: 'stale-project-${_slug(entry.key)}',
          title: 'Project stale with open tasks',
          message:
              '${entry.key} has $openTasks open tasks and no recent activity.',
          severity: InsightRiskSeverity.high,
          actionType: InsightRiskActionType.filterContext,
          count: openTasks,
          contextName: entry.key,
        ),
      );
    }
  }
  return risks;
}

List<InsightRisk> _unscheduledTaskRisks(List<MindmapNode> nodes) {
  final unscheduled = nodes.where((node) {
    return node.type == NodeType.task &&
        !_isComplete(node) &&
        node.dueDate == null;
  }).length;
  if (unscheduled < 8) return const [];
  return [
    InsightRisk(
      id: 'unscheduled-task-load',
      title: 'Many tasks without schedule',
      message: '$unscheduled open tasks have no due date.',
      severity: InsightRiskSeverity.watch,
      actionType: InsightRiskActionType.scheduleOverdue,
      count: unscheduled,
    ),
  ];
}

List<InsightRisk> _snoozeRisks(List<MindmapNode> nodes, DateTime today) {
  var count = 0;
  for (final node in nodes) {
    final event = automationEventFromNode(node);
    if (event != null &&
        event.type == AutomationEventType.snoozeRoutines &&
        today.difference(event.day.dateOnly).inDays <= 30) {
      count += event.affectedLabels.length;
    }
    final automation = node.data['automation'];
    if (automation is Map && automation['state'] == 'snoozed') count++;
  }
  if (count < 3) return const [];
  return [
    InsightRisk(
      id: 'repeated-snoozing',
      title: 'Repeated snoozing',
      message: '$count routine snoozes in the recent window.',
      severity: InsightRiskSeverity.watch,
      actionType: InsightRiskActionType.openCalendar,
      count: count,
    ),
  ];
}

List<InsightRisk> _workloadCompletionRisks(
  List<MindmapNode> nodes,
  DateTime today,
) {
  final recentStart = today.addDays(-6);
  final previousStart = today.addDays(-13);
  final previousEnd = today.addDays(-7);
  final recent = _windowStats(nodes, recentStart, today);
  final previous = _windowStats(nodes, previousStart, previousEnd);
  if (recent.openTasks > previous.openTasks &&
      recent.completedTasks < previous.completedTasks) {
    return [
      InsightRisk(
        id: 'workload-up-completion-down',
        title: 'Workload rising, completion dropping',
        message: 'Open work increased while completions fell vs previous week.',
        severity: InsightRiskSeverity.high,
        actionType: InsightRiskActionType.balanceWorkload,
        count: recent.openTasks,
      ),
    ];
  }
  return const [];
}

_WindowStats _windowStats(
  List<MindmapNode> nodes,
  DateTime start,
  DateTime end,
) {
  var openTasks = 0;
  var completedTasks = 0;
  for (final node in nodes) {
    if (node.type != NodeType.task) continue;
    final day = node.day.dateOnly;
    if (day.isBefore(start) || day.isAfter(end)) continue;
    if (_isComplete(node)) {
      completedTasks++;
    } else {
      openTasks++;
    }
  }
  return _WindowStats(openTasks: openTasks, completedTasks: completedTasks);
}

bool _isReview(MindmapNode node) {
  if (node.type != NodeType.journal && node.type != NodeType.note) return false;
  final title = node.title.toLowerCase();
  final tags = node.tags.map((tag) => tag.toLowerCase()).toSet();
  final journal = node.data['journal'];
  return title.contains('review') ||
      tags.contains('review') ||
      tags.contains('weekly-review') ||
      tags.contains('monthly-review') ||
      (journal is Map &&
          (journal['isWeeklyReview'] == true ||
              journal['isMonthlyReview'] == true));
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}

String _slug(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

final class _WindowStats {
  const _WindowStats({required this.openTasks, required this.completedTasks});

  final int openTasks;
  final int completedTasks;
}

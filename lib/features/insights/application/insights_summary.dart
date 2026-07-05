/// Phase 1 mission dashboard summaries for Insights.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

enum InsightsWindowKind { today, week, month }

enum InsightMissionStatus { stable, improving, atRisk, critical }

final class InsightsWindow {
  const InsightsWindow({
    required this.kind,
    required this.start,
    required this.end,
  });

  factory InsightsWindow.today(DateTime today) {
    final day = today.dateOnly;
    return InsightsWindow(kind: InsightsWindowKind.today, start: day, end: day);
  }

  factory InsightsWindow.week(DateTime today) {
    final end = today.dateOnly;
    return InsightsWindow(
      kind: InsightsWindowKind.week,
      start: end.startOfWeek,
      end: end,
    );
  }

  factory InsightsWindow.month(DateTime today) {
    final end = today.dateOnly;
    return InsightsWindow(
      kind: InsightsWindowKind.month,
      start: end.firstOfMonth,
      end: end,
    );
  }

  final InsightsWindowKind kind;
  final DateTime start;
  final DateTime end;

  int get dayCount => end.difference(start).inDays + 1;

  InsightsWindow get previous {
    final previousEnd = start.addDays(-1);
    return InsightsWindow(
      kind: kind,
      start: previousEnd.addDays(-(dayCount - 1)),
      end: previousEnd,
    );
  }

  bool contains(DateTime day) {
    final value = day.dateOnly;
    return !value.isBefore(start) && !value.isAfter(end);
  }
}

final class InsightMissionMetrics {
  const InsightMissionMetrics({
    required this.openTasks,
    required this.completedTasks,
    required this.overdueTasks,
    required this.highPriorityOpenTasks,
    required this.focusMinutes,
    required this.habitCompletionRate,
    required this.reviewCount,
  });

  final int openTasks;
  final int completedTasks;
  final int overdueTasks;
  final int highPriorityOpenTasks;
  final int focusMinutes;
  final double habitCompletionRate;
  final int reviewCount;

  double get taskCompletionRate {
    final total = openTasks + completedTasks;
    return total == 0 ? 0 : completedTasks / total;
  }
}

final class InsightsSummary {
  const InsightsSummary({
    required this.window,
    required this.current,
    required this.previous,
    required this.status,
  });

  final InsightsWindow window;
  final InsightMissionMetrics current;
  final InsightMissionMetrics previous;
  final InsightMissionStatus status;

  int get completedTaskDelta =>
      current.completedTasks - previous.completedTasks;
  int get openTaskDelta => current.openTasks - previous.openTasks;
  int get overdueTaskDelta => current.overdueTasks - previous.overdueTasks;
  int get highPriorityOpenTaskDelta =>
      current.highPriorityOpenTasks - previous.highPriorityOpenTasks;
  int get focusMinuteDelta => current.focusMinutes - previous.focusMinutes;
  double get habitCompletionDelta =>
      current.habitCompletionRate - previous.habitCompletionRate;
  int get reviewCountDelta => current.reviewCount - previous.reviewCount;
}

List<InsightsSummary> buildInsightsSummary({
  required DateTime today,
  required Iterable<MindmapNode> nodes,
}) {
  final normalizedToday = today.dateOnly;
  final activeNodes = nodes.where((node) => !node.isArchived).toList();
  return [
        InsightsWindow.today(normalizedToday),
        InsightsWindow.week(normalizedToday),
        InsightsWindow.month(normalizedToday),
      ]
      .map((window) {
        final current = _metricsForWindow(
          nodes: activeNodes,
          window: window,
          today: normalizedToday,
        );
        final previous = _metricsForWindow(
          nodes: activeNodes,
          window: window.previous,
          today: normalizedToday,
        );
        return InsightsSummary(
          window: window,
          current: current,
          previous: previous,
          status: _classifyStatus(current: current, previous: previous),
        );
      })
      .toList(growable: false);
}

InsightMissionStatus classifyInsightMissionStatus({
  required InsightMissionMetrics current,
  required InsightMissionMetrics previous,
}) {
  return _classifyStatus(current: current, previous: previous);
}

InsightMissionMetrics _metricsForWindow({
  required Iterable<MindmapNode> nodes,
  required InsightsWindow window,
  required DateTime today,
}) {
  var openTasks = 0;
  var completedTasks = 0;
  var overdueTasks = 0;
  var highPriorityOpenTasks = 0;
  var focusMinutes = 0;
  var reviewCount = 0;
  var habitCount = 0;
  var habitCompletions = 0;

  final habitWindowKeys = {
    for (var day = window.start; !day.isAfter(window.end); day = day.addDays(1))
      dayKey(day),
  };

  for (final node in nodes) {
    final inWindow = window.contains(node.day);
    final complete = _isComplete(node);

    if (node.type == NodeType.task && inWindow) {
      if (complete) {
        completedTasks++;
      } else {
        openTasks++;
        if (node.priority.index >= NodePriority.high.index) {
          highPriorityOpenTasks++;
        }
      }
    }

    if (node.type == NodeType.task &&
        !complete &&
        node.dueDate != null &&
        window.contains(node.dueDate!) &&
        node.dueDate!.dateOnly.isBefore(today)) {
      overdueTasks++;
    }

    if (inWindow) {
      focusMinutes += _focusMinutesFor(node);
      if (_isReview(node)) reviewCount++;
    }

    if (node.type == NodeType.habit && inWindow) {
      habitCount++;
      habitCompletions += _habitCompletionKeys(
        node,
      ).where(habitWindowKeys.contains).toSet().length;
    }
  }

  return InsightMissionMetrics(
    openTasks: openTasks,
    completedTasks: completedTasks,
    overdueTasks: overdueTasks,
    highPriorityOpenTasks: highPriorityOpenTasks,
    focusMinutes: focusMinutes,
    habitCompletionRate: habitCount == 0
        ? 0
        : habitCompletions / (habitCount * window.dayCount),
    reviewCount: reviewCount,
  );
}

InsightMissionStatus _classifyStatus({
  required InsightMissionMetrics current,
  required InsightMissionMetrics previous,
}) {
  if (current.overdueTasks >= 5 || current.highPriorityOpenTasks >= 8) {
    return InsightMissionStatus.critical;
  }
  if (current.overdueTasks >= 2 || current.highPriorityOpenTasks >= 4) {
    return InsightMissionStatus.atRisk;
  }
  final completionImproved =
      current.taskCompletionRate > previous.taskCompletionRate + 0.05;
  final focusImproved = current.focusMinutes > previous.focusMinutes;
  final riskReduced =
      current.overdueTasks < previous.overdueTasks ||
      current.openTasks < previous.openTasks;
  if (completionImproved || focusImproved || riskReduced) {
    return InsightMissionStatus.improving;
  }
  return InsightMissionStatus.stable;
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}

bool _isReview(MindmapNode node) {
  if (node.type != NodeType.journal && node.type != NodeType.note) return false;
  final lowerTitle = node.title.toLowerCase();
  final tags = node.tags.map((tag) => tag.toLowerCase()).toSet();
  final journal = _sectionData(node.data, 'journal');
  return lowerTitle.contains('review') ||
      tags.contains('review') ||
      tags.contains('weekly-review') ||
      tags.contains('monthly-review') ||
      journal['isWeeklyReview'] == true ||
      journal['isMonthlyReview'] == true;
}

int _focusMinutesFor(MindmapNode node) {
  var total = 0;
  for (final key in const ['focusMinutes', 'focus_minutes', 'duration_mins']) {
    final value = node.data[key];
    if (value is num) total += value.round();
  }
  final rawSessions = node.data['focus_sessions'];
  if (rawSessions is List<Object?>) {
    for (final session in rawSessions) {
      if (session is Map<Object?, Object?>) {
        final duration = session['duration_mins'] ?? session['focusMinutes'];
        if (duration is num) total += duration.round();
      }
    }
  }
  return total;
}

Set<String> _habitCompletionKeys(MindmapNode node) {
  return _dateKeysFromData(
    _sectionData(node.data, 'habit')['completions'],
  ).toSet();
}

Map<String, Object?> _sectionData(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is Map<String, Object?>) return value;
  if (value is Map<Object?, Object?>) return value.cast<String, Object?>();
  return const {};
}

List<String> _dateKeysFromData(Object? value) {
  if (value is List<Object?>) {
    return [
      for (final entry in value)
        if (entry is String) entry,
    ];
  }
  return const [];
}

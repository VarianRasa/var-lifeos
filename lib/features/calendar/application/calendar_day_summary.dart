/// Calendar day tactical summary helpers.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

const Set<NodeType> _taskLikeTypes = {
  NodeType.task,
  NodeType.plan,
  NodeType.goal,
  NodeType.kanban,
  NodeType.habit,
};

enum CalendarDayStatus { clear, busy, critical, complete }

final class CalendarDaySummary {
  CalendarDaySummary({
    required DateTime day,
    required this.totalNodes,
    required this.openTasks,
    required this.completedTasks,
    required this.overdueTasks,
    required this.highPriorityCount,
    required this.habitCount,
    required this.completedHabits,
    required this.focusMinutes,
    required this.hasJournalOrReview,
    required this.status,
  }) : day = day.dateOnly;

  final DateTime day;
  final int totalNodes;
  final int openTasks;
  final int completedTasks;
  final int overdueTasks;
  final int highPriorityCount;
  final int habitCount;
  final int completedHabits;
  final int focusMinutes;
  final bool hasJournalOrReview;
  final CalendarDayStatus status;

  int get taskLikeTotal => openTasks + completedTasks;
  double get habitCompletion =>
      habitCount == 0 ? 0 : completedHabits / habitCount;
}

CalendarDaySummary buildCalendarDaySummary(
  DateTime day,
  Iterable<MindmapNode> nodes,
) {
  final dayOnly = day.dateOnly;
  final dayNodes = nodes
      .where((node) => !node.isArchived && node.day.dateOnly.isSameDay(dayOnly))
      .toList(growable: false);
  var openTasks = 0;
  var completedTasks = 0;
  var overdueTasks = 0;
  var highPriorityCount = 0;
  var habitCount = 0;
  var completedHabits = 0;
  var focusMinutes = 0;
  var hasJournalOrReview = false;

  for (final node in dayNodes) {
    final isDone = node.isDone || node.status == NodeStatus.done;
    final isTaskLike = _taskLikeTypes.contains(node.type);
    if (isTaskLike) {
      if (isDone) {
        completedTasks += 1;
      } else {
        openTasks += 1;
      }
    }
    final due = node.dueDate?.dateOnly;
    if (isTaskLike && !isDone && due != null && due.isBefore(dayOnly)) {
      overdueTasks += 1;
    }
    if (!isDone && node.priority.index >= NodePriority.high.index) {
      highPriorityCount += 1;
    }
    if (node.type == NodeType.habit) {
      habitCount += 1;
      if (isDone) {
        completedHabits += 1;
      }
    }
    if (node.type == NodeType.journal || node.data['isReview'] == true) {
      hasJournalOrReview = true;
    }
    focusMinutes += _intData(node.data, 'focusMinutes');
    focusMinutes += _intData(node.data, 'durationMinutes');
  }

  final status = classifyCalendarDayStatus(
    openTasks: openTasks,
    completedTasks: completedTasks,
    overdueTasks: overdueTasks,
    highPriorityCount: highPriorityCount,
  );

  return CalendarDaySummary(
    day: dayOnly,
    totalNodes: dayNodes.length,
    openTasks: openTasks,
    completedTasks: completedTasks,
    overdueTasks: overdueTasks,
    highPriorityCount: highPriorityCount,
    habitCount: habitCount,
    completedHabits: completedHabits,
    focusMinutes: focusMinutes,
    hasJournalOrReview: hasJournalOrReview,
    status: status,
  );
}

CalendarDayStatus classifyCalendarDayStatus({
  required int openTasks,
  required int completedTasks,
  required int overdueTasks,
  required int highPriorityCount,
}) {
  if (overdueTasks > 0 || highPriorityCount >= 4) {
    return CalendarDayStatus.critical;
  }
  if (openTasks == 0 && completedTasks > 0) {
    return CalendarDayStatus.complete;
  }
  if (openTasks >= 5 || highPriorityCount >= 2) {
    return CalendarDayStatus.busy;
  }
  return CalendarDayStatus.clear;
}

Map<DateTime, CalendarDaySummary> buildCalendarRangeSummaries({
  required Iterable<DateTime> days,
  required Iterable<MindmapNode> nodes,
}) {
  final normalizedNodes = nodes.toList(growable: false);
  return {
    for (final day in days)
      day.dateOnly: buildCalendarDaySummary(day, normalizedNodes),
  };
}

int _intData(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is int) return value;
  if (value is num) return value.round();
  return 0;
}

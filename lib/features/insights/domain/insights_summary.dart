/// Analytics model for the Insights dashboard.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/life_os_summary.dart';
import '../../mindmap/domain/mindmap_node.dart';

final class InsightsSummary {
  const InsightsSummary({
    required this.totalNodeCount,
    required this.activeDayCount,
    required this.averageNodesPerActiveDay,
    required this.busiestDay,
    required this.busiestDayNodeCount,
    required this.taskCount,
    required this.completedTaskCount,
    required this.taskCompletionRate,
    required this.overdueCount,
    required this.productiveDayCount,
    required this.habitConsistency,
    required this.averageGoalProgress,
    required this.weeklyReviewCount,
    required this.monthlyReviewCount,
    required this.totalFocusMinutesToday,
    required this.weeklyFocusSessionsCount,
    required this.focusMinutesByDay,
  });

  factory InsightsSummary.fromNodes({
    required DateTime today,
    required Iterable<MindmapNode> nodes,
  }) {
    final normalizedToday = today.dateOnly;
    final nodeList = nodes.toList(growable: false);
    final dayCounts = <DateTime, int>{};
    final productiveDayKeys = <String>{};
    var taskCount = 0;
    var completedTaskCount = 0;
    var overdueCount = 0;
    var habitCount = 0;
    var habitCompletionCount = 0;
    var goalCount = 0;
    var goalProgressTotal = 0.0;
    var weeklyReviewCount = 0;
    var monthlyReviewCount = 0;
    var totalFocusMinutesToday = 0;
    var weeklyFocusSessionsCount = 0;
    final focusMinutesByDay = <String, int>{};

    final habitWindowKeys = {
      for (var offset = 0; offset < 7; offset++)
        dayKey(normalizedToday.addDays(-offset)),
    };
    final focusWindowKeys = {
      for (var offset = 0; offset < 7; offset++)
        dayKey(normalizedToday.addDays(-offset)),
    };
    final todayKey = dayKey(normalizedToday);

    for (final node in nodeList) {
      final normalizedDay = node.day.dateOnly;
      dayCounts[normalizedDay] = (dayCounts[normalizedDay] ?? 0) + 1;

      if (node.dueDate != null &&
          node.dueDate!.dateOnly.isBefore(normalizedToday) &&
          !_isComplete(node) &&
          !node.isArchived) {
        overdueCount++;
      }

      if (_isProductiveNode(node)) {
        productiveDayKeys.add(dayKey(normalizedDay));
      }

      switch (node.type) {
        case NodeType.task:
          taskCount++;
          if (_isComplete(node)) completedTaskCount++;
        case NodeType.habit:
          habitCount++;
          final completions = _dateKeysFromData(
            _sectionData(node.data, 'habit')['completions'],
          ).toSet();
          habitCompletionCount += completions
              .where(habitWindowKeys.contains)
              .length;
          if (completions.isNotEmpty) productiveDayKeys.add(dayKey(node.day));
        case NodeType.goal:
          goalCount++;
          final progress = LifeOsSummary.goalProgressFor(node);
          goalProgressTotal += progress;
          if (progress > 0) productiveDayKeys.add(dayKey(node.day));
        case NodeType.journal:
          final journalData = _sectionData(node.data, 'journal');
          if (journalData['isWeeklyReview'] == true) weeklyReviewCount++;
          if (journalData['isMonthlyReview'] == true ||
              node.tags.contains('monthly-review')) {
            monthlyReviewCount++;
          }
          final rawSessions = node.data['focus_sessions'];
          if (rawSessions is List) {
            final nodeDayKey = dayKey(node.day.dateOnly);
            var nodeDayMinutes = 0;
            for (final session in rawSessions) {
              if (session is Map) {
                final duration = session['duration_mins'] as num? ?? 0;
                nodeDayMinutes += duration.round();
                if (focusWindowKeys.contains(nodeDayKey)) {
                  weeklyFocusSessionsCount++;
                }
              }
            }
            focusMinutesByDay[nodeDayKey] = nodeDayMinutes;
            if (nodeDayKey == todayKey) {
              totalFocusMinutesToday = nodeDayMinutes;
            }
          }
        case NodeType.kanban ||
            NodeType.plan ||
            NodeType.note ||
            NodeType.link ||
            NodeType.event ||
            NodeType.decision ||
            NodeType.resource ||
            NodeType.idea ||
            NodeType.question ||
            NodeType.contact ||
            NodeType.metric ||
            NodeType.expense ||
            NodeType.bookmark ||
            NodeType.routine ||
            NodeType.empty:
          break;
        default:
          break;
      }
    }

    final busiest = _busiestDay(dayCounts);
    return InsightsSummary(
      totalNodeCount: nodeList.length,
      activeDayCount: dayCounts.length,
      averageNodesPerActiveDay: dayCounts.isEmpty
          ? 0
          : nodeList.length / dayCounts.length,
      busiestDay: busiest,
      busiestDayNodeCount: busiest == null ? 0 : dayCounts[busiest] ?? 0,
      taskCount: taskCount,
      completedTaskCount: completedTaskCount,
      taskCompletionRate: taskCount == 0 ? 0 : completedTaskCount / taskCount,
      overdueCount: overdueCount,
      productiveDayCount: productiveDayKeys.length,
      habitConsistency: habitCount == 0
          ? 0
          : habitCompletionCount / (habitCount * 7),
      averageGoalProgress: goalCount == 0 ? 0 : goalProgressTotal / goalCount,
      weeklyReviewCount: weeklyReviewCount,
      monthlyReviewCount: monthlyReviewCount,
      totalFocusMinutesToday: totalFocusMinutesToday,
      weeklyFocusSessionsCount: weeklyFocusSessionsCount,
      focusMinutesByDay: Map.unmodifiable(focusMinutesByDay),
    );
  }

  final int totalNodeCount;
  final int activeDayCount;
  final double averageNodesPerActiveDay;
  final DateTime? busiestDay;
  final int busiestDayNodeCount;
  final int taskCount;
  final int completedTaskCount;
  final double taskCompletionRate;
  final int overdueCount;
  final int productiveDayCount;
  final double habitConsistency;
  final double averageGoalProgress;
  final int weeklyReviewCount;
  final int monthlyReviewCount;
  final int totalFocusMinutesToday;
  final int weeklyFocusSessionsCount;
  final Map<String, int> focusMinutesByDay;
}

final class InsightsDayPulse {
  const InsightsDayPulse({required this.day, required this.nodeCount});

  final DateTime day;
  final int nodeCount;

  bool get isActive => nodeCount > 0;
}

final class InsightsWeeklyReview {
  const InsightsWeeklyReview({
    required this.completedTasks,
    required this.overdueTasks,
    required this.activeGoals,
    required this.reviewNotes,
    required this.suggestedActions,
  });

  factory InsightsWeeklyReview.fromNodes({
    required DateTime today,
    required Iterable<MindmapNode> nodes,
  }) {
    final normalizedToday = today.dateOnly;
    final windowStart = normalizedToday.addDays(-6);
    final completedTasks = <MindmapNode>[];
    final overdueTasks = <MindmapNode>[];
    final activeGoals = <MindmapNode>[];
    final reviewNotes = <MindmapNode>[];

    for (final node in nodes) {
      if (node.isArchived) continue;
      final inWeek = _isInRange(node.day, windowStart, normalizedToday);
      final completedInWeek = _isInRange(
        node.updatedAt,
        windowStart,
        normalizedToday,
      );
      if (completedInWeek && node.type == NodeType.task && _isComplete(node)) {
        completedTasks.add(node);
      }
      if (node.type == NodeType.task &&
          !_isComplete(node) &&
          node.dueDate != null &&
          node.dueDate!.dateOnly.isBefore(normalizedToday)) {
        overdueTasks.add(node);
      }
      if (node.type == NodeType.goal && !node.isDone) {
        activeGoals.add(node);
      }
      if (inWeek &&
          node.type == NodeType.journal &&
          (_sectionData(node.data, 'journal')['isWeeklyReview'] == true ||
              node.tags.contains('weekly-review'))) {
        reviewNotes.add(node);
      }
    }

    completedTasks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    overdueTasks.sort((a, b) {
      final aDue = a.dueDate ?? a.day;
      final bDue = b.dueDate ?? b.day;
      return aDue.compareTo(bDue);
    });
    activeGoals.sort(
      (a, b) => LifeOsSummary.goalProgressFor(
        a,
      ).compareTo(LifeOsSummary.goalProgressFor(b)),
    );
    reviewNotes.sort((a, b) => b.day.compareTo(a.day));

    return InsightsWeeklyReview(
      completedTasks: List.unmodifiable(completedTasks.take(5)),
      overdueTasks: List.unmodifiable(overdueTasks.take(5)),
      activeGoals: List.unmodifiable(activeGoals.take(5)),
      reviewNotes: List.unmodifiable(reviewNotes.take(3)),
      suggestedActions: List.unmodifiable(
        _weeklyReviewActions(
          completedTasks: completedTasks.length,
          overdueTasks: overdueTasks.length,
          activeGoals: activeGoals.length,
          reviewNotes: reviewNotes.length,
        ),
      ),
    );
  }

  final List<MindmapNode> completedTasks;
  final List<MindmapNode> overdueTasks;
  final List<MindmapNode> activeGoals;
  final List<MindmapNode> reviewNotes;
  final List<String> suggestedActions;
}

final class InsightsWeeklyPulse {
  const InsightsWeeklyPulse({
    required this.days,
    required this.activeDayCount,
    required this.quietDayCount,
    required this.busiestDay,
    required this.busiestDayNodeCount,
    required this.taskCount,
    required this.completedTaskCount,
    required this.upcomingTaskCount,
  });

  factory InsightsWeeklyPulse.fromNodes({
    required DateTime today,
    required Iterable<MindmapNode> nodes,
    int windowDayCount = 7,
  }) {
    final normalizedToday = today.dateOnly;
    final windowStart = normalizedToday.addDays(-(windowDayCount - 1));
    final upcomingEnd = normalizedToday.addDays(windowDayCount - 1);
    final dayCounts = <DateTime, int>{};
    var taskCount = 0;
    var completedTaskCount = 0;
    var upcomingTaskCount = 0;

    for (final node in nodes) {
      if (node.isArchived) continue;

      final normalizedDay = node.day.dateOnly;
      if (_isInRange(normalizedDay, windowStart, normalizedToday)) {
        dayCounts[normalizedDay] = (dayCounts[normalizedDay] ?? 0) + 1;
        if (node.type == NodeType.task) {
          taskCount++;
          if (_isComplete(node)) completedTaskCount++;
        }
      }

      final dueDate = node.dueDate;
      if (node.type == NodeType.task &&
          dueDate != null &&
          !_isComplete(node) &&
          _isInRange(dueDate, normalizedToday, upcomingEnd)) {
        upcomingTaskCount++;
      }
    }

    final days = [
      for (var offset = 0; offset < windowDayCount; offset++)
        () {
          final day = windowStart.addDays(offset);
          return InsightsDayPulse(day: day, nodeCount: dayCounts[day] ?? 0);
        }(),
    ];
    final activeDayCount = days.where((day) => day.isActive).length;
    final busiestDay = _busiestPulseDay(days);

    return InsightsWeeklyPulse(
      days: List.unmodifiable(days),
      activeDayCount: activeDayCount,
      quietDayCount: windowDayCount - activeDayCount,
      busiestDay: busiestDay?.day,
      busiestDayNodeCount: busiestDay?.nodeCount ?? 0,
      taskCount: taskCount,
      completedTaskCount: completedTaskCount,
      upcomingTaskCount: upcomingTaskCount,
    );
  }

  final List<InsightsDayPulse> days;
  final int activeDayCount;
  final int quietDayCount;
  final DateTime? busiestDay;
  final int busiestDayNodeCount;
  final int taskCount;
  final int completedTaskCount;
  final int upcomingTaskCount;

  double get taskCompletionRate {
    if (taskCount == 0) return 0;
    return completedTaskCount / taskCount;
  }
}

DateTime? _busiestDay(Map<DateTime, int> dayCounts) {
  DateTime? result;
  var maxCount = 0;
  for (final entry in dayCounts.entries) {
    if (entry.value > maxCount ||
        (entry.value == maxCount &&
            result != null &&
            entry.key.isAfter(result))) {
      result = entry.key;
      maxCount = entry.value;
    }
  }
  return result;
}

List<String> _weeklyReviewActions({
  required int completedTasks,
  required int overdueTasks,
  required int activeGoals,
  required int reviewNotes,
}) {
  return [
    if (reviewNotes == 0)
      'Create a weekly review journal before planning next week.',
    if (overdueTasks > 0) 'Reschedule or close $overdueTasks overdue tasks.',
    if (completedTasks > 0)
      'Capture wins from $completedTasks completed tasks.',
    if (activeGoals > 3) 'Pick the top 3 goals to protect focus.',
    if (completedTasks == 0 && overdueTasks == 0)
      'Add one concrete next action for tomorrow.',
  ];
}

InsightsDayPulse? _busiestPulseDay(List<InsightsDayPulse> days) {
  InsightsDayPulse? result;
  for (final day in days) {
    if (day.nodeCount == 0) continue;
    if (result == null ||
        day.nodeCount > result.nodeCount ||
        (day.nodeCount == result.nodeCount && day.day.isAfter(result.day))) {
      result = day;
    }
  }
  return result;
}

bool _isInRange(DateTime value, DateTime start, DateTime end) {
  final normalized = value.dateOnly;
  return !normalized.isBefore(start.dateOnly) &&
      !normalized.isAfter(end.dateOnly);
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done;
}

bool _isProductiveNode(MindmapNode node) {
  return _isComplete(node) || node.type == NodeType.journal;
}

Map<String, Object?> _sectionData(Map<String, Object?> data, String key) {
  final section = data[key];
  if (section is Map) return section.cast<String, Object?>();
  return const {};
}

List<String> _dateKeysFromData(Object? value) {
  final rawValues = switch (value) {
    List() => [
      for (final item in value)
        if (item is String) item,
    ],
    String() => value.split(RegExp(r'[,\n]')),
    _ => const <String>[],
  };
  final keys = <String>[];
  final seen = <String>{};

  for (final rawValue in rawValues) {
    final parsed = DateTime.tryParse(rawValue.trim())?.dateOnly;
    if (parsed == null) continue;
    final key = dayKey(parsed);
    if (seen.add(key)) keys.add(key);
  }

  return keys;
}

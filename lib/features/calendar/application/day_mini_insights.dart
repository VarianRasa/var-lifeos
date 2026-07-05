/// Compact 7-day day-page insight summaries.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/habit_completion.dart';
import '../../mindmap/domain/mindmap_node.dart';
import 'daily_review_builder.dart';
import 'focus_session.dart';

final class DayMiniInsight {
  const DayMiniInsight({
    required this.day,
    required this.totalTasks,
    required this.completedTasks,
    required this.totalHabits,
    required this.completedHabits,
    required this.focusMinutes,
    required this.hasReview,
  });

  final DateTime day;
  final int totalTasks;
  final int completedTasks;
  final int totalHabits;
  final int completedHabits;
  final int focusMinutes;
  final bool hasReview;

  double get taskCompletionRate {
    if (totalTasks == 0) return 0;
    return completedTasks / totalTasks;
  }

  double get habitCompletionRate {
    if (totalHabits == 0) return 0;
    return completedHabits / totalHabits;
  }

  int get score {
    final taskScore = (taskCompletionRate * 40).round();
    final habitScore = (habitCompletionRate * 25).round();
    final focusScore = focusMinutes.clamp(0, 120) ~/ 6;
    final reviewScore = hasReview ? 15 : 0;
    return (taskScore + habitScore + focusScore + reviewScore).clamp(0, 100);
  }
}

List<DayMiniInsight> buildDayMiniInsights({
  required List<MindmapNode> nodes,
  required DateTime selectedDay,
  int span = 7,
}) {
  final normalizedDay = selectedDay.dateOnly;
  final start = normalizedDay.subtract(Duration(days: span - 1));
  return List.unmodifiable([
    for (var i = 0; i < span; i += 1)
      _buildInsightForDay(nodes, start.add(Duration(days: i)).dateOnly),
  ]);
}

DayMiniInsight _buildInsightForDay(List<MindmapNode> nodes, DateTime day) {
  final dayNodes = nodes
      .where((node) => !node.isArchived && node.day.dateOnly == day)
      .toList();
  final tasks = dayNodes.where((node) => node.type == NodeType.task).toList();
  final habits = dayNodes.where((node) => node.type == NodeType.habit).toList();

  return DayMiniInsight(
    day: day,
    totalTasks: tasks.length,
    completedTasks: tasks.where(_isComplete).length,
    totalHabits: habits.length,
    completedHabits: habits
        .where((node) => hasHabitCompletionOn(node, day))
        .length,
    focusMinutes: dayNodes.fold<int>(
      0,
      (total, node) => total + totalFocusMinutes(node),
    ),
    hasReview: dayNodes.any((node) => _isDailyReview(node, day)),
  );
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}

bool _isDailyReview(MindmapNode node, DateTime day) {
  final journalData = node.data['journal'];
  return node.type == NodeType.journal &&
      (node.tags.contains('daily-review') ||
          node.title == dailyReviewTitle(day) ||
          (journalData is Map && journalData['isDailyReview'] == true));
}

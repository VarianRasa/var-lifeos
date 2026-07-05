/// Habit consistency and routine marker insights.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/automation_event.dart';
import '../../mindmap/domain/habit_completion.dart';
import '../../mindmap/domain/mindmap_node.dart';

enum RoutineMarkerType { applied, skipped, snoozed }

final class HabitStreak {
  const HabitStreak({
    required this.nodeId,
    required this.title,
    required this.currentStreak,
    required this.longestStreak,
    required this.isAtRisk,
  });

  final String nodeId;
  final String title;
  final int currentStreak;
  final int longestStreak;
  final bool isAtRisk;
}

final class HabitInsightSummary {
  const HabitInsightSummary({
    required this.habitCount,
    required this.completionRate,
    required this.completedCount,
    required this.expectedCount,
    required this.missedHabits,
    required this.streaks,
    required this.mostConsistentHabit,
    required this.streakAtRisk,
  });

  final int habitCount;
  final double completionRate;
  final int completedCount;
  final int expectedCount;
  final List<MindmapNode> missedHabits;
  final List<HabitStreak> streaks;
  final HabitStreak? mostConsistentHabit;
  final HabitStreak? streakAtRisk;
}

final class RoutineInsightSummary {
  const RoutineInsightSummary({
    required this.appliedCount,
    required this.skippedCount,
    required this.snoozedCount,
    required this.frequentlySnoozedRoutine,
  });

  final int appliedCount;
  final int skippedCount;
  final int snoozedCount;
  final String? frequentlySnoozedRoutine;
}

final class HabitRoutineInsightSummary {
  const HabitRoutineInsightSummary({
    required this.habits,
    required this.routines,
  });

  final HabitInsightSummary habits;
  final RoutineInsightSummary routines;
}

HabitRoutineInsightSummary buildHabitRoutineInsights({
  required DateTime start,
  required DateTime end,
  required DateTime today,
  required Iterable<MindmapNode> nodes,
}) {
  final habitSummary = buildHabitInsightSummary(
    start: start,
    end: end,
    today: today,
    nodes: nodes,
  );
  final routineSummary = buildRoutineInsightSummary(
    start: start,
    end: end,
    nodes: nodes,
  );
  return HabitRoutineInsightSummary(
    habits: habitSummary,
    routines: routineSummary,
  );
}

HabitInsightSummary buildHabitInsightSummary({
  required DateTime start,
  required DateTime end,
  required DateTime today,
  required Iterable<MindmapNode> nodes,
}) {
  final normalizedStart = start.dateOnly;
  final normalizedEnd = end.dateOnly;
  final normalizedToday = today.dateOnly;
  final habitNodes = [
    for (final node in nodes)
      if (!node.isArchived &&
          node.type == NodeType.habit &&
          _isInRange(node.day, normalizedStart, normalizedEnd))
        node,
  ];
  final windowKeys = _windowKeys(normalizedStart, normalizedEnd);
  var completedCount = 0;
  final missedHabits = <MindmapNode>[];
  final streaks = <HabitStreak>[];

  for (final node in habitNodes) {
    final completions = habitCompletionKeys(node).toSet();
    final inWindowCount = completions.where(windowKeys.contains).length;
    completedCount += inWindowCount;
    if (inWindowCount == 0 || !completions.contains(dayKey(normalizedToday))) {
      missedHabits.add(node);
    }
    streaks.add(
      HabitStreak(
        nodeId: node.id,
        title: node.title,
        currentStreak: _currentStreakFor(node, normalizedToday),
        longestStreak: calculateMaxStreak(node),
        isAtRisk: _isHabitAtRisk(node, normalizedToday),
      ),
    );
  }

  streaks.sort((a, b) {
    final streakCompare = b.currentStreak.compareTo(a.currentStreak);
    if (streakCompare != 0) return streakCompare;
    return a.title.compareTo(b.title);
  });
  missedHabits.sort((a, b) => a.title.compareTo(b.title));

  final expectedCount = habitNodes.length * windowKeys.length;
  final risky =
      [
        for (final streak in streaks)
          if (streak.isAtRisk) streak,
      ]..sort((a, b) {
        final streakCompare = b.longestStreak.compareTo(a.longestStreak);
        if (streakCompare != 0) return streakCompare;
        return a.title.compareTo(b.title);
      });

  return HabitInsightSummary(
    habitCount: habitNodes.length,
    completionRate: expectedCount == 0 ? 0 : completedCount / expectedCount,
    completedCount: completedCount,
    expectedCount: expectedCount,
    missedHabits: List.unmodifiable(missedHabits),
    streaks: List.unmodifiable(streaks),
    mostConsistentHabit: streaks.isEmpty ? null : streaks.first,
    streakAtRisk: risky.isEmpty ? null : risky.first,
  );
}

RoutineInsightSummary buildRoutineInsightSummary({
  required DateTime start,
  required DateTime end,
  required Iterable<MindmapNode> nodes,
}) {
  final normalizedStart = start.dateOnly;
  final normalizedEnd = end.dateOnly;
  var appliedCount = 0;
  var skippedCount = 0;
  var snoozedCount = 0;
  final snoozedByLabel = <String, int>{};

  for (final node in nodes) {
    if (!_isInRange(node.day, normalizedStart, normalizedEnd)) continue;
    final event = automationEventFromNode(node);
    if (event != null) {
      switch (event.type) {
        case AutomationEventType.applyRoutines:
          appliedCount += event.affectedLabels.length;
        case AutomationEventType.skipRoutines:
          skippedCount += event.affectedLabels.length;
        case AutomationEventType.snoozeRoutines:
          snoozedCount += event.affectedLabels.length;
          for (final label in event.affectedLabels) {
            snoozedByLabel[label] = (snoozedByLabel[label] ?? 0) + 1;
          }
        case AutomationEventType.pauseDuplicateRules:
          break;
      }
      continue;
    }

    final automation = _sectionData(node.data, 'automation');
    final state = automation['state'];
    final label = _stringValue(automation['label']) ?? node.title;
    if (state == 'applied') appliedCount++;
    if (state == 'skipped') skippedCount++;
    if (state == 'snoozed') {
      snoozedCount++;
      snoozedByLabel[label] = (snoozedByLabel[label] ?? 0) + 1;
    }
  }

  return RoutineInsightSummary(
    appliedCount: appliedCount,
    skippedCount: skippedCount,
    snoozedCount: snoozedCount,
    frequentlySnoozedRoutine: _topLabel(snoozedByLabel),
  );
}

bool _isHabitAtRisk(MindmapNode node, DateTime today) {
  final keys = habitCompletionKeys(node).toSet();
  if (keys.isEmpty) return true;
  return !keys.contains(dayKey(today)) &&
      keys.contains(dayKey(today.addDays(-1)));
}

int _currentStreakFor(MindmapNode node, DateTime today) {
  final keys = habitCompletionKeys(node).toSet();
  var cursor = keys.contains(dayKey(today)) ? today : today.addDays(-1);
  var streak = 0;
  while (keys.contains(dayKey(cursor))) {
    streak++;
    cursor = cursor.addDays(-1);
  }
  return streak;
}

Set<String> _windowKeys(DateTime start, DateTime end) {
  return {
    for (var day = start; !day.isAfter(end); day = day.addDays(1)) dayKey(day),
  };
}

bool _isInRange(DateTime day, DateTime start, DateTime end) {
  final value = day.dateOnly;
  return !value.isBefore(start) && !value.isAfter(end);
}

Map<String, Object?> _sectionData(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is Map<String, Object?>) return value;
  if (value is Map<Object?, Object?>) return value.cast<String, Object?>();
  return const {};
}

String? _stringValue(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _topLabel(Map<String, int> counts) {
  if (counts.isEmpty) return null;
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final countCompare = b.value.compareTo(a.value);
      if (countCompare != 0) return countCompare;
      return a.key.compareTo(b.key);
    });
  return entries.first.key;
}

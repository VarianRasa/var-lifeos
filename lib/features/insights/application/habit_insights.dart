/// Habit consistency and routine marker insights.
library;

import 'dart:math' as math;
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
    this.strengthScore = 0.0,
  });

  final String nodeId;
  final String title;
  final int currentStreak;
  final int longestStreak;
  final bool isAtRisk;
  final double strengthScore;
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
    this.aggregateStrengthScore = 0.0,
  });

  final int habitCount;
  final double completionRate;
  final int completedCount;
  final int expectedCount;
  final List<MindmapNode> missedHabits;
  final List<HabitStreak> streaks;
  final HabitStreak? mostConsistentHabit;
  final HabitStreak? streakAtRisk;
  final double aggregateStrengthScore;
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
          !node.day.dateOnly.isAfter(normalizedEnd))
        node,
  ];
  var completedCount = 0;
  var expectedCount = 0;
  final missedHabits = <MindmapNode>[];
  final streaks = <HabitStreak>[];

  for (final node in habitNodes) {
    final completions = habitCompletionKeys(node).toSet();
    final opportunityKeys = _habitOpportunityKeys(
      node,
      normalizedStart,
      normalizedEnd,
    );
    final inWindowCount = completions.where(opportunityKeys.contains).length;
    completedCount += inWindowCount;
    expectedCount += opportunityKeys.length;
    if (opportunityKeys.any((key) => !completions.contains(key))) {
      missedHabits.add(node);
    }
    final strength = calculateHabitStrength(node, normalizedToday);
    streaks.add(
      HabitStreak(
        nodeId: node.id,
        title: node.title,
        currentStreak: _currentStreakFor(node, normalizedToday),
        longestStreak: calculateMaxStreak(node),
        isAtRisk: _isHabitAtRisk(node, normalizedToday),
        strengthScore: strength,
      ),
    );
  }

  streaks.sort((a, b) {
    final streakCompare = b.currentStreak.compareTo(a.currentStreak);
    if (streakCompare != 0) return streakCompare;
    return a.title.compareTo(b.title);
  });
  missedHabits.sort((a, b) => a.title.compareTo(b.title));

  final risky =
      [
        for (final streak in streaks)
          if (streak.isAtRisk) streak,
      ]..sort((a, b) {
        final streakCompare = b.longestStreak.compareTo(a.longestStreak);
        if (streakCompare != 0) return streakCompare;
        return a.title.compareTo(b.title);
      });

  final avgStrength = streaks.isEmpty
      ? 0.0
      : streaks.map((s) => s.strengthScore).reduce((a, b) => a + b) /
            streaks.length;

  return HabitInsightSummary(
    habitCount: habitNodes.length,
    completionRate: expectedCount == 0 ? 0 : completedCount / expectedCount,
    completedCount: completedCount,
    expectedCount: expectedCount,
    missedHabits: List.unmodifiable(missedHabits),
    streaks: List.unmodifiable(streaks),
    mostConsistentHabit: streaks.isEmpty ? null : streaks.first,
    streakAtRisk: risky.isEmpty ? null : risky.first,
    aggregateStrengthScore: double.parse(avgStrength.toStringAsFixed(1)),
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

/// Calculates Habit Strength Score [0.0 - 100.0] using exponential decay.
/// Half-life of habit completion weight is ~14 days (lambda = 0.05).
double calculateHabitStrength(MindmapNode node, DateTime today) {
  final keys = habitCompletionKeys(node);
  if (keys.isEmpty) return 0.0;

  final normalizedToday = today.dateOnly;
  double rawScore = 0.0;
  const lambda = 0.05;

  for (final key in keys) {
    final completionDate = DateTime.tryParse(key)?.dateOnly;
    if (completionDate == null || completionDate.isAfter(normalizedToday)) {
      continue;
    }
    final daysAgo = normalizedToday.difference(completionDate).inDays;
    // Base weight per completion is 20, decayed exponentially over daysAgo
    final weight = 20.0 * math.exp(-lambda * daysAgo);
    rawScore += weight;
  }

  final score = rawScore.clamp(0.0, 100.0);
  return double.parse(score.toStringAsFixed(1));
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

Set<String> _habitOpportunityKeys(
  MindmapNode node,
  DateTime start,
  DateTime end,
) {
  final effectiveStart = node.day.dateOnly.isAfter(start)
      ? node.day.dateOnly
      : start;
  final recurrence = _stringValue(
    _sectionData(node.data, 'habit')['recurrence'],
  );
  return {
    for (var day = effectiveStart; !day.isAfter(end); day = day.addDays(1))
      if (_habitIsDueOn(day, node.day.dateOnly, recurrence ?? 'daily'))
        dayKey(day),
  };
}

bool _habitIsDueOn(DateTime day, DateTime startedOn, String recurrence) {
  return switch (recurrence) {
    'weekdays' => day.weekday <= DateTime.friday,
    'weekly' => day.weekday == startedOn.weekday,
    'monthly' => day.day == startedOn.day,
    _ => true,
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

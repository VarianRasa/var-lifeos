/// Habit completion helpers shared by Life OS surfaces.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import 'mindmap_node.dart';

MindmapNode logHabitCompletion(
  MindmapNode node,
  DateTime day, {
  DateTime? now,
}) {
  if (node.type != NodeType.habit) return node;

  final normalizedDay = day.dateOnly;
  final existingKeys = habitCompletionKeys(node);
  final nextKeys = {...existingKeys, dayKey(normalizedDay)}.toList()..sort();
  if (nextKeys.length == existingKeys.length) return node;

  return _withHabitCompletions(node, nextKeys, now: now);
}

MindmapNode removeHabitCompletion(
  MindmapNode node,
  DateTime day, {
  DateTime? now,
}) {
  if (node.type != NodeType.habit) return node;

  final key = dayKey(day.dateOnly);
  final existingKeys = habitCompletionKeys(node);
  if (!existingKeys.contains(key)) return node;

  return _withHabitCompletions(
    node,
    existingKeys.where((completion) => completion != key).toList(),
    now: now,
  );
}

MindmapNode _withHabitCompletions(
  MindmapNode node,
  List<String> completions, {
  DateTime? now,
}) {
  final habitData = _habitData(node);
  return node.copyWith(
    data: {
      ...node.data,
      'habit': {...habitData, 'completions': completions},
    },
    updatedAt: now ?? DateTime.now(),
  );
}

bool hasHabitCompletionOn(MindmapNode node, DateTime day) {
  return habitCompletionKeys(node).contains(dayKey(day));
}

List<String> habitCompletionKeys(MindmapNode node) {
  final rawCompletions = _habitData(node)['completions'];
  final rawValues = switch (rawCompletions) {
    List() => [
      for (final item in rawCompletions)
        if (item is String) item,
    ],
    String() => rawCompletions.split(RegExp(r'[,\n]')),
    _ => const <String>[],
  };
  final seen = <String>{};
  final keys = <String>[];

  for (final rawValue in rawValues) {
    final parsed = DateTime.tryParse(rawValue.trim())?.dateOnly;
    if (parsed == null) continue;
    final key = dayKey(parsed);
    if (seen.add(key)) keys.add(key);
  }

  return keys..sort();
}

int calculateCurrentStreak(MindmapNode node) {
  final keys = habitCompletionKeys(node);
  final freezes = streakFreezeKeys(node);
  final validKeys = {...keys, ...freezes};
  if (validKeys.isEmpty) return 0;

  final today = DateTime.now().dateOnly;
  final yesterday = today.subtract(const Duration(days: 1));

  final todayKey = dayKey(today);
  final yesterdayKey = dayKey(yesterday);

  if (!validKeys.contains(todayKey) && !validKeys.contains(yesterdayKey)) {
    return 0;
  }

  int streak = 0;
  DateTime currentDay = validKeys.contains(todayKey) ? today : yesterday;

  while (true) {
    final currentKey = dayKey(currentDay);
    if (validKeys.contains(currentKey)) {
      streak++;
      currentDay = currentDay.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }

  return streak;
}

int calculateMaxStreak(MindmapNode node) {
  final keys = habitCompletionKeys(node);
  final freezes = streakFreezeKeys(node);
  final validKeys = ({...keys, ...freezes}).toList()..sort();
  if (validKeys.isEmpty) return 0;

  int maxStreak = 0;
  int currentStreak = 0;
  DateTime? prevDate;

  for (final key in validKeys) {
    final date = DateTime.tryParse(key)?.dateOnly;
    if (date == null) continue;

    if (prevDate == null) {
      currentStreak = 1;
    } else {
      final difference = date.difference(prevDate).inDays;
      if (difference == 1) {
        currentStreak++;
      } else if (difference > 1) {
        if (currentStreak > maxStreak) {
          maxStreak = currentStreak;
        }
        currentStreak = 1;
      }
    }
    prevDate = date;
  }

  if (currentStreak > maxStreak) {
    maxStreak = currentStreak;
  }

  return maxStreak;
}

Map<String, Object?> _habitData(MindmapNode node) {
  final section = node.data['habit'];
  if (section is Map) return section.cast<String, Object?>();
  return const {};
}

/// Habit Stacking & Streak Freeze additions.

/// Sets a habit stacking trigger node ID on a habit ("After [triggerId], I will do this habit").
MindmapNode setHabitStackingTrigger(
  MindmapNode node,
  String? triggerHabitId, {
  DateTime? now,
}) {
  if (node.type != NodeType.habit) return node;
  final habitData = _habitData(node);
  final updatedData = {...habitData};
  if (triggerHabitId == null || triggerHabitId.isEmpty) {
    updatedData.remove('stackedTriggerHabitId');
  } else {
    updatedData['stackedTriggerHabitId'] = triggerHabitId;
  }
  return node.copyWith(
    data: {...node.data, 'habit': updatedData},
    updatedAt: now ?? DateTime.now(),
  );
}

/// Reads the stacked trigger habit ID if configured.
String? getHabitStackingTriggerId(MindmapNode node) {
  final raw = _habitData(node)['stackedTriggerHabitId'];
  return raw is String && raw.isNotEmpty ? raw : null;
}

/// Consumes a streak freeze token on a specific date to protect streak calculation.
MindmapNode applyStreakFreeze(MindmapNode node, DateTime day, {DateTime? now}) {
  if (node.type != NodeType.habit) return node;
  final habitData = _habitData(node);
  final existingFreezes = streakFreezeKeys(node);
  final key = dayKey(day.dateOnly);
  if (existingFreezes.contains(key)) return node;

  final nextFreezes = [...existingFreezes, key]..sort();
  return node.copyWith(
    data: {
      ...node.data,
      'habit': {...habitData, 'streakFreezes': nextFreezes},
    },
    updatedAt: now ?? DateTime.now(),
  );
}

/// Reads all streak freeze keys stored on habit.
List<String> streakFreezeKeys(MindmapNode node) {
  final raw = _habitData(node)['streakFreezes'];
  if (raw is List) {
    return [
      for (final item in raw)
        if (item is String && item.isNotEmpty) item,
    ]..sort();
  }
  return const [];
}

final class HabitStreakStats {
  const HabitStreakStats({
    required this.currentStreak,
    required this.maxStreak,
    required this.totalCompletions,
    required this.completionRate30Days,
  });

  final int currentStreak;
  final int maxStreak;
  final int totalCompletions;
  final double completionRate30Days;
}

HabitStreakStats calculateHabitStreakStats(MindmapNode node, DateTime today) {
  final keys = habitCompletionKeys(node);
  final validKeys = {...keys, ...streakFreezeKeys(node)};
  final todayNorm = today.dateOnly;
  final yesterday = todayNorm.subtract(const Duration(days: 1));
  var currentDay = validKeys.contains(dayKey(todayNorm))
      ? todayNorm
      : yesterday;
  var currentStreak = 0;
  while (validKeys.contains(dayKey(currentDay))) {
    currentStreak++;
    currentDay = currentDay.subtract(const Duration(days: 1));
  }
  final maxStreak = calculateMaxStreak(node);
  final totalCompletions = keys.length;

  final thirtyDaysAgo = todayNorm.subtract(const Duration(days: 29));

  var completionsInLast30 = 0;
  for (final key in keys) {
    final date = DateTime.tryParse(key)?.dateOnly;
    if (date != null &&
        !date.isBefore(thirtyDaysAgo) &&
        !date.isAfter(todayNorm)) {
      completionsInLast30++;
    }
  }

  final rate = (completionsInLast30 / 30.0).clamp(0.0, 1.0);

  return HabitStreakStats(
    currentStreak: currentStreak,
    maxStreak: maxStreak,
    totalCompletions: totalCompletions,
    completionRate30Days: rate,
  );
}

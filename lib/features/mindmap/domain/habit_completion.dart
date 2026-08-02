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
  if (keys.isEmpty) return 0;

  final today = DateTime.now().dateOnly;
  final yesterday = today.subtract(const Duration(days: 1));

  final todayKey = dayKey(today);
  final yesterdayKey = dayKey(yesterday);

  if (!keys.contains(todayKey) && !keys.contains(yesterdayKey)) {
    return 0;
  }

  int streak = 0;
  DateTime currentDay = keys.contains(todayKey) ? today : yesterday;

  while (true) {
    final currentKey = dayKey(currentDay);
    if (keys.contains(currentKey)) {
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
  if (keys.isEmpty) return 0;

  int maxStreak = 0;
  int currentStreak = 0;
  DateTime? prevDate;

  for (final key in keys) {
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

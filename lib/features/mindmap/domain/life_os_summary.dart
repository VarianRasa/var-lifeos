/// Life OS domain signals derived from mindmap nodes.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import 'mindmap_node.dart';

final class LifeOsSummary {
  const LifeOsSummary({
    required this.habitCount,
    required this.bestHabitStreak,
    required this.journalCount,
    required this.averageMood,
    required this.averageEnergy,
    required this.weeklyReviewCount,
    required this.goalCount,
    required this.averageGoalProgress,
  });

  factory LifeOsSummary.fromNodes({
    required DateTime today,
    required Iterable<MindmapNode> nodes,
  }) {
    final normalizedToday = today.dateOnly;
    var habitCount = 0;
    var bestHabitStreak = 0;
    var journalCount = 0;
    var moodTotal = 0.0;
    var moodSamples = 0;
    var energyTotal = 0.0;
    var energySamples = 0;
    var weeklyReviewCount = 0;
    var goalCount = 0;
    var goalProgressTotal = 0.0;

    for (final node in nodes) {
      switch (node.type) {
        case NodeType.habit:
          habitCount++;
          final streak = habitStreakFor(node, normalizedToday);
          if (streak > bestHabitStreak) bestHabitStreak = streak;
        case NodeType.journal:
          journalCount++;
          final journalData = _sectionData(node.data, 'journal');
          final mood = _ratingFromData(journalData['mood']);
          if (mood != null) {
            moodTotal += mood;
            moodSamples++;
          }
          final energy = _ratingFromData(journalData['energy']);
          if (energy != null) {
            energyTotal += energy;
            energySamples++;
          }
          if (journalData['isWeeklyReview'] == true) weeklyReviewCount++;
        case NodeType.goal:
          goalCount++;
          goalProgressTotal += goalProgressFor(node);
        case NodeType.task ||
            NodeType.kanban ||
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

    return LifeOsSummary(
      habitCount: habitCount,
      bestHabitStreak: bestHabitStreak,
      journalCount: journalCount,
      averageMood: moodSamples == 0 ? 0 : moodTotal / moodSamples,
      averageEnergy: energySamples == 0 ? 0 : energyTotal / energySamples,
      weeklyReviewCount: weeklyReviewCount,
      goalCount: goalCount,
      averageGoalProgress: goalCount == 0 ? 0 : goalProgressTotal / goalCount,
    );
  }

  final int habitCount;
  final int bestHabitStreak;
  final int journalCount;
  final double averageMood;
  final double averageEnergy;
  final int weeklyReviewCount;
  final int goalCount;
  final double averageGoalProgress;

  static int habitStreakFor(MindmapNode node, DateTime today) {
    final completionKeys = _dateKeysFromData(
      _sectionData(node.data, 'habit')['completions'],
    ).toSet();
    var cursor = today.dateOnly;
    var streak = 0;

    while (completionKeys.contains(dayKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1)).dateOnly;
    }

    return streak;
  }

  static double goalProgressFor(MindmapNode node) {
    final goalData = _sectionData(node.data, 'goal');
    final milestones = _stringListFromData(goalData['milestones']);
    if (milestones.isEmpty) return node.progress;

    final completedMilestones = _stringListFromData(
      goalData['completedMilestones'],
    );
    if (completedMilestones.isEmpty) return node.progress;

    final milestoneKeys = {
      for (final milestone in milestones) _normalizedKey(milestone),
    };
    final completedCount = {
      for (final milestone in completedMilestones)
        if (milestoneKeys.contains(_normalizedKey(milestone)))
          _normalizedKey(milestone),
    }.length;

    return (completedCount / milestones.length).clamp(0, 1).toDouble();
  }
}

final class LifeOsRhythm {
  const LifeOsRhythm({
    required this.windowDayCount,
    required this.journalDayCount,
    required this.habitCompletionDayCount,
    required this.hasWeeklyReviewThisWeek,
  });

  factory LifeOsRhythm.fromNodes({
    required DateTime today,
    required Iterable<MindmapNode> nodes,
    int windowDayCount = 7,
  }) {
    final normalizedToday = today.dateOnly;
    final windowStart = normalizedToday.addDays(-(windowDayCount - 1));
    final weekStart = normalizedToday.startOfWeek;
    final journalKeys = <String>{};
    final habitCompletionKeys = <String>{};
    var hasWeeklyReviewThisWeek = false;

    for (final node in nodes) {
      switch (node.type) {
        case NodeType.habit:
          for (final key in _dateKeysFromData(
            _sectionData(node.data, 'habit')['completions'],
          )) {
            final parsed = DateTime.tryParse(key)?.dateOnly;
            if (parsed == null) continue;
            if (_isInRange(parsed, windowStart, normalizedToday)) {
              habitCompletionKeys.add(key);
            }
          }
        case NodeType.journal:
          final journalDay = node.day.dateOnly;
          if (_isInRange(journalDay, windowStart, normalizedToday)) {
            journalKeys.add(dayKey(journalDay));
          }
          final journalData = _sectionData(node.data, 'journal');
          if (journalData['isWeeklyReview'] == true &&
              _isInRange(journalDay, weekStart, normalizedToday)) {
            hasWeeklyReviewThisWeek = true;
          }
        case NodeType.task ||
            NodeType.kanban ||
            NodeType.plan ||
            NodeType.note ||
            NodeType.goal ||
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

    return LifeOsRhythm(
      windowDayCount: windowDayCount,
      journalDayCount: journalKeys.length,
      habitCompletionDayCount: habitCompletionKeys.length,
      hasWeeklyReviewThisWeek: hasWeeklyReviewThisWeek,
    );
  }

  final int windowDayCount;
  final int journalDayCount;
  final int habitCompletionDayCount;
  final bool hasWeeklyReviewThisWeek;

  double get journalCoverage {
    if (windowDayCount == 0) return 0;
    return (journalDayCount / windowDayCount).clamp(0, 1).toDouble();
  }

  double get habitCoverage {
    if (windowDayCount == 0) return 0;
    return (habitCompletionDayCount / windowDayCount).clamp(0, 1).toDouble();
  }

  double get rhythmScore {
    final reviewScore = hasWeeklyReviewThisWeek ? 1.0 : 0.0;
    return ((journalCoverage + habitCoverage + reviewScore) / 3)
        .clamp(0, 1)
        .toDouble();
  }

  String get scoreLabel => '${(rhythmScore * 100).round()}% rhythm';
}

enum LifeOsAttentionType { overdueTask, habitDue, stuckGoal, journalIncomplete }

enum LifeOsAttentionSeverity { info, warning, critical }

final class LifeOsAttentionSignal {
  const LifeOsAttentionSignal({
    required this.nodeId,
    required this.title,
    required this.day,
    required this.type,
    required this.severity,
    required this.message,
    required this.actionLabel,
  });

  final String nodeId;
  final String title;
  final DateTime day;
  final LifeOsAttentionType type;
  final LifeOsAttentionSeverity severity;
  final String message;
  final String actionLabel;
}

final class LifeOsAttention {
  const LifeOsAttention({required this.signals});

  factory LifeOsAttention.fromNodes({
    required DateTime today,
    required Iterable<MindmapNode> nodes,
  }) {
    final normalizedToday = today.dateOnly;
    final critical = <LifeOsAttentionSignal>[];
    final warning = <LifeOsAttentionSignal>[];
    final info = <LifeOsAttentionSignal>[];

    void addSignal(LifeOsAttentionSignal signal) {
      switch (signal.severity) {
        case LifeOsAttentionSeverity.critical:
          critical.add(signal);
        case LifeOsAttentionSeverity.warning:
          warning.add(signal);
        case LifeOsAttentionSeverity.info:
          info.add(signal);
      }
    }

    for (final node in nodes) {
      if (node.isArchived) continue;

      final overdueTask = _overdueTaskSignal(node, normalizedToday);
      if (overdueTask != null) addSignal(overdueTask);

      final habitDue = _habitDueSignal(node, normalizedToday);
      if (habitDue != null) addSignal(habitDue);

      final stuckGoal = _stuckGoalSignal(node, normalizedToday);
      if (stuckGoal != null) addSignal(stuckGoal);

      final journalIncomplete = _journalIncompleteSignal(node, normalizedToday);
      if (journalIncomplete != null) addSignal(journalIncomplete);
    }

    return LifeOsAttention(
      signals: List.unmodifiable([...critical, ...warning, ...info]),
    );
  }

  final List<LifeOsAttentionSignal> signals;

  int get criticalCount => _countSeverity(LifeOsAttentionSeverity.critical);

  int get warningCount => _countSeverity(LifeOsAttentionSeverity.warning);

  int get infoCount => _countSeverity(LifeOsAttentionSeverity.info);

  int _countSeverity(LifeOsAttentionSeverity severity) {
    return signals.where((signal) => signal.severity == severity).length;
  }
}

LifeOsAttentionSignal? _overdueTaskSignal(MindmapNode node, DateTime today) {
  final dueDate = node.dueDate;
  if (node.type != NodeType.task ||
      dueDate == null ||
      !dueDate.dateOnly.isBefore(today) ||
      _isComplete(node)) {
    return null;
  }

  return LifeOsAttentionSignal(
    nodeId: node.id,
    title: node.title,
    day: node.day,
    type: LifeOsAttentionType.overdueTask,
    severity: LifeOsAttentionSeverity.critical,
    message: 'Overdue since ${dayKey(dueDate)}',
    actionLabel: 'Review task',
  );
}

LifeOsAttentionSignal? _habitDueSignal(MindmapNode node, DateTime today) {
  if (node.type != NodeType.habit) return null;
  final habitData = _sectionData(node.data, 'habit');
  final recurrence = (habitData['recurrence'] as String? ?? 'daily')
      .trim()
      .toLowerCase();
  final completionKeys = _dateKeysFromData(habitData['completions']).toSet();
  final isDue = switch (recurrence) {
    'weekly' => !_hasCompletionInRange(
      completionKeys,
      today.startOfWeek,
      today,
    ),
    'monthly' => !_hasCompletionInRange(
      completionKeys,
      today.firstOfMonth,
      today,
    ),
    _ => !completionKeys.contains(dayKey(today)),
  };
  if (!isDue) return null;

  final yesterdayKey = dayKey(today.addDays(-1));
  final message = recurrence == 'daily' && completionKeys.contains(yesterdayKey)
      ? 'Keep the streak alive today'
      : 'Log the next ${recurrence == 'daily' ? 'daily' : recurrence} completion';

  return LifeOsAttentionSignal(
    nodeId: node.id,
    title: node.title,
    day: node.day,
    type: LifeOsAttentionType.habitDue,
    severity: LifeOsAttentionSeverity.warning,
    message: message,
    actionLabel: 'Log habit',
  );
}

LifeOsAttentionSignal? _stuckGoalSignal(MindmapNode node, DateTime today) {
  if (node.type != NodeType.goal || _isComplete(node)) return null;
  final progress = LifeOsSummary.goalProgressFor(node);
  final daysSinceUpdate = today.difference(node.updatedAt.dateOnly).inDays;
  if (progress >= 1 || daysSinceUpdate < 14) return null;

  return LifeOsAttentionSignal(
    nodeId: node.id,
    title: node.title,
    day: node.day,
    type: LifeOsAttentionType.stuckGoal,
    severity: LifeOsAttentionSeverity.warning,
    message: 'No progress update in $daysSinceUpdate days',
    actionLabel: 'Update goal',
  );
}

LifeOsAttentionSignal? _journalIncompleteSignal(
  MindmapNode node,
  DateTime today,
) {
  if (node.type != NodeType.journal || !node.day.isSameDay(today)) {
    return null;
  }
  final journalData = _sectionData(node.data, 'journal');
  final mood = _ratingFromData(journalData['mood']);
  final energy = _ratingFromData(journalData['energy']);
  if (mood != null && energy != null) return null;

  return LifeOsAttentionSignal(
    nodeId: node.id,
    title: node.title,
    day: node.day,
    type: LifeOsAttentionType.journalIncomplete,
    severity: LifeOsAttentionSeverity.info,
    message: 'Add mood and energy to complete today',
    actionLabel: 'Complete log',
  );
}

bool _hasCompletionInRange(
  Set<String> completionKeys,
  DateTime start,
  DateTime end,
) {
  var cursor = start.dateOnly;
  final normalizedEnd = end.dateOnly;
  while (!cursor.isAfter(normalizedEnd)) {
    if (completionKeys.contains(dayKey(cursor))) return true;
    cursor = cursor.addDays(1);
  }
  return false;
}

bool _isInRange(DateTime value, DateTime start, DateTime end) {
  final normalized = value.dateOnly;
  return !normalized.isBefore(start.dateOnly) &&
      !normalized.isAfter(end.dateOnly);
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done;
}

Map<String, Object?> _sectionData(Map<String, Object?> data, String key) {
  final section = data[key];
  if (section is Map) return section.cast<String, Object?>();
  return const {};
}

List<String> _stringListFromData(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
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
  final seen = <String>{};
  final keys = <String>[];

  for (final rawValue in rawValues) {
    final parsed = DateTime.tryParse(rawValue.trim())?.dateOnly;
    if (parsed == null) continue;
    final key = dayKey(parsed);
    if (seen.add(key)) keys.add(key);
  }

  return keys;
}

double? _ratingFromData(Object? value) {
  final rating = switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value.trim()),
    _ => null,
  };
  if (rating == null || rating <= 0) return null;
  return rating.clamp(1, 5).toDouble();
}

String _normalizedKey(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

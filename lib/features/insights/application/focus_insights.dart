/// Focus/time investment analytics for Insights.
library;

import '../../../core/utils/date_utils.dart';
import '../../calendar/application/focus_session.dart';
import '../../mindmap/domain/mindmap_node.dart';

final class FocusBucket {
  const FocusBucket({required this.label, required this.minutes});

  final String label;
  final int minutes;
}

final class FocusInsightSummary {
  const FocusInsightSummary({
    required this.totalMinutes,
    required this.minutesByDay,
    required this.minutesByProject,
    required this.minutesByArea,
    required this.minutesByTag,
    required this.bestFocusDay,
    required this.bestFocusMinutes,
    required this.plannedOpenTasks,
    required this.hasLowFocusWarning,
  });

  final int totalMinutes;
  final List<FocusBucket> minutesByDay;
  final List<FocusBucket> minutesByProject;
  final List<FocusBucket> minutesByArea;
  final List<FocusBucket> minutesByTag;
  final DateTime? bestFocusDay;
  final int bestFocusMinutes;
  final int plannedOpenTasks;
  final bool hasLowFocusWarning;
}

FocusInsightSummary buildFocusInsightSummary({
  required DateTime start,
  required DateTime end,
  required Iterable<MindmapNode> nodes,
}) {
  final normalizedStart = start.dateOnly;
  final normalizedEnd = end.dateOnly;
  final minutesByDay = <String, int>{};
  final minutesByProject = <String, int>{};
  final minutesByArea = <String, int>{};
  final minutesByTag = <String, int>{};
  var totalMinutes = 0;
  var plannedOpenTasks = 0;

  for (
    var day = normalizedStart;
    !day.isAfter(normalizedEnd);
    day = day.addDays(1)
  ) {
    minutesByDay[dayKey(day)] = 0;
  }

  for (final node in nodes) {
    if (node.isArchived ||
        !_isInRange(node.day, normalizedStart, normalizedEnd)) {
      continue;
    }
    if (!_isComplete(node) && _isTaskLike(node)) plannedOpenTasks++;
    final minutes = focusMinutesForNode(node);
    if (minutes <= 0) continue;
    totalMinutes += minutes;
    final day = dayKey(node.day);
    minutesByDay[day] = (minutesByDay[day] ?? 0) + minutes;
    if (node.project.isNotEmpty) {
      minutesByProject[node.project] =
          (minutesByProject[node.project] ?? 0) + minutes;
    }
    if (node.area.isNotEmpty) {
      minutesByArea[node.area] = (minutesByArea[node.area] ?? 0) + minutes;
    }
    for (final tag in node.tags) {
      minutesByTag[tag] = (minutesByTag[tag] ?? 0) + minutes;
    }
  }

  DateTime? bestFocusDay;
  var bestFocusMinutes = 0;
  for (final entry in minutesByDay.entries) {
    final day = DateTime.parse(entry.key).dateOnly;
    if (entry.value > bestFocusMinutes ||
        (entry.value == bestFocusMinutes &&
            bestFocusDay != null &&
            day.isBefore(bestFocusDay))) {
      bestFocusDay = day;
      bestFocusMinutes = entry.value;
    }
  }

  return FocusInsightSummary(
    totalMinutes: totalMinutes,
    minutesByDay: _dayBuckets(minutesByDay),
    minutesByProject: _topBuckets(minutesByProject),
    minutesByArea: _topBuckets(minutesByArea),
    minutesByTag: _topBuckets(minutesByTag),
    bestFocusDay: bestFocusMinutes == 0 ? null : bestFocusDay,
    bestFocusMinutes: bestFocusMinutes,
    plannedOpenTasks: plannedOpenTasks,
    hasLowFocusWarning: plannedOpenTasks >= 4 && totalMinutes < 60,
  );
}

int focusMinutesForNode(MindmapNode node) {
  var total = totalFocusMinutes(node);
  for (final key in const [
    'focusMinutes',
    'focus_minutes',
    'durationMinutes',
    'duration_mins',
  ]) {
    final value = node.data[key];
    if (value is num) total += value.round();
  }
  final legacy = node.data['focus_sessions'];
  if (legacy is List<Object?>) {
    for (final session in legacy) {
      if (session is Map<Object?, Object?>) {
        final value = session['duration_mins'] ?? session['durationMinutes'];
        if (value is num) total += value.round();
      }
    }
  }
  return total;
}

List<FocusBucket> _dayBuckets(Map<String, int> values) {
  return List.unmodifiable([
    for (final entry in values.entries)
      FocusBucket(label: entry.key, minutes: entry.value),
  ]);
}

List<FocusBucket> _topBuckets(Map<String, int> values) {
  final buckets =
      [
        for (final entry in values.entries)
          FocusBucket(label: entry.key, minutes: entry.value),
      ]..sort((a, b) {
        final minutesCompare = b.minutes.compareTo(a.minutes);
        if (minutesCompare != 0) return minutesCompare;
        return a.label.compareTo(b.label);
      });
  return List.unmodifiable(buckets.take(5));
}

bool _isInRange(DateTime day, DateTime start, DateTime end) {
  final value = day.dateOnly;
  return !value.isBefore(start) && !value.isAfter(end);
}

bool _isTaskLike(MindmapNode node) {
  return node.type.name == 'task' || node.type.name == 'plan';
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status.name == 'done' || node.progress >= 1;
}

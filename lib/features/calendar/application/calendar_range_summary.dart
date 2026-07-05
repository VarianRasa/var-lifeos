/// Inclusive calendar range summaries.
library;

import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import 'calendar_day_summary.dart';

final class CalendarRangeSummary {
  CalendarRangeSummary({required List<CalendarDaySummary> days})
    : days = List.unmodifiable(days);

  final List<CalendarDaySummary> days;

  int get totalTasks => days.fold(0, (sum, day) => sum + day.taskLikeTotal);
  int get completedTasks =>
      days.fold(0, (sum, day) => sum + day.completedTasks);
  int get overdueTasks => days.fold(0, (sum, day) => sum + day.overdueTasks);
  int get focusMinutes => days.fold(0, (sum, day) => sum + day.focusMinutes);
  int get journals => days.where((day) => day.hasJournalOrReview).length;
  int get habitCompletions =>
      days.fold(0, (sum, day) => sum + day.completedHabits);
}

List<DateTime> inclusiveCalendarDays(DateTime start, DateTime end) {
  var cursor = start.dateOnly;
  final last = end.dateOnly;
  if (cursor.isAfter(last)) {
    return inclusiveCalendarDays(last, cursor);
  }
  final days = <DateTime>[];
  while (!cursor.isAfter(last)) {
    days.add(cursor);
    cursor = cursor.add(const Duration(days: 1));
  }
  return days;
}

CalendarRangeSummary buildCalendarRangeSummary({
  required DateTime start,
  required DateTime end,
  required Iterable<MindmapNode> nodes,
}) {
  return CalendarRangeSummary(
    days: [
      for (final day in inclusiveCalendarDays(start, end))
        buildCalendarDaySummary(day, nodes),
    ],
  );
}

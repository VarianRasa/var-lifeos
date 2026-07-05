/// Weekly calendar workload summaries.
library;

import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import 'calendar_day_summary.dart';

final class CalendarWeekSummary {
  CalendarWeekSummary({required List<CalendarDaySummary> days})
    : days = List.unmodifiable(days);

  final List<CalendarDaySummary> days;

  DateTime get startDay => days.first.day;
  DateTime get endDay => days.last.day;
  int get openTasks => days.fold(0, (sum, day) => sum + day.openTasks);
  int get completedTasks =>
      days.fold(0, (sum, day) => sum + day.completedTasks);
  int get overdueTasks => days.fold(0, (sum, day) => sum + day.overdueTasks);
  int get focusMinutes => days.fold(0, (sum, day) => sum + day.focusMinutes);
  int get reviewCount => days.where((day) => day.hasJournalOrReview).length;
}

List<DateTime> calendarWeekDays(DateTime selectedDay) {
  final day = selectedDay.dateOnly;
  final start = day.subtract(Duration(days: day.weekday - DateTime.monday));
  return List.generate(7, (index) => start.add(Duration(days: index)));
}

CalendarWeekSummary buildCalendarWeekSummary({
  required DateTime selectedDay,
  required Iterable<MindmapNode> nodes,
}) {
  final days = calendarWeekDays(selectedDay);
  return CalendarWeekSummary(
    days: [for (final day in days) buildCalendarDaySummary(day, nodes)],
  );
}

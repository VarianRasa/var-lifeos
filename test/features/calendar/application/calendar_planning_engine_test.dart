import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/calendar/application/calendar_day_summary.dart';
import 'package:var_app/features/calendar/application/calendar_planning_engine.dart';
import 'package:var_app/features/calendar/application/calendar_week_summary.dart';

CalendarDaySummary summary({
  required DateTime day,
  int totalNodes = 0,
  int openTasks = 0,
  int completedTasks = 0,
  int overdueTasks = 0,
  int highPriorityCount = 0,
  int habitCount = 0,
  int completedHabits = 0,
  bool hasJournalOrReview = false,
}) {
  return CalendarDaySummary(
    day: day,
    totalNodes: totalNodes,
    openTasks: openTasks,
    completedTasks: completedTasks,
    overdueTasks: overdueTasks,
    highPriorityCount: highPriorityCount,
    habitCount: habitCount,
    completedHabits: completedHabits,
    focusMinutes: 0,
    hasJournalOrReview: hasJournalOrReview,
    status: CalendarDayStatus.clear,
  );
}

void main() {
  test(
    'buildCalendarPlanningSuggestions detects priority cluster and empty weekend',
    () {
      final week = CalendarWeekSummary(
        days: [
          summary(day: DateTime(2026, 6, 29)),
          summary(day: DateTime(2026, 6, 30)),
          summary(day: DateTime(2026, 7, 1), highPriorityCount: 3),
          summary(day: DateTime(2026, 7, 2)),
          summary(day: DateTime(2026, 7, 3)),
          summary(day: DateTime(2026, 7, 4)),
          summary(day: DateTime(2026, 7, 5)),
        ],
      );

      final suggestions = buildCalendarPlanningSuggestions(
        week: week,
        today: DateTime(2026, 7, 1),
      );

      expect(
        suggestions.map((suggestion) => suggestion.title),
        contains('High-priority cluster on Wednesday'),
      );
      expect(
        suggestions.map((suggestion) => suggestion.title),
        contains('Empty weekend - plan reset?'),
      );
    },
  );
}

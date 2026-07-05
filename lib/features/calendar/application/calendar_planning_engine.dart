/// Deterministic calendar planning suggestions.
library;

import 'calendar_day_summary.dart';
import 'calendar_week_summary.dart';

enum CalendarPlanningActionType { reschedule, review, habit, plan }

enum CalendarPlanningSeverity { info, warning, critical }

final class CalendarPlanningSuggestion {
  const CalendarPlanningSuggestion({
    required this.title,
    required this.message,
    required this.actionType,
    required this.severity,
  });

  final String title;
  final String message;
  final CalendarPlanningActionType actionType;
  final CalendarPlanningSeverity severity;
}

List<CalendarPlanningSuggestion> buildCalendarPlanningSuggestions({
  required CalendarWeekSummary week,
  required DateTime today,
}) {
  final suggestions = <CalendarPlanningSuggestion>[];
  final tomorrow = today.add(const Duration(days: 1));
  CalendarDaySummary? tomorrowSummary;
  for (final day in week.days) {
    if (day.day.year == tomorrow.year &&
        day.day.month == tomorrow.month &&
        day.day.day == tomorrow.day) {
      tomorrowSummary = day;
      break;
    }
  }

  if (tomorrowSummary != null && tomorrowSummary.openTasks >= 6) {
    suggestions.add(
      const CalendarPlanningSuggestion(
        title: 'Overloaded tomorrow',
        message: 'Move low-priority work to a lighter day.',
        actionType: CalendarPlanningActionType.reschedule,
        severity: CalendarPlanningSeverity.warning,
      ),
    );
  }
  if (week.overdueTasks > 0) {
    suggestions.add(
      CalendarPlanningSuggestion(
        title: '${week.overdueTasks} overdue tasks need scheduling',
        message: 'Review overdue work before planning new missions.',
        actionType: CalendarPlanningActionType.reschedule,
        severity: CalendarPlanningSeverity.critical,
      ),
    );
  }
  if (week.reviewCount == 0) {
    suggestions.add(
      const CalendarPlanningSuggestion(
        title: 'No review this week',
        message: 'Add a weekly review to close loops.',
        actionType: CalendarPlanningActionType.review,
        severity: CalendarPlanningSeverity.info,
      ),
    );
  }
  CalendarDaySummary? clusterDay;
  for (final day in week.days) {
    if (day.highPriorityCount >= 3) {
      clusterDay = day;
      break;
    }
  }
  if (clusterDay != null) {
    suggestions.add(
      CalendarPlanningSuggestion(
        title:
            'High-priority cluster on ${_weekdayLabel(clusterDay.day.weekday)}',
        message: 'Spread priority work across the week to reduce context debt.',
        actionType: CalendarPlanningActionType.reschedule,
        severity: CalendarPlanningSeverity.warning,
      ),
    );
  }

  final emptyWeekend = week.days
      .where(_isWeekend)
      .every((day) => day.totalNodes == 0);
  if (emptyWeekend) {
    suggestions.add(
      const CalendarPlanningSuggestion(
        title: 'Empty weekend - plan reset?',
        message: 'Add a reset or review template before the week closes.',
        actionType: CalendarPlanningActionType.plan,
        severity: CalendarPlanningSeverity.info,
      ),
    );
  }

  final hasRiskyHabitDay = week.days.any(
    (day) => day.habitCount > 0 && day.completedHabits == 0,
  );
  if (hasRiskyHabitDay) {
    suggestions.add(
      const CalendarPlanningSuggestion(
        title: 'Habit streak at risk',
        message: 'Complete or reschedule today habit nodes.',
        actionType: CalendarPlanningActionType.habit,
        severity: CalendarPlanningSeverity.warning,
      ),
    );
  }
  return suggestions;
}

bool _isWeekend(CalendarDaySummary day) {
  return day.day.weekday == DateTime.saturday ||
      day.day.weekday == DateTime.sunday;
}

String _weekdayLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => 'day',
  };
}

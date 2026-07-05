/// Calendar heatmap scoring helpers.
library;

import 'dart:math' as math;

import 'calendar_day_summary.dart';

enum CalendarHeatmapMode {
  workload,
  completion,
  habits,
  focus,
  journaling,
  overdue,
}

String calendarHeatmapModeLabel(CalendarHeatmapMode mode) {
  return switch (mode) {
    CalendarHeatmapMode.workload => 'Workload',
    CalendarHeatmapMode.completion => 'Completion',
    CalendarHeatmapMode.habits => 'Habits',
    CalendarHeatmapMode.focus => 'Focus',
    CalendarHeatmapMode.journaling => 'Journaling',
    CalendarHeatmapMode.overdue => 'Overdue',
  };
}

final class CalendarHeatmapScore {
  const CalendarHeatmapScore({
    required this.mode,
    required this.value,
    required this.label,
  });

  final CalendarHeatmapMode mode;
  final double value;
  final String label;
}

CalendarHeatmapScore scoreCalendarDay(
  CalendarDaySummary summary,
  CalendarHeatmapMode mode,
) {
  final value = switch (mode) {
    CalendarHeatmapMode.workload => summary.openTasks / 8,
    CalendarHeatmapMode.completion =>
      summary.taskLikeTotal == 0
          ? 0
          : summary.completedTasks / summary.taskLikeTotal,
    CalendarHeatmapMode.habits =>
      summary.habitCount == 0
          ? 0
          : summary.completedHabits / summary.habitCount,
    CalendarHeatmapMode.focus => summary.focusMinutes / 240,
    CalendarHeatmapMode.journaling => summary.hasJournalOrReview ? 1 : 0,
    CalendarHeatmapMode.overdue => summary.overdueTasks / 5,
  };
  return CalendarHeatmapScore(
    mode: mode,
    value: math.max(0, math.min(1, value.toDouble())),
    label: _heatmapLabel(summary, mode),
  );
}

String _heatmapLabel(CalendarDaySummary summary, CalendarHeatmapMode mode) {
  return switch (mode) {
    CalendarHeatmapMode.workload => '${summary.openTasks} open tasks',
    CalendarHeatmapMode.completion =>
      '${summary.completedTasks}/${summary.taskLikeTotal} complete',
    CalendarHeatmapMode.habits =>
      '${summary.completedHabits}/${summary.habitCount} habits',
    CalendarHeatmapMode.focus => '${summary.focusMinutes} focus minutes',
    CalendarHeatmapMode.journaling =>
      summary.hasJournalOrReview ? 'journaled' : 'no journal',
    CalendarHeatmapMode.overdue => '${summary.overdueTasks} overdue',
  };
}

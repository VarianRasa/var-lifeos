import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/calendar_heatmap.dart';
import 'package:var_app/features/calendar/application/calendar_range_summary.dart';
import 'package:var_app/features/calendar/application/calendar_week_summary.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

MindmapNode task(String id, DateTime day, {bool done = false}) {
  return MindmapNode.create(
    id: id,
    type: NodeType.task,
    title: id,
    day: day,
    isDone: done,
    now: DateTime(2026),
  );
}

void main() {
  test('calendarWeekDays starts Monday', () {
    final days = calendarWeekDays(DateTime(2026, 7, 5));

    expect(days.first, DateTime(2026, 6, 29));
    expect(days.last, DateTime(2026, 7, 5));
  });

  test('buildCalendarWeekSummary totals week tasks', () {
    final summary = buildCalendarWeekSummary(
      selectedDay: DateTime(2026, 7, 2),
      nodes: [
        task('a', DateTime(2026, 7, 2)),
        task('b', DateTime(2026, 7, 3), done: true),
      ],
    );

    expect(summary.openTasks, 1);
    expect(summary.completedTasks, 1);
  });

  test('inclusiveCalendarDays includes both ends', () {
    expect(inclusiveCalendarDays(DateTime(2026, 7, 2), DateTime(2026, 7, 4)), [
      DateTime(2026, 7, 2),
      DateTime(2026, 7, 3),
      DateTime(2026, 7, 4),
    ]);
  });

  test('calendarHeatmapModeLabel is human readable', () {
    expect(
      calendarHeatmapModeLabel(CalendarHeatmapMode.journaling),
      'Journaling',
    );
  });

  test('scoreCalendarDay clamps workload', () {
    final range = buildCalendarRangeSummary(
      start: DateTime(2026, 7, 2),
      end: DateTime(2026, 7, 2),
      nodes: List.generate(
        20,
        (index) => task('t$index', DateTime(2026, 7, 2)),
      ),
    );

    final score = scoreCalendarDay(
      range.days.single,
      CalendarHeatmapMode.workload,
    );

    expect(score.value, 1);
  });
}

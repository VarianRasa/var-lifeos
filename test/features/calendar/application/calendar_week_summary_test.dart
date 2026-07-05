import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/calendar_week_summary.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

MindmapNode node({
  required String id,
  required DateTime day,
  bool isDone = false,
  DateTime? dueDate,
  Map<String, Object?> data = const {},
  NodeType type = NodeType.task,
}) {
  return MindmapNode.create(
    id: id,
    type: type,
    title: id,
    day: day,
    isDone: isDone,
    dueDate: dueDate,
    data: data,
    now: DateTime(2026),
  );
}

void main() {
  test('calendarWeekDays starts Monday and ends Sunday', () {
    final days = calendarWeekDays(DateTime(2026, 7, 3));

    expect(days.first, DateTime(2026, 6, 29));
    expect(days.last, DateTime(2026, 7, 5));
    expect(days, hasLength(7));
  });

  test('buildCalendarWeekSummary totals selected week only', () {
    final selected = DateTime(2026, 7, 3);
    final summary = buildCalendarWeekSummary(
      selectedDay: selected,
      nodes: [
        node(id: 'open', day: DateTime(2026, 7, 3)),
        node(id: 'done', day: DateTime(2026, 7, 4), isDone: true),
        node(
          id: 'late',
          day: DateTime(2026, 7, 5),
          dueDate: DateTime(2026, 7, 1),
        ),
        node(
          id: 'focus',
          day: DateTime(2026, 7, 5),
          data: const {'focusMinutes': 40},
        ),
        node(id: 'review', day: DateTime(2026, 7, 5), type: NodeType.journal),
        node(id: 'outside', day: DateTime(2026, 7, 6)),
      ],
    );

    expect(summary.startDay, DateTime(2026, 6, 29));
    expect(summary.endDay, DateTime(2026, 7, 5));
    expect(summary.openTasks, 3);
    expect(summary.completedTasks, 1);
    expect(summary.overdueTasks, 1);
    expect(summary.focusMinutes, 40);
    expect(summary.reviewCount, 1);
  });
}

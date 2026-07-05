import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/calendar_day_summary.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

MindmapNode node({
  required String id,
  required DateTime day,
  NodeType type = NodeType.task,
  bool isDone = false,
  NodePriority priority = NodePriority.none,
  DateTime? dueDate,
  Map<String, Object?> data = const {},
}) {
  return MindmapNode.create(
    id: id,
    type: type,
    title: id,
    day: day,
    isDone: isDone,
    priority: priority,
    dueDate: dueDate,
    data: data,
    now: DateTime(2026),
  );
}

void main() {
  test('buildCalendarDaySummary counts mission indicators', () {
    final day = DateTime(2026, 7, 2);
    final summary = buildCalendarDaySummary(day, [
      node(id: 'open', day: day),
      node(id: 'done', day: day, isDone: true),
      node(id: 'late', day: day, dueDate: DateTime(2026, 7, 1)),
      node(id: 'high', day: day, priority: NodePriority.high),
      node(id: 'habit', day: day, type: NodeType.habit, isDone: true),
      node(id: 'journal', day: day, type: NodeType.journal),
      node(id: 'focus', day: day, data: const {'focusMinutes': 25}),
    ]);

    expect(summary.totalNodes, 7);
    expect(summary.openTasks, 4);
    expect(summary.completedTasks, 2);
    expect(summary.overdueTasks, 1);
    expect(summary.highPriorityCount, 1);
    expect(summary.completedHabits, 1);
    expect(summary.focusMinutes, 25);
    expect(summary.hasJournalOrReview, isTrue);
    expect(summary.status, CalendarDayStatus.critical);
  });

  test('classifyCalendarDayStatus classifies complete', () {
    expect(
      classifyCalendarDayStatus(
        openTasks: 0,
        completedTasks: 2,
        overdueTasks: 0,
        highPriorityCount: 0,
      ),
      CalendarDayStatus.complete,
    );
  });
}

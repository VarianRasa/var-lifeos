import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/calendar_agenda_builder.dart';

import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_data.dart';

MindmapNode node({
  required String id,
  required DateTime day,
  NodeType type = NodeType.task,
  NodePriority priority = NodePriority.none,
  DateTime? dueDate,
  Map<String, Object?> data = const {},
}) {
  return MindmapNode.create(
    id: id,
    type: type,
    title: id,
    day: day,
    priority: priority,
    dueDate: dueDate,
    data: data,
    now: DateTime(2026),
  );
}

void main() {
  test('buildCalendarAgendaSections groups actionable nodes', () {
    final today = DateTime(2026, 7, 3);
    final sections = buildCalendarAgendaSections(
      today: today,
      nodes: [
        node(id: 'late', day: today, dueDate: DateTime(2026, 7, 1)),
        node(id: 'high', day: today, priority: NodePriority.high),
        node(
          id: 'scheduled',
          day: today,
          data: const {
            mindmapTimeBlockDataKey: {
              'timeBlockStart': 540,
              'timeBlockEnd': 600,
            },
          },
        ),
        node(id: 'habit', day: today, type: NodeType.habit),
        node(id: 'note', day: today, type: NodeType.note),
      ],
    );

    expect(
      sections.map((section) => section.kind),
      containsAllInOrder([
        CalendarAgendaSectionKind.overdue,
        CalendarAgendaSectionKind.priority,
        CalendarAgendaSectionKind.scheduled,
        CalendarAgendaSectionKind.habits,
        CalendarAgendaSectionKind.notes,
      ]),
    );
  });
}

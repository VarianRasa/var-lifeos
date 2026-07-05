import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/node_filtering.dart';
import 'package:var_app/features/calendar/domain/time_block.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_data.dart';

void main() {
  MindmapNode node({
    String id = 'n1',
    NodeType type = NodeType.task,
    String title = 'Task',
    DateTime? day,
    NodeStatus status = NodeStatus.open,
    NodePriority priority = NodePriority.none,
    String project = '',
    String area = '',
    List<String> tags = const [],
    DateTime? dueDate,
    bool done = false,
    Map<String, Object?> data = const {},
  }) {
    final baseDay = day ?? DateTime(2026, 7, 3);
    return MindmapNode.create(
      id: id,
      type: type,
      title: title,
      day: baseDay,
      status: status,
      priority: priority,
      project: project,
      area: area,
      tags: tags,
      dueDate: dueDate,
      isDone: done,
      data: data,
      now: baseDay,
    );
  }

  test('matches project area tag contains case-insensitive', () {
    final item = node(
      project: 'Var App',
      area: 'Product Lab',
      tags: const ['Ship'],
    );

    expect(
      matchesCalendarNodeFilter(
        item,
        const CalendarNodeFilter(project: 'var', area: 'lab', tag: 'ship'),
        today: DateTime(2026, 7, 3),
      ),
      isTrue,
    );
    expect(
      matchesCalendarNodeFilter(
        item,
        const CalendarNodeFilter(project: 'other'),
        today: DateTime(2026, 7, 3),
      ),
      isFalse,
    );
  });

  test('matches type status and priority', () {
    final item = node(
      type: NodeType.goal,
      status: NodeStatus.doing,
      priority: NodePriority.high,
    );

    expect(
      matchesCalendarNodeFilter(
        item,
        const CalendarNodeFilter(
          type: NodeType.goal,
          status: NodeStatus.doing,
          priority: NodePriority.high,
        ),
        today: DateTime(2026, 7, 3),
      ),
      isTrue,
    );
    expect(
      matchesCalendarNodeFilter(
        item,
        const CalendarNodeFilter(type: NodeType.note),
        today: DateTime(2026, 7, 3),
      ),
      isFalse,
    );
  });

  test('matches scheduled nodes from typed time block data', () {
    final scheduled = node(
      data: dataWithTimeBlock(
        const {},
        const TimeBlock(startMinute: 9 * 60, endMinute: 10 * 60),
      ),
    );

    expect(
      matchesCalendarNodeFilter(
        scheduled,
        const CalendarNodeFilter(hasSchedule: true),
        today: DateTime(2026, 7, 3),
      ),
      isTrue,
    );
    expect(
      matchesCalendarNodeFilter(
        scheduled,
        const CalendarNodeFilter(hasSchedule: false),
        today: DateTime(2026, 7, 3),
      ),
      isFalse,
    );
  });

  test('matches overdue open nodes only', () {
    final today = DateTime(2026, 7, 3);
    final overdue = node(dueDate: DateTime(2026, 7, 2));
    final doneOverdue = node(
      id: 'n2',
      dueDate: DateTime(2026, 7, 2),
      done: true,
    );

    expect(
      matchesCalendarNodeFilter(
        overdue,
        const CalendarNodeFilter(hasOverdue: true),
        today: today,
      ),
      isTrue,
    );
    expect(
      matchesCalendarNodeFilter(
        doneOverdue,
        const CalendarNodeFilter(hasOverdue: true),
        today: today,
      ),
      isFalse,
    );
  });
}

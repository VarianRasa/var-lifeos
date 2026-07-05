import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/calendar_day_summary.dart';
import 'package:var_app/features/calendar/application/calendar_markdown_export.dart';
import 'package:var_app/features/calendar/application/calendar_range_summary.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  MindmapNode node(
    String title, {
    required DateTime day,
    bool done = false,
    DateTime? dueDate,
  }) {
    return MindmapNode.create(
      id: title,
      type: NodeType.task,
      title: title,
      day: day,
      isDone: done,
      dueDate: dueDate,
      now: day,
    );
  }

  test('exports selected day with completed and open sections', () {
    final day = DateTime(2026, 7, 3);
    final nodes = [
      node('Done task', day: day, done: true),
      node('Open task', day: day),
    ];

    final markdown = exportCalendarDayMarkdown(
      summary: buildCalendarDaySummary(day, nodes),
      nodes: nodes,
    );

    expect(markdown, contains('# Friday, Jul 3, 2026'));
    expect(markdown, contains('- Completed tasks: 1'));
    expect(markdown, contains('## Completed tasks'));
    expect(markdown, contains('## Open tasks'));
  });

  test('exports selected range totals', () {
    final start = DateTime(2026, 7, 1);
    final nodes = [
      node('Open task', day: start),
      node('Done task', day: DateTime(2026, 7, 2), done: true),
    ];

    final markdown = exportCalendarRangeMarkdown(
      summary: buildCalendarRangeSummary(
        start: start,
        end: DateTime(2026, 7, 2),
        nodes: nodes,
      ),
      title: 'Selected range',
    );

    expect(markdown, contains('# Selected range'));
    expect(markdown, contains('- Total tasks: 2'));
    expect(markdown, contains('- Completed: 1'));
  });

  test('exports current month sections', () {
    final markdown = exportCalendarMonthMarkdown(
      month: DateTime(2026, 7),
      nodes: [
        node('July task', day: DateTime(2026, 7, 3)),
        node(
          'Due task',
          day: DateTime(2026, 7, 4),
          dueDate: DateTime(2026, 7, 2),
        ),
        node('Other month', day: DateTime(2026, 8, 1)),
      ],
    );

    expect(markdown, contains('# July 2026'));
    expect(markdown, contains('- Total tasks: 2'));
    expect(markdown, contains('## Overdue tasks'));
    expect(markdown, contains('Due task'));
    expect(markdown, isNot(contains('Other month')));
  });
}

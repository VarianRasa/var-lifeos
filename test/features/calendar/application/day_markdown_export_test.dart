import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/day_markdown_export.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  MindmapNode node(
    String id, {
    required NodeType type,
    required DateTime day,
    bool done = false,
    String body = '',
    NodePriority priority = NodePriority.none,
    List<String> tags = const [],
  }) {
    return MindmapNode.create(
      id: id,
      type: type,
      title: id,
      day: day,
      isDone: done,
      body: body,
      priority: priority,
      tags: tags,
      now: day,
    );
  }

  test('buildDayMarkdownExport includes day summary sections', () {
    final day = DateTime(2026, 7, 2);
    final markdown = buildDayMarkdownExport(
      day: day,
      nodes: [
        node('Done task', type: NodeType.task, day: day, done: true),
        node(
          'Open task',
          type: NodeType.task,
          day: day,
          priority: NodePriority.high,
          tags: const ['ship'],
        ),
        node('Journal', type: NodeType.journal, day: day, body: 'Won the day'),
        node('Decision', type: NodeType.decision, day: day),
        node('Resource', type: NodeType.resource, day: day),
        node('Other day', type: NodeType.task, day: DateTime(2026, 7, 3)),
      ],
    );

    expect(markdown, contains('# Day summary — 2026-07-02'));
    expect(markdown, contains('- Total nodes: 5'));
    expect(markdown, contains('- [x] Done task'));
    expect(markdown, contains('- [ ] Open task (High · #ship)'));
    expect(markdown, contains('## Notes / journal'));
    expect(markdown, contains('  > Won the day'));
    expect(markdown, contains('## Decisions'));
    expect(markdown, contains('## Tomorrow carry-over'));
    expect(markdown, isNot(contains('Other day')));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/daily_review_builder.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('dailyReviewTitle includes day key', () {
    expect(dailyReviewTitle(DateTime(2026, 7, 2)), 'Daily review — 2026-07-02');
  });

  test('extractTomorrowTop3 returns up to three bullet items', () {
    final items = extractTomorrowTop3('''
## Wins
- shipped

## Tomorrow top 3
- Write docs
- Fix bug
- Plan launch
- Extra item

## Notes
- ignored
''');

    expect(items, ['Write docs', 'Fix bug', 'Plan launch']);
  });

  test(
    'buildDailyReviewBody summarizes completed, blocked, and open tasks, ignoring next status',
    () {
      final day = DateTime(2026, 7, 2);
      final body = buildDailyReviewBody(day, [
        MindmapNode.create(
          id: 'done',
          type: NodeType.task,
          title: 'Ship feature',
          day: day,
          isDone: true,
          status: NodeStatus.done,
        ),
        MindmapNode.create(
          id: 'blocked',
          type: NodeType.task,
          title: 'Wait for API',
          day: day,
          status: NodeStatus.waiting,
        ),
        MindmapNode.create(
          id: 'open',
          type: NodeType.task,
          title: 'Write docs',
          day: day,
        ),
        MindmapNode.create(
          id: 'next',
          type: NodeType.task,
          title: 'Triaged for future',
          day: day,
          status: NodeStatus.next,
        ),
      ]);

      expect(body, contains('# Daily review — 2026-07-02'));
      expect(body, contains('## Wins'));
      expect(body, contains('- Ship feature'));
      expect(body, contains('- Wait for API'));
      expect(body, contains('- Write docs'));
      expect(body, isNot(contains('- Triaged for future')));
      expect(body, contains('## Tomorrow top 3'));
    },
  );
}

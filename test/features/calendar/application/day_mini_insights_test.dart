import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/day_mini_insights.dart';
import 'package:var_app/features/calendar/application/focus_session.dart';
import 'package:var_app/features/mindmap/domain/habit_completion.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  MindmapNode node(
    String id, {
    required NodeType type,
    required DateTime day,
    bool done = false,
    Map<String, Object?> data = const {},
    List<String> tags = const [],
  }) {
    return MindmapNode.create(
      id: id,
      type: type,
      title: id,
      day: day,
      isDone: done,
      tags: tags,
      data: data,
      now: day,
    );
  }

  test('buildDayMiniInsights summarizes tasks habits focus and review', () {
    final day = DateTime(2026, 7, 2);
    final focusRecord = FocusSessionRecord(
      startedAt: DateTime(2026, 7, 2, 9),
      endedAt: DateTime(2026, 7, 2, 9, 25),
      durationMinutes: 25,
    );
    final insights = buildDayMiniInsights(
      selectedDay: day,
      nodes: [
        node('done', type: NodeType.task, day: day, done: true),
        node('open', type: NodeType.task, day: day),
        logHabitCompletion(node('habit', type: NodeType.habit, day: day), day),
        node(
          'focus',
          type: NodeType.note,
          day: day,
          data: {
            focusSessionsDataKey: [focusRecord.toJson()],
          },
        ),
        node(
          'review',
          type: NodeType.journal,
          day: day,
          tags: const ['daily-review'],
        ),
      ],
    );

    final today = insights.last;
    expect(today.day, day);
    expect(today.totalTasks, 2);
    expect(today.completedTasks, 1);
    expect(today.totalHabits, 1);
    expect(today.completedHabits, 1);
    expect(today.focusMinutes, 25);
    expect(today.hasReview, isTrue);
    expect(today.score, greaterThan(0));
  });

  test('buildDayMiniInsights returns selected 7 day window', () {
    final day = DateTime(2026, 7, 7);
    final insights = buildDayMiniInsights(selectedDay: day, nodes: const []);

    expect(insights, hasLength(7));
    expect(insights.first.day, DateTime(2026, 7, 1));
    expect(insights.last.day, day);
  });
}

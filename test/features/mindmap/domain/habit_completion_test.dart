import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/habit_completion.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('logHabitCompletion adds a unique normalized completion day', () {
    final node = MindmapNode.create(
      id: 'habit-workout',
      type: NodeType.habit,
      title: 'Workout',
      day: DateTime(2026, 6, 19),
      data: const {
        'habit': {
          'recurrence': 'daily',
          'target': '30 min',
          'completions': ['2026-06-18'],
        },
      },
      now: DateTime(2026, 6, 19, 8),
    );

    final logged = logHabitCompletion(
      node,
      DateTime(2026, 6, 19, 14),
      now: DateTime(2026, 6, 19, 15),
    );
    final loggedAgain = logHabitCompletion(
      logged,
      DateTime(2026, 6, 19, 20),
      now: DateTime(2026, 6, 19, 21),
    );

    expect(habitCompletionKeys(loggedAgain), ['2026-06-18', '2026-06-19']);
    expect(hasHabitCompletionOn(loggedAgain, DateTime(2026, 6, 19)), isTrue);
    expect(loggedAgain.updatedAt, DateTime(2026, 6, 19, 15));
    expect(
      (loggedAgain.data['habit']! as Map<String, Object?>)['recurrence'],
      'daily',
    );
    expect(
      (loggedAgain.data['habit']! as Map<String, Object?>)['target'],
      '30 min',
    );
  });
}

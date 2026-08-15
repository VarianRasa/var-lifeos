import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/habit_completion.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('Habit Streak Stats Engine', () {
    final today = DateTime(2026, 8, 7);

    test('calculates correct 30-day completion rate and streak stats', () {
      final habitNode = MindmapNode.create(
        id: 'habit-1',
        type: NodeType.habit,
        title: 'Daily Meditation',
        day: today,
        data: {
          'habit': {
            'completions': ['2026-08-07', '2026-08-06', '2026-08-05'],
          },
        },
      );

      final stats = calculateHabitStreakStats(habitNode, today);
      expect(stats.currentStreak, equals(3));
      expect(stats.totalCompletions, equals(3));
      expect(stats.completionRate30Days, closeTo(3 / 30.0, 0.001));
    });
  });
}

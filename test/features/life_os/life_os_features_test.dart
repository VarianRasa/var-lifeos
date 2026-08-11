import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/calendar/application/energy_task_scheduler.dart';
import 'package:var_app/features/life_os/domain/user_gamification.dart';
import 'package:var_app/features/mindmap/domain/habit_completion.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/spaced_repetition.dart';

void main() {
  group('SpacedRepetition SM-2 Engine', () {
    test('initial state defaults to EF 2.5 and interval 1 day', () {
      final item = SpacedRepetitionItem.initial();
      expect(item.easeFactor, equals(2.5));
      expect(item.intervalDays, equals(1));
      expect(item.repetitions, equals(0));
    });

    test('answering perfect rating (5) increases interval and EF', () {
      final item = SpacedRepetitionItem.initial();
      final next = item.answer(
        FlashcardRating.perfect,
        now: DateTime(2026, 8, 7),
      );
      expect(next.repetitions, equals(1));
      expect(next.intervalDays, equals(1));
      expect(next.easeFactor, greaterThan(2.5));
    });

    test('answering blackout rating (0) resets repetitions and interval', () {
      final item = SpacedRepetitionItem.initial().answer(
        FlashcardRating.perfect,
      );
      final blackout = item.answer(FlashcardRating.blackout);
      expect(blackout.repetitions, equals(0));
      expect(blackout.intervalDays, equals(1));
    });
  });

  group('UserGamification Domain', () {
    test('XP calculation levels up correctly', () {
      var stats = UserGamificationStats.initial();
      expect(stats.level, equals(1));

      // Level formula: floor(sqrt(XP / 50)) + 1
      // Level 2 requires 50 XP
      stats = stats.addXp(50);
      expect(stats.level, equals(2));
    });

    test('unlocks badges when thresholds met', () {
      var stats = UserGamificationStats.initial();
      stats = stats.recordTaskCompletion();
      expect(stats.unlockedBadgeIds, contains(LifeOsBadge.firstStep.id));
    });
  });

  group('Habit Stacking & Streak Freeze', () {
    test('streak freeze protects current streak across missed day', () {
      final today = DateTime.now().dateOnly;
      final twoDaysAgo = today.subtract(const Duration(days: 2));
      final yesterday = today.subtract(const Duration(days: 1));

      final now = DateTime.now();
      var node = MindmapNode(
        id: 'h1',
        day: today,
        type: NodeType.habit,
        title: 'Exercise',
        createdAt: now,
        updatedAt: now,
      );

      // Log completion 2 days ago
      node = logHabitCompletion(node, twoDaysAgo);
      // Freeze yesterday
      node = applyStreakFreeze(node, yesterday);

      // Streak should bridge over yesterday freeze (2 days total streak)
      expect(calculateCurrentStreak(node), equals(2));
    });

    test('habit stacking trigger getter and setter', () {
      final now = DateTime.now();
      var node = MindmapNode(
        id: 'h2',
        day: now,
        type: NodeType.habit,
        title: 'Meditate',
        createdAt: now,
        updatedAt: now,
      );

      node = setHabitStackingTrigger(node, 'h1');
      expect(getHabitStackingTriggerId(node), equals('h1'));

      node = setHabitStackingTrigger(node, null);
      expect(getHabitStackingTriggerId(node), isNull);
    });
  });

  group('Auto Time-Block Solver', () {
    test('assigns non-overlapping time blocks for unallocated tasks', () {
      final now = DateTime.now();
      final day = now.dateOnly;
      final tasks = <MindmapNode>[
        MindmapNode(
          id: 't1',
          day: day,
          type: NodeType.task,
          title: 'Write Report',
          priority: NodePriority.urgent,
          createdAt: now,
          updatedAt: now,
        ),
        MindmapNode(
          id: 't2',
          day: day,
          type: NodeType.task,
          title: 'Clean Email',
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final assignments = autoTimeBlockDay(dayNodes: tasks);
      expect(assignments.length, equals(2));
      expect(assignments.containsKey('t1'), isTrue);
      expect(assignments.containsKey('t2'), isTrue);

      final block1 = assignments['t1']!;
      final block2 = assignments['t2']!;
      // Should not overlap
      final overlap =
          block1.startMinute < block2.endMinute &&
          block2.startMinute < block1.endMinute;
      expect(overlap, isFalse);
    });
  });
}

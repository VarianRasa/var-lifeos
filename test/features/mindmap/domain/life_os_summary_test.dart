import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/life_os_summary.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('LifeOsSummary calculates habit, journal, and goal signals', () {
    final today = DateTime(2026, 6, 18);
    final nodes = [
      MindmapNode.create(
        id: 'habit-1',
        type: NodeType.habit,
        title: 'Workout',
        day: today,
        data: const {
          'habit': {
            'recurrence': 'daily',
            'target': '30 min',
            'completions': ['2026-06-16', '2026-06-17', '2026-06-18'],
          },
        },
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'goal-1',
        type: NodeType.goal,
        title: 'Launch v1',
        day: today,
        data: const {
          'goal': {
            'milestones': ['Prototype', 'Beta'],
            'completedMilestones': ['Prototype'],
          },
        },
        now: DateTime(2026, 6, 18, 9),
      ),
      MindmapNode.create(
        id: 'journal-1',
        type: NodeType.journal,
        title: 'Daily journal',
        day: today,
        data: const {
          'journal': {
            'mood': 4,
            'energy': 3,
            'gratitude': ['Focus time'],
            'isWeeklyReview': true,
          },
        },
        now: DateTime(2026, 6, 18, 10),
      ),
    ];

    final summary = LifeOsSummary.fromNodes(today: today, nodes: nodes);

    expect(summary.habitCount, 1);
    expect(summary.bestHabitStreak, 3);
    expect(summary.goalCount, 1);
    expect(summary.averageGoalProgress, 0.5);
    expect(summary.journalCount, 1);
    expect(summary.averageMood, 4);
    expect(summary.averageEnergy, 3);
    expect(summary.weeklyReviewCount, 1);
  });

  test('LifeOsAttention surfaces actionable Life OS signals', () {
    final today = DateTime(2026, 6, 18);
    final nodes = [
      MindmapNode.create(
        id: 'overdue-task',
        type: NodeType.task,
        title: 'Pay invoice',
        day: today.subtract(const Duration(days: 3)),
        status: NodeStatus.doing,
        dueDate: today.subtract(const Duration(days: 1)),
        now: DateTime(2026, 6, 14, 8),
      ),
      MindmapNode.create(
        id: 'habit',
        type: NodeType.habit,
        title: 'Workout',
        day: today,
        data: const {
          'habit': {
            'recurrence': 'daily',
            'completions': ['2026-06-17'],
          },
        },
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'goal',
        type: NodeType.goal,
        title: 'Launch v1',
        day: today.subtract(const Duration(days: 20)),
        data: const {
          'goal': {
            'milestones': ['Prototype', 'Beta'],
            'completedMilestones': <String>[],
          },
        },
        now: DateTime(2026, 5, 25, 8),
      ),
      MindmapNode.create(
        id: 'journal',
        type: NodeType.journal,
        title: 'Daily journal',
        day: today,
        data: const {
          'journal': {'mood': 0, 'energy': 3},
        },
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'done-overdue-task',
        type: NodeType.task,
        title: 'Closed invoice',
        day: today.subtract(const Duration(days: 2)),
        status: NodeStatus.done,
        dueDate: today.subtract(const Duration(days: 1)),
        now: DateTime(2026, 6, 18, 8),
      ),
    ];

    final attention = LifeOsAttention.fromNodes(today: today, nodes: nodes);

    expect(attention.signals.map((signal) => signal.nodeId), [
      'overdue-task',
      'habit',
      'goal',
      'journal',
    ]);
    expect(attention.criticalCount, 1);
    expect(attention.warningCount, 2);
    expect(attention.infoCount, 1);
    expect(attention.signals.first.type, LifeOsAttentionType.overdueTask);
    expect(attention.signals.first.message, 'Overdue since 2026-06-17');
    expect(
      attention.signals.map((signal) => signal.actionLabel),
      containsAll(['Review task', 'Log habit', 'Update goal', 'Complete log']),
    );
  });

  test(
    'LifeOsRhythm calculates weekly journal, habit, and review coverage',
    () {
      final today = DateTime(2026, 6, 18);
      final nodes = [
        MindmapNode.create(
          id: 'habit-1',
          type: NodeType.habit,
          title: 'Workout',
          day: today,
          data: const {
            'habit': {
              'completions': ['2026-06-14', '2026-06-16', '2026-06-18'],
            },
          },
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'habit-2',
          type: NodeType.habit,
          title: 'Read',
          day: today,
          data: const {
            'habit': {
              'completions': ['2026-06-17'],
            },
          },
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'journal-1',
          type: NodeType.journal,
          title: 'Journal one',
          day: DateTime(2026, 6, 16),
          now: DateTime(2026, 6, 16, 8),
        ),
        MindmapNode.create(
          id: 'journal-2',
          type: NodeType.journal,
          title: 'Journal two',
          day: DateTime(2026, 6, 17),
          data: const {
            'journal': {'isWeeklyReview': true},
          },
          now: DateTime(2026, 6, 17, 8),
        ),
        MindmapNode.create(
          id: 'journal-3',
          type: NodeType.journal,
          title: 'Journal three',
          day: today,
          now: DateTime(2026, 6, 18, 8),
        ),
      ];

      final rhythm = LifeOsRhythm.fromNodes(today: today, nodes: nodes);

      expect(rhythm.windowDayCount, 7);
      expect(rhythm.journalDayCount, 3);
      expect(rhythm.habitCompletionDayCount, 4);
      expect(rhythm.hasWeeklyReviewThisWeek, isTrue);
      expect(rhythm.journalCoverage, closeTo(3 / 7, 0.001));
      expect(rhythm.habitCoverage, closeTo(4 / 7, 0.001));
      expect(rhythm.rhythmScore, closeTo(2 / 3, 0.001));
      expect(rhythm.scoreLabel, '67% rhythm');
    },
  );
}

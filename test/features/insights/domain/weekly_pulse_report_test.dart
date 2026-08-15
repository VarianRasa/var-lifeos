import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/insights/domain/weekly_pulse_report.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('LifeOsWeeklyPulseReport', () {
    final start = DateTime(2026, 8, 1);
    final end = DateTime(2026, 8, 7);

    test('generates markdown report with aggregated weekly stats', () {
      final task1 = MindmapNode.create(
        id: 't1',
        type: NodeType.task,
        title: 'Task 1',
        isDone: true,
        status: NodeStatus.done,
        day: start,
        now: start,
      );

      final habit1 = MindmapNode.create(
        id: 'h1',
        type: NodeType.habit,
        title: 'Habit 1',
        day: start,
      );

      final goal1 = MindmapNode.create(
        id: 'g1',
        type: NodeType.goal,
        title: 'Goal 1',
        day: start,
      );

      final report = LifeOsWeeklyPulseReport.generate(
        start: start,
        end: end,
        nodes: [task1, habit1, goal1],
        winsText: 'Completed feature X',
        lessonsText: 'Focus on small iterations',
        nextFocusText: 'Ship release v1',
        moodRating: 4.5,
      );

      expect(report.completedTasksCount, equals(1));
      expect(report.habitsKeptCount, equals(1));
      expect(report.activeGoalsCount, equals(1));
      expect(report.averageMoodScore, equals(4.5));
      expect(report.markdownSummary, contains('Life OS Weekly Pulse Report'));
      expect(report.markdownSummary, contains('Completed feature X'));
    });
  });
}

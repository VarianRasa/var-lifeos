import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/carry_over_planner.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('buildCarryOverCandidates', () {
    test('detects unfinished task-like nodes before selected day', () {
      final selectedDay = DateTime(2026, 7, 2);
      final yesterday = DateTime(2026, 7, 1);
      final oldDay = DateTime(2026, 6, 30);
      final nodes = [
        MindmapNode.create(
          id: 'task-open',
          type: NodeType.task,
          title: 'Open task',
          day: yesterday,
          priority: NodePriority.high,
        ),
        MindmapNode.create(
          id: 'plan-open',
          type: NodeType.plan,
          title: 'Open plan',
          day: oldDay,
          data: {
            'plan': {
              'steps': ['Draft', 'Ship'],
              'completedSteps': ['Draft'],
            },
          },
        ),
        MindmapNode.create(
          id: 'habit-missed',
          type: NodeType.habit,
          title: 'Workout',
          day: yesterday,
        ),
        MindmapNode.create(
          id: 'routine-open',
          type: NodeType.routine,
          title: 'Morning routine',
          day: oldDay,
        ),
      ];

      final candidates = buildCarryOverCandidates(
        nodes: nodes,
        selectedDay: selectedDay,
      );

      expect(candidates.map((candidate) => candidate.node.id), [
        'task-open',
        'habit-missed',
        'plan-open',
        'routine-open',
      ]);
      expect(candidates.first.reason, CarryOverReason.unfinishedTask);
    });

    test('ignores complete, archived, and same-day nodes', () {
      final selectedDay = DateTime(2026, 7, 2);
      final yesterday = DateTime(2026, 7, 1);
      final nodes = [
        MindmapNode.create(
          id: 'done-task',
          type: NodeType.task,
          title: 'Done task',
          day: yesterday,
          status: NodeStatus.done,
          isDone: true,
        ),
        MindmapNode.create(
          id: 'archived-task',
          type: NodeType.task,
          title: 'Archived task',
          day: yesterday,
          isArchived: true,
        ),
        MindmapNode.create(
          id: 'today-task',
          type: NodeType.task,
          title: 'Today task',
          day: selectedDay,
        ),
        MindmapNode.create(
          id: 'done-plan',
          type: NodeType.plan,
          title: 'Done plan',
          day: yesterday,
          progress: 1,
        ),
      ];

      final candidates = buildCarryOverCandidates(
        nodes: nodes,
        selectedDay: selectedDay,
      );

      expect(candidates, isEmpty);
    });

    test('orders urgent candidates before newer low-priority items', () {
      final selectedDay = DateTime(2026, 7, 2);
      final nodes = [
        MindmapNode.create(
          id: 'low-newer',
          type: NodeType.task,
          title: 'Low newer',
          day: DateTime(2026, 7, 1),
          priority: NodePriority.low,
        ),
        MindmapNode.create(
          id: 'urgent-older',
          type: NodeType.task,
          title: 'Urgent older',
          day: DateTime(2026, 6, 29),
          priority: NodePriority.urgent,
        ),
      ];

      final candidates = buildCarryOverCandidates(
        nodes: nodes,
        selectedDay: selectedDay,
      );

      expect(candidates.map((candidate) => candidate.node.id), [
        'urgent-older',
        'low-newer',
      ]);
    });

    test('does not carry completed habit', () {
      final selectedDay = DateTime(2026, 7, 2);
      final yesterday = DateTime(2026, 7, 1);
      final node = MindmapNode.create(
        id: 'habit-done',
        type: NodeType.habit,
        title: 'Read',
        day: yesterday,
        data: {
          'habit': {
            'completions': ['2026-07-01'],
          },
        },
      );

      final candidates = buildCarryOverCandidates(
        nodes: [node],
        selectedDay: selectedDay,
      );

      expect(candidates, isEmpty);
    });
  });
}

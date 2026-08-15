import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/para_okr_rollup.dart';

void main() {
  group('ParaOkrRollupSummary', () {
    test(
      'computes correct top-down progress rollups from goal to project to task',
      () {
        final now = DateTime(2026, 8, 7);
        final goal = MindmapNode.create(
          id: 'goal-1',
          type: NodeType.goal,
          title: 'Launch App v1',
          day: now,
        );

        final project = MindmapNode.create(
          id: 'proj-1',
          type: NodeType.plan,
          title: 'Engine Refactor',
          project: 'Launch App v1',
          day: now,
        );

        final task1 = MindmapNode.create(
          id: 'task-1',
          type: NodeType.task,
          title: 'Write Unit Tests',
          project: 'Engine Refactor',
          progress: 1.0,
          day: now,
        );

        final task2 = MindmapNode.create(
          id: 'task-2',
          type: NodeType.task,
          title: 'Fix UI Bugs',
          project: 'Engine Refactor',
          progress: 0.0,
          day: now,
        );

        final summary = ParaOkrRollupSummary.fromNodes([
          goal,
          project,
          task1,
          task2,
        ]);

        expect(summary.goals.length, equals(1));
        final goalRollup = summary.goals.first;
        expect(goalRollup.title, equals('Launch App v1'));
        expect(goalRollup.children.length, equals(1));

        final projRollup = goalRollup.children.first;
        expect(projRollup.title, equals('Engine Refactor'));
        expect(projRollup.children.length, equals(2));
        expect(projRollup.rollupProgress, equals(0.5));
        expect(goalRollup.rollupProgress, equals(0.5));
      },
    );
  });
}

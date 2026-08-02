import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_integrator.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('MindmapIntegrator - Domain Rules Integration', () {
    const integrator = MindmapIntegrator();
    final goalDay = DateTime(2026, 7, 22);

    test(
      'Penyelesaian Task terafiliasi memperbarui Progress Goal secara otomatis',
      () {
        final goalNode = MindmapNode.create(
          id: 'goal-1',
          type: NodeType.goal,
          title: 'Membaca Buku',
          day: goalDay,
          data: {
            'goal': {
              'milestones': ['Bab 1', 'Bab 2'],
              'completedMilestones': <String>[],
            },
          },
        );

        final task1Node = MindmapNode.create(
          id: 'task-1',
          type: NodeType.task,
          title: 'Bab 1',
          day: goalDay,
          isDone: true,
          status: NodeStatus.done,
          relatedNodeIds: ['goal-1'],
        );

        final task2Node = MindmapNode.create(
          id: 'task-2',
          type: NodeType.task,
          title: 'Bab 2',
          day: goalDay,
          isDone: false,
          status: NodeStatus.open,
          relatedNodeIds: ['goal-1'],
        );

        final sideEffects = integrator.integrateMutations(
          mutatedNode: task1Node,
          allNodes: [goalNode, task1Node, task2Node],
        );

        expect(sideEffects, hasLength(1));
        final updatedGoal = sideEffects.first;
        expect(updatedGoal.progress, equals(0.5));
        final goalData = updatedGoal.data['goal'] as Map<String, Object?>?;
        final completedMilestones = goalData?['completedMilestones'] as List?;
        expect(completedMilestones, contains('Bab 1'));
      },
    );
  });
}

/// Domain integrator rule engine connecting Goals, Tasks, Habits, and Routines automatically.
library;

import '../../../core/constants/app_constants.dart';
import 'goal_progress.dart';
import 'habit_completion.dart';
import 'mindmap_node.dart';

class MindmapIntegrator {
  const MindmapIntegrator();

  /// Calculates side-effect mutations for related nodes upon node mutation.
  List<MindmapNode> integrateMutations({
    required MindmapNode mutatedNode,
    required List<MindmapNode> allNodes,
  }) {
    final updatedNodes = <MindmapNode>[];

    // Case 1: Task updated -> Recalculate Goal Progress & Milestones for linked Goals
    if (mutatedNode.type == NodeType.task) {
      for (final goalId in mutatedNode.relatedNodeIds) {
        final goalNode = allNodes.firstWhere(
          (n) => n.id == goalId && n.type == NodeType.goal,
          orElse: () => mutatedNode,
        );
        if (goalNode.id == goalId) {
          final updatedGoal = _updateGoalProgress(
            goalNode,
            allNodes,
            mutatedNode,
          );
          updatedNodes.add(updatedGoal);
        }
      }
    }

    // Case 2: Daily Habit from Routine completed -> Record completion in main Habit node
    if (mutatedNode.type == NodeType.habit &&
        (mutatedNode.isDone || mutatedNode.status == NodeStatus.done)) {
      final automation = mutatedNode.data['automation'];
      if (automation is Map && automation['routineId'] != null) {
        final parentHabitId = automation['routineId'] as String;
        final parentHabit = allNodes.firstWhere(
          (n) => n.id == parentHabitId && n.type == NodeType.habit,
          orElse: () => mutatedNode,
        );
        if (parentHabit.id == parentHabitId) {
          final updatedHabit = logHabitCompletion(parentHabit, mutatedNode.day);
          updatedNodes.add(updatedHabit);
        }
      }
    }

    return updatedNodes;
  }

  MindmapNode _updateGoalProgress(
    MindmapNode goalNode,
    List<MindmapNode> allNodes,
    MindmapNode triggeringTask,
  ) {
    final linkedTasks = allNodes.where((n) {
      if (n.id == triggeringTask.id) return true;
      return n.type == NodeType.task && n.relatedNodeIds.contains(goalNode.id);
    }).toList();

    final idx = linkedTasks.indexWhere((t) => t.id == triggeringTask.id);
    if (idx != -1) {
      linkedTasks[idx] = triggeringTask;
    } else {
      linkedTasks.add(triggeringTask);
    }

    final totalTasks = linkedTasks.length;
    if (totalTasks == 0) return goalNode;

    final completedTasks = linkedTasks
        .where((t) => t.isDone || t.status == NodeStatus.done)
        .length;
    final progress = completedTasks / totalTasks;

    final milestones = goalMilestones(goalNode);
    final completedMilestones = <String>[];
    for (final milestone in milestones) {
      final taskForMilestone = linkedTasks.firstWhere(
        (t) => t.title.trim().toLowerCase() == milestone.trim().toLowerCase(),
        orElse: () => triggeringTask,
      );
      if (taskForMilestone.id != triggeringTask.id &&
          (taskForMilestone.isDone ||
              taskForMilestone.status == NodeStatus.done)) {
        completedMilestones.add(milestone);
      } else if (taskForMilestone.id == triggeringTask.id &&
          (triggeringTask.isDone || triggeringTask.status == NodeStatus.done)) {
        completedMilestones.add(milestone);
      }
    }

    final goalData = goalNode.data['goal'] as Map<String, Object?>? ?? const {};
    return goalNode.copyWith(
      progress: progress,
      data: {
        ...goalNode.data,
        'goal': {...goalData, 'completedMilestones': completedMilestones},
      },
      updatedAt: DateTime.now(),
    );
  }
}

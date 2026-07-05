import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/workspace_context.dart';

final class WorkspaceGoalItem {
  const WorkspaceGoalItem({
    required this.node,
    required this.progress,
    required this.relatedCount,
    required this.milestones,
    required this.missingNextAction,
    required this.stalled,
  });

  final MindmapNode node;
  final double progress;
  final int relatedCount;
  final List<String> milestones;
  final bool missingNextAction;
  final bool stalled;
}

final class WorkspaceGoalSummary {
  const WorkspaceGoalSummary({required this.goals});

  final List<WorkspaceGoalItem> goals;

  int get stalledCount => goals.where((goal) => goal.stalled).length;
  int get missingNextActionCount =>
      goals.where((goal) => goal.missingNextAction).length;
}

WorkspaceGoalSummary buildWorkspaceGoalSummary(
  WorkspaceContext workspace,
  DateTime today,
) {
  final openTasks = workspace.activeNodes.where(
    (node) =>
        node.type == NodeType.task &&
        !node.isDone &&
        node.status != NodeStatus.done,
  );
  final goals = workspace.activeNodes
      .where((node) => node.type == NodeType.goal)
      .map((node) {
        final related = workspace.activeNodes.where(
          (other) =>
              other.id != node.id &&
              (node.relatedNodeIds.contains(other.id) ||
                  other.relatedNodeIds.contains(node.id)),
        );
        final hasTask = openTasks.any(
          (task) =>
              node.relatedNodeIds.contains(task.id) ||
              task.relatedNodeIds.contains(node.id),
        );
        return WorkspaceGoalItem(
          node: node,
          progress: node.progress,
          relatedCount: related.length,
          milestones: _milestones(node),
          missingNextAction: !hasTask,
          stalled:
              today.dateOnly.difference(node.updatedAt.dateOnly).inDays >= 14 &&
              node.progress < 1,
        );
      })
      .toList(growable: false);
  return WorkspaceGoalSummary(goals: goals);
}

List<String> _milestones(MindmapNode node) {
  final raw = node.data['milestones'];
  if (raw is List<Object?>) {
    return raw
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

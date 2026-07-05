import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/workspace_context.dart';
import 'workspace_overview.dart';

enum WorkspaceNextActionSeverity { info, warning, critical }

enum WorkspaceNextActionType {
  overdueTask,
  highPriorityTask,
  waitingOrBlockedTask,
  staleTask,
  goalWithoutTask,
  notesWithoutTask,
  staleProject,
}

final class WorkspaceNextAction {
  const WorkspaceNextAction({
    required this.type,
    required this.severity,
    required this.title,
    required this.reason,
    this.node,
  });

  final WorkspaceNextActionType type;
  final WorkspaceNextActionSeverity severity;
  final String title;
  final String reason;
  final MindmapNode? node;
}

List<WorkspaceNextAction> buildWorkspaceNextActions(
  WorkspaceContext workspace,
  DateTime today, {
  int limit = 6,
}) {
  final actions = <WorkspaceNextAction>[];
  final open = workspace.activeNodes
      .where((node) => !node.isDone && node.status != NodeStatus.done)
      .toList(growable: false);
  open.sort((a, b) => b.priority.index.compareTo(a.priority.index));

  for (final node in open) {
    final dueDate = node.dueDate;
    if (dueDate != null && dueDate.dateOnly.isBefore(today.dateOnly)) {
      actions.add(
        WorkspaceNextAction(
          type: WorkspaceNextActionType.overdueTask,
          severity: WorkspaceNextActionSeverity.critical,
          title: 'Schedule overdue task',
          reason: node.title,
          node: node,
        ),
      );
      break;
    }
  }
  final high = open.where(
    (node) => node.priority.index >= NodePriority.high.index,
  );
  if (high.isNotEmpty) {
    final node = high.first;
    actions.add(
      WorkspaceNextAction(
        type: WorkspaceNextActionType.highPriorityTask,
        severity: WorkspaceNextActionSeverity.warning,
        title: 'Pick high-priority task',
        reason: node.title,
        node: node,
      ),
    );
  }
  final waiting = open.where(_isWaitingOrBlocked);
  if (waiting.isNotEmpty) {
    final node = waiting.first;
    actions.add(
      WorkspaceNextAction(
        type: WorkspaceNextActionType.waitingOrBlockedTask,
        severity: WorkspaceNextActionSeverity.warning,
        title: 'Unblock waiting work',
        reason: node.title,
        node: node,
      ),
    );
  }
  final stale = open.where(
    (node) => today.dateOnly.difference(node.updatedAt.dateOnly).inDays >= 14,
  );
  if (stale.isNotEmpty) {
    final node = stale.first;
    actions.add(
      WorkspaceNextAction(
        type: WorkspaceNextActionType.staleTask,
        severity: WorkspaceNextActionSeverity.info,
        title: 'Review stale task',
        reason: node.title,
        node: node,
      ),
    );
  }
  final hasGoal = workspace.activeNodes.any(
    (node) => node.type == NodeType.goal,
  );
  final hasTask = open.any((node) => node.type == NodeType.task);
  if (hasGoal && !hasTask) {
    actions.add(
      const WorkspaceNextAction(
        type: WorkspaceNextActionType.goalWithoutTask,
        severity: WorkspaceNextActionSeverity.warning,
        title: 'Add next task to goal',
        reason: 'Goal exists without an open task',
      ),
    );
  }
  final noteCount = workspace.activeNodes
      .where((node) => node.type == NodeType.note)
      .length;
  if (noteCount >= 3 && !hasTask) {
    actions.add(
      WorkspaceNextAction(
        type: WorkspaceNextActionType.notesWithoutTask,
        severity: WorkspaceNextActionSeverity.info,
        title: 'Convert notes into action',
        reason: '$noteCount notes, no task',
      ),
    );
  }
  if (workspace.type == WorkspaceContextType.project &&
      isWorkspaceStale(workspace, today) &&
      open.isNotEmpty) {
    actions.add(
      const WorkspaceNextAction(
        type: WorkspaceNextActionType.staleProject,
        severity: WorkspaceNextActionSeverity.warning,
        title: 'Review quiet project',
        reason: 'No recent activity',
      ),
    );
  }
  return _dedupe(actions).take(limit).toList(growable: false);
}

bool _isWaitingOrBlocked(MindmapNode node) {
  return node.status == NodeStatus.waiting ||
      node.tags.any((tag) => tag.toLowerCase() == 'blocked') ||
      node.data['blocked'] == true ||
      node.data['isBlocked'] == true;
}

List<WorkspaceNextAction> _dedupe(List<WorkspaceNextAction> actions) {
  final seen = <WorkspaceNextActionType>{};
  return [
    for (final action in actions)
      if (seen.add(action.type)) action,
  ];
}

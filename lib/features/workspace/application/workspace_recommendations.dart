import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/workspace_context.dart';
import 'workspace_overview.dart';
import 'workspace_relationships.dart';

enum WorkspaceRecommendationType {
  addNextAction,
  connectPriorityTask,
  reviewStaleArea,
  closeDoneHeavyWorkspace,
  splitCrowdedWorkspace,
  scheduleOverdueTask,
  promoteRepeatedTag,
}

final class WorkspaceRecommendation {
  const WorkspaceRecommendation({
    required this.type,
    required this.title,
    required this.reason,
    required this.score,
  });

  final WorkspaceRecommendationType type;
  final String title;
  final String reason;
  final int score;
}

List<WorkspaceRecommendation> buildWorkspaceRecommendations(
  WorkspaceContext workspace,
  DateTime today,
  WorkspaceRelationshipSummary relationships,
) {
  final recs = <WorkspaceRecommendation>[];
  final open = workspace.activeNodes
      .where((node) => !node.isDone && node.status != NodeStatus.done)
      .toList(growable: false);
  if (classifyWorkspaceHealth(workspace, today) ==
          WorkspaceHealthStatus.quiet &&
      open.isNotEmpty) {
    recs.add(
      const WorkspaceRecommendation(
        type: WorkspaceRecommendationType.addNextAction,
        title: 'Add next action',
        reason: 'Quiet workspace still has open work',
        score: 70,
      ),
    );
  }
  if (relationships.isolatedNodes.any(
    (node) => node.priority.index >= NodePriority.high.index,
  )) {
    recs.add(
      const WorkspaceRecommendation(
        type: WorkspaceRecommendationType.connectPriorityTask,
        title: 'Connect priority task',
        reason: 'High-priority isolated node',
        score: 80,
      ),
    );
  }
  if (workspace.type == WorkspaceContextType.area &&
      isWorkspaceStale(workspace, today)) {
    recs.add(
      const WorkspaceRecommendation(
        type: WorkspaceRecommendationType.reviewStaleArea,
        title: 'Review stale area',
        reason: 'Area has no recent activity',
        score: 60,
      ),
    );
  }
  final done = workspace.activeNodes
      .where((node) => node.isDone || node.status == NodeStatus.done)
      .length;
  if (done >= 5 && done > open.length * 2) {
    recs.add(
      const WorkspaceRecommendation(
        type: WorkspaceRecommendationType.closeDoneHeavyWorkspace,
        title: 'Archive or close completed work',
        reason: 'Done-heavy workspace',
        score: 40,
      ),
    );
  }
  if (workspace.activeNodes.length >= 20) {
    recs.add(
      const WorkspaceRecommendation(
        type: WorkspaceRecommendationType.splitCrowdedWorkspace,
        title: 'Split crowded workspace',
        reason: 'Many nodes in one context',
        score: 50,
      ),
    );
  }
  if (workspace.overdueCount(today) > 0) {
    recs.add(
      WorkspaceRecommendation(
        type: WorkspaceRecommendationType.scheduleOverdueTask,
        title: 'Schedule overdue work',
        reason: '${workspace.overdueCount(today)} overdue nodes',
        score: 90,
      ),
    );
  }
  final tags = <String, int>{};
  for (final node in workspace.activeNodes) {
    for (final tag in node.tags) {
      tags[tag] = (tags[tag] ?? 0) + 1;
    }
  }
  final repeated = tags.entries
      .where((entry) => entry.value >= 3)
      .toList(growable: false);
  if (repeated.isNotEmpty) {
    recs.add(
      WorkspaceRecommendation(
        type: WorkspaceRecommendationType.promoteRepeatedTag,
        title: 'Promote #${repeated.first.key}',
        reason: 'Repeated active tag',
        score: 30,
      ),
    );
  }
  recs.sort((a, b) {
    final score = b.score.compareTo(a.score);
    return score != 0 ? score : a.title.compareTo(b.title);
  });
  final seen = <WorkspaceRecommendationType>{};
  return [
    for (final rec in recs)
      if (seen.add(rec.type)) rec,
  ];
}

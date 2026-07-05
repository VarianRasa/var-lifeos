import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/workspace_context.dart';
import 'workspace_goal_summary.dart';
import 'workspace_health.dart';
import 'workspace_next_actions.dart';
import 'workspace_overview.dart';
import 'workspace_recommendations.dart';
import 'workspace_relationships.dart';
import 'workspace_timeline.dart';

final class WorkspaceIndexEntry {
  const WorkspaceIndexEntry({
    required this.workspace,
    required this.health,
    required this.nextActions,
    required this.timeline,
    required this.goals,
    required this.relationships,
    required this.recommendations,
  });

  final WorkspaceContext workspace;
  final WorkspaceHealthSummary health;
  final List<WorkspaceNextAction> nextActions;
  final WorkspaceTimelineSummary timeline;
  final WorkspaceGoalSummary goals;
  final WorkspaceRelationshipSummary relationships;
  final List<WorkspaceRecommendation> recommendations;
}

final class WorkspaceIndex {
  const WorkspaceIndex({required this.overview, required this.entries});

  final WorkspaceOverviewSummary overview;
  final Map<String, WorkspaceIndexEntry> entries;

  WorkspaceIndexEntry? entryFor(WorkspaceContext workspace) {
    return entries[workspaceHealthKey(workspace)];
  }
}

WorkspaceIndex buildWorkspaceIndex(
  WorkspaceContexts contexts,
  List<MindmapNode> allNodes,
  DateTime today,
) {
  final entries = <String, WorkspaceIndexEntry>{};
  for (final workspace in contexts.contexts) {
    final health = buildWorkspaceHealth(workspace, today);
    final nextActions = buildWorkspaceNextActions(workspace, today);
    final timeline = buildWorkspaceTimeline(workspace, today);
    final goals = buildWorkspaceGoalSummary(workspace, today);
    final relationships = buildWorkspaceRelationshipSummary(
      workspace,
      allNodes,
    );
    final recommendations = buildWorkspaceRecommendations(
      workspace,
      today,
      relationships,
    );
    entries[workspaceHealthKey(workspace)] = WorkspaceIndexEntry(
      workspace: workspace,
      health: health,
      nextActions: nextActions,
      timeline: timeline,
      goals: goals,
      relationships: relationships,
      recommendations: recommendations,
    );
  }
  return WorkspaceIndex(
    overview: buildWorkspaceOverview(contexts, today),
    entries: Map.unmodifiable(entries),
  );
}

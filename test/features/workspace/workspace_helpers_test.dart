import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/workspace_context.dart';
import 'package:var_app/features/workspace/application/workspace_filters.dart';
import 'package:var_app/features/workspace/application/workspace_goal_summary.dart';
import 'package:var_app/features/workspace/application/workspace_health.dart';
import 'package:var_app/features/workspace/application/workspace_index.dart';
import 'package:var_app/features/workspace/application/workspace_markdown_export.dart';
import 'package:var_app/features/workspace/application/workspace_next_actions.dart';
import 'package:var_app/features/workspace/application/workspace_recommendations.dart';
import 'package:var_app/features/workspace/application/workspace_relationships.dart';
import 'package:var_app/features/workspace/application/workspace_timeline.dart';

void main() {
  test('filters, health, timeline, actions, goals, relationships compose', () {
    final today = DateTime(2026, 6, 19);
    final nodes = [
      MindmapNode.create(
        id: 'goal',
        type: NodeType.goal,
        title: 'Ship goal',
        day: today,
        project: 'Ship',
        progress: 0.4,
        now: today.subtract(const Duration(days: 20)),
        relatedNodeIds: ['task'],
        data: {
          'milestones': ['Alpha'],
        },
      ),
      MindmapNode.create(
        id: 'task',
        type: NodeType.task,
        title: 'Overdue task',
        day: today,
        project: 'Ship',
        priority: NodePriority.urgent,
        dueDate: today.subtract(const Duration(days: 1)),
        tags: ['release'],
        now: today,
        relatedNodeIds: ['goal'],
      ),
      MindmapNode.create(
        id: 'waiting',
        type: NodeType.task,
        title: 'Waiting task',
        day: today,
        project: 'Ship',
        status: NodeStatus.waiting,
        tags: ['release'],
        now: today,
      ),
    ];
    final contexts = WorkspaceContexts.fromNodes(nodes);
    final workspace = contexts.contextFor(WorkspaceContextType.project, 'Ship');

    expect(
      matchesWorkspaceFilter(
        workspace,
        const WorkspaceFilterState(
          type: WorkspaceContextType.project,
          overdueOnly: true,
          tag: 'release',
        ),
        today,
      ),
      isTrue,
    );
    expect(sortFilteredWorkspaces([workspace], WorkspaceSortMode.risk, today), [
      workspace,
    ]);

    final health = buildWorkspaceHealth(workspace, today);
    expect(health.overdue, 1);
    expect(health.waiting, 1);

    final actions = buildWorkspaceNextActions(workspace, today);
    expect(actions.first.type, WorkspaceNextActionType.overdueTask);

    final timeline = buildWorkspaceTimeline(workspace, today);
    expect(timeline.overdue, hasLength(1));

    final goals = buildWorkspaceGoalSummary(workspace, today);
    expect(goals.goals.single.milestones, ['Alpha']);

    final relationships = buildWorkspaceRelationshipSummary(workspace, nodes);
    expect(relationships.internalRelations, 2);

    final recommendations = buildWorkspaceRecommendations(
      workspace,
      today,
      relationships,
    );
    expect(recommendations, isNotEmpty);

    final index = buildWorkspaceIndex(contexts, nodes, today);
    expect(index.entryFor(workspace), isNotNull);

    final markdown = exportWorkspaceMarkdown(
      workspace: workspace,
      today: today,
      health: health,
      timeline: timeline,
      goals: goals,
      relationships: relationships,
      nextActions: actions,
      recommendations: recommendations,
    );
    expect(markdown, contains('# Project Ship'));
    expect(markdown, contains('## Recommendations'));
  });
}

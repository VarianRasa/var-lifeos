import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/workspace_context.dart';
import 'workspace_goal_summary.dart';
import 'workspace_health.dart';
import 'workspace_next_actions.dart';
import 'workspace_overview.dart';
import 'workspace_recommendations.dart';
import 'workspace_relationships.dart';
import 'workspace_timeline.dart';

String exportWorkspaceMarkdown({
  required WorkspaceContext workspace,
  required DateTime today,
  required WorkspaceHealthSummary health,
  required WorkspaceTimelineSummary timeline,
  required WorkspaceGoalSummary goals,
  required WorkspaceRelationshipSummary relationships,
  required List<WorkspaceNextAction> nextActions,
  required List<WorkspaceRecommendation> recommendations,
}) {
  final buffer = StringBuffer()
    ..writeln('# ${workspace.type.label} ${workspace.name}')
    ..writeln()
    ..writeln('- Generated: ${dayKey(today)}')
    ..writeln('- Health: ${health.status.label}')
    ..writeln('- Active: ${health.active}')
    ..writeln('- Done: ${health.done}')
    ..writeln('- Overdue: ${health.overdue}')
    ..writeln('- High priority: ${health.highPriority}')
    ..writeln('- Progress: ${(health.progress * 100).round()}%')
    ..writeln()
    ..writeln('## Next actions');
  if (nextActions.isEmpty) {
    buffer.writeln('- None');
  } else {
    for (final action in nextActions) {
      buffer.writeln('- ${action.title}: ${action.reason}');
    }
  }
  buffer
    ..writeln()
    ..writeln('## Timeline')
    ..writeln('- Overdue: ${timeline.overdue.length}')
    ..writeln('- Due today: ${timeline.dueToday.length}')
    ..writeln('- Due this week: ${timeline.dueThisWeek.length}')
    ..writeln('- Upcoming 30 days: ${timeline.upcoming30Days.length}')
    ..writeln('- Completed recently: ${timeline.completedRecently.length}')
    ..writeln()
    ..writeln('## Goals');
  if (goals.goals.isEmpty) {
    buffer.writeln('- None');
  } else {
    for (final goal in goals.goals) {
      buffer.writeln('- ${goal.node.title}: ${(goal.progress * 100).round()}%');
    }
  }
  buffer
    ..writeln()
    ..writeln('## Relationships')
    ..writeln('- Relations: ${relationships.relationCount}')
    ..writeln('- Internal: ${relationships.internalRelations}')
    ..writeln('- External: ${relationships.externalRelations}')
    ..writeln('- Isolated: ${relationships.isolatedNodes.length}')
    ..writeln()
    ..writeln('## Recommendations');
  if (recommendations.isEmpty) {
    buffer.writeln('- None');
  } else {
    for (final rec in recommendations) {
      buffer.writeln('- ${rec.title}: ${rec.reason}');
    }
  }
  return buffer.toString().trimRight();
}

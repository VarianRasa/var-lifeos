import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/workspace_context.dart';

enum WorkspaceHealthStatus { healthy, quiet, busy, atRisk }

extension WorkspaceHealthStatusLabel on WorkspaceHealthStatus {
  String get label => switch (this) {
    WorkspaceHealthStatus.healthy => 'Healthy',
    WorkspaceHealthStatus.quiet => 'Quiet',
    WorkspaceHealthStatus.busy => 'Busy',
    WorkspaceHealthStatus.atRisk => 'At risk',
  };
}

final class WorkspaceOverviewSummary {
  const WorkspaceOverviewSummary({
    required this.totalWorkspaces,
    required this.projects,
    required this.areas,
    required this.dailies,
    required this.activeNodes,
    required this.overdueNodes,
    required this.highPriorityOpenNodes,
    required this.staleWorkspaces,
    required this.healthByWorkspace,
  });

  final int totalWorkspaces;
  final int projects;
  final int areas;
  final int dailies;
  final int activeNodes;
  final int overdueNodes;
  final int highPriorityOpenNodes;
  final int staleWorkspaces;
  final Map<String, WorkspaceHealthStatus> healthByWorkspace;
}

WorkspaceOverviewSummary buildWorkspaceOverview(
  WorkspaceContexts contexts,
  DateTime today, {
  Duration staleAfter = const Duration(days: 14),
}) {
  final normalizedToday = today.dateOnly;
  final healthByWorkspace = <String, WorkspaceHealthStatus>{};
  final activeNodeIds = <String>{};
  final overdueNodeIds = <String>{};
  final highPriorityOpenNodeIds = <String>{};
  var staleWorkspaces = 0;

  for (final workspace in contexts.contexts) {
    final health = classifyWorkspaceHealth(
      workspace,
      normalizedToday,
      staleAfter: staleAfter,
    );
    healthByWorkspace[_workspaceKey(workspace)] = health;
    if (health == WorkspaceHealthStatus.quiet) staleWorkspaces += 1;

    for (final node in workspace.activeNodes) {
      activeNodeIds.add(node.id);
      if (_isOpen(node) && node.priority.index >= NodePriority.high.index) {
        highPriorityOpenNodeIds.add(node.id);
      }
      final dueDate = node.dueDate;
      if (_isOpen(node) &&
          dueDate != null &&
          dueDate.dateOnly.isBefore(normalizedToday)) {
        overdueNodeIds.add(node.id);
      }
    }
  }

  return WorkspaceOverviewSummary(
    totalWorkspaces: contexts.contexts.length,
    projects: contexts.projects.length,
    areas: contexts.areas.length,
    dailies: contexts.dailies.length,
    activeNodes: activeNodeIds.length,
    overdueNodes: overdueNodeIds.length,
    highPriorityOpenNodes: highPriorityOpenNodeIds.length,
    staleWorkspaces: staleWorkspaces,
    healthByWorkspace: Map.unmodifiable(healthByWorkspace),
  );
}

WorkspaceHealthStatus classifyWorkspaceHealth(
  WorkspaceContext workspace,
  DateTime today, {
  Duration staleAfter = const Duration(days: 14),
}) {
  final active = workspace.activeNodes.where(_isOpen).toList(growable: false);
  final overdue = active.where((node) {
    final dueDate = node.dueDate;
    return dueDate != null && dueDate.dateOnly.isBefore(today.dateOnly);
  }).length;
  final high = active
      .where((node) => node.priority.index >= NodePriority.high.index)
      .length;
  final latest = _latestActivity(workspace.activeNodes);
  final stale =
      latest == null ||
      today.dateOnly.difference(latest.dateOnly) >= staleAfter;

  if (overdue > 0 || high >= 3) return WorkspaceHealthStatus.atRisk;
  if (stale || active.isEmpty) return WorkspaceHealthStatus.quiet;
  if (active.length >= 8 || high > 0) return WorkspaceHealthStatus.busy;
  return WorkspaceHealthStatus.healthy;
}

bool isWorkspaceStale(
  WorkspaceContext workspace,
  DateTime today, {
  Duration staleAfter = const Duration(days: 14),
}) {
  final latest = _latestActivity(workspace.activeNodes);
  return latest == null ||
      today.dateOnly.difference(latest.dateOnly) >= staleAfter;
}

String workspaceHealthKey(WorkspaceContext workspace) =>
    _workspaceKey(workspace);

String _workspaceKey(WorkspaceContext workspace) =>
    '${workspace.type.name}:${workspace.name}';

DateTime? _latestActivity(List<MindmapNode> nodes) {
  DateTime? latest;
  for (final node in nodes) {
    if (latest == null || node.updatedAt.isAfter(latest)) {
      latest = node.updatedAt;
    }
  }
  return latest;
}

bool _isOpen(MindmapNode node) =>
    !node.isDone && node.status != NodeStatus.done;

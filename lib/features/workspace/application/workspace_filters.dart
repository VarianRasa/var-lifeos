import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/workspace_context.dart';
import 'workspace_overview.dart';

enum WorkspaceSortMode { manual, name, activity, risk, progress }

final class WorkspaceFilterState {
  const WorkspaceFilterState({
    this.type,
    this.health,
    this.priority,
    this.overdueOnly = false,
    this.staleOnly = false,
    this.activeOnly = false,
    this.tag,
    this.sortMode = WorkspaceSortMode.manual,
  });

  final WorkspaceContextType? type;
  final WorkspaceHealthStatus? health;
  final NodePriority? priority;
  final bool overdueOnly;
  final bool staleOnly;
  final bool activeOnly;
  final String? tag;
  final WorkspaceSortMode sortMode;

  WorkspaceFilterState copyWith({
    WorkspaceContextType? type,
    WorkspaceHealthStatus? health,
    NodePriority? priority,
    bool? overdueOnly,
    bool? staleOnly,
    bool? activeOnly,
    String? tag,
    WorkspaceSortMode? sortMode,
    bool clearType = false,
    bool clearHealth = false,
    bool clearPriority = false,
    bool clearTag = false,
  }) {
    return WorkspaceFilterState(
      type: clearType ? null : (type ?? this.type),
      health: clearHealth ? null : (health ?? this.health),
      priority: clearPriority ? null : (priority ?? this.priority),
      overdueOnly: overdueOnly ?? this.overdueOnly,
      staleOnly: staleOnly ?? this.staleOnly,
      activeOnly: activeOnly ?? this.activeOnly,
      tag: clearTag ? null : (tag ?? this.tag),
      sortMode: sortMode ?? this.sortMode,
    );
  }

  bool get hasFilters =>
      type != null ||
      health != null ||
      priority != null ||
      overdueOnly ||
      staleOnly ||
      activeOnly ||
      (tag?.trim().isNotEmpty ?? false) ||
      sortMode != WorkspaceSortMode.manual;
}

bool matchesWorkspaceFilter(
  WorkspaceContext workspace,
  WorkspaceFilterState filter,
  DateTime today,
) {
  if (filter.type != null && workspace.type != filter.type) return false;
  if (filter.health != null &&
      classifyWorkspaceHealth(workspace, today) != filter.health) {
    return false;
  }
  if (filter.priority != null &&
      !workspace.activeNodes.any((node) => node.priority == filter.priority)) {
    return false;
  }
  if (filter.overdueOnly && workspace.overdueCount(today) == 0) return false;
  if (filter.staleOnly && !isWorkspaceStale(workspace, today)) return false;
  if (filter.activeOnly &&
      !workspace.activeNodes.any(
        (node) => !node.isDone && node.status != NodeStatus.done,
      )) {
    return false;
  }
  final tag = filter.tag?.trim().toLowerCase();
  if (tag != null && tag.isNotEmpty) {
    final hasTag = workspace.activeNodes.any(
      (node) => node.tags.any((item) => item.toLowerCase() == tag),
    );
    if (!hasTag) return false;
  }
  return true;
}

List<WorkspaceContext> sortFilteredWorkspaces(
  List<WorkspaceContext> workspaces,
  WorkspaceSortMode sortMode,
  DateTime today,
) {
  final sorted = [...workspaces];
  int compareStable(WorkspaceContext a, WorkspaceContext b, int value) {
    if (value != 0) return value;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  sorted.sort((a, b) {
    return switch (sortMode) {
      WorkspaceSortMode.manual => 0,
      WorkspaceSortMode.name => compareStable(
        a,
        b,
        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      ),
      WorkspaceSortMode.activity => compareStable(
        a,
        b,
        _latest(b).compareTo(_latest(a)),
      ),
      WorkspaceSortMode.risk => compareStable(
        a,
        b,
        _risk(b, today) - _risk(a, today),
      ),
      WorkspaceSortMode.progress => compareStable(
        a,
        b,
        b.averageProgress.compareTo(a.averageProgress),
      ),
    };
  });
  return sorted;
}

DateTime _latest(WorkspaceContext workspace) {
  var latest = DateTime.fromMillisecondsSinceEpoch(0);
  for (final node in workspace.activeNodes) {
    if (node.updatedAt.isAfter(latest)) latest = node.updatedAt;
  }
  return latest;
}

int _risk(WorkspaceContext workspace, DateTime today) {
  return (workspace.overdueCount(today) * 10) +
      workspace.highPriorityCount +
      (isWorkspaceStale(workspace, today) ? 3 : 0) +
      (today.dateOnly.difference(_latest(workspace).dateOnly).inDays ~/ 7);
}

Map<String, Object?> workspaceFilterStateToJson(WorkspaceFilterState state) {
  return {
    'type': state.type?.name,
    'health': state.health?.name,
    'priority': state.priority?.name,
    'overdueOnly': state.overdueOnly,
    'staleOnly': state.staleOnly,
    'activeOnly': state.activeOnly,
    'tag': state.tag,
    'sortMode': state.sortMode.name,
  };
}

WorkspaceFilterState workspaceFilterStateFromJson(Map<String, Object?> json) {
  T? byName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  return WorkspaceFilterState(
    type: byName(WorkspaceContextType.values, json['type']),
    health: byName(WorkspaceHealthStatus.values, json['health']),
    priority: byName(NodePriority.values, json['priority']),
    overdueOnly: json['overdueOnly'] == true,
    staleOnly: json['staleOnly'] == true,
    activeOnly: json['activeOnly'] == true,
    tag: json['tag'] is String ? json['tag'] as String : null,
    sortMode:
        byName(WorkspaceSortMode.values, json['sortMode']) ??
        WorkspaceSortMode.manual,
  );
}

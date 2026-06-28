/// Project and area grouping derived from node metadata.
library;

import '../../../core/utils/date_utils.dart';
import 'mindmap_node.dart';

enum WorkspaceContextType {
  project('Project'),
  area('Area'),
  daily('Daily');

  const WorkspaceContextType(this.label);

  final String label;
}

final class WorkspaceContext {
  WorkspaceContext({
    required this.type,
    required this.name,
    required List<MindmapNode> nodes,
  }) : nodes = List.unmodifiable(nodes);

  final WorkspaceContextType type;
  final String name;
  final List<MindmapNode> nodes;

  List<String> get nodeIds => [for (final node in nodes) node.id];

  String get countLabel => '${type.label} $name ${nodes.length}';

  List<MindmapNode> get activeNodes {
    return nodes.where((node) => !node.isArchived).toList(growable: false);
  }

  int get activeNodeCount => activeNodes.length;

  int get completedCount {
    return activeNodes.where(_isComplete).length;
  }

  int get highPriorityCount {
    return activeNodes
        .where((node) => node.priority.index >= NodePriority.high.index)
        .length;
  }

  double get completionRate {
    if (activeNodeCount == 0) return 0;
    return completedCount / activeNodeCount;
  }

  double get averageProgress {
    final active = activeNodes;
    if (active.isEmpty) return 0;
    final total = active.fold<double>(
      0,
      (total, node) => total + _nodeProgress(node),
    );
    return total / active.length;
  }

  int overdueCount(DateTime today) {
    final normalizedToday = today.dateOnly;
    return activeNodes.where((node) {
      final dueDate = node.dueDate;
      if (dueDate == null || _isComplete(node)) return false;
      return dueDate.dateOnly.isBefore(normalizedToday);
    }).length;
  }

  String healthLabel(DateTime today) {
    final parts = [
      if (overdueCount(today) > 0) '${overdueCount(today)} overdue',
      if (highPriorityCount > 0) '$highPriorityCount high',
      '${(averageProgress * 100).round()}% progress',
    ];
    return parts.join(' / ');
  }

  List<MindmapNode> nextActions(DateTime today, {int limit = 3}) {
    if (limit <= 0) return const [];

    final normalizedToday = today.dateOnly;
    final candidates = activeNodes
        .where((node) => !_isComplete(node))
        .toList(growable: false);
    candidates.sort((a, b) => _compareNextAction(a, b, normalizedToday));
    return candidates.take(limit).toList(growable: false);
  }
}

final class WorkspaceContexts {
  WorkspaceContexts({required List<WorkspaceContext> contexts})
    : contexts = List.unmodifiable(contexts);

  factory WorkspaceContexts.fromNodes(List<MindmapNode> nodes) {
    final projects = <String, List<MindmapNode>>{};
    final areas = <String, List<MindmapNode>>{};
    final dailies = <String, List<MindmapNode>>{};

    for (final node in nodes) {
      if (node.project.isNotEmpty) {
        projects.putIfAbsent(node.project, () => []).add(node);
      }
      if (node.area.isNotEmpty) {
        areas.putIfAbsent(node.area, () => []).add(node);
      }
      final dayStr = dayKey(node.day);
      dailies.putIfAbsent(dayStr, () => []).add(node);
    }

    final contexts = [
      for (final entry in _sortedEntries(projects))
        WorkspaceContext(
          type: WorkspaceContextType.project,
          name: entry.key,
          nodes: entry.value,
        ),
      for (final entry in _sortedEntries(areas))
        WorkspaceContext(
          type: WorkspaceContextType.area,
          name: entry.key,
          nodes: entry.value,
        ),
      for (final entry in _sortedEntries(dailies))
        WorkspaceContext(
          type: WorkspaceContextType.daily,
          name: entry.key,
          nodes: entry.value,
        ),
    ];

    return WorkspaceContexts(contexts: contexts);
  }

  final List<WorkspaceContext> contexts;

  List<WorkspaceContext> get projects {
    return contexts
        .where((context) => context.type == WorkspaceContextType.project)
        .toList(growable: false);
  }

  List<WorkspaceContext> get areas {
    return contexts
        .where((context) => context.type == WorkspaceContextType.area)
        .toList(growable: false);
  }

  List<WorkspaceContext> get dailies {
    return contexts
        .where((context) => context.type == WorkspaceContextType.daily)
        .toList(growable: false);
  }

  WorkspaceContext contextFor(WorkspaceContextType type, String name) {
    return contexts.firstWhere(
      (context) => context.type == type && context.name == name,
      orElse: () => WorkspaceContext(type: type, name: name, nodes: const []),
    );
  }
}

String workspaceContextKey(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return normalized.isEmpty ? 'untitled' : normalized;
}

List<MapEntry<String, List<MindmapNode>>> _sortedEntries(
  Map<String, List<MindmapNode>> values,
) {
  return values.entries.toList()
    ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done;
}

double _nodeProgress(MindmapNode node) {
  if (_isComplete(node)) return 1;
  if (node.checklist.isNotEmpty) return node.checklistProgress;
  return node.progress;
}

int _compareNextAction(MindmapNode a, MindmapNode b, DateTime today) {
  final dueBucketCompare = _dueBucket(a, today).compareTo(_dueBucket(b, today));
  if (dueBucketCompare != 0) return dueBucketCompare;

  final dueA = a.dueDate;
  final dueB = b.dueDate;
  if (dueA != null && dueB != null) {
    final dueCompare = dueA.compareTo(dueB);
    if (dueCompare != 0) return dueCompare;
  }

  final priorityCompare = b.priority.index.compareTo(a.priority.index);
  if (priorityCompare != 0) return priorityCompare;

  final updatedCompare = b.updatedAt.compareTo(a.updatedAt);
  if (updatedCompare != 0) return updatedCompare;

  return a.title.compareTo(b.title);
}

int _dueBucket(MindmapNode node, DateTime today) {
  final dueDate = node.dueDate;
  if (dueDate == null) return 2;
  return dueDate.dateOnly.isBefore(today) ? 0 : 1;
}

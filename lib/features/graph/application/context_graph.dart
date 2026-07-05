/// Context cluster summaries for project/area/tag graph modes.
library;

import '../../mindmap/domain/mindmap_node.dart';

enum ContextGraphMode { nodes, projects, areas, tags }

final class ContextGraphSummary {
  ContextGraphSummary({required List<ContextGraphCluster> clusters})
    : clusters = List.unmodifiable(clusters);

  final List<ContextGraphCluster> clusters;
}

final class ContextGraphCluster {
  const ContextGraphCluster({
    required this.name,
    required this.mode,
    required this.nodeCount,
    required this.openTasks,
    required this.doneTasks,
    required this.overdue,
    required this.highPriority,
    required this.lastActivity,
  });

  final String name;
  final ContextGraphMode mode;
  final int nodeCount;
  final int openTasks;
  final int doneTasks;
  final int overdue;
  final int highPriority;
  final DateTime? lastActivity;
}

ContextGraphSummary buildContextGraphSummary(
  Iterable<MindmapNode> nodes, {
  required ContextGraphMode mode,
  DateTime? now,
}) {
  final groups = <String, List<MindmapNode>>{};
  if (mode == ContextGraphMode.nodes) {
    return ContextGraphSummary(clusters: const []);
  }
  for (final node in nodes) {
    final keys = switch (mode) {
      ContextGraphMode.projects => [if (node.project.isNotEmpty) node.project],
      ContextGraphMode.areas => [if (node.area.isNotEmpty) node.area],
      ContextGraphMode.tags => node.tags,
      ContextGraphMode.nodes => const <String>[],
    };
    for (final key in keys) {
      groups.putIfAbsent(key, () => <MindmapNode>[]).add(node);
    }
  }
  final today = _dateOnly(now ?? DateTime.now());
  final clusters =
      [
        for (final entry in groups.entries)
          _cluster(entry.key, mode, entry.value, today),
      ]..sort((a, b) {
        final count = b.nodeCount.compareTo(a.nodeCount);
        if (count != 0) return count;
        return a.name.compareTo(b.name);
      });
  return ContextGraphSummary(clusters: clusters);
}

ContextGraphCluster _cluster(
  String name,
  ContextGraphMode mode,
  List<MindmapNode> nodes,
  DateTime today,
) {
  DateTime? lastActivity;
  var openTasks = 0;
  var doneTasks = 0;
  var overdue = 0;
  var highPriority = 0;
  for (final node in nodes) {
    if (lastActivity == null || node.updatedAt.isAfter(lastActivity)) {
      lastActivity = node.updatedAt;
    }
    if (node.type.name == 'task') {
      if (node.status == NodeStatus.done) {
        doneTasks++;
      } else {
        openTasks++;
      }
    }
    if (node.dueDate != null && node.dueDate!.isBefore(today)) overdue++;
    if (node.priority == NodePriority.high ||
        node.priority == NodePriority.urgent) {
      highPriority++;
    }
  }
  return ContextGraphCluster(
    name: name,
    mode: mode,
    nodeCount: nodes.length,
    openTasks: openTasks,
    doneTasks: doneTasks,
    overdue: overdue,
    highPriority: highPriority,
    lastActivity: lastActivity,
  );
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

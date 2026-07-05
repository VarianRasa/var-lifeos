/// Project/area health analytics for Insights.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

enum ContextHealthStatus { good, watch, stale, critical }

final class ContextHealthItem {
  const ContextHealthItem({
    required this.name,
    required this.isProject,
    required this.openTasks,
    required this.completedTasks,
    required this.overdueTasks,
    required this.highPriorityOpenTasks,
    required this.lastActivity,
    required this.status,
  });

  final String name;
  final bool isProject;
  final int openTasks;
  final int completedTasks;
  final int overdueTasks;
  final int highPriorityOpenTasks;
  final DateTime? lastActivity;
  final ContextHealthStatus status;

  int get totalTasks => openTasks + completedTasks;
}

final class ContextHealthSummary {
  const ContextHealthSummary({
    required this.items,
    required this.neglectedContexts,
    required this.hotContexts,
  });

  final List<ContextHealthItem> items;
  final List<ContextHealthItem> neglectedContexts;
  final List<ContextHealthItem> hotContexts;
}

ContextHealthSummary buildContextHealthSummary({
  required DateTime today,
  required Iterable<MindmapNode> nodes,
}) {
  final byKey = <String, _ContextAccumulator>{};
  for (final node in nodes) {
    if (node.isArchived) continue;
    if (node.project.isNotEmpty) {
      _accumulator(
        byKey,
        'project:${node.project}',
        node.project,
        true,
      ).add(node, today.dateOnly);
    }
    if (node.area.isNotEmpty) {
      _accumulator(
        byKey,
        'area:${node.area}',
        node.area,
        false,
      ).add(node, today.dateOnly);
    }
  }

  final items = byKey.values.map((item) => item.toItem(today.dateOnly)).toList()
    ..sort((a, b) {
      final statusCompare = b.status.index.compareTo(a.status.index);
      if (statusCompare != 0) return statusCompare;
      final loadCompare = b.openTasks.compareTo(a.openTasks);
      if (loadCompare != 0) return loadCompare;
      return a.name.compareTo(b.name);
    });

  final neglected = [
    for (final item in items)
      if (item.status == ContextHealthStatus.stale ||
          item.status == ContextHealthStatus.critical)
        item,
  ];
  final hot =
      [
        for (final item in items)
          if (item.openTasks >= 3 ||
              item.highPriorityOpenTasks >= 2 ||
              item.overdueTasks > 0)
            item,
      ]..sort((a, b) {
        final scoreCompare = _hotScore(b).compareTo(_hotScore(a));
        if (scoreCompare != 0) return scoreCompare;
        return a.name.compareTo(b.name);
      });

  return ContextHealthSummary(
    items: List.unmodifiable(items),
    neglectedContexts: List.unmodifiable(neglected.take(5)),
    hotContexts: List.unmodifiable(hot.take(5)),
  );
}

ContextHealthStatus scoreContextHealth({
  required int openTasks,
  required int overdueTasks,
  required int highPriorityOpenTasks,
  required DateTime? lastActivity,
  required DateTime today,
}) {
  if (overdueTasks >= 3 || highPriorityOpenTasks >= 4) {
    return ContextHealthStatus.critical;
  }
  if (lastActivity != null &&
      today.difference(lastActivity.dateOnly).inDays >= 14 &&
      openTasks > 0) {
    return ContextHealthStatus.stale;
  }
  if (overdueTasks > 0 || highPriorityOpenTasks >= 2 || openTasks >= 6) {
    return ContextHealthStatus.watch;
  }
  return ContextHealthStatus.good;
}

_ContextAccumulator _accumulator(
  Map<String, _ContextAccumulator> values,
  String key,
  String name,
  bool isProject,
) {
  return values.putIfAbsent(
    key,
    () => _ContextAccumulator(name: name, isProject: isProject),
  );
}

int _hotScore(ContextHealthItem item) {
  return item.openTasks +
      item.highPriorityOpenTasks * 2 +
      item.overdueTasks * 3;
}

final class _ContextAccumulator {
  _ContextAccumulator({required this.name, required this.isProject});

  final String name;
  final bool isProject;
  int openTasks = 0;
  int completedTasks = 0;
  int overdueTasks = 0;
  int highPriorityOpenTasks = 0;
  DateTime? lastActivity;

  void add(MindmapNode node, DateTime today) {
    if (lastActivity == null || node.updatedAt.isAfter(lastActivity!)) {
      lastActivity = node.updatedAt.dateOnly;
    }
    if (node.type != NodeType.task) return;
    final complete = _isComplete(node);
    if (complete) {
      completedTasks++;
      return;
    }
    openTasks++;
    if (node.priority.index >= NodePriority.high.index) highPriorityOpenTasks++;
    if (node.dueDate != null && node.dueDate!.dateOnly.isBefore(today)) {
      overdueTasks++;
    }
  }

  ContextHealthItem toItem(DateTime today) {
    return ContextHealthItem(
      name: name,
      isProject: isProject,
      openTasks: openTasks,
      completedTasks: completedTasks,
      overdueTasks: overdueTasks,
      highPriorityOpenTasks: highPriorityOpenTasks,
      lastActivity: lastActivity,
      status: scoreContextHealth(
        openTasks: openTasks,
        overdueTasks: overdueTasks,
        highPriorityOpenTasks: highPriorityOpenTasks,
        lastActivity: lastActivity,
        today: today,
      ),
    );
  }
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}

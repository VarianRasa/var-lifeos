/// Shared precomputed node slices for Insights performance.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import 'insight_filters.dart';

final class InsightNodeIndex {
  const InsightNodeIndex({
    required this.activeNodes,
    required this.scopedNodes,
    required this.completedNodes,
    required this.openTaskNodes,
    required this.overdueTaskNodes,
    required this.highPriorityOpenTaskNodes,
    required this.typeCounts,
  });

  final List<MindmapNode> activeNodes;
  final List<MindmapNode> scopedNodes;
  final List<MindmapNode> completedNodes;
  final List<MindmapNode> openTaskNodes;
  final List<MindmapNode> overdueTaskNodes;
  final List<MindmapNode> highPriorityOpenTaskNodes;
  final Map<NodeType, int> typeCounts;

  int get activeCount => activeNodes.length;
  int get scopedCount => scopedNodes.length;
  int get completedCount => completedNodes.length;
  int get openTaskCount => openTaskNodes.length;
  int get overdueTaskCount => overdueTaskNodes.length;
  int get highPriorityOpenTaskCount => highPriorityOpenTaskNodes.length;
}

InsightNodeIndex buildInsightNodeIndex({
  required Iterable<MindmapNode> nodes,
  required InsightFilterState filter,
  required InsightDateRange range,
  required DateTime today,
}) {
  final normalizedToday = today.dateOnly;
  final activeNodes = <MindmapNode>[];
  final scopedNodes = <MindmapNode>[];
  final completedNodes = <MindmapNode>[];
  final openTaskNodes = <MindmapNode>[];
  final overdueTaskNodes = <MindmapNode>[];
  final highPriorityOpenTaskNodes = <MindmapNode>[];
  final typeCounts = <NodeType, int>{};

  for (final node in nodes) {
    if (node.isArchived) continue;
    activeNodes.add(node);
    typeCounts[node.type] = (typeCounts[node.type] ?? 0) + 1;

    if (!matchesInsightFilter(node, filter, range: range)) continue;
    scopedNodes.add(node);

    if (_isComplete(node)) {
      completedNodes.add(node);
    }

    if (node.type != NodeType.task || _isComplete(node)) continue;
    openTaskNodes.add(node);

    if (node.dueDate != null &&
        node.dueDate!.dateOnly.isBefore(normalizedToday)) {
      overdueTaskNodes.add(node);
    }
    if (node.priority.index >= NodePriority.high.index) {
      highPriorityOpenTaskNodes.add(node);
    }
  }

  overdueTaskNodes.sort(_priorityNodeSort);
  highPriorityOpenTaskNodes.sort(_priorityNodeSort);

  return InsightNodeIndex(
    activeNodes: List.unmodifiable(activeNodes),
    scopedNodes: List.unmodifiable(scopedNodes),
    completedNodes: List.unmodifiable(completedNodes),
    openTaskNodes: List.unmodifiable(openTaskNodes),
    overdueTaskNodes: List.unmodifiable(overdueTaskNodes),
    highPriorityOpenTaskNodes: List.unmodifiable(highPriorityOpenTaskNodes),
    typeCounts: Map.unmodifiable(typeCounts),
  );
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}

int _priorityNodeSort(MindmapNode a, MindmapNode b) {
  final priorityCompare = b.priority.index.compareTo(a.priority.index);
  if (priorityCompare != 0) return priorityCompare;
  final dueA = a.dueDate ?? a.day;
  final dueB = b.dueDate ?? b.day;
  final dueCompare = dueA.compareTo(dueB);
  if (dueCompare != 0) return dueCompare;
  return a.title.compareTo(b.title);
}

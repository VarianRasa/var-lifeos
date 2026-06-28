/// Task checklist helpers shared by interactive node surfaces.
library;

import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';

TaskChecklistItem? nextOpenChecklistItem(MindmapNode node) {
  if (node.type != NodeType.task) return null;
  for (final item in node.checklist) {
    if (!item.isDone) return item;
  }
  return null;
}

MindmapNode completeNextChecklistItem(MindmapNode node, {DateTime? now}) {
  if (node.type != NodeType.task) return node;

  final nextItem = nextOpenChecklistItem(node);
  if (nextItem == null) return node;

  final checklist = [
    for (final item in node.checklist)
      item.id == nextItem.id ? item.copyWith(isDone: true) : item,
  ];
  final completedCount = checklist.where((item) => item.isDone).length;
  final progress = checklist.isEmpty
      ? node.progress
      : completedCount / checklist.length;
  final isComplete = checklist.isNotEmpty && completedCount == checklist.length;
  final nextStatus = isComplete
      ? NodeStatus.done
      : node.status == NodeStatus.open
      ? NodeStatus.doing
      : node.status;

  return node.copyWith(
    checklist: checklist,
    progress: progress,
    isDone: isComplete ? true : node.isDone,
    status: nextStatus,
    updatedAt: now ?? DateTime.now(),
  );
}

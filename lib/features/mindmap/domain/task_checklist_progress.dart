/// Task checklist helpers shared by interactive node surfaces.
library;

import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';

List<TaskChecklistItem> moveTaskChecklistItem(
  List<TaskChecklistItem> items,
  int oldIndex,
  int newIndex,
) {
  if (oldIndex < 0 || oldIndex >= items.length) return List.unmodifiable(items);
  final moved = items[oldIndex];
  final blockIds = <String>{moved.id};
  var changed = true;
  while (changed) {
    changed = false;
    for (final item in items) {
      if (item.parentId != null &&
          blockIds.contains(item.parentId) &&
          blockIds.add(item.id)) {
        changed = true;
      }
    }
  }
  final block = [
    for (final item in items)
      if (blockIds.contains(item.id)) item,
  ];
  final remaining = [
    for (final item in items)
      if (!blockIds.contains(item.id)) item,
  ];
  final adjustedIndex = newIndex > oldIndex
      ? newIndex - block.length
      : newIndex;
  remaining.insertAll(adjustedIndex.clamp(0, remaining.length), block);
  return List.unmodifiable(remaining);
}

TaskChecklistItem? setTaskChecklistParent(
  List<TaskChecklistItem> items,
  String itemId,
  String? parentId,
) {
  TaskChecklistItem? item;
  for (final value in items) {
    if (value.id == itemId) {
      item = value;
      break;
    }
  }
  if (item == null || parentId == itemId) return item;
  if (parentId == null) return item.copyWith(clearParentId: true);
  final byId = {for (final value in items) value.id: value};
  if (!byId.containsKey(parentId) ||
      _isChecklistAncestor(itemId, parentId, byId)) {
    return item;
  }
  return item.copyWith(parentId: parentId);
}

bool _isChecklistAncestor(
  String potentialAncestorId,
  String descendantId,
  Map<String, TaskChecklistItem> byId,
) {
  var cursor = byId[descendantId];
  final visited = <String>{};
  while (cursor != null) {
    final parentId = cursor.parentId;
    if (parentId == null) break;
    if (parentId == potentialAncestorId) return true;
    if (!visited.add(parentId)) return true;
    cursor = byId[parentId];
  }
  return false;
}

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

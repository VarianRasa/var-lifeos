/// Local metadata helpers for day-page inbox nodes.
library;

import '../../mindmap/domain/mindmap_node.dart';

const inboxNodeDataKey = 'inbox';
const inboxAssignedFromDataKey = 'inboxAssignedFrom';

bool isInboxNode(MindmapNode node) {
  return (node.status == NodeStatus.inbox ||
          node.data[inboxNodeDataKey] == true) &&
      !node.isArchived;
}

List<MindmapNode> inboxNodesForDay(Iterable<MindmapNode> nodes, DateTime day) {
  final normalizedDay = DateTime(day.year, day.month, day.day);
  final inboxNodes = nodes.where(isInboxNode).where((node) {
    return !node.day.isAfter(normalizedDay);
  }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return List.unmodifiable(inboxNodes);
}

MindmapNode markInboxNode(MindmapNode node, {required bool isInbox}) {
  return node.copyWith(
    status: isInbox ? NodeStatus.inbox : NodeStatus.next,
    data: {...node.data, inboxNodeDataKey: isInbox},
    updatedAt: DateTime.now(),
  );
}

MindmapNode assignInboxNodeToDay(MindmapNode node, DateTime day) {
  final normalizedDay = DateTime(day.year, day.month, day.day);
  return node.copyWith(
    day: normalizedDay,
    status: NodeStatus.next,
    data: {
      ...node.data,
      inboxNodeDataKey: false,
      inboxAssignedFromDataKey: node.day.toIso8601String(),
    },
    updatedAt: DateTime.now(),
  );
}

MindmapNode deferInboxNode(MindmapNode node) {
  return node.copyWith(
    status: NodeStatus.someday,
    data: {...node.data, inboxNodeDataKey: false},
    updatedAt: DateTime.now(),
  );
}

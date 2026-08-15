import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';
import 'node_type_payloads.dart';
import 'project_plan.dart';

MindmapNode synchronizeNodeMiniAppProgress(MindmapNode node) {
  return switch (node.type) {
    NodeType.task => _synchronize(
      node,
      node.checklist.isEmpty ? node.progress : node.checklistProgress,
      hasWork: node.checklist.isNotEmpty,
    ),
    NodeType.kanban => _kanban(node),
    NodeType.plan => _plan(node),
    _ => node,
  };
}

MindmapNode _kanban(MindmapNode node) {
  final payload = KanbanPayload.fromNode(node);
  if (payload.cards.isEmpty) return node;
  final doneColumnIds = <String>{
    for (final column in payload.columns)
      if (column.isDoneColumn) column.id,
  };
  final done = payload.cards
      .where((card) => doneColumnIds.contains(card.columnId))
      .length;
  return _synchronize(node, done / payload.cards.length, hasWork: true);
}

MindmapNode _plan(MindmapNode node) {
  final tasks = PlanPayload.fromNode(node).project.tasks;
  if (tasks.isEmpty) return node;
  final done = tasks
      .where((task) => task.status == ProjectTaskStatus.done)
      .length;
  return _synchronize(node, done / tasks.length, hasWork: true);
}

MindmapNode _synchronize(
  MindmapNode node,
  double progress, {
  required bool hasWork,
}) {
  if (!hasWork) return node;
  final completed = progress >= 1;
  return node.copyWith(
    progress: progress,
    isDone: completed,
    status: completed
        ? NodeStatus.done
        : node.status == NodeStatus.done
        ? NodeStatus.doing
        : node.status,
  );
}

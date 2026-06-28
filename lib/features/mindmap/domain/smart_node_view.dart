/// Curated workspace views derived from the complete node index.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import 'mindmap_node.dart';

enum SmartNodeViewType {
  today('Today'),
  open('Open'),
  overdue('Overdue'),
  dueSoon('Due soon'),
  waiting('Waiting'),
  highPriority('High priority'),
  activeGoals('Active goals'),
  routines('Routines'),
  reviews('Reviews'),
  pinned('Pinned'),
  archived('Archived'),
  linked('Linked');

  const SmartNodeViewType(this.label);

  final String label;
}

final class SmartNodeView {
  SmartNodeView({required this.type, required List<MindmapNode> nodes})
    : nodes = List.unmodifiable(nodes);

  final SmartNodeViewType type;
  final List<MindmapNode> nodes;

  String get countLabel => '${type.label} ${nodes.length}';
}

final class SmartNodeViews {
  SmartNodeViews({
    required DateTime today,
    required List<MindmapNode> allNodes,
    required List<SmartNodeView> views,
  }) : today = today.dateOnly,
       allNodes = List.unmodifiable(allNodes),
       views = List.unmodifiable(views);

  factory SmartNodeViews.fromNodes({
    required DateTime today,
    required List<MindmapNode> nodes,
  }) {
    final normalizedToday = today.dateOnly;
    return SmartNodeViews(
      today: normalizedToday,
      allNodes: nodes,
      views: [
        SmartNodeView(
          type: SmartNodeViewType.today,
          nodes: [
            for (final node in nodes)
              if (!node.isArchived && node.day.isSameDay(normalizedToday)) node,
          ],
        ),
        SmartNodeView(
          type: SmartNodeViewType.open,
          nodes: [
            for (final node in nodes)
              if (_isActionable(node)) node,
          ],
        ),
        SmartNodeView(
          type: SmartNodeViewType.overdue,
          nodes: [
            for (final node in nodes)
              if (_isOverdue(node, normalizedToday)) node,
          ],
        ),
        SmartNodeView(
          type: SmartNodeViewType.dueSoon,
          nodes: [
            for (final node in nodes)
              if (_isDueSoon(node, normalizedToday)) node,
          ],
        ),
        SmartNodeView(
          type: SmartNodeViewType.waiting,
          nodes: [
            for (final node in nodes)
              if (_isWaiting(node)) node,
          ],
        ),
        SmartNodeView(
          type: SmartNodeViewType.highPriority,
          nodes: [
            for (final node in nodes)
              if (!node.isArchived &&
                  node.priority.index >= NodePriority.high.index)
                node,
          ],
        ),
        SmartNodeView(
          type: SmartNodeViewType.activeGoals,
          nodes: [
            for (final node in nodes)
              if (_isActiveGoal(node)) node,
          ],
        ),
        SmartNodeView(
          type: SmartNodeViewType.routines,
          nodes: [
            for (final node in nodes)
              if (_isRoutineNode(node)) node,
          ],
        ),
        SmartNodeView(
          type: SmartNodeViewType.reviews,
          nodes: [
            for (final node in nodes)
              if (_isReviewNode(node)) node,
          ],
        ),
        SmartNodeView(
          type: SmartNodeViewType.pinned,
          nodes: [
            for (final node in nodes)
              if (!node.isArchived && node.isPinned) node,
          ],
        ),
        SmartNodeView(
          type: SmartNodeViewType.archived,
          nodes: [
            for (final node in nodes)
              if (node.isArchived) node,
          ],
        ),
        SmartNodeView(
          type: SmartNodeViewType.linked,
          nodes: [
            for (final node in nodes)
              if (!node.isArchived && node.relatedNodeIds.isNotEmpty) node,
          ],
        ),
      ],
    );
  }

  final DateTime today;
  final List<MindmapNode> allNodes;
  final List<SmartNodeView> views;

  SmartNodeView viewFor(SmartNodeViewType type) {
    return views.firstWhere((view) => view.type == type);
  }

  List<MindmapNode> nodesFor(SmartNodeViewType? type) {
    if (type == null) return allNodes;
    return viewFor(type).nodes;
  }
}

bool _isActionable(MindmapNode node) {
  return !node.isArchived && !node.isDone && node.status != NodeStatus.done;
}

bool _isOverdue(MindmapNode node, DateTime today) {
  final dueDate = node.dueDate;
  if (dueDate == null || !_isActionable(node)) return false;
  return dueDate.dateOnly.isBefore(today.dateOnly);
}

bool _isDueSoon(MindmapNode node, DateTime today) {
  final dueDate = node.dueDate?.dateOnly;
  if (dueDate == null || !_isActionable(node)) return false;
  final start = today.dateOnly;
  final end = start.addDays(7);
  return !dueDate.isBefore(start) && !dueDate.isAfter(end);
}

bool _isWaiting(MindmapNode node) {
  return _isActionable(node) && node.status == NodeStatus.waiting;
}

bool _isActiveGoal(MindmapNode node) {
  return node.type == NodeType.goal && _isActionable(node) && node.progress < 1;
}

bool _isRoutineNode(MindmapNode node) {
  if (node.isArchived) return false;
  if (node.tags.contains('routine')) return true;
  final automation = _sectionData(node.data, 'automation');
  final routineId = automation['routineId'];
  return routineId is String && routineId.trim().isNotEmpty;
}

bool _isReviewNode(MindmapNode node) {
  if (node.isArchived || node.type != NodeType.journal) return false;
  final journal = _sectionData(node.data, 'journal');
  return journal['isWeeklyReview'] == true ||
      journal['isMonthlyReview'] == true ||
      node.tags.contains('review') ||
      node.tags.contains('weekly-review') ||
      node.tags.contains('monthly-review');
}

Map<String, Object?> _sectionData(Map<String, Object?> data, String key) {
  final section = data[key];
  if (section is Map) return section.cast<String, Object?>();
  return const {};
}

/// Calendar node filtering predicates.
library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/mindmap_node_data.dart';

final class CalendarNodeFilter {
  const CalendarNodeFilter({
    this.query = '',
    this.project = '',
    this.area = '',
    this.tag = '',
    this.type,
    this.status,
    this.priority,
    this.hasSchedule,
    this.hasJournal,
    this.hasOverdue,
  });

  final String query;
  final String project;
  final String area;
  final String tag;
  final NodeType? type;
  final NodeStatus? status;
  final NodePriority? priority;
  final bool? hasSchedule;
  final bool? hasJournal;
  final bool? hasOverdue;
}

bool matchesCalendarNodeFilter(
  MindmapNode node,
  CalendarNodeFilter filter, {
  required DateTime today,
}) {
  final query = filter.query.trim().toLowerCase();
  if (query.isNotEmpty &&
      !('${node.title} ${node.body} ${node.tags.join(' ')}'.toLowerCase())
          .contains(query)) {
    return false;
  }
  final project = filter.project.trim().toLowerCase();
  if (project.isNotEmpty && !node.project.toLowerCase().contains(project)) {
    return false;
  }
  final area = filter.area.trim().toLowerCase();
  if (area.isNotEmpty && !node.area.toLowerCase().contains(area)) {
    return false;
  }
  final tag = filter.tag.trim().toLowerCase();
  if (tag.isNotEmpty &&
      !node.tags.any((nodeTag) => nodeTag.toLowerCase().contains(tag))) {
    return false;
  }
  if (filter.type != null && node.type != filter.type) return false;
  if (filter.status != null && node.status != filter.status) return false;
  if (filter.priority != null && node.priority != filter.priority) return false;
  if (filter.hasSchedule != null) {
    final scheduled = timeBlockForNode(node).isValid;
    if (scheduled != filter.hasSchedule) return false;
  }
  if (filter.hasJournal != null) {
    final journal = node.type == NodeType.journal;
    if (journal != filter.hasJournal) return false;
  }
  if (filter.hasOverdue != null) {
    final overdue =
        !node.isDone && node.dueDate != null && node.dueDate!.isBefore(today);
    if (overdue != filter.hasOverdue) return false;
  }
  return true;
}

/// Agenda grouping helpers for Calendar page.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/mindmap_node_data.dart';
import '../domain/calendar_node_payload.dart';

enum CalendarAgendaSectionKind {
  overdue,
  priority,
  scheduled,
  tasks,
  habits,
  notes,
}

final class CalendarAgendaSection {
  CalendarAgendaSection({
    required this.kind,
    required this.label,
    required Iterable<MindmapNode> nodes,
  }) : nodes = List.unmodifiable(nodes);

  final CalendarAgendaSectionKind kind;
  final String label;
  final List<MindmapNode> nodes;
}

List<CalendarAgendaSection> buildCalendarAgendaSections({
  required DateTime today,
  required Iterable<MindmapNode> nodes,
}) {
  final normalizedToday = today.dateOnly;
  final buckets = <CalendarAgendaSectionKind, List<MindmapNode>>{
    for (final kind in CalendarAgendaSectionKind.values) kind: <MindmapNode>[],
  };

  for (final node in nodes) {
    if (_isOverdue(node, normalizedToday)) {
      buckets[CalendarAgendaSectionKind.overdue]!.add(node);
    } else if (_isHighPriorityOpen(node)) {
      buckets[CalendarAgendaSectionKind.priority]!.add(node);
    } else if (timeBlockForNode(node).isValid ||
        calendarNodePayloadFromData(node.data) != null) {
      buckets[CalendarAgendaSectionKind.scheduled]!.add(node);
    } else if (node.type == NodeType.task || node.type == NodeType.plan) {
      buckets[CalendarAgendaSectionKind.tasks]!.add(node);
    } else if (node.type == NodeType.habit || node.type == NodeType.routine) {
      buckets[CalendarAgendaSectionKind.habits]!.add(node);
    } else {
      buckets[CalendarAgendaSectionKind.notes]!.add(node);
    }
  }

  return [
    for (final kind in CalendarAgendaSectionKind.values)
      if (buckets[kind]!.isNotEmpty)
        CalendarAgendaSection(
          kind: kind,
          label: _sectionLabel(kind),
          nodes: buckets[kind]!,
        ),
  ];
}

bool _isOverdue(MindmapNode node, DateTime today) {
  final due = node.dueDate?.dateOnly;
  if (due == null || !due.isBefore(today)) return false;
  return !node.isDone && node.status != NodeStatus.done && !node.isArchived;
}

bool _isHighPriorityOpen(MindmapNode node) {
  return node.priority.index >= NodePriority.high.index &&
      !node.isDone &&
      node.status != NodeStatus.done &&
      !node.isArchived;
}

String _sectionLabel(CalendarAgendaSectionKind kind) {
  return switch (kind) {
    CalendarAgendaSectionKind.overdue => 'Overdue',
    CalendarAgendaSectionKind.priority => 'Missions',
    CalendarAgendaSectionKind.scheduled => 'Scheduled',
    CalendarAgendaSectionKind.tasks => 'Tasks',
    CalendarAgendaSectionKind.habits => 'Habits + routines',
    CalendarAgendaSectionKind.notes => 'Notes + journals',
  };
}

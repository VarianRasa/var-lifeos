/// Local carry-over detection for unfinished work before a selected day.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/habit_completion.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/plan_progress.dart';

final class CarryOverCandidate {
  const CarryOverCandidate({required this.node, required this.reason});

  final MindmapNode node;
  final CarryOverReason reason;
}

enum CarryOverReason {
  unfinishedTask,
  incompletePlan,
  missedHabit,
  unfinishedRoutine;

  String get label {
    switch (this) {
      case CarryOverReason.unfinishedTask:
        return 'Unfinished task';
      case CarryOverReason.incompletePlan:
        return 'Incomplete plan';
      case CarryOverReason.missedHabit:
        return 'Missed habit';
      case CarryOverReason.unfinishedRoutine:
        return 'Unfinished routine';
    }
  }
}

enum CarryOverAction {
  moveToDay,
  duplicateToDay,
  reschedule,
  markDone,
  archive,
  splitChecklist,
}

List<CarryOverCandidate> buildCarryOverCandidates({
  required List<MindmapNode> nodes,
  required DateTime selectedDay,
}) {
  final day = selectedDay.dateOnly;
  final candidates = <CarryOverCandidate>[];

  for (final node in nodes) {
    if (node.isArchived || !node.day.dateOnly.isBefore(day)) continue;

    final reason = _carryOverReason(node);
    if (reason == null) continue;

    candidates.add(CarryOverCandidate(node: node, reason: reason));
  }

  candidates.sort((a, b) {
    final priority = _priorityRank(b.node).compareTo(_priorityRank(a.node));
    if (priority != 0) return priority;
    return b.node.day.compareTo(a.node.day);
  });

  return List.unmodifiable(candidates);
}

CarryOverReason? _carryOverReason(MindmapNode node) {
  if (_isComplete(node)) return null;

  switch (node.type) {
    case NodeType.task:
      return CarryOverReason.unfinishedTask;
    case NodeType.plan:
      final steps = planSteps(node);
      if (steps.isEmpty) {
        return node.progress < 1 ? CarryOverReason.incompletePlan : null;
      }
      return nextPlanStep(node) == null ? null : CarryOverReason.incompletePlan;
    case NodeType.habit:
      return hasHabitCompletionOn(node, node.day)
          ? null
          : CarryOverReason.missedHabit;
    case NodeType.routine:
      return CarryOverReason.unfinishedRoutine;
    case NodeType.kanban:
    case NodeType.note:
    case NodeType.journal:
    case NodeType.goal:
    case NodeType.link:
    case NodeType.event:
    case NodeType.decision:
    case NodeType.resource:
    case NodeType.idea:
    case NodeType.question:
    case NodeType.contact:
    case NodeType.metric:
    case NodeType.expense:
    case NodeType.bookmark:
    case NodeType.empty:
      return null;
  }
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}

int _priorityRank(MindmapNode node) {
  switch (node.priority) {
    case NodePriority.urgent:
      return 4;
    case NodePriority.high:
      return 3;
    case NodePriority.medium:
      return 2;
    case NodePriority.low:
      return 1;
    case NodePriority.none:
      return 0;
  }
}

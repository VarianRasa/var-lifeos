/// Deterministic calendar workload balancing helpers.
library;

import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import 'calendar_day_summary.dart';

final class WorkloadMoveSuggestion {
  const WorkloadMoveSuggestion({
    required this.node,
    required this.fromDay,
    required this.toDay,
  });

  final MindmapNode node;
  final DateTime fromDay;
  final DateTime toDay;
}

final class WorkloadBalancePlan {
  const WorkloadBalancePlan({
    required this.moves,
    required this.overloadedDays,
  });

  final List<WorkloadMoveSuggestion> moves;
  final List<DateTime> overloadedDays;
}

WorkloadBalancePlan buildWorkloadBalancePlan({
  required Iterable<DateTime> candidateDays,
  required Iterable<MindmapNode> nodes,
  int overloadThreshold = 6,
}) {
  final days = candidateDays.map((day) => day.dateOnly).toList(growable: false);
  final allNodes = nodes
      .where((node) => !node.isArchived)
      .toList(growable: false);
  final summaries = buildCalendarRangeSummaries(days: days, nodes: allNodes);
  final loads = <DateTime, int>{
    for (final day in days) day: summaries[day]?.openTasks ?? 0,
  };
  final overloadedDays = days
      .where((day) => (loads[day] ?? 0) >= overloadThreshold)
      .toList(growable: false);
  final moves = <WorkloadMoveSuggestion>[];

  for (final day in overloadedDays) {
    final movable = _movableNodesForDay(day, allNodes);
    for (final node in movable) {
      if ((loads[day] ?? 0) < overloadThreshold) break;
      final targetDay = _lightestDay(days, loads, exclude: day);
      if (targetDay == null ||
          (loads[targetDay] ?? 0) >= overloadThreshold - 1) {
        break;
      }
      moves.add(
        WorkloadMoveSuggestion(node: node, fromDay: day, toDay: targetDay),
      );
      loads[day] = (loads[day] ?? 0) - 1;
      loads[targetDay] = (loads[targetDay] ?? 0) + 1;
    }
  }

  return WorkloadBalancePlan(
    moves: List.unmodifiable(moves),
    overloadedDays: List.unmodifiable(overloadedDays),
  );
}

DateTime? _lightestDay(
  List<DateTime> days,
  Map<DateTime, int> loads, {
  required DateTime exclude,
}) {
  DateTime? best;
  var bestLoad = 1 << 30;
  for (final day in days) {
    if (day.isSameDay(exclude)) continue;
    final load = loads[day] ?? 0;
    if (load < bestLoad) {
      best = day;
      bestLoad = load;
    }
  }
  return best;
}

List<MindmapNode> _movableNodesForDay(DateTime day, List<MindmapNode> nodes) {
  final result = nodes
      .where(
        (node) =>
            node.day.isSameDay(day) &&
            !node.isDone &&
            node.priority.index <= NodePriority.medium.index,
      )
      .toList(growable: false);
  return [...result]..sort((a, b) {
    final priorityCompare = a.priority.index.compareTo(b.priority.index);
    if (priorityCompare != 0) return priorityCompare;
    return a.createdAt.compareTo(b.createdAt);
  });
}

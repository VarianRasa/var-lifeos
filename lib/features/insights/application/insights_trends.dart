/// Completion/workload trend helpers for Insights.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

enum InsightTrendDirection { up, down, flat, volatile }

final class InsightTrendPoint {
  const InsightTrendPoint({
    required this.day,
    required this.openTasks,
    required this.completedTasks,
    required this.overdueTasks,
    required this.highPriorityOpenTasks,
  });

  final DateTime day;
  final int openTasks;
  final int completedTasks;
  final int overdueTasks;
  final int highPriorityOpenTasks;
}

final class InsightTrendSeries {
  const InsightTrendSeries({
    required this.points,
    required this.completionDirection,
    required this.openWorkDirection,
    required this.overdueDirection,
    required this.highPriorityDirection,
  });

  final List<InsightTrendPoint> points;
  final InsightTrendDirection completionDirection;
  final InsightTrendDirection openWorkDirection;
  final InsightTrendDirection overdueDirection;
  final InsightTrendDirection highPriorityDirection;

  bool get isEmpty => points.every(
    (point) =>
        point.openTasks == 0 &&
        point.completedTasks == 0 &&
        point.overdueTasks == 0 &&
        point.highPriorityOpenTasks == 0,
  );
}

InsightTrendSeries buildCompletionTrend({
  required DateTime start,
  required DateTime end,
  required DateTime today,
  required Iterable<MindmapNode> nodes,
}) {
  final normalizedStart = start.dateOnly;
  final normalizedEnd = end.dateOnly;
  if (normalizedEnd.isBefore(normalizedStart)) {
    return const InsightTrendSeries(
      points: [],
      completionDirection: InsightTrendDirection.flat,
      openWorkDirection: InsightTrendDirection.flat,
      overdueDirection: InsightTrendDirection.flat,
      highPriorityDirection: InsightTrendDirection.flat,
    );
  }

  final nodesByDay = <String, List<MindmapNode>>{};
  for (final node in nodes) {
    if (node.isArchived || node.type != NodeType.task) continue;
    final nodeDay = node.day.dateOnly;
    if (nodeDay.isBefore(normalizedStart) || nodeDay.isAfter(normalizedEnd)) {
      continue;
    }
    (nodesByDay[dayKey(nodeDay)] ??= []).add(node);
  }

  final points = <InsightTrendPoint>[];
  for (
    var day = normalizedStart;
    !day.isAfter(normalizedEnd);
    day = day.addDays(1)
  ) {
    var openTasks = 0;
    var completedTasks = 0;
    var overdueTasks = 0;
    var highPriorityOpenTasks = 0;
    for (final node in nodesByDay[dayKey(day)] ?? const <MindmapNode>[]) {
      final complete = _isComplete(node);
      if (complete) {
        completedTasks++;
      } else {
        openTasks++;
        if (node.priority.index >= NodePriority.high.index) {
          highPriorityOpenTasks++;
        }
      }
      if (!complete &&
          node.dueDate != null &&
          node.dueDate!.dateOnly.isBefore(today.dateOnly)) {
        overdueTasks++;
      }
    }
    points.add(
      InsightTrendPoint(
        day: day,
        openTasks: openTasks,
        completedTasks: completedTasks,
        overdueTasks: overdueTasks,
        highPriorityOpenTasks: highPriorityOpenTasks,
      ),
    );
  }

  return InsightTrendSeries(
    points: List.unmodifiable(points),
    completionDirection: classifyInsightTrend(
      points.map((point) => point.completedTasks).toList(growable: false),
    ),
    openWorkDirection: classifyInsightTrend(
      points.map((point) => point.openTasks).toList(growable: false),
    ),
    overdueDirection: classifyInsightTrend(
      points.map((point) => point.overdueTasks).toList(growable: false),
    ),
    highPriorityDirection: classifyInsightTrend(
      points
          .map((point) => point.highPriorityOpenTasks)
          .toList(growable: false),
    ),
  );
}

InsightTrendDirection classifyInsightTrend(List<int> values) {
  if (values.length < 2 || values.every((value) => value == values.first)) {
    return InsightTrendDirection.flat;
  }

  var increases = 0;
  var decreases = 0;
  for (var index = 1; index < values.length; index++) {
    final previous = values[index - 1];
    final current = values[index];
    if (current > previous) increases++;
    if (current < previous) decreases++;
  }

  if (increases > 0 && decreases > 0) {
    final smaller = increases < decreases ? increases : decreases;
    final larger = increases > decreases ? increases : decreases;
    if (smaller / larger >= 0.5) return InsightTrendDirection.volatile;
  }
  if (increases > decreases) return InsightTrendDirection.up;
  if (decreases > increases) return InsightTrendDirection.down;
  return InsightTrendDirection.volatile;
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}

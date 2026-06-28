/// Aggregate counts for a calendar day.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import 'mindmap_node.dart';

final class DayNodeSummary {
  DayNodeSummary({
    required DateTime day,
    required Map<NodeType, int> countsByType,
    this.doneCount = 0,
    this.openCount = 0,
    this.highPriorityCount = 0,
    this.overdueCount = 0,
  }) : day = day.dateOnly,
       countsByType = Map.unmodifiable(countsByType);

  factory DayNodeSummary.fromNodes(DateTime day, Iterable<MindmapNode> nodes) {
    final counts = <NodeType, int>{};
    var doneCount = 0;
    var openCount = 0;
    var highPriorityCount = 0;
    var overdueCount = 0;
    final dayOnly = day.dateOnly;
    for (final node in nodes) {
      counts[node.type] = (counts[node.type] ?? 0) + 1;
      if (node.isDone) {
        doneCount++;
      } else {
        openCount++;
      }
      if (node.priority.index >= NodePriority.high.index) {
        highPriorityCount++;
      }
      final due = node.dueDate;
      if (!node.isDone &&
          due != null &&
          due.dateOnly.isBefore(dayOnly) &&
          node.day.dateOnly.isAtSameMomentAs(dayOnly)) {
        overdueCount++;
      }
    }
    return DayNodeSummary(
      day: day,
      countsByType: counts,
      doneCount: doneCount,
      openCount: openCount,
      highPriorityCount: highPriorityCount,
      overdueCount: overdueCount,
    );
  }

  final DateTime day;
  final Map<NodeType, int> countsByType;
  final int doneCount;
  final int openCount;
  final int highPriorityCount;
  final int overdueCount;

  int get totalCount =>
      countsByType.values.fold(0, (sum, count) => sum + count);

  bool get hasNodes => totalCount > 0;

  int countFor(NodeType type) => countsByType[type] ?? 0;
}

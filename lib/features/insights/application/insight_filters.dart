/// Insight range/filter state and predicates.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

enum InsightRangePreset { today, sevenDays, thirtyDays, thisMonth }

final class InsightDateRange {
  const InsightDateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool contains(DateTime day) {
    final value = day.dateOnly;
    return !value.isBefore(start) && !value.isAfter(end);
  }
}

final class InsightFilterState {
  const InsightFilterState({
    this.project,
    this.area,
    this.tag,
    this.nodeType,
    this.priority,
    this.status,
  });

  final String? project;
  final String? area;
  final String? tag;
  final NodeType? nodeType;
  final NodePriority? priority;
  final NodeStatus? status;

  bool get isEmpty =>
      project == null &&
      area == null &&
      tag == null &&
      nodeType == null &&
      priority == null &&
      status == null;
}

InsightDateRange insightDateRangeForPreset({
  required InsightRangePreset preset,
  required DateTime today,
}) {
  final end = today.dateOnly;
  switch (preset) {
    case InsightRangePreset.today:
      return InsightDateRange(start: end, end: end);
    case InsightRangePreset.sevenDays:
      return InsightDateRange(start: end.addDays(-6), end: end);
    case InsightRangePreset.thirtyDays:
      return InsightDateRange(start: end.addDays(-29), end: end);
    case InsightRangePreset.thisMonth:
      return InsightDateRange(start: end.firstOfMonth, end: end);
  }
}

bool matchesInsightFilter(
  MindmapNode node,
  InsightFilterState filter, {
  InsightDateRange? range,
}) {
  if (node.isArchived) return false;
  if (range != null && !range.contains(node.day)) return false;
  if (filter.project != null && node.project != filter.project) return false;
  if (filter.area != null && node.area != filter.area) return false;
  if (filter.tag != null && !node.tags.contains(filter.tag)) return false;
  if (filter.nodeType != null && node.type != filter.nodeType) return false;
  if (filter.priority != null && node.priority != filter.priority) return false;
  if (filter.status != null && node.status != filter.status) return false;
  return true;
}

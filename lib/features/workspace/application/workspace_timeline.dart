import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/workspace_context.dart';

final class WorkspaceTimelineSummary {
  const WorkspaceTimelineSummary({
    required this.overdue,
    required this.dueToday,
    required this.dueThisWeek,
    required this.upcoming30Days,
    required this.completedRecently,
    required this.activityByDay,
  });

  final List<MindmapNode> overdue;
  final List<MindmapNode> dueToday;
  final List<MindmapNode> dueThisWeek;
  final List<MindmapNode> upcoming30Days;
  final List<MindmapNode> completedRecently;
  final Map<String, int> activityByDay;
}

WorkspaceTimelineSummary buildWorkspaceTimeline(
  WorkspaceContext workspace,
  DateTime today,
) {
  final normalized = today.dateOnly;
  final weekEnd = normalized.add(const Duration(days: 7));
  final monthEnd = normalized.add(const Duration(days: 30));
  final recentStart = normalized.subtract(const Duration(days: 7));
  final overdue = <MindmapNode>[];
  final dueToday = <MindmapNode>[];
  final dueThisWeek = <MindmapNode>[];
  final upcoming = <MindmapNode>[];
  final completed = <MindmapNode>[];
  final activity = <String, int>{};

  for (final node in workspace.activeNodes) {
    activity[dayKey(node.updatedAt)] =
        (activity[dayKey(node.updatedAt)] ?? 0) + 1;
    final done = node.isDone || node.status == NodeStatus.done;
    if (done && !node.updatedAt.dateOnly.isBefore(recentStart)) {
      completed.add(node);
    }
    final due = node.dueDate?.dateOnly;
    if (due == null || done) continue;
    if (due.isBefore(normalized)) overdue.add(node);
    if (due == normalized) dueToday.add(node);
    if (due.isAfter(normalized) && !due.isAfter(weekEnd)) dueThisWeek.add(node);
    if (due.isAfter(weekEnd) && !due.isAfter(monthEnd)) upcoming.add(node);
  }
  int compareDue(MindmapNode a, MindmapNode b) =>
      (a.dueDate ?? a.day).compareTo(b.dueDate ?? b.day);
  overdue.sort(compareDue);
  dueToday.sort(compareDue);
  dueThisWeek.sort(compareDue);
  upcoming.sort(compareDue);
  completed.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return WorkspaceTimelineSummary(
    overdue: overdue,
    dueToday: dueToday,
    dueThisWeek: dueThisWeek,
    upcoming30Days: upcoming,
    completedRecently: completed,
    activityByDay: Map.unmodifiable(activity),
  );
}

import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/workspace_context.dart';
import 'workspace_overview.dart';

final class WorkspaceHealthSummary {
  const WorkspaceHealthSummary({
    required this.status,
    required this.active,
    required this.done,
    required this.blocked,
    required this.waiting,
    required this.overdue,
    required this.highPriority,
    required this.lastActivity,
    required this.tags,
    required this.progress,
  });

  final WorkspaceHealthStatus status;
  final int active;
  final int done;
  final int blocked;
  final int waiting;
  final int overdue;
  final int highPriority;
  final DateTime? lastActivity;
  final List<String> tags;
  final double progress;
}

WorkspaceHealthSummary buildWorkspaceHealth(
  WorkspaceContext workspace,
  DateTime today,
) {
  final activeNodes = workspace.activeNodes;
  final open = activeNodes.where(
    (node) => !node.isDone && node.status != NodeStatus.done,
  );
  DateTime? latest;
  final tags = <String, int>{};
  for (final node in activeNodes) {
    if (latest == null || node.updatedAt.isAfter(latest)) {
      latest = node.updatedAt;
    }
    for (final tag in node.tags) {
      tags[tag] = (tags[tag] ?? 0) + 1;
    }
  }
  final sortedTags = tags.entries.toList()
    ..sort((a, b) {
      final count = b.value.compareTo(a.value);
      return count != 0 ? count : a.key.compareTo(b.key);
    });
  return WorkspaceHealthSummary(
    status: classifyWorkspaceHealth(workspace, today),
    active: open.length,
    done: activeNodes
        .where((node) => node.isDone || node.status == NodeStatus.done)
        .length,
    blocked: open.where((node) => _isBlocked(node)).length,
    waiting: open.where((node) => node.status == NodeStatus.waiting).length,
    overdue: workspace.overdueCount(today),
    highPriority: open
        .where((node) => node.priority.index >= NodePriority.high.index)
        .length,
    lastActivity: latest,
    tags: sortedTags.take(5).map((entry) => entry.key).toList(growable: false),
    progress: workspace.averageProgress,
  );
}

bool _isBlocked(MindmapNode node) {
  final blocked = node.data['blocked'] ?? node.data['isBlocked'];
  return blocked == true ||
      node.tags.any((tag) => tag.toLowerCase() == 'blocked');
}

String workspaceLastActivityLabel(DateTime? date, DateTime today) {
  if (date == null) return 'No activity';
  final days = today.dateOnly.difference(date.dateOnly).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return '$days days ago';
}

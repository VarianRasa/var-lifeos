/// Goal and milestone progress insights.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/goal_progress.dart';
import '../../mindmap/domain/life_os_summary.dart';
import '../../mindmap/domain/mindmap_node.dart';

final class GoalProgressItem {
  const GoalProgressItem({
    required this.node,
    required this.progress,
    required this.milestoneCount,
    required this.completedMilestoneCount,
    required this.nextMilestone,
    required this.isStalled,
    required this.recentlyProgressed,
    required this.needsNextAction,
  });

  final MindmapNode node;
  final double progress;
  final int milestoneCount;
  final int completedMilestoneCount;
  final String? nextMilestone;
  final bool isStalled;
  final bool recentlyProgressed;
  final bool needsNextAction;
}

final class GoalInsightSummary {
  const GoalInsightSummary({
    required this.goalCount,
    required this.averageProgress,
    required this.notStartedCount,
    required this.inProgressCount,
    required this.completedCount,
    required this.stalledGoals,
    required this.recentlyProgressedGoals,
    required this.needsNextActionGoals,
    required this.milestoneMomentumCount,
    required this.items,
  });

  final int goalCount;
  final double averageProgress;
  final int notStartedCount;
  final int inProgressCount;
  final int completedCount;
  final List<GoalProgressItem> stalledGoals;
  final List<GoalProgressItem> recentlyProgressedGoals;
  final List<GoalProgressItem> needsNextActionGoals;
  final int milestoneMomentumCount;
  final List<GoalProgressItem> items;
}

GoalInsightSummary buildGoalInsightSummary({
  required DateTime today,
  required Iterable<MindmapNode> nodes,
}) {
  final normalizedToday = today.dateOnly;
  final allNodes = nodes.toList(growable: false);
  final openTaskIds = {
    for (final node in allNodes)
      if (node.type == NodeType.task && !node.isArchived && !_isComplete(node))
        node.id,
  };
  final items = <GoalProgressItem>[];
  for (final node in allNodes) {
    if (node.isArchived || node.type != NodeType.goal) continue;
    final progress = goalProgressFor(node);
    final milestones = goalMilestones(node);
    final completed = completedGoalMilestones(node);
    final next = nextGoalMilestone(node);
    final daysSinceUpdate = normalizedToday
        .difference(node.updatedAt.dateOnly)
        .inDays;
    final isComplete = _isComplete(node) || progress >= 1;
    items.add(
      GoalProgressItem(
        node: node,
        progress: progress,
        milestoneCount: milestones.length,
        completedMilestoneCount: completed.length,
        nextMilestone: next,
        isStalled: !isComplete && progress < 1 && daysSinceUpdate >= 14,
        recentlyProgressed: !isComplete && progress > 0 && daysSinceUpdate <= 7,
        needsNextAction:
            !isComplete && !node.relatedNodeIds.any(openTaskIds.contains),
      ),
    );
  }

  items.sort((a, b) {
    final stalledCompare = _boolRank(
      b.isStalled,
    ).compareTo(_boolRank(a.isStalled));
    if (stalledCompare != 0) return stalledCompare;
    final progressCompare = a.progress.compareTo(b.progress);
    if (progressCompare != 0) return progressCompare;
    return a.node.title.compareTo(b.node.title);
  });

  final totalProgress = items.fold<double>(
    0,
    (sum, item) => sum + item.progress,
  );
  final stalled = [
    for (final item in items)
      if (item.isStalled) item,
  ];
  final recent = [
    for (final item in items)
      if (item.recentlyProgressed) item,
  ]..sort((a, b) => b.node.updatedAt.compareTo(a.node.updatedAt));
  final needsAction = [
    for (final item in items)
      if (item.needsNextAction) item,
  ];

  return GoalInsightSummary(
    goalCount: items.length,
    averageProgress: items.isEmpty ? 0 : totalProgress / items.length,
    notStartedCount: items.where((item) => item.progress <= 0).length,
    inProgressCount: items
        .where((item) => item.progress > 0 && item.progress < 1)
        .length,
    completedCount: items.where((item) => item.progress >= 1).length,
    stalledGoals: List.unmodifiable(stalled.take(5)),
    recentlyProgressedGoals: List.unmodifiable(recent.take(5)),
    needsNextActionGoals: List.unmodifiable(needsAction.take(5)),
    milestoneMomentumCount: recent.fold<int>(
      0,
      (sum, item) => sum + item.completedMilestoneCount,
    ),
    items: List.unmodifiable(items),
  );
}

double goalProgressFor(MindmapNode node) {
  if (node.type != NodeType.goal) return 0;
  return LifeOsSummary.goalProgressFor(node).clamp(0, 1).toDouble();
}

int _boolRank(bool value) => value ? 1 : 0;

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}

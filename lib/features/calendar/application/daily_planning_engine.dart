/// Deterministic local planning suggestions for the day page.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import 'carry_over_planner.dart';
import 'daily_review_builder.dart';

final class DailyPlanningContext {
  const DailyPlanningContext({
    required this.day,
    required this.allNodes,
    required this.dayNodes,
    this.readyRoutineCount = 0,
  });

  final DateTime day;
  final List<MindmapNode> allNodes;
  final List<MindmapNode> dayNodes;
  final int readyRoutineCount;
}

enum DailyPlanningActionType {
  applyRoutines,
  carryOver,
  reviewOverdue,
  rescheduleLowPriority,
  createGoalNextAction,
  applyTemplate,
  startDailyReview,
  createTomorrowTopTasks,
}

enum DailyPlanningSeverity { info, action, warning }

final class DailyPlanningSuggestionModel {
  const DailyPlanningSuggestionModel({
    required this.type,
    required this.label,
    required this.severity,
    this.nodeId,
    this.count = 0,
    this.payload = const <String>[],
  });

  final DailyPlanningActionType type;
  final String label;
  final DailyPlanningSeverity severity;
  final String? nodeId;
  final int count;
  final List<String> payload;
}

List<DailyPlanningSuggestionModel> buildDailyPlanningSuggestions(
  DailyPlanningContext context,
) {
  final day = context.day.dateOnly;
  final dailyReview = _dailyReviewNode(day, context.dayNodes);
  final tomorrowTop3 = dailyReview == null
      ? const <String>[]
      : extractTomorrowTop3(dailyReview.body);
  final carryOverCandidates = buildCarryOverCandidates(
    nodes: context.allNodes,
    selectedDay: day,
  );
  final overdueTasks = carryOverCandidates
      .where(
        (candidate) =>
            candidate.node.type == NodeType.task &&
            candidate.node.dueDate != null &&
            candidate.node.dueDate!.dateOnly.isBefore(day),
      )
      .map((candidate) => candidate.node)
      .take(3)
      .toList();
  final lowPriorityCarryOverCandidates = carryOverCandidates
      .where(
        (candidate) =>
            candidate.node.priority == NodePriority.low ||
            candidate.node.priority == NodePriority.none,
      )
      .toList();
  final unpinnedGoal = context.allNodes
      .where(
        (node) =>
            node.type == NodeType.goal &&
            !node.isArchived &&
            !node.isDone &&
            !node.isPinned,
      )
      .cast<MindmapNode?>()
      .firstWhere((node) => node != null, orElse: () => null);

  return [
    if (context.readyRoutineCount > 0)
      DailyPlanningSuggestionModel(
        type: DailyPlanningActionType.applyRoutines,
        label: context.readyRoutineCount == 1
            ? 'Apply 1 routine'
            : 'Apply ${context.readyRoutineCount} routines',
        severity: DailyPlanningSeverity.action,
        count: context.readyRoutineCount,
      ),
    if (carryOverCandidates.isNotEmpty)
      DailyPlanningSuggestionModel(
        type: DailyPlanningActionType.carryOver,
        label: 'Carry over ${carryOverCandidates.length} items',
        severity: DailyPlanningSeverity.action,
        count: carryOverCandidates.length,
      ),
    if (overdueTasks.isNotEmpty)
      DailyPlanningSuggestionModel(
        type: DailyPlanningActionType.reviewOverdue,
        label: 'Review overdue',
        severity: DailyPlanningSeverity.warning,
        count: overdueTasks.length,
        payload: [for (final node in overdueTasks) node.id],
      ),
    if (lowPriorityCarryOverCandidates.isNotEmpty)
      DailyPlanningSuggestionModel(
        type: DailyPlanningActionType.rescheduleLowPriority,
        label: 'Reschedule low priority',
        severity: DailyPlanningSeverity.info,
        count: lowPriorityCarryOverCandidates.length,
        payload: [
          for (final candidate in lowPriorityCarryOverCandidates)
            candidate.node.id,
        ],
      ),
    if (unpinnedGoal != null)
      DailyPlanningSuggestionModel(
        type: DailyPlanningActionType.createGoalNextAction,
        label: 'Next action: ${unpinnedGoal.title}',
        severity: DailyPlanningSeverity.action,
        nodeId: unpinnedGoal.id,
      ),
    const DailyPlanningSuggestionModel(
      type: DailyPlanningActionType.applyTemplate,
      label: 'Apply template',
      severity: DailyPlanningSeverity.info,
    ),
    if (dailyReview == null)
      const DailyPlanningSuggestionModel(
        type: DailyPlanningActionType.startDailyReview,
        label: 'Start daily review',
        severity: DailyPlanningSeverity.info,
      )
    else if (tomorrowTop3.isNotEmpty)
      DailyPlanningSuggestionModel(
        type: DailyPlanningActionType.createTomorrowTopTasks,
        label: 'Create tomorrow top ${tomorrowTop3.length}',
        severity: DailyPlanningSeverity.action,
        nodeId: dailyReview.id,
        count: tomorrowTop3.length,
        payload: tomorrowTop3,
      ),
  ];
}

MindmapNode? _dailyReviewNode(DateTime day, List<MindmapNode> dayNodes) {
  for (final node in dayNodes) {
    final journalData = node.data['journal'];
    final isDailyReview =
        node.type == NodeType.journal &&
        (node.tags.contains('daily-review') ||
            node.title == dailyReviewTitle(day) ||
            (journalData is Map && journalData['isDailyReview'] == true));
    if (isDailyReview) return node;
  }
  return null;
}

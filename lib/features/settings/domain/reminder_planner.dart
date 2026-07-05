/// Pure reminder planning for settings previews and future notification adapters.
library;

import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/recurring_routine.dart';

final class ReminderPlannerOptions {
  const ReminderPlannerOptions({
    required this.today,
    required this.lookaheadDays,
    required this.dueRemindersEnabled,
    required this.routineRemindersEnabled,
  });

  final DateTime today;
  final int lookaheadDays;
  final bool dueRemindersEnabled;
  final bool routineRemindersEnabled;
}

enum ReminderPlanItemKind { dueNode, routine }

final class ReminderPlanItem {
  const ReminderPlanItem.dueNode({
    required this.node,
    required this.day,
    this.isOverdue = false,
  }) : kind = ReminderPlanItemKind.dueNode,
       routine = null;

  const ReminderPlanItem.routine({required this.routine, required this.day})
    : kind = ReminderPlanItemKind.routine,
      node = null,
      isOverdue = false;

  final ReminderPlanItemKind kind;
  final MindmapNode? node;
  final RecurringNodeRoutine? routine;
  final DateTime day;
  final bool isOverdue;

  String get title => switch (kind) {
    ReminderPlanItemKind.dueNode => node!.title,
    ReminderPlanItemKind.routine => routine!.label,
  };
}

final class ReminderPlan {
  const ReminderPlan({required this.items});

  final List<ReminderPlanItem> items;

  Iterable<ReminderPlanItem> get dueNodes {
    return items.where((item) => item.kind == ReminderPlanItemKind.dueNode);
  }

  Iterable<ReminderPlanItem> get routines {
    return items.where((item) => item.kind == ReminderPlanItemKind.routine);
  }

  Iterable<ReminderPlanItem> get overdue {
    return dueNodes.where((item) => item.isOverdue);
  }

  Map<DateTime, List<ReminderPlanItem>> get groupedByDay {
    final grouped = <DateTime, List<ReminderPlanItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.day.dateOnly, () => []).add(item);
    }
    return Map.unmodifiable(grouped);
  }
}

ReminderPlan buildReminderPlan({
  required Iterable<MindmapNode> nodes,
  required Iterable<RecurringNodeRoutine> routines,
  required ReminderPlannerOptions options,
}) {
  final today = options.today.dateOnly;
  final end = today.add(Duration(days: options.lookaheadDays));
  final items = <ReminderPlanItem>[];

  if (options.dueRemindersEnabled) {
    final dueNodes =
        nodes
            .where(
              (node) =>
                  !node.isArchived &&
                  !node.isDone &&
                  node.dueDate != null &&
                  !node.dueDate!.dateOnly.isAfter(end),
            )
            .toList()
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    items.addAll([
      for (final node in dueNodes)
        ReminderPlanItem.dueNode(
          node: node,
          day: node.dueDate!.dateOnly.isBefore(today)
              ? today
              : node.dueDate!.dateOnly,
          isOverdue: node.dueDate!.dateOnly.isBefore(today),
        ),
    ]);
  }

  if (options.routineRemindersEnabled) {
    for (var offset = 0; offset <= options.lookaheadDays; offset++) {
      final day = today.add(Duration(days: offset));
      final plan = RecurringRoutinePlan.fromRoutines(
        day: day,
        existingNodes: nodes,
        routines: routines,
      );
      items.addAll([
        for (final item in plan.items)
          if (item.status == RecurringRoutinePlanItemStatus.ready)
            ReminderPlanItem.routine(routine: item.routine, day: day),
      ]);
    }
  }

  items.sort((a, b) => a.day.compareTo(b.day));
  return ReminderPlan(items: List.unmodifiable(items));
}

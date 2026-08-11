/// Pure reminder planning for settings previews and future notification adapters.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_mini_app_data.dart';
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

enum ReminderPlanItemKind { dueNode, routine, habit }

final class ReminderPlanItem {
  const ReminderPlanItem.dueNode({
    required this.node,
    required this.day,
    this.isOverdue = false,
  }) : kind = ReminderPlanItemKind.dueNode,
       routine = null,
       scheduledAt = null;

  const ReminderPlanItem.routine({required this.routine, required this.day})
    : kind = ReminderPlanItemKind.routine,
      node = null,
      scheduledAt = null,
      isOverdue = false;

  const ReminderPlanItem.habit({
    required this.node,
    required this.day,
    required this.scheduledAt,
  }) : kind = ReminderPlanItemKind.habit,
       routine = null,
       isOverdue = false;

  final ReminderPlanItemKind kind;
  final MindmapNode? node;
  final RecurringNodeRoutine? routine;
  final DateTime day;
  final DateTime? scheduledAt;
  final bool isOverdue;

  String get title => switch (kind) {
    ReminderPlanItemKind.dueNode || ReminderPlanItemKind.habit => node!.title,
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

  Iterable<ReminderPlanItem> get habits {
    return items.where((item) => item.kind == ReminderPlanItemKind.habit);
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

  for (final node in nodes) {
    if (node.isArchived ||
        node.isDone ||
        (node.type != NodeType.habit && node.type != NodeType.routine)) {
      continue;
    }
    final section = nodeMiniAppSection(node, 'habit');
    if (section['reminderEnabled'] != true) continue;
    final time = _reminderTime(section['reminderTime']);
    if (time == null) continue;
    for (var offset = 0; offset <= options.lookaheadDays; offset++) {
      final day = today.add(Duration(days: offset));
      if (day.isBefore(node.day.dateOnly)) continue;
      final scheduledAt = DateTime(
        day.year,
        day.month,
        day.day,
        time.$1,
        time.$2,
      );
      if (!scheduledAt.isAfter(options.today)) continue;
      items.add(
        ReminderPlanItem.habit(node: node, day: day, scheduledAt: scheduledAt),
      );
    }
  }

  items.sort((a, b) {
    final day = a.day.compareTo(b.day);
    if (day != 0) return day;
    return (a.scheduledAt ?? a.day).compareTo(b.scheduledAt ?? b.day);
  });
  return ReminderPlan(items: List.unmodifiable(items));
}

(int, int)? _reminderTime(Object? value) {
  final text = value == null ? '08:00' : value.toString().trim();
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  return hour <= 23 && minute <= 59 ? (hour, minute) : null;
}

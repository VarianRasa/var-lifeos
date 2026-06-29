/// Recurring routines built from reusable node templates.
library;

import '../../../core/utils/date_utils.dart';
import 'canvas_position.dart';
import 'mindmap_node.dart';
import 'node_template.dart';

enum RecurringFrequency { daily, weekly, monthly }

final class RecurringRule {
  const RecurringRule._({
    required this.frequency,
    this.weekday,
    this.dayOfMonth,
  });

  factory RecurringRule.daily() {
    return const RecurringRule._(frequency: RecurringFrequency.daily);
  }

  factory RecurringRule.weekly({required int weekday}) {
    return RecurringRule._(
      frequency: RecurringFrequency.weekly,
      weekday: weekday,
    );
  }

  factory RecurringRule.monthly({required int dayOfMonth}) {
    return RecurringRule._(
      frequency: RecurringFrequency.monthly,
      dayOfMonth: dayOfMonth,
    );
  }

  final RecurringFrequency frequency;
  final int? weekday;
  final int? dayOfMonth;

  bool isDueOn(DateTime day) {
    final normalizedDay = day.dateOnly;
    return switch (frequency) {
      RecurringFrequency.daily => true,
      RecurringFrequency.weekly => normalizedDay.weekday == weekday,
      RecurringFrequency.monthly => normalizedDay.day == dayOfMonth,
    };
  }
}

final class RecurringNodeRoutine {
  const RecurringNodeRoutine({
    required this.id,
    required this.label,
    required this.template,
    required this.rule,
    this.nodeTitle,
  });

  final String id;
  final String label;
  final NodeTemplate template;
  final RecurringRule rule;
  final String? nodeTitle;

  bool isDueOn(DateTime day) => rule.isDueOn(day);
}

final defaultRecurringRoutines = List<RecurringNodeRoutine>.unmodifiable([
  RecurringNodeRoutine(
    id: 'daily-plan',
    label: 'Daily plan',
    template: nodeTemplateById('daily-plan'),
    rule: RecurringRule.daily(),
  ),
  RecurringNodeRoutine(
    id: 'daily-journal',
    label: 'Daily journal',
    template: nodeTemplateById('daily-journal'),
    rule: RecurringRule.daily(),
  ),
  RecurringNodeRoutine(
    id: 'workout-habit',
    label: 'Workout habit',
    template: nodeTemplateById('workout-habit'),
    rule: RecurringRule.daily(),
  ),
  RecurringNodeRoutine(
    id: 'weekly-review',
    label: 'Weekly review',
    template: nodeTemplateById('weekly-review'),
    rule: RecurringRule.weekly(weekday: DateTime.monday),
  ),
  RecurringNodeRoutine(
    id: 'monthly-review',
    label: 'Monthly review',
    template: nodeTemplateById('monthly-review'),
    rule: RecurringRule.monthly(dayOfMonth: 1),
  ),
]);

enum RecurringRoutinePlanItemStatus {
  ready,
  skippedExisting,
  skippedToday,
  snoozedToday,
  notDue,
}

final class RecurringRoutinePlanItem {
  const RecurringRoutinePlanItem({
    required this.routine,
    required this.status,
    this.node,
  }) : assert(
         status == RecurringRoutinePlanItemStatus.ready
             ? node != null
             : node == null,
       );

  final RecurringNodeRoutine routine;
  final RecurringRoutinePlanItemStatus status;
  final MindmapNode? node;

  bool get willCreate => status == RecurringRoutinePlanItemStatus.ready;

  String get statusLabel => switch (status) {
    RecurringRoutinePlanItemStatus.ready => 'Ready',
    RecurringRoutinePlanItemStatus.skippedExisting => 'Already exists',
    RecurringRoutinePlanItemStatus.skippedToday => 'Skipped today',
    RecurringRoutinePlanItemStatus.snoozedToday => 'Snoozed',
    RecurringRoutinePlanItemStatus.notDue => 'Not due',
  };
}

final class RecurringRoutinePlan {
  const RecurringRoutinePlan({required this.items});

  factory RecurringRoutinePlan.fromRoutines({
    required DateTime day,
    required Iterable<MindmapNode> existingNodes,
    required Iterable<RecurringNodeRoutine> routines,
    DateTime? now,
    bool forceDue = false,
  }) {
    final normalizedDay = day.dateOnly;
    final timestamp = now ?? DateTime.now();
    final existing = existingNodes.toList(growable: false);
    final items = <RecurringRoutinePlanItem>[];
    var readyIndex = 0;

    for (final routine in routines) {
      final isDue =
          forceDue ||
          routine.isDueOn(normalizedDay) ||
          _isSnoozedIntoDay(existing, routine, normalizedDay);
      if (!isDue) {
        items.add(
          RecurringRoutinePlanItem(
            routine: routine,
            status: RecurringRoutinePlanItemStatus.notDue,
          ),
        );
        continue;
      }

      final existingStatus = _existingRoutineStatus(
        existing,
        routine,
        normalizedDay,
      );
      if (existingStatus != null) {
        items.add(
          RecurringRoutinePlanItem(routine: routine, status: existingStatus),
        );
        continue;
      }

      final node = _nodeFromRoutine(
        routine,
        normalizedDay,
        timestamp,
        readyIndex,
      );
      readyIndex++;
      items.add(
        RecurringRoutinePlanItem(
          routine: routine,
          status: RecurringRoutinePlanItemStatus.ready,
          node: node,
        ),
      );
    }

    return RecurringRoutinePlan(items: List.unmodifiable(items));
  }

  final List<RecurringRoutinePlanItem> items;

  List<MindmapNode> get nodes {
    return List.unmodifiable([
      for (final item in items)
        if (item.node != null) item.node!,
    ]);
  }

  int get readyCount => _countItems(RecurringRoutinePlanItemStatus.ready);

  int get skippedCount {
    return _countItems(RecurringRoutinePlanItemStatus.skippedExisting);
  }

  int get skippedTodayCount {
    return _countItems(RecurringRoutinePlanItemStatus.skippedToday);
  }

  int get snoozedTodayCount {
    return _countItems(RecurringRoutinePlanItemStatus.snoozedToday);
  }

  int get notDueCount => _countItems(RecurringRoutinePlanItemStatus.notDue);

  int _countItems(RecurringRoutinePlanItemStatus status) {
    return items.where((item) => item.status == status).length;
  }
}

MindmapNode _nodeFromRoutine(
  RecurringNodeRoutine routine,
  DateTime day,
  DateTime now,
  int index,
) {
  final template = routine.template;
  return MindmapNode.create(
    id: 'routine-${routine.id}-${dayKey(day)}',
    type: template.type,
    title: routine.nodeTitle ?? template.title,
    body: template.body,
    day: day,
    position: CanvasPosition(-180 + (index * 120), 230 + (index * 34)),
    status: template.status,
    priority: template.priority,
    project: template.project,
    area: template.area,
    tags: [...template.tags, 'routine'],
    progress: template.progress,
    checklist: [
      for (var index = 0; index < template.checklist.length; index++)
        TaskChecklistItem(
          id: 'routine-${routine.id}-item-${index + 1}',
          title: template.checklist[index],
        ),
    ],
    data: {
      ...template.data,
      'automation': {
        'routineId': routine.id,
        'templateId': template.id,
        'recurrence': routine.rule.frequency.name,
      },
    },
    now: now,
  );
}

RecurringRoutinePlanItemStatus? _existingRoutineStatus(
  List<MindmapNode> nodes,
  RecurringNodeRoutine routine,
  DateTime day,
) {
  final routineNodeId = 'routine-${routine.id}-${dayKey(day)}';
  final template = routine.template;
  var hasSkipMarker = false;
  var hasSnoozeMarker = false;

  for (final node in nodes) {
    if (!node.day.isSameDay(day)) continue;
    if (node.id == routineNodeId) {
      return RecurringRoutinePlanItemStatus.skippedExisting;
    }
    final automation = node.data['automation'];
    if (automation is Map && automation['routineId'] == routine.id) {
      if (automation['state'] == 'skipped') {
        hasSkipMarker = true;
        continue;
      }
      if (automation['state'] == 'snoozed') {
        hasSnoozeMarker = true;
        continue;
      }
      return RecurringRoutinePlanItemStatus.skippedExisting;
    }
    if (node.type == template.type && node.title == template.title) {
      return RecurringRoutinePlanItemStatus.skippedExisting;
    }
  }
  if (hasSkipMarker) return RecurringRoutinePlanItemStatus.skippedToday;
  if (hasSnoozeMarker) return RecurringRoutinePlanItemStatus.snoozedToday;
  return null;
}

bool _isSnoozedIntoDay(
  List<MindmapNode> nodes,
  RecurringNodeRoutine routine,
  DateTime day,
) {
  final targetKey = dayKey(day);
  for (final node in nodes) {
    final automation = node.data['automation'];
    if (automation is! Map) continue;
    if (automation['routineId'] != routine.id) continue;
    if (automation['state'] != 'snoozed') continue;
    if (automation['snoozedTo'] == targetKey) return true;
  }
  return false;
}

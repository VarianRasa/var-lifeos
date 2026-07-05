/// Application use case for applying due recurring routines to a day.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/automation_rule.dart';
import '../domain/mindmap_node.dart';
import '../domain/mindmap_repository.dart';
import '../domain/recurring_routine.dart';

Future<List<RecurringNodeRoutine>> loadRecurringRoutines({
  required MindmapRepository repository,
}) async {
  final nodes = await repository.listNodes();
  return allRecurringRoutinesFromNodes(nodes);
}

Future<RecurringRoutinePlan> previewRecurringRoutines({
  required MindmapRepository repository,
  required DateTime day,
  Iterable<RecurringNodeRoutine>? routines,
  DateTime? now,
  bool forceDue = false,
}) async {
  final normalizedDay = day.dateOnly;
  final existingNodes = await repository.listNodes();
  final availableRoutines =
      routines ?? allRecurringRoutinesFromNodes(existingNodes);
  return RecurringRoutinePlan.fromRoutines(
    day: normalizedDay,
    existingNodes: existingNodes,
    routines: availableRoutines,
    now: now,
    forceDue: forceDue,
  );
}

Future<List<MindmapNode>> applyRecurringRoutines({
  required MindmapRepository repository,
  required DateTime day,
  Iterable<RecurringNodeRoutine>? routines,
  DateTime? now,
  bool forceDue = false,
}) async {
  final plan = await previewRecurringRoutines(
    repository: repository,
    day: day,
    routines: routines,
    now: now,
    forceDue: forceDue,
  );
  final savedNodes = <MindmapNode>[];
  for (final node in plan.nodes) {
    savedNodes.add(await repository.saveNode(node));
  }
  return List.unmodifiable(savedNodes);
}

Future<List<MindmapNode>> skipRecurringRoutines({
  required MindmapRepository repository,
  required DateTime day,
  required Iterable<RecurringNodeRoutine> routines,
  DateTime? now,
}) async {
  final normalizedDay = day.dateOnly;
  final timestamp = now ?? DateTime.now();
  final plan = await previewRecurringRoutines(
    repository: repository,
    day: normalizedDay,
    routines: routines,
    now: timestamp,
  );
  final savedNodes = <MindmapNode>[];

  for (final item in plan.items) {
    if (!item.willCreate) continue;
    final routine = item.routine;
    final template = routine.template;
    final marker = MindmapNode.create(
      id: 'routine-skip-${routine.id}-${dayKey(normalizedDay)}',
      type: NodeType.note,
      title: 'Skipped ${routine.label}',
      body: 'Skipped ${routine.label} for ${dayKey(normalizedDay)}.',
      day: normalizedDay,
      tags: const ['routine', 'automation-skip'],
      isArchived: true,
      data: {
        'automation': {
          'routineId': routine.id,
          'templateId': template.id,
          'recurrence': routine.rule.frequency.name,
          'state': 'skipped',
        },
      },
      now: timestamp,
    );
    savedNodes.add(await repository.saveNode(marker));
  }

  return List.unmodifiable(savedNodes);
}

Future<List<MindmapNode>> snoozeRecurringRoutines({
  required MindmapRepository repository,
  required DateTime day,
  required DateTime targetDay,
  required Iterable<RecurringNodeRoutine> routines,
  DateTime? now,
}) async {
  final normalizedDay = day.dateOnly;
  final normalizedTargetDay = targetDay.dateOnly;
  if (!normalizedTargetDay.isAfter(normalizedDay)) return const [];
  final timestamp = now ?? DateTime.now();
  final plan = await previewRecurringRoutines(
    repository: repository,
    day: normalizedDay,
    routines: routines,
    now: timestamp,
  );
  final savedNodes = <MindmapNode>[];

  for (final item in plan.items) {
    if (!item.willCreate) continue;
    final routine = item.routine;
    final template = routine.template;
    final marker = MindmapNode.create(
      id: 'routine-snooze-${routine.id}-${dayKey(normalizedDay)}-to-${dayKey(normalizedTargetDay)}',
      type: NodeType.note,
      title: 'Snoozed ${routine.label}',
      body:
          'Snoozed ${routine.label} from ${dayKey(normalizedDay)} to ${dayKey(normalizedTargetDay)}.',
      day: normalizedDay,
      tags: const ['routine', 'automation-snooze'],
      isArchived: true,
      data: {
        'automation': {
          'routineId': routine.id,
          'templateId': template.id,
          'recurrence': routine.rule.frequency.name,
          'state': 'snoozed',
          'snoozedTo': dayKey(normalizedTargetDay),
        },
      },
      now: timestamp,
    );
    savedNodes.add(await repository.saveNode(marker));
  }

  return List.unmodifiable(savedNodes);
}

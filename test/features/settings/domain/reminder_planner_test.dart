import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/recurring_routine.dart';
import 'package:var_app/features/settings/domain/reminder_planner.dart';

void main() {
  test('buildReminderPlan includes due nodes and ready routines', () {
    final today = DateTime(2026, 6, 29);
    final dueTask = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Pay invoice',
      day: today,
      now: today,
    ).copyWith(dueDate: today.add(const Duration(days: 2)));
    final doneTask = MindmapNode.create(
      id: 'task-2',
      type: NodeType.task,
      title: 'Done task',
      day: today,
      now: today,
    ).copyWith(isDone: true, dueDate: today.add(const Duration(days: 1)));

    final plan = buildReminderPlan(
      nodes: [dueTask, doneTask],
      routines: defaultRecurringRoutines.take(1),
      options: ReminderPlannerOptions(
        today: today,
        lookaheadDays: 3,
        dueRemindersEnabled: true,
        routineRemindersEnabled: true,
      ),
    );

    expect(plan.dueNodes.map((item) => item.title), contains('Pay invoice'));
    expect(
      plan.dueNodes.map((item) => item.title),
      isNot(contains('Done task')),
    );
    expect(plan.routines.map((item) => item.title), contains('Daily plan'));
  });

  test('buildReminderPlan groups overdue nodes into today', () {
    final today = DateTime(2026, 6, 29);
    final overdueTask = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Pay invoice',
      day: today,
      now: today,
    ).copyWith(dueDate: today.subtract(const Duration(days: 2)));

    final plan = buildReminderPlan(
      nodes: [overdueTask],
      routines: const [],
      options: ReminderPlannerOptions(
        today: today,
        lookaheadDays: 3,
        dueRemindersEnabled: true,
        routineRemindersEnabled: false,
      ),
    );

    expect(plan.overdue.single.title, 'Pay invoice');
    expect(plan.groupedByDay[today]!.single.isOverdue, isTrue);
  });

  test('buildReminderPlan respects disabled reminder types', () {
    final today = DateTime(2026, 6, 29);
    final dueTask = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Pay invoice',
      day: today,
      now: today,
    ).copyWith(dueDate: today);

    final plan = buildReminderPlan(
      nodes: [dueTask],
      routines: defaultRecurringRoutines.take(1),
      options: ReminderPlannerOptions(
        today: today,
        lookaheadDays: 3,
        dueRemindersEnabled: false,
        routineRemindersEnabled: false,
      ),
    );

    expect(plan.items, isEmpty);
  });
}

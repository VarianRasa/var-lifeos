import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_mini_app_data.dart';
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

  test('buildReminderPlan schedules enabled habits at stored local time', () {
    final now = DateTime(2026, 6, 29, 12);
    final base = MindmapNode.create(
      id: 'habit-1',
      type: NodeType.habit,
      title: 'Walk',
      day: now,
      now: now,
    );
    final habit = updateNodeMiniAppSection(base, 'habit', {
      'reminderEnabled': true,
      'reminderTime': '18:30',
    });

    final plan = buildReminderPlan(
      nodes: [habit],
      routines: const [],
      options: ReminderPlannerOptions(
        today: now,
        lookaheadDays: 1,
        dueRemindersEnabled: false,
        routineRemindersEnabled: false,
      ),
    );

    expect(plan.habits, hasLength(2));
    expect(plan.habits.first.scheduledAt, DateTime(2026, 6, 29, 18, 30));
    expect(plan.habits.last.scheduledAt, DateTime(2026, 6, 30, 18, 30));
  });

  test('habit reminders skip elapsed, malformed, archived, and done items', () {
    final now = DateTime(2026, 6, 29, 20);
    MindmapNode habit(String id, String time) => updateNodeMiniAppSection(
      MindmapNode.create(
        id: id,
        type: NodeType.habit,
        title: id,
        day: now,
        now: now,
      ),
      'habit',
      {'reminderEnabled': true, 'reminderTime': time},
    );

    final plan = buildReminderPlan(
      nodes: [
        habit('elapsed', '08:00'),
        habit('malformed', '25:00'),
        habit('archived', '21:00').copyWith(isArchived: true),
        habit('done', '21:00').copyWith(isDone: true),
      ],
      routines: const [],
      options: ReminderPlannerOptions(
        today: now,
        lookaheadDays: 0,
        dueRemindersEnabled: false,
        routineRemindersEnabled: false,
      ),
    );

    expect(plan.habits, isEmpty);
  });
}

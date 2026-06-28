import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_template.dart';
import 'package:var_app/features/mindmap/domain/recurring_routine.dart';

void main() {
  test('recurring rules know when they are due', () {
    final monday = DateTime(2026, 6, 22);
    final tuesday = monday.addDays(1);
    final firstOfMonth = DateTime(2026, 7, 1);

    expect(RecurringRule.daily().isDueOn(monday), isTrue);
    expect(
      RecurringRule.weekly(weekday: DateTime.monday).isDueOn(monday),
      isTrue,
    );
    expect(
      RecurringRule.weekly(weekday: DateTime.monday).isDueOn(tuesday),
      isFalse,
    );
    expect(RecurringRule.monthly(dayOfMonth: 1).isDueOn(firstOfMonth), isTrue);
    expect(RecurringRule.monthly(dayOfMonth: 1).isDueOn(monday), isFalse);
  });

  test(
    'default recurring routines cover daily, weekly, and monthly templates',
    () {
      expect(
        defaultRecurringRoutines.map((routine) => routine.id),
        containsAll([
          'daily-plan',
          'daily-journal',
          'workout-habit',
          'weekly-review',
          'monthly-review',
        ]),
      );
    },
  );

  test(
    'RecurringRoutinePlan creates due routine nodes and skips duplicates',
    () {
      final monday = DateTime(2026, 6, 22);
      final existingJournal = MindmapNode.create(
        id: 'existing-journal',
        type: NodeType.journal,
        title: 'Daily journal',
        day: monday,
        data: const {
          'automation': {
            'routineId': 'daily-journal',
            'templateId': 'daily-journal',
          },
        },
        now: DateTime(2026, 6, 22, 8),
      );

      final plan = RecurringRoutinePlan.fromRoutines(
        day: monday,
        existingNodes: [existingJournal],
        routines: defaultRecurringRoutines,
        now: DateTime(2026, 6, 22, 9),
      );

      expect(
        plan.nodes.map((node) => node.id),
        containsAll([
          'routine-daily-plan-2026-06-22',
          'routine-workout-habit-2026-06-22',
          'routine-weekly-review-2026-06-22',
        ]),
      );
      expect(
        plan.nodes.any((node) => node.id.contains('daily-journal')),
        isFalse,
      );

      final dailyPlan = plan.nodes.firstWhere(
        (node) => node.id == 'routine-daily-plan-2026-06-22',
      );
      expect(dailyPlan.type, NodeType.plan);
      expect(dailyPlan.title, 'Daily plan');
      expect(dailyPlan.data['automation'], {
        'routineId': 'daily-plan',
        'templateId': 'daily-plan',
        'recurrence': 'daily',
      });
    },
  );

  test('RecurringRoutinePlan exposes preview statuses for every routine', () {
    final tuesday = DateTime(2026, 6, 23);
    final existingJournal = MindmapNode.create(
      id: 'existing-journal',
      type: NodeType.journal,
      title: 'Daily journal',
      day: tuesday,
      data: const {
        'automation': {
          'routineId': 'daily-journal',
          'templateId': 'daily-journal',
        },
      },
      now: DateTime(2026, 6, 23, 8),
    );

    final plan = RecurringRoutinePlan.fromRoutines(
      day: tuesday,
      existingNodes: [existingJournal],
      routines: defaultRecurringRoutines,
      now: DateTime(2026, 6, 23, 9),
    );

    expect(plan.items, hasLength(defaultRecurringRoutines.length));
    expect(plan.readyCount, 2);
    expect(plan.skippedCount, 1);
    expect(plan.notDueCount, 2);
    expect(plan.nodes.map((node) => node.id), [
      'routine-daily-plan-2026-06-23',
      'routine-workout-habit-2026-06-23',
    ]);

    final dailyJournal = plan.items.singleWhere(
      (item) => item.routine.id == 'daily-journal',
    );
    final weeklyReview = plan.items.singleWhere(
      (item) => item.routine.id == 'weekly-review',
    );

    expect(dailyJournal.status, RecurringRoutinePlanItemStatus.skippedExisting);
    expect(dailyJournal.statusLabel, 'Already exists');
    expect(weeklyReview.status, RecurringRoutinePlanItemStatus.notDue);
    expect(weeklyReview.statusLabel, 'Not due');
  });

  test(
    'RecurringRoutinePlan treats automation skip markers as skipped today',
    () {
      final monday = DateTime(2026, 6, 22);
      final skippedJournal = MindmapNode.create(
        id: 'routine-skip-daily-journal-2026-06-22',
        type: NodeType.note,
        title: 'Skipped Daily journal',
        day: monday,
        tags: const ['routine', 'automation-skip'],
        isArchived: true,
        data: const {
          'automation': {
            'routineId': 'daily-journal',
            'templateId': 'daily-journal',
            'recurrence': 'daily',
            'state': 'skipped',
          },
        },
        now: DateTime(2026, 6, 22, 8),
      );

      final plan = RecurringRoutinePlan.fromRoutines(
        day: monday,
        existingNodes: [skippedJournal],
        routines: defaultRecurringRoutines,
        now: DateTime(2026, 6, 22, 9),
      );

      final dailyJournal = plan.items.singleWhere(
        (item) => item.routine.id == 'daily-journal',
      );

      expect(plan.readyCount, 3);
      expect(plan.skippedTodayCount, 1);
      expect(dailyJournal.status, RecurringRoutinePlanItemStatus.skippedToday);
      expect(dailyJournal.statusLabel, 'Skipped today');
      expect(
        plan.nodes.map((node) => node.id),
        isNot(contains('routine-daily-journal-2026-06-22')),
      );
    },
  );

  test(
    'RecurringRoutinePlan lets snoozed routines become due on target day',
    () {
      final monday = DateTime(2026, 6, 22);
      final tuesday = DateTime(2026, 6, 23);
      final snoozedWeeklyReview = MindmapNode.create(
        id: 'routine-snooze-weekly-review-2026-06-22-to-2026-06-23',
        type: NodeType.note,
        title: 'Snoozed Weekly review',
        day: monday,
        tags: const ['routine', 'automation-snooze'],
        isArchived: true,
        data: const {
          'automation': {
            'routineId': 'weekly-review',
            'templateId': 'weekly-review',
            'recurrence': 'weekly',
            'state': 'snoozed',
            'snoozedTo': '2026-06-23',
          },
        },
        now: DateTime(2026, 6, 22, 8),
      );

      final mondayPlan = RecurringRoutinePlan.fromRoutines(
        day: monday,
        existingNodes: [snoozedWeeklyReview],
        routines: defaultRecurringRoutines,
        now: DateTime(2026, 6, 22, 9),
      );
      final tuesdayPlan = RecurringRoutinePlan.fromRoutines(
        day: tuesday,
        existingNodes: [snoozedWeeklyReview],
        routines: defaultRecurringRoutines,
        now: DateTime(2026, 6, 23, 9),
      );
      final mondayWeeklyReview = mondayPlan.items.singleWhere(
        (item) => item.routine.id == 'weekly-review',
      );
      final tuesdayWeeklyReview = tuesdayPlan.items.singleWhere(
        (item) => item.routine.id == 'weekly-review',
      );

      expect(
        mondayWeeklyReview.status,
        RecurringRoutinePlanItemStatus.snoozedToday,
      );
      expect(mondayWeeklyReview.statusLabel, 'Snoozed');
      expect(mondayPlan.snoozedTodayCount, 1);
      expect(tuesdayWeeklyReview.status, RecurringRoutinePlanItemStatus.ready);
      expect(
        tuesdayPlan.nodes.map((node) => node.id),
        contains('routine-weekly-review-2026-06-23'),
      );
    },
  );

  test('monthly review routine is due on the first day of the month', () {
    final firstOfMonth = DateTime(2026, 7, 1);
    final plan = RecurringRoutinePlan.fromRoutines(
      day: firstOfMonth,
      existingNodes: const [],
      routines: defaultRecurringRoutines,
      now: DateTime(2026, 7, 1, 9),
    );

    expect(
      plan.nodes.map((node) => node.id),
      contains('routine-monthly-review-2026-07-01'),
    );
  });

  test('node templates include reusable plan and monthly review templates', () {
    expect(
      defaultNodeTemplates.map((template) => template.id),
      containsAll(['daily-plan', 'monthly-review']),
    );
  });
}

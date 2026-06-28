import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/mindmap/application/recurring_routine_application.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/automation_rule.dart';
import 'package:var_app/features/mindmap/domain/recurring_routine.dart';

void main() {
  test('applyRecurringRoutines saves due routines once per day', () async {
    final day = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    final created = await applyRecurringRoutines(
      repository: repository,
      day: day,
      now: DateTime(2026, 6, 22, 9),
    );

    expect(
      created.map((node) => node.title),
      containsAll(['Daily plan', 'Daily journal', 'Workout', 'Weekly review']),
    );

    final secondPass = await applyRecurringRoutines(
      repository: repository,
      day: day,
      now: DateTime(2026, 6, 22, 10),
    );
    expect(secondPass, isEmpty);

    final savedNodes = await repository.listNodes(day: day);
    expect(savedNodes.length, created.length);
    expect(
      savedNodes.map((node) => node.id),
      contains('routine-weekly-review-${dayKey(day)}'),
    );
  });

  test(
    'previewRecurringRoutines returns ready and skipped automation',
    () async {
      final day = DateTime(2026, 6, 22);
      final repository = InMemoryMindmapRepository();

      final beforeApply = await previewRecurringRoutines(
        repository: repository,
        day: day,
        now: DateTime(2026, 6, 22, 9),
      );

      expect(beforeApply.readyCount, 4);
      expect(beforeApply.skippedCount, 0);

      await applyRecurringRoutines(
        repository: repository,
        day: day,
        now: DateTime(2026, 6, 22, 10),
      );

      final afterApply = await previewRecurringRoutines(
        repository: repository,
        day: day,
        now: DateTime(2026, 6, 22, 11),
      );

      expect(afterApply.readyCount, 0);
      expect(afterApply.skippedCount, 4);
      expect(
        afterApply.items
            .where(
              (item) =>
                  item.status == RecurringRoutinePlanItemStatus.skippedExisting,
            )
            .map((item) => item.routine.id),
        containsAll(['daily-plan', 'daily-journal', 'workout-habit']),
      );
    },
  );

  test(
    'skipRecurringRoutines records skip markers and prevents apply',
    () async {
      final day = DateTime(2026, 6, 22);
      final repository = InMemoryMindmapRepository();
      final dailyJournal = defaultRecurringRoutines.singleWhere(
        (routine) => routine.id == 'daily-journal',
      );

      final skipped = await skipRecurringRoutines(
        repository: repository,
        day: day,
        routines: [dailyJournal],
        now: DateTime(2026, 6, 22, 9),
      );

      expect(skipped, hasLength(1));
      expect(skipped.single.id, 'routine-skip-daily-journal-${dayKey(day)}');
      expect(skipped.single.isArchived, isTrue);
      expect(skipped.single.tags, contains('automation-skip'));
      expect(skipped.single.data['automation'], {
        'routineId': 'daily-journal',
        'templateId': 'daily-journal',
        'recurrence': 'daily',
        'state': 'skipped',
      });

      final preview = await previewRecurringRoutines(
        repository: repository,
        day: day,
        now: DateTime(2026, 6, 22, 10),
      );
      final dailyJournalPreview = preview.items.singleWhere(
        (item) => item.routine.id == 'daily-journal',
      );

      expect(preview.skippedTodayCount, 1);
      expect(
        dailyJournalPreview.status,
        RecurringRoutinePlanItemStatus.skippedToday,
      );

      final created = await applyRecurringRoutines(
        repository: repository,
        day: day,
        now: DateTime(2026, 6, 22, 11),
      );

      expect(
        created.map((node) => node.title),
        isNot(contains('Daily journal')),
      );
      expect(
        created.map((node) => node.id),
        isNot(contains('routine-daily-journal-${dayKey(day)}')),
      );
    },
  );

  test('snoozeRecurringRoutines moves a routine to the target day', () async {
    final monday = DateTime(2026, 6, 22);
    final tuesday = DateTime(2026, 6, 23);
    final repository = InMemoryMindmapRepository();
    final weeklyReview = defaultRecurringRoutines.singleWhere(
      (routine) => routine.id == 'weekly-review',
    );

    final snoozed = await snoozeRecurringRoutines(
      repository: repository,
      day: monday,
      targetDay: tuesday,
      routines: [weeklyReview],
      now: DateTime(2026, 6, 22, 9),
    );

    expect(snoozed, hasLength(1));
    expect(
      snoozed.single.id,
      'routine-snooze-weekly-review-${dayKey(monday)}-to-${dayKey(tuesday)}',
    );
    expect(snoozed.single.isArchived, isTrue);
    expect(snoozed.single.tags, contains('automation-snooze'));
    expect(snoozed.single.data['automation'], {
      'routineId': 'weekly-review',
      'templateId': 'weekly-review',
      'recurrence': 'weekly',
      'state': 'snoozed',
      'snoozedTo': dayKey(tuesday),
    });

    final mondayPreview = await previewRecurringRoutines(
      repository: repository,
      day: monday,
      now: DateTime(2026, 6, 22, 10),
    );
    final tuesdayPreview = await previewRecurringRoutines(
      repository: repository,
      day: tuesday,
      now: DateTime(2026, 6, 23, 9),
    );

    expect(mondayPreview.snoozedTodayCount, 1);
    expect(
      mondayPreview.items
          .singleWhere((item) => item.routine.id == 'weekly-review')
          .status,
      RecurringRoutinePlanItemStatus.snoozedToday,
    );
    expect(
      tuesdayPreview.items
          .singleWhere((item) => item.routine.id == 'weekly-review')
          .status,
      RecurringRoutinePlanItemStatus.ready,
    );

    final created = await applyRecurringRoutines(
      repository: repository,
      day: tuesday,
      now: DateTime(2026, 6, 23, 10),
    );

    expect(created.map((node) => node.title), contains('Weekly review'));
    expect(
      created.map((node) => node.id),
      contains('routine-weekly-review-${dayKey(tuesday)}'),
    );
  });

  test('previewRecurringRoutines includes custom automation rules', () async {
    final day = DateTime(2026, 6, 23);
    final repository = InMemoryMindmapRepository();
    await repository.saveNode(
      createAutomationRuleNode(
        id: 'custom-research',
        label: 'Daily research',
        templateId: 'research-note',
        rule: RecurringRule.daily(),
        day: day,
        now: DateTime(2026, 6, 23, 8),
      ),
    );

    final preview = await previewRecurringRoutines(
      repository: repository,
      day: day,
      now: DateTime(2026, 6, 23, 9),
    );

    expect(
      preview.items.map((item) => item.routine.id),
      contains('custom-research'),
    );
    expect(
      preview.nodes.map((node) => node.id),
      contains('routine-custom-research-${dayKey(day)}'),
    );

    final created = await applyRecurringRoutines(
      repository: repository,
      day: day,
      now: DateTime(2026, 6, 23, 10),
    );
    final customNode = created.singleWhere(
      (node) => node.id == 'routine-custom-research-${dayKey(day)}',
    );

    expect(customNode.title, 'Daily research');
    expect(customNode.data['automation'], {
      'routineId': 'custom-research',
      'templateId': 'research-note',
      'recurrence': 'daily',
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/automation_suggestion.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/recurring_routine.dart';

void main() {
  test(
    'AutomationSuggestions exposes ready routines and skips unavailable ones',
    () {
      final monday = DateTime(2026, 6, 22);
      final existingJournal = MindmapNode.create(
        id: 'existing-journal',
        type: NodeType.journal,
        title: 'Daily journal',
        day: monday,
        data: const {
          'automation': {'routineId': 'daily-journal'},
        },
        now: DateTime(2026, 6, 22, 8),
      );
      final plan = RecurringRoutinePlan.fromRoutines(
        day: monday,
        existingNodes: [existingJournal],
        routines: defaultRecurringRoutines,
        now: DateTime(2026, 6, 22, 9),
      );

      final suggestions = AutomationSuggestions.fromRoutinePlan(
        day: monday,
        plan: plan,
      );

      expect(suggestions.readyCount, 3);
      expect(suggestions.blockedCount, 2);
      expect(suggestions.completedCount, 1);
      expect(suggestions.completedItems.map((item) => item.routineId), [
        'daily-journal',
      ]);
      expect(
        suggestions.completedItems.single.message,
        'Already created for 2026-06-22',
      );
      expect(suggestions.primaryActionLabel, 'Review 3 automations');
      expect(suggestions.items.map((item) => item.id), [
        'routine-daily-plan-2026-06-22',
        'routine-workout-habit-2026-06-22',
        'routine-weekly-review-2026-06-22',
      ]);
      expect(suggestions.items.map((item) => item.title), [
        'Daily plan',
        'Workout habit',
        'Weekly review',
      ]);
      expect(suggestions.items.map((item) => item.message), [
        'Ready to create from Daily plan',
        'Ready to create from Workout habit',
        'Ready to create from Weekly review',
      ]);
      expect(
        suggestions.items.map((item) => item.actionLabel),
        everyElement('Apply routine'),
      );
    },
  );

  test('AutomationSuggestions builds routine schedule rows', () {
    final tuesday = DateTime(2026, 6, 23);
    final plan = RecurringRoutinePlan.fromRoutines(
      day: tuesday,
      existingNodes: const [],
      routines: defaultRecurringRoutines,
      now: DateTime(2026, 6, 23, 9),
    );

    final suggestions = AutomationSuggestions.fromRoutinePlan(
      day: tuesday,
      plan: plan,
    );
    final weeklyReview = suggestions.scheduleItems.singleWhere(
      (item) => item.routineId == 'weekly-review',
    );
    final monthlyReview = suggestions.scheduleItems.singleWhere(
      (item) => item.routineId == 'monthly-review',
    );
    final dailyPlan = suggestions.scheduleItems.singleWhere(
      (item) => item.routineId == 'daily-plan',
    );

    expect(
      suggestions.scheduleItems,
      hasLength(defaultRecurringRoutines.length),
    );
    expect(dailyPlan.cadenceLabel, 'Daily');
    expect(dailyPlan.statusLabel, 'Ready');
    expect(dailyPlan.nextDueLabel, 'Next 2026-06-23');
    expect(weeklyReview.title, 'Weekly review');
    expect(weeklyReview.cadenceLabel, 'Weekly Monday');
    expect(weeklyReview.statusLabel, 'Not due');
    expect(weeklyReview.nextDueDay, DateTime(2026, 6, 29));
    expect(weeklyReview.nextDueLabel, 'Next 2026-06-29');
    expect(monthlyReview.cadenceLabel, 'Monthly day 1');
    expect(monthlyReview.nextDueDay, DateTime(2026, 7, 1));
  });
}

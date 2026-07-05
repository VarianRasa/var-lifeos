import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/insights/application/habit_insights.dart';
import 'package:var_app/features/mindmap/domain/automation_event.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('buildHabitInsightSummary calculates completion and streaks', () {
    final today = DateTime(2026, 7, 6);
    final start = today.addDays(-2);
    final nodes = [
      MindmapNode.create(
        id: 'workout',
        type: NodeType.habit,
        title: 'Workout',
        day: today,
        data: const {
          'habit': {
            'completions': ['2026-07-04', '2026-07-05'],
          },
        },
        now: DateTime(2026, 7, 6, 8),
      ),
      MindmapNode.create(
        id: 'read',
        type: NodeType.habit,
        title: 'Read',
        day: today,
        data: const {
          'habit': {
            'completions': ['2026-07-04', '2026-07-05', '2026-07-06'],
          },
        },
        now: DateTime(2026, 7, 6, 9),
      ),
    ];

    final summary = buildHabitInsightSummary(
      start: start,
      end: today,
      today: today,
      nodes: nodes,
    );

    expect(summary.habitCount, 2);
    expect(summary.completedCount, 5);
    expect(summary.expectedCount, 6);
    expect(summary.completionRate, closeTo(5 / 6, 0.001));
    expect(summary.missedHabits.map((node) => node.title), ['Workout']);
    expect(summary.mostConsistentHabit?.title, 'Read');
    expect(summary.mostConsistentHabit?.currentStreak, 3);
    expect(summary.streakAtRisk?.title, 'Workout');
  });

  test('buildRoutineInsightSummary counts routine markers', () {
    final today = DateTime(2026, 7, 6);
    final nodes = [
      createAutomationEventNode(
        id: 'apply-1',
        type: AutomationEventType.applyRoutines,
        title: 'Applied routines',
        message: 'Applied',
        day: today,
        occurredAt: DateTime(2026, 7, 6, 8),
        affectedLabels: const ['Daily plan', 'Workout'],
      ),
      createAutomationEventNode(
        id: 'skip-1',
        type: AutomationEventType.skipRoutines,
        title: 'Skipped routines',
        message: 'Skipped',
        day: today,
        occurredAt: DateTime(2026, 7, 6, 9),
        affectedLabels: const ['Weekly review'],
      ),
      createAutomationEventNode(
        id: 'snooze-1',
        type: AutomationEventType.snoozeRoutines,
        title: 'Snoozed routines',
        message: 'Snoozed',
        day: today,
        occurredAt: DateTime(2026, 7, 6, 10),
        affectedLabels: const ['Workout'],
      ),
      createAutomationEventNode(
        id: 'snooze-2',
        type: AutomationEventType.snoozeRoutines,
        title: 'Snoozed routines',
        message: 'Snoozed',
        day: today.addDays(-1),
        occurredAt: DateTime(2026, 7, 5, 10),
        affectedLabels: const ['Workout'],
      ),
    ];

    final summary = buildRoutineInsightSummary(
      start: today.addDays(-2),
      end: today,
      nodes: nodes,
    );

    expect(summary.appliedCount, 2);
    expect(summary.skippedCount, 1);
    expect(summary.snoozedCount, 2);
    expect(summary.frequentlySnoozedRoutine, 'Workout');
  });
}

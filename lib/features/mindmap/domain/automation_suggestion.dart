/// Automation suggestions derived from reusable routines and workspace state.
library;

import '../../../core/utils/date_utils.dart';
import 'recurring_routine.dart';

final class AutomationSuggestion {
  const AutomationSuggestion({
    required this.id,
    required this.routineId,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.day,
  });

  final String id;
  final String routineId;
  final String title;
  final String message;
  final String actionLabel;
  final DateTime day;
}

final class AutomationScheduleItem {
  const AutomationScheduleItem({
    required this.routineId,
    required this.title,
    required this.cadenceLabel,
    required this.statusLabel,
    required this.nextDueDay,
    required this.nextDueLabel,
  });

  final String routineId;
  final String title;
  final String cadenceLabel;
  final String statusLabel;
  final DateTime nextDueDay;
  final String nextDueLabel;
}

final class AutomationSuggestions {
  AutomationSuggestions({
    required this.day,
    required this.readyCount,
    required this.blockedCount,
    required List<AutomationSuggestion> items,
    required List<AutomationSuggestion> completedItems,
    required List<AutomationSuggestion> skippedItems,
    required List<AutomationSuggestion> snoozedItems,
    required List<AutomationScheduleItem> scheduleItems,
  }) : items = List.unmodifiable(items),
       completedItems = List.unmodifiable(completedItems),
       skippedItems = List.unmodifiable(skippedItems),
       snoozedItems = List.unmodifiable(snoozedItems),
       scheduleItems = List.unmodifiable(scheduleItems);

  factory AutomationSuggestions.fromRoutinePlan({
    required DateTime day,
    required RecurringRoutinePlan plan,
  }) {
    final normalizedDay = day.dateOnly;
    final items = [
      for (final item in plan.items)
        if (item.willCreate)
          AutomationSuggestion(
            id: item.node?.id ?? 'routine-${item.routine.id}-${dayKey(day)}',
            routineId: item.routine.id,
            title: item.routine.label,
            message: 'Ready to create from ${item.routine.label}',
            actionLabel: 'Apply routine',
            day: normalizedDay,
          ),
    ];
    final completedItems = [
      for (final item in plan.items)
        if (item.status == RecurringRoutinePlanItemStatus.skippedExisting)
          AutomationSuggestion(
            id: 'completed-${item.routine.id}-${dayKey(normalizedDay)}',
            routineId: item.routine.id,
            title: item.routine.label,
            message: 'Already created for ${dayKey(normalizedDay)}',
            actionLabel: 'Open day',
            day: normalizedDay,
          ),
    ];
    final skippedItems = [
      for (final item in plan.items)
        if (item.status == RecurringRoutinePlanItemStatus.skippedToday)
          AutomationSuggestion(
            id: 'skipped-${item.routine.id}-${dayKey(normalizedDay)}',
            routineId: item.routine.id,
            title: 'Skipped ${item.routine.label}',
            message: 'Skipped for ${dayKey(normalizedDay)}',
            actionLabel: 'Open day',
            day: normalizedDay,
          ),
    ];
    final snoozedItems = [
      for (final item in plan.items)
        if (item.status == RecurringRoutinePlanItemStatus.snoozedToday)
          AutomationSuggestion(
            id: 'snoozed-${item.routine.id}-${dayKey(normalizedDay)}',
            routineId: item.routine.id,
            title: 'Snoozed ${item.routine.label}',
            message: 'Snoozed from ${dayKey(normalizedDay)}',
            actionLabel: 'Open day',
            day: normalizedDay,
          ),
    ];
    final scheduleItems = [
      for (final item in plan.items)
        AutomationScheduleItem(
          routineId: item.routine.id,
          title: item.routine.label,
          cadenceLabel: _cadenceLabel(item.routine.rule),
          statusLabel: _scheduleStatusLabel(item.status),
          nextDueDay: _nextDueDay(
            day: normalizedDay,
            rule: item.routine.rule,
            status: item.status,
          ),
          nextDueLabel:
              'Next ${dayKey(_nextDueDay(day: normalizedDay, rule: item.routine.rule, status: item.status))}',
        ),
    ];

    return AutomationSuggestions(
      day: normalizedDay,
      readyCount: plan.readyCount,
      blockedCount:
          plan.skippedCount +
          plan.skippedTodayCount +
          plan.snoozedTodayCount +
          plan.notDueCount,
      items: items,
      completedItems: completedItems,
      skippedItems: skippedItems,
      snoozedItems: snoozedItems,
      scheduleItems: scheduleItems,
    );
  }

  final DateTime day;
  final int readyCount;
  final int blockedCount;
  final List<AutomationSuggestion> items;
  final List<AutomationSuggestion> completedItems;
  final List<AutomationSuggestion> skippedItems;
  final List<AutomationSuggestion> snoozedItems;
  final List<AutomationScheduleItem> scheduleItems;

  int get completedCount => completedItems.length;

  int get skippedTodayCount => skippedItems.length;

  int get snoozedTodayCount => snoozedItems.length;

  bool get isEmpty =>
      items.isEmpty &&
      completedItems.isEmpty &&
      skippedItems.isEmpty &&
      snoozedItems.isEmpty;

  String get primaryActionLabel {
    if (readyCount == 0 &&
        (completedCount > 0 ||
            skippedTodayCount > 0 ||
            snoozedTodayCount > 0)) {
      return 'Review automation history';
    }
    return readyCount == 1
        ? 'Review 1 automation'
        : 'Review $readyCount automations';
  }
}

String _cadenceLabel(RecurringRule rule) {
  return switch (rule.frequency) {
    RecurringFrequency.daily => 'Daily',
    RecurringFrequency.weekly => 'Weekly ${_weekdayLabel(rule.weekday)}',
    RecurringFrequency.monthly => 'Monthly day ${rule.dayOfMonth}',
  };
}

String _weekdayLabel(int? weekday) {
  return switch (weekday) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => 'weekly',
  };
}

String _scheduleStatusLabel(RecurringRoutinePlanItemStatus status) {
  return switch (status) {
    RecurringRoutinePlanItemStatus.ready => 'Ready',
    RecurringRoutinePlanItemStatus.skippedExisting => 'Done',
    RecurringRoutinePlanItemStatus.skippedToday => 'Skipped',
    RecurringRoutinePlanItemStatus.snoozedToday => 'Snoozed',
    RecurringRoutinePlanItemStatus.notDue => 'Not due',
  };
}

DateTime _nextDueDay({
  required DateTime day,
  required RecurringRule rule,
  required RecurringRoutinePlanItemStatus status,
}) {
  final start = switch (status) {
    RecurringRoutinePlanItemStatus.ready ||
    RecurringRoutinePlanItemStatus.notDue => day.dateOnly,
    RecurringRoutinePlanItemStatus.snoozedToday => day.addDays(1),
    RecurringRoutinePlanItemStatus.skippedExisting ||
    RecurringRoutinePlanItemStatus.skippedToday => day.addDays(1),
  };

  for (var offset = 0; offset < 370; offset++) {
    final candidate = start.addDays(offset);
    if (rule.isDueOn(candidate)) return candidate;
  }

  return start;
}

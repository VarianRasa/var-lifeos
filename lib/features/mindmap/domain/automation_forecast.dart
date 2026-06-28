/// Forward-looking automation schedule summary.
library;

import '../../../core/utils/date_utils.dart';
import 'automation_rule.dart';
import 'mindmap_node.dart';
import 'recurring_routine.dart';

final class AutomationForecast {
  AutomationForecast({
    required this.day,
    required this.horizonDays,
    required List<AutomationForecastItem> tomorrowItems,
    required List<AutomationForecastItem> weekItems,
    required List<AutomationRuleRecord> pausedRules,
  }) : tomorrowItems = List.unmodifiable(tomorrowItems),
       weekItems = List.unmodifiable(weekItems),
       pausedRules = List.unmodifiable(pausedRules);

  factory AutomationForecast.fromNodes({
    required DateTime today,
    required Iterable<MindmapNode> nodes,
    int horizonDays = 7,
  }) {
    assert(horizonDays > 0, 'horizonDays must be greater than zero');

    final normalizedDay = today.dateOnly;
    final nodeList = nodes.toList(growable: false);
    final tomorrow = normalizedDay.addDays(1);
    final routines = allRecurringRoutinesFromNodes(nodeList);
    final tomorrowItems = <AutomationForecastItem>[];
    final weekItems = <AutomationForecastItem>[];

    for (final routine in routines) {
      if (routine.isDueOn(tomorrow)) {
        tomorrowItems.add(
          AutomationForecastItem.fromRoutine(routine: routine, day: tomorrow),
        );
      }

      final nextDueDay = _firstDueDay(
        routine: routine,
        start: tomorrow,
        horizonDays: horizonDays,
      );
      if (nextDueDay != null) {
        weekItems.add(
          AutomationForecastItem.fromRoutine(routine: routine, day: nextDueDay),
        );
      }
    }

    final pausedRules = [
      for (final rule in automationRulesFromNodes(nodeList))
        if (!rule.enabled) rule,
    ];

    return AutomationForecast(
      day: normalizedDay,
      horizonDays: horizonDays,
      tomorrowItems: tomorrowItems,
      weekItems: weekItems,
      pausedRules: pausedRules,
    );
  }

  final DateTime day;
  final int horizonDays;
  final List<AutomationForecastItem> tomorrowItems;
  final List<AutomationForecastItem> weekItems;
  final List<AutomationRuleRecord> pausedRules;

  int get tomorrowCount => tomorrowItems.length;

  int get weekCount => weekItems.length;

  int get pausedCount => pausedRules.length;

  bool get isEmpty =>
      tomorrowItems.isEmpty && weekItems.isEmpty && pausedRules.isEmpty;
}

final class AutomationForecastItem {
  const AutomationForecastItem({
    required this.routineId,
    required this.title,
    required this.day,
  });

  factory AutomationForecastItem.fromRoutine({
    required RecurringNodeRoutine routine,
    required DateTime day,
  }) {
    return AutomationForecastItem(
      routineId: routine.id,
      title: routine.label,
      day: day.dateOnly,
    );
  }

  final String routineId;
  final String title;
  final DateTime day;

  String get dayLabel => dayKey(day);
}

DateTime? _firstDueDay({
  required RecurringNodeRoutine routine,
  required DateTime start,
  required int horizonDays,
}) {
  for (var offset = 0; offset < horizonDays; offset++) {
    final candidate = start.addDays(offset);
    if (routine.isDueOn(candidate)) return candidate;
  }

  return null;
}

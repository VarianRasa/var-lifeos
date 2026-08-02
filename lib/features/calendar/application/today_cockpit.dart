/// Pure summary model for the Calendar home Today cockpit.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/habit_completion.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/mindmap_node_data.dart';
import '../domain/calendar_node_payload.dart';
import '../domain/time_block.dart';
import 'daily_review_builder.dart';
import 'focus_session.dart';
import 'node_inbox.dart';

final class TodayCockpitSchedule {
  const TodayCockpitSchedule({required this.node, required this.block});

  final MindmapNode node;
  final TimeBlock block;
}

final class TodayCockpitSummary {
  const TodayCockpitSummary({
    required this.inboxNodes,
    required this.missionNodes,
    required this.nextSchedule,
    required this.unscheduledActionCount,
    required this.habitDueCount,
    required this.habitCompletedCount,
    required this.dailyReview,
  });

  factory TodayCockpitSummary.fromNodes({
    required DateTime today,
    required DateTime now,
    required Iterable<MindmapNode> dayNodes,
    required Iterable<MindmapNode> allNodes,
  }) {
    final normalizedToday = today.dateOnly;
    final dayList = dayNodes.toList(growable: false);
    final allNodeList = allNodes.toList(growable: false);
    final activeDayNodes = dayList
        .where((node) => !node.isArchived && !_isComplete(node))
        .toList(growable: false);
    final missionNodes = activeDayNodes.where(isTodayMission).take(3).toList();
    final scheduleCandidates = <TodayCockpitSchedule>[];
    var unscheduledActionCount = 0;

    for (final node in activeDayNodes.where(_isSchedulable)) {
      final parsed = timeBlockForNode(node);
      final block = parsed.block;
      if (parsed.isUnscheduled) {
        unscheduledActionCount += 1;
      } else if (parsed.isValid && block != null) {
        scheduleCandidates.add(TodayCockpitSchedule(node: node, block: block));
      }
    }
    scheduleCandidates.sort(
      (left, right) =>
          left.block.startMinute.compareTo(right.block.startMinute),
    );
    final currentMinute = normalizedToday.isSameDay(now)
        ? now.hour * 60 + now.minute
        : 0;
    TodayCockpitSchedule? nextSchedule;
    for (final schedule in scheduleCandidates) {
      if (schedule.block.endMinute > currentMinute) {
        nextSchedule = schedule;
        break;
      }
    }

    var habitDueCount = 0;
    var habitCompletedCount = 0;
    for (final node in allNodeList.where(
      (node) =>
          node.type == NodeType.habit &&
          !node.isArchived &&
          !_isComplete(node) &&
          !node.day.dateOnly.isAfter(normalizedToday),
    )) {
      final status = _habitStatus(node, normalizedToday);
      if (!status.isDue) continue;
      habitDueCount += 1;
      if (status.isComplete) habitCompletedCount += 1;
    }

    MindmapNode? dailyReview;
    for (final node in dayList) {
      if (_isDailyReview(node, normalizedToday)) {
        dailyReview = node;
        break;
      }
    }

    return TodayCockpitSummary(
      inboxNodes: inboxNodesForDay(allNodeList, normalizedToday),
      missionNodes: List.unmodifiable(missionNodes),
      nextSchedule: nextSchedule,
      unscheduledActionCount: unscheduledActionCount,
      habitDueCount: habitDueCount,
      habitCompletedCount: habitCompletedCount,
      dailyReview: dailyReview,
    );
  }

  final List<MindmapNode> inboxNodes;
  final List<MindmapNode> missionNodes;
  final TodayCockpitSchedule? nextSchedule;
  final int unscheduledActionCount;
  final int habitDueCount;
  final int habitCompletedCount;
  final MindmapNode? dailyReview;

  int get openMissionSlots => 3 - missionNodes.length;
  bool get hasDailyReview => dailyReview != null;
}

final class _HabitStatus {
  const _HabitStatus({required this.isDue, required this.isComplete});

  final bool isDue;
  final bool isComplete;
}

_HabitStatus _habitStatus(MindmapNode node, DateTime today) {
  final habitData = _sectionData(node.data, 'habit');
  final recurrence = (habitData['recurrence'] as String? ?? 'daily')
      .trim()
      .toLowerCase();
  final completions = habitCompletionKeys(node).toSet();
  final todayKey = dayKey(today);

  return switch (recurrence) {
    'weekdays' => _HabitStatus(
      isDue: today.weekday <= DateTime.friday,
      isComplete: completions.contains(todayKey),
    ),
    'weekly' => _HabitStatus(
      isDue: true,
      isComplete: _hasCompletionInRange(completions, today.startOfWeek, today),
    ),
    'monthly' => _HabitStatus(
      isDue: true,
      isComplete: _hasCompletionInRange(completions, today.firstOfMonth, today),
    ),
    _ => _HabitStatus(isDue: true, isComplete: completions.contains(todayKey)),
  };
}

bool _hasCompletionInRange(
  Set<String> completions,
  DateTime start,
  DateTime end,
) {
  for (
    var day = start.dateOnly;
    !day.isAfter(end.dateOnly);
    day = day.addDays(1)
  ) {
    if (completions.contains(dayKey(day))) return true;
  }
  return false;
}

bool _isDailyReview(MindmapNode node, DateTime day) {
  if (node.isArchived || node.type != NodeType.journal) return false;
  final journalData = _sectionData(node.data, 'journal');
  return node.tags.contains('daily-review') ||
      node.title == dailyReviewTitle(day) ||
      journalData['isDailyReview'] == true;
}

bool _isSchedulable(MindmapNode node) {
  if (node.type == NodeType.note &&
      calendarPayloadForNode(node)?.kind == CalendarNodeKind.event) {
    return true;
  }
  return switch (node.type) {
    NodeType.task ||
    NodeType.event ||
    NodeType.plan ||
    NodeType.habit ||
    NodeType.routine => true,
    _ => false,
  };
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}

Map<String, Object?> _sectionData(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

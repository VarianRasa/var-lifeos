import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/focus_session.dart';
import 'package:var_app/features/calendar/application/today_cockpit.dart';
import 'package:var_app/features/calendar/domain/time_block.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_data.dart';

void main() {
  final today = DateTime(2026, 7, 22);

  test('summarizes inbox, missions, schedule, habits, and review', () {
    final scheduled = _node(
      id: 'scheduled',
      type: NodeType.task,
      title: 'Deep work',
      day: today,
      data: dataWithTimeBlock(
        const {},
        const TimeBlock(startMinute: 600, endMinute: 660),
      ),
    );
    final unscheduled = _node(
      id: 'unscheduled',
      type: NodeType.task,
      title: 'Admin',
      day: today,
    );
    final calendarEventNote = _node(
      id: 'event-note',
      type: NodeType.note,
      title: 'Calendar event note',
      day: today,
      data: const {'calendar_kind': 'event'},
    );
    final mission = markTodayMission(
      _node(
        id: 'mission',
        type: NodeType.task,
        title: 'Ship release',
        day: today,
      ),
      isMission: true,
    );
    final inbox = _node(
      id: 'inbox',
      type: NodeType.note,
      title: 'Captured idea',
      day: today.subtract(const Duration(days: 1)),
      data: const {'inbox': true},
    );
    final dailyHabit = _node(
      id: 'daily-habit',
      type: NodeType.habit,
      title: 'Read',
      day: today.subtract(const Duration(days: 20)),
      data: const {
        'habit': {
          'recurrence': 'daily',
          'completions': ['2026-07-22'],
        },
      },
    );
    final weeklyHabit = _node(
      id: 'weekly-habit',
      type: NodeType.habit,
      title: 'Workout',
      day: today.subtract(const Duration(days: 20)),
      data: const {
        'habit': {
          'recurrence': 'weekly',
          'completions': ['2026-07-20'],
        },
      },
    );
    final review = _node(
      id: 'review',
      type: NodeType.journal,
      title: 'Daily review — 2026-07-22',
      day: today,
      data: const {
        'journal': {'isDailyReview': true},
      },
    );
    final nodes = [
      scheduled,
      unscheduled,
      calendarEventNote,
      mission,
      inbox,
      dailyHabit,
      weeklyHabit,
      review,
    ];

    final summary = TodayCockpitSummary.fromNodes(
      today: today,
      now: DateTime(2026, 7, 22, 9, 30),
      dayNodes: nodes.where((node) => node.day == today),
      allNodes: nodes,
    );

    expect(summary.inboxNodes.map((node) => node.id), ['inbox']);
    expect(summary.missionNodes.map((node) => node.id), ['mission']);
    expect(summary.openMissionSlots, 2);
    expect(summary.nextSchedule?.node.id, 'scheduled');
    expect(summary.unscheduledActionCount, 3);
    expect(summary.habitDueCount, 2);
    expect(summary.habitCompletedCount, 2);
    expect(summary.dailyReview?.id, 'review');
  });

  test('excludes completed and archived work and past schedule blocks', () {
    final past = _node(
      id: 'past',
      type: NodeType.task,
      title: 'Past',
      day: today,
      data: dataWithTimeBlock(
        const {},
        const TimeBlock(startMinute: 480, endMinute: 540),
      ),
    );
    final next = _node(
      id: 'next',
      type: NodeType.event,
      title: 'Next',
      day: today,
      data: dataWithTimeBlock(
        const {},
        const TimeBlock(startMinute: 660, endMinute: 720),
      ),
    );
    final completed = markTodayMission(
      _node(
        id: 'done',
        type: NodeType.task,
        title: 'Done',
        day: today,
        status: NodeStatus.done,
      ),
      isMission: true,
    );
    final archived = markTodayMission(
      _node(
        id: 'archived',
        type: NodeType.task,
        title: 'Archived',
        day: today,
        isArchived: true,
      ),
      isMission: true,
    );

    final summary = TodayCockpitSummary.fromNodes(
      today: today,
      now: DateTime(2026, 7, 22, 10),
      dayNodes: [past, next, completed, archived],
      allNodes: [past, next, completed, archived],
    );

    expect(summary.missionNodes, isEmpty);
    expect(summary.nextSchedule?.node.id, 'next');
    expect(summary.unscheduledActionCount, 0);
    expect(summary.hasDailyReview, isFalse);
  });

  test('completed habit is not counted as active', () {
    final completedHabit = _node(
      id: 'completed-habit',
      type: NodeType.habit,
      title: 'Retired habit',
      day: today.subtract(const Duration(days: 10)),
      status: NodeStatus.done,
      data: const {
        'habit': {'recurrence': 'daily'},
      },
    );

    final summary = TodayCockpitSummary.fromNodes(
      today: today,
      now: today,
      dayNodes: const [],
      allNodes: [completedHabit],
    );

    expect(summary.habitDueCount, 0);
  });

  test('weekday habit is not due on weekend', () {
    final saturday = DateTime(2026, 7, 25);
    final habit = _node(
      id: 'weekdays',
      type: NodeType.habit,
      title: 'Commute walk',
      day: saturday.subtract(const Duration(days: 10)),
      data: const {
        'habit': {'recurrence': 'weekdays'},
      },
    );

    final summary = TodayCockpitSummary.fromNodes(
      today: saturday,
      now: saturday,
      dayNodes: const [],
      allNodes: [habit],
    );

    expect(summary.habitDueCount, 0);
  });
}

MindmapNode _node({
  required String id,
  required NodeType type,
  required String title,
  required DateTime day,
  NodeStatus status = NodeStatus.open,
  bool isArchived = false,
  Map<String, Object?> data = const {},
}) {
  return MindmapNode(
    id: id,
    type: type,
    title: title,
    day: day,
    position: const CanvasPosition(0, 0),
    createdAt: day,
    updatedAt: day,
    status: status,
    isArchived: isArchived,
    data: data,
  );
}

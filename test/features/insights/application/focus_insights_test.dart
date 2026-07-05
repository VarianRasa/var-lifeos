import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/calendar/application/focus_session.dart';
import 'package:var_app/features/insights/application/focus_insights.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('focusMinutesForNode extracts explicit and session focus minutes', () {
    final node = MindmapNode.create(
      id: 'focus',
      type: NodeType.note,
      title: 'Focus',
      day: DateTime(2026, 7, 8),
      data: {
        'focusMinutes': 15,
        focusSessionsDataKey: [
          FocusSessionRecord(
            startedAt: DateTime(2026, 7, 8, 9),
            endedAt: DateTime(2026, 7, 8, 9, 25),
            durationMinutes: 25,
          ).toJson(),
        ],
        'focus_sessions': const [
          {'duration_mins': 20},
        ],
      },
    );

    expect(focusMinutesForNode(node), 60);
  });

  test('buildFocusInsightSummary groups focus by day and context', () {
    final today = DateTime(2026, 7, 8);
    final nodes = [
      MindmapNode.create(
        id: 'alpha',
        type: NodeType.note,
        title: 'Alpha focus',
        day: today,
        project: 'Launch',
        area: 'Work',
        tags: const ['deep'],
        data: const {'focusMinutes': 45},
      ),
      MindmapNode.create(
        id: 'beta',
        type: NodeType.note,
        title: 'Beta focus',
        day: today.addDays(-1),
        project: 'Launch',
        area: 'Work',
        tags: const ['deep'],
        data: const {'durationMinutes': 30},
      ),
      MindmapNode.create(
        id: 'gamma',
        type: NodeType.note,
        title: 'Gamma focus',
        day: today.addDays(-1),
        project: 'Health',
        area: 'Personal',
        tags: const ['body'],
        data: const {'focus_minutes': 20},
      ),
    ];

    final summary = buildFocusInsightSummary(
      start: today.addDays(-2),
      end: today,
      nodes: nodes,
    );

    expect(summary.totalMinutes, 95);
    expect(summary.bestFocusDay, today.addDays(-1));
    expect(summary.bestFocusMinutes, 50);
    expect(summary.minutesByProject.first.label, 'Launch');
    expect(summary.minutesByProject.first.minutes, 75);
    expect(summary.minutesByArea.first.label, 'Work');
    expect(summary.minutesByTag.first.label, 'deep');
    expect(summary.minutesByDay.map((bucket) => bucket.label), [
      '2026-07-06',
      '2026-07-07',
      '2026-07-08',
    ]);
  });

  test(
    'buildFocusInsightSummary warns when planned work is high and focus low',
    () {
      final today = DateTime(2026, 7, 8);
      final nodes = List.generate(
        4,
        (index) => MindmapNode.create(
          id: 'task-$index',
          type: NodeType.task,
          title: 'Task $index',
          day: today,
        ),
      );

      final summary = buildFocusInsightSummary(
        start: today,
        end: today,
        nodes: nodes,
      );

      expect(summary.plannedOpenTasks, 4);
      expect(summary.hasLowFocusWarning, isTrue);
    },
  );
}

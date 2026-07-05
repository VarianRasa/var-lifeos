import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/daily_planning_engine.dart';
import 'package:var_app/features/calendar/application/daily_review_builder.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  MindmapNode node(
    String id, {
    required NodeType type,
    required DateTime day,
    String? title,
    DateTime? dueDate,
    NodePriority priority = NodePriority.none,
    bool isPinned = false,
    String body = '',
    List<String> tags = const [],
  }) {
    return MindmapNode.create(
      id: id,
      type: type,
      title: title ?? id,
      day: day,
      dueDate: dueDate,
      priority: priority,
      isPinned: isPinned,
      body: body,
      tags: tags,
      now: day,
    );
  }

  test('buildDailyPlanningSuggestions emits deterministic day actions', () {
    final day = DateTime(2026, 7, 2);
    final yesterday = DateTime(2026, 7, 1);
    final suggestions = buildDailyPlanningSuggestions(
      DailyPlanningContext(
        day: day,
        readyRoutineCount: 2,
        dayNodes: const [],
        allNodes: [
          node(
            'overdue',
            type: NodeType.task,
            day: yesterday,
            dueDate: yesterday,
            priority: NodePriority.high,
          ),
          node(
            'low',
            type: NodeType.task,
            day: yesterday,
            priority: NodePriority.low,
          ),
          node('goal', type: NodeType.goal, day: day, title: 'Launch'),
        ],
      ),
    );

    expect(suggestions.map((item) => item.type), [
      DailyPlanningActionType.applyRoutines,
      DailyPlanningActionType.carryOver,
      DailyPlanningActionType.reviewOverdue,
      DailyPlanningActionType.rescheduleLowPriority,
      DailyPlanningActionType.createGoalNextAction,
      DailyPlanningActionType.applyTemplate,
      DailyPlanningActionType.startDailyReview,
    ]);
    expect(suggestions.first.label, 'Apply 2 routines');
    expect(
      suggestions
          .singleWhere(
            (item) => item.type == DailyPlanningActionType.reviewOverdue,
          )
          .payload,
      ['overdue'],
    );
  });

  test(
    'buildDailyPlanningSuggestions emits tomorrow top tasks from review',
    () {
      final day = DateTime(2026, 7, 2);
      final review = node(
        'review',
        type: NodeType.journal,
        day: day,
        title: dailyReviewTitle(day),
        tags: const ['daily-review'],
        body: '''
## Tomorrow top 3
- Write docs
- Fix sync
''',
      );

      final suggestions = buildDailyPlanningSuggestions(
        DailyPlanningContext(day: day, allNodes: [review], dayNodes: [review]),
      );

      final tomorrow = suggestions.singleWhere(
        (item) => item.type == DailyPlanningActionType.createTomorrowTopTasks,
      );
      expect(tomorrow.nodeId, 'review');
      expect(tomorrow.payload, ['Write docs', 'Fix sync']);
      expect(tomorrow.label, 'Create tomorrow top 2');
    },
  );
}

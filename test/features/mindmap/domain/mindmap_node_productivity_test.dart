import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('MindmapNode preserves effort and review state through JSON', () {
    final now = DateTime(2026, 7, 6, 9);
    final node = MindmapNode.create(
      id: 'node-1',
      type: NodeType.task,
      title: 'Draft launch plan',
      day: now,
      effort: NodeEffort.thirtyMinutes,
      reviewState: NodeReviewState.needsReview,
      contextTags: const ['Deep Work', 'computer', 'deep work'],
      now: now,
    );

    final restored = MindmapNode.fromJson(node.toJson());

    expect(restored.effort, NodeEffort.thirtyMinutes);
    expect(restored.reviewState, NodeReviewState.needsReview);
    expect(restored.contextTags, ['deep work', 'computer']);
  });

  test('MindmapNode defaults productivity fields safely', () {
    final now = DateTime(2026, 7, 6, 9);
    final node = MindmapNode.create(
      id: 'node-1',
      type: NodeType.note,
      title: 'Inbox idea',
      day: now,
      now: now,
    );

    expect(node.effort, NodeEffort.unspecified);
    expect(node.reviewState, NodeReviewState.none);
    expect(node.contextTags, isEmpty);
  });

  test('MindmapNode suggests deterministic review nudges from fields', () {
    final today = DateTime(2026, 7, 6);
    final node = MindmapNode.create(
      id: 'stale-task',
      type: NodeType.task,
      title: 'Old vague task',
      day: today,
      priority: NodePriority.high,
      effort: NodeEffort.unspecified,
      reviewState: NodeReviewState.needsReview,
      dueDate: today.subtract(const Duration(days: 1)),
      checklist: const [
        TaskChecklistItem(id: 'a', title: 'First step'),
        TaskChecklistItem(id: 'b', title: 'Second step'),
      ],
      now: today,
    );

    expect(node.reviewNudges(today), [
      'Pick next action',
      'Set effort',
      'Reschedule overdue node',
      'Finish checklist: 0/2 done',
    ]);
  });

  test('MindmapNode next action score prioritizes urgent actionable work', () {
    final today = DateTime(2026, 7, 6);
    final urgent = MindmapNode.create(
      id: 'urgent',
      type: NodeType.task,
      title: 'Ship fix',
      day: today,
      priority: NodePriority.urgent,
      effort: NodeEffort.fifteenMinutes,
      dueDate: today,
      reviewState: NodeReviewState.needsReview,
      now: today,
    );
    final someday = MindmapNode.create(
      id: 'someday',
      type: NodeType.idea,
      title: 'Maybe later',
      day: today,
      priority: NodePriority.low,
      effort: NodeEffort.oneHourPlus,
      reviewState: NodeReviewState.someday,
      now: today,
    );

    expect(
      urgent.nextActionScore(today),
      greaterThan(someday.nextActionScore(today)),
    );
    expect(someday.isNextActionCandidate(today), isFalse);
  });
}

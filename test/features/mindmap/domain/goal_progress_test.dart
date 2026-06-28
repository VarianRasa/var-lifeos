import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/goal_progress.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('goalMilestones returns trimmed milestones from goal data', () {
    final node = _goalNode(
      data: const {
        'goal': {
          'milestones': [' Prototype ', '', 'Beta'],
          'completedMilestones': ['Prototype'],
        },
      },
    );

    expect(goalMilestones(node), ['Prototype', 'Beta']);
    expect(completedGoalMilestones(node), ['Prototype']);
    expect(nextGoalMilestone(node), 'Beta');
  });

  test(
    'advanceGoalMilestone marks the next milestone and updates progress',
    () {
      final updatedAt = DateTime(2026, 6, 19, 8);
      final node = _goalNode(
        progress: 0.1,
        data: const {
          'goal': {
            'milestones': ['Prototype', 'Beta', 'Launch'],
            'completedMilestones': ['Prototype'],
            'owner': 'Product',
          },
          'custom': 'keep me',
        },
      );

      final updated = advanceGoalMilestone(node, now: updatedAt);

      expect(completedGoalMilestones(updated), ['Prototype', 'Beta']);
      expect(updated.progress, closeTo(2 / 3, 0.0001));
      expect(updated.updatedAt, updatedAt);
      expect(updated.data['custom'], 'keep me');
      expect(updated.data['goal'], {
        'milestones': ['Prototype', 'Beta', 'Launch'],
        'completedMilestones': ['Prototype', 'Beta'],
        'owner': 'Product',
      });
    },
  );

  test('advanceGoalMilestone ignores already completed milestones by key', () {
    final node = _goalNode(
      data: const {
        'goal': {
          'milestones': ['Prototype', 'Beta Launch'],
          'completedMilestones': [' prototype '],
        },
      },
    );

    final updated = advanceGoalMilestone(node, now: DateTime(2026, 6, 19, 8));

    expect(completedGoalMilestones(updated), ['prototype', 'Beta Launch']);
    expect(updated.progress, 1);
  });

  test('advanceGoalMilestone leaves completed or non-goal nodes unchanged', () {
    final goal = _goalNode(
      updatedAt: DateTime(2026, 6, 18, 8),
      data: const {
        'goal': {
          'milestones': ['Prototype'],
          'completedMilestones': ['Prototype'],
        },
      },
    );
    final note = MindmapNode.create(
      id: 'note-1',
      type: NodeType.note,
      title: 'Context',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 8),
    );

    expect(advanceGoalMilestone(goal), goal);
    expect(advanceGoalMilestone(note), note);
  });
}

MindmapNode _goalNode({
  Map<String, Object?> data = const {
    'goal': {
      'milestones': ['Prototype'],
      'completedMilestones': <String>[],
    },
  },
  double progress = 0,
  DateTime? updatedAt,
}) {
  final timestamp = updatedAt ?? DateTime(2026, 6, 18, 8);
  return MindmapNode.create(
    id: 'goal-1',
    type: NodeType.goal,
    title: 'Launch v1',
    day: DateTime(2026, 6, 18),
    data: data,
    progress: progress,
    now: timestamp,
  );
}

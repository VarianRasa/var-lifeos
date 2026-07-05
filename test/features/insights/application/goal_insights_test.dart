import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/insights/application/goal_insights.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('goalProgressFor parses milestone completion', () {
    final goal = MindmapNode.create(
      id: 'goal',
      type: NodeType.goal,
      title: 'Launch',
      day: DateTime(2026, 7, 14),
      data: const {
        'goal': {
          'milestones': ['Prototype', 'Beta', 'Launch'],
          'completedMilestones': ['Prototype'],
        },
      },
    );

    expect(goalProgressFor(goal), closeTo(1 / 3, 0.001));
  });

  test('buildGoalInsightSummary detects stalled and recent goals', () {
    final today = DateTime(2026, 7, 14);
    final nodes = [
      MindmapNode.create(
        id: 'stalled',
        type: NodeType.goal,
        title: 'Stalled goal',
        day: today.addDays(-30),
        data: const {
          'goal': {
            'milestones': ['Plan', 'Ship'],
            'completedMilestones': ['Plan'],
          },
        },
        now: DateTime(2026, 6, 20),
      ),
      MindmapNode.create(
        id: 'recent',
        type: NodeType.goal,
        title: 'Recent goal',
        day: today,
        relatedNodeIds: const ['task-1'],
        data: const {
          'goal': {
            'milestones': ['Draft', 'Publish'],
            'completedMilestones': ['Draft'],
          },
        },
        now: DateTime(2026, 7, 13),
      ),
      MindmapNode.create(
        id: 'done',
        type: NodeType.goal,
        title: 'Done goal',
        day: today,
        status: NodeStatus.done,
        data: const {
          'goal': {
            'milestones': ['Done'],
            'completedMilestones': ['Done'],
          },
        },
        now: DateTime(2026, 7, 14),
      ),
    ];

    final summary = buildGoalInsightSummary(today: today, nodes: nodes);

    expect(summary.goalCount, 3);
    expect(summary.completedCount, 1);
    expect(summary.inProgressCount, 2);
    expect(summary.stalledGoals.single.node.title, 'Stalled goal');
    expect(summary.recentlyProgressedGoals.first.node.title, 'Recent goal');
    expect(summary.needsNextActionGoals.single.node.title, 'Stalled goal');
    expect(summary.milestoneMomentumCount, 1);
  });
}

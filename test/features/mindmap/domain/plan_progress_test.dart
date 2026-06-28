import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/plan_progress.dart';

void main() {
  test('planSteps returns trimmed steps and the next open step', () {
    final node = _planNode(
      data: const {
        'plan': {
          'steps': [' Scope ', '', 'Build'],
          'completedSteps': ['Scope'],
        },
      },
    );

    expect(planSteps(node), ['Scope', 'Build']);
    expect(completedPlanSteps(node), ['Scope']);
    expect(nextPlanStep(node), 'Build');
  });

  test('advancePlanStep marks the next step and updates progress', () {
    final updatedAt = DateTime(2026, 6, 20, 9);
    final node = _planNode(
      data: const {
        'plan': {
          'steps': ['Scope', 'Build', 'Review'],
          'completedSteps': ['Scope'],
          'cadence': 'weekly',
        },
        'custom': 'keep me',
      },
    );

    final updated = advancePlanStep(node, now: updatedAt);

    expect(completedPlanSteps(updated), ['Scope', 'Build']);
    expect(updated.progress, closeTo(2 / 3, 0.0001));
    expect(updated.status, NodeStatus.doing);
    expect(updated.updatedAt, updatedAt);
    expect(updated.data['custom'], 'keep me');
    expect(updated.data['plan'], {
      'steps': ['Scope', 'Build', 'Review'],
      'completedSteps': ['Scope', 'Build'],
      'cadence': 'weekly',
    });
  });

  test('advancePlanStep completes the plan after the final step', () {
    final node = _planNode(
      data: const {
        'plan': {
          'steps': ['Scope', 'Build'],
          'completedSteps': [' scope '],
        },
      },
    );

    final updated = advancePlanStep(node, now: DateTime(2026, 6, 20, 9));

    expect(completedPlanSteps(updated), ['scope', 'Build']);
    expect(updated.progress, 1);
    expect(updated.status, NodeStatus.done);
    expect(updated.isDone, isTrue);
  });

  test('advancePlanStep leaves completed or non-plan nodes unchanged', () {
    final completePlan = _planNode(
      data: const {
        'plan': {
          'steps': ['Scope'],
          'completedSteps': ['Scope'],
        },
      },
    );
    final note = MindmapNode.create(
      id: 'note-1',
      type: NodeType.note,
      title: 'Context',
      day: DateTime(2026, 6, 20),
      now: DateTime(2026, 6, 20, 8),
    );

    expect(advancePlanStep(completePlan), completePlan);
    expect(advancePlanStep(note), note);
  });
}

MindmapNode _planNode({required Map<String, Object?> data}) {
  return MindmapNode.create(
    id: 'plan-1',
    type: NodeType.plan,
    title: 'Sprint plan',
    day: DateTime(2026, 6, 20),
    data: data,
    now: DateTime(2026, 6, 20, 8),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/domain/project_plan.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/plan_node_editor.dart';

void main() {
  testWidgets('plan editor renders hierarchy and emits task completion', (
    tester,
  ) async {
    final payloads = <Object>[];
    final node = _node();
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
        home: Scaffold(
          body: SizedBox(
            width: 720,
            height: 900,
            child: PlanNodeEditor(
              node: node,
              payload: PlanPayload.fromNode(node),
              onTitleChanged: (_) {},
              onBodyChanged: (_) {},
              onPayloadChanged: payloads.add,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('plan-project-editor')), findsOne);
    expect(find.byKey(const ValueKey<String>('plan-phase-phase')), findsOne);
    expect(
      find.byKey(const ValueKey<String>('plan-milestone-milestone')),
      findsOne,
    );
    expect(find.byKey(const ValueKey<String>('plan-task-task')), findsOne);

    await tester.tap(
      find.byKey(const ValueKey<String>('plan-task-toggle-task')),
    );
    await tester.pump();

    final updated = payloads.single as PlanPayload;
    expect(updated.project.taskById('task')?.status, ProjectTaskStatus.done);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan task drag handle supports free pointer movement', (
    tester,
  ) async {
    final node = _node();
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 720,
            height: 900,
            child: PlanNodeEditor(
              node: node,
              payload: PlanPayload.fromNode(node),
              onTitleChanged: (_) {},
              onBodyChanged: (_) {},
              onPayloadChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final draggable =
        tester.widget(find.byKey(const ValueKey<String>('plan-task-drag-task')))
            as Draggable<Object?>;
    expect(draggable.axis, isNull);
  });
}

MindmapNode _node() {
  final now = DateTime(2026, 7, 16, 9);
  const project = ProjectPlan(
    status: ProjectPlanStatus.active,
    phases: <ProjectPhase>[
      ProjectPhase(
        id: 'phase',
        title: 'Delivery',
        order: 0,
        milestones: <ProjectMilestone>[
          ProjectMilestone(
            id: 'milestone',
            title: 'Beta',
            order: 0,
            tasks: <ProjectTask>[
              ProjectTask(id: 'task', title: 'Ship beta', order: 0),
            ],
          ),
        ],
      ),
    ],
  );
  final node = MindmapNode.create(
    id: 'plan',
    type: NodeType.plan,
    title: 'Launch plan',
    day: now,
    now: now,
  );
  return node.copyWith(
    data: const PlanPayload(project: project).toData(node.data),
  );
}

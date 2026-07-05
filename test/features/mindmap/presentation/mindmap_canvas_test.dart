import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/kanban_board.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';

void main() {
  testWidgets(
    'MindmapCanvas renders positioned nodes inside an InteractiveViewer',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final nodes = [
        MindmapNode.create(
          id: 'task-1',
          type: NodeType.task,
          title: 'Plan the day',
          body: 'Pick top three outcomes.',
          day: day,
          position: const CanvasPosition(-120, -40),
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'note-1',
          type: NodeType.note,
          title: 'Context',
          day: day,
          position: const CanvasPosition(90, 24),
          now: DateTime(2026, 6, 18, 9),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: MindmapCanvas(nodes: nodes, highlightedNodeId: 'note-1'),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('mindmap-canvas')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byKey(const ValueKey('mindmap-node-task-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('mindmap-node-note-1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mindmap-highlight-note-1')),
        findsOneWidget,
      );
      expect(find.text('Plan the day'), findsOneWidget);
      expect(find.text('Context'), findsOneWidget);
      expect(find.text('Task'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
    },
  );

  testWidgets('MindmapCanvas does not paint cursor trails on hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(body: MindmapCanvas(nodes: [])),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byKey(const ValueKey('mindmap-canvas'))),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();

    final backgroundPaints = tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    );
    final hasCursorTrail = backgroundPaints.any((paint) {
      final painter = paint.painter as dynamic;
      try {
        // ignore: avoid_dynamic_calls
        return (painter.cursorTrail as List).isNotEmpty;
      } catch (_) {
        return false;
      }
    });

    expect(hasCursorTrail, isFalse);
  });

  testWidgets('MindmapCanvas exposes toolbar state and shortcut help', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(body: MindmapCanvas(nodes: [])),
      ),
    );

    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.text('100%'));
    await tester.pumpAndSettle();

    expect(find.text('Grid on'), findsOneWidget);
    expect(find.text('Snap off'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mindmap-shortcut-help')));
    await tester.pumpAndSettle();

    expect(find.text('Mindmap shortcuts'), findsOneWidget);
    expect(find.text('Ctrl+F'), findsOneWidget);
    expect(find.text('Focus search'), findsOneWidget);
    expect(find.text('Ctrl+G'), findsOneWidget);
    expect(find.text('Toggle grid'), findsOneWidget);
  });

  testWidgets('MindmapCanvas disables primary-button canvas panning', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(body: MindmapCanvas(nodes: [])),
      ),
    );

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('mindmap-canvas')),
    );

    expect(viewer.panEnabled, isFalse);
  });

  testWidgets('MindmapCanvas keeps node drag under cursor when zoomed out', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'task-zoom',
      type: NodeType.task,
      title: 'Zoom drag',
      day: day,
      position: const CanvasPosition(-120, -40),
      now: DateTime(2026, 6, 18, 8),
    );
    CanvasPosition? movedPosition;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeMoved: (_, position) {
              movedPosition = position;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom Out'));
    await tester.pumpAndSettle();

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('mindmap-canvas')),
    );
    final scale = viewer.transformationController!.value.getMaxScaleOnAxis();
    expect(scale, lessThan(1));

    await tester.drag(
      find.byKey(const ValueKey('mindmap-node-task-zoom')),
      const Offset(32, 16),
    );
    await tester.pump();

    expect(movedPosition, CanvasPosition(-120 + 32 / scale, -40 + 16 / scale));
  });

  testWidgets('MindmapCanvas reports a dragged node position', (tester) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Plan the day',
      day: day,
      position: const CanvasPosition(-120, -40),
      now: DateTime(2026, 6, 18, 8),
    );
    CanvasPosition? movedPosition;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeMoved: (_, position) {
              movedPosition = position;
            },
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('mindmap-node-task-1')),
      const Offset(32, 16),
    );
    await tester.pump();

    expect(movedPosition, const CanvasPosition(-88, -24));
  });

  testWidgets('MindmapCanvas reports a tapped node selection', (tester) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'note-1',
      type: NodeType.note,
      title: 'Context',
      day: day,
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 6, 18, 9),
    );
    MindmapNode? selectedNode;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeSelected: (node) {
              selectedNode = node;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('mindmap-node-note-1')));
    await tester.pump();

    expect(selectedNode?.id, 'note-1');
  });

  testWidgets('MindmapCanvas reports a task done toggle', (tester) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Plan the day',
      day: day,
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 6, 18, 8),
    );
    bool? toggledValue;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onTaskDoneChanged: (_, isDone) {
              toggledValue = isDone;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('mindmap-task-toggle-task-1')));
    await tester.pump();

    expect(toggledValue, isTrue);
  });

  testWidgets('MindmapCanvas reports a task checklist advance request', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Launch task',
      day: day,
      checklist: const [
        TaskChecklistItem(id: 'item-1', title: 'Draft copy'),
        TaskChecklistItem(id: 'item-2', title: 'Review scope'),
      ],
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 6, 18, 8),
    );
    MindmapNode? advancedNode;
    MindmapNode? selectedNode;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeSelected: (node) {
              selectedNode = node;
            },
            onTaskChecklistItemCompleted: (node) {
              advancedNode = node;
            },
          ),
        ),
      ),
    );

    await _pressButton(
      tester,
      find.byKey(const ValueKey('mindmap-task-checklist-next-task-1')),
    );

    expect(advancedNode?.id, 'task-1');
    expect(selectedNode, isNull);
  });

  testWidgets('MindmapCanvas disables checklist advance when items are done', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Launch task',
      day: day,
      checklist: const [
        TaskChecklistItem(id: 'item-1', title: 'Draft copy', isDone: true),
      ],
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onTaskChecklistItemCompleted: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Checklist done'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('mindmap-task-checklist-next-task-1')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('MindmapCanvas reports a habit completion request', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'habit-1',
      type: NodeType.habit,
      title: 'Workout',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'habit': {'recurrence': 'daily', 'target': '30 min'},
      },
      now: DateTime(2026, 6, 18, 8),
    );
    MindmapNode? loggedNode;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onHabitCompleted: (node) {
              loggedNode = node;
            },
          ),
        ),
      ),
    );

    await _pressButton(
      tester,
      find.byKey(const ValueKey('mindmap-habit-log-habit-1')),
    );

    expect(loggedNode?.id, 'habit-1');
  });

  testWidgets('MindmapCanvas disables habit logging once completed today', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'habit-1',
      type: NodeType.habit,
      title: 'Workout',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'habit': {
          'recurrence': 'daily',
          'completions': ['2026-06-18'],
        },
      },
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(nodes: [node], onHabitCompleted: (_) {}),
        ),
      ),
    );

    expect(find.text('Logged'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('mindmap-habit-log-habit-1')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('MindmapCanvas reports a goal milestone advance request', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'goal-1',
      type: NodeType.goal,
      title: 'Launch v1',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'goal': {
          'milestones': ['Prototype', 'Beta'],
          'completedMilestones': ['Prototype'],
        },
      },
      now: DateTime(2026, 6, 18, 8),
    );
    MindmapNode? advancedNode;
    MindmapNode? selectedNode;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeSelected: (node) {
              selectedNode = node;
            },
            onGoalMilestoneAdvanced: (node) {
              advancedNode = node;
            },
          ),
        ),
      ),
    );

    await _pressButton(
      tester,
      find.byKey(const ValueKey('mindmap-goal-advance-goal-1')),
    );

    expect(advancedNode?.id, 'goal-1');
    expect(selectedNode, isNull);
  });

  testWidgets('MindmapCanvas disables goal advancement when complete', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'goal-1',
      type: NodeType.goal,
      title: 'Launch v1',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'goal': {
          'milestones': ['Prototype', 'Beta'],
          'completedMilestones': ['Prototype', 'Beta'],
        },
      },
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(nodes: [node], onGoalMilestoneAdvanced: (_) {}),
        ),
      ),
    );

    expect(find.text('Complete'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('mindmap-goal-advance-goal-1')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('MindmapCanvas reports a plan step advance request', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'plan-1',
      type: NodeType.plan,
      title: 'Sprint plan',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'plan': {
          'steps': ['Scope', 'Build'],
          'completedSteps': ['Scope'],
        },
      },
      now: DateTime(2026, 6, 18, 8),
    );
    MindmapNode? advancedNode;
    MindmapNode? selectedNode;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeSelected: (node) {
              selectedNode = node;
            },
            onPlanStepAdvanced: (node) {
              advancedNode = node;
            },
          ),
        ),
      ),
    );

    await _pressButton(
      tester,
      find.byKey(const ValueKey('mindmap-plan-advance-plan-1')),
    );

    expect(advancedNode?.id, 'plan-1');
    expect(selectedNode, isNull);
  });

  testWidgets('MindmapCanvas disables plan advancement when complete', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'plan-1',
      type: NodeType.plan,
      title: 'Sprint plan',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'plan': {
          'steps': ['Scope', 'Build'],
          'completedSteps': ['Scope', 'Build'],
        },
      },
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(nodes: [node], onPlanStepAdvanced: (_) {}),
        ),
      ),
    );

    expect(find.text('Plan done'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('mindmap-plan-advance-plan-1')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('MindmapCanvas renders advanced node metadata chips', (
    tester,
  ) async {
    final today = DateTime.now();
    final node = MindmapNode.create(
      id: 'task-advanced',
      type: NodeType.task,
      title: 'Launch task',
      day: today,
      status: NodeStatus.doing,
      priority: NodePriority.high,
      tags: const ['work'],
      dueDate: today,
      progress: 0.5,
      checklist: const [
        TaskChecklistItem(id: 'item-1', title: 'Draft copy', isDone: true),
        TaskChecklistItem(id: 'item-2', title: 'Review scope'),
      ],
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );

    expect(find.text('High'), findsOneWidget);
    expect(find.text('Doing'), findsOneWidget);
    expect(find.text('#work'), findsOneWidget);
    expect(find.text('Due Today'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('MindmapCanvas shows empty search state when no nodes match', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'note-1',
      type: NodeType.note,
      title: 'Project context',
      day: day,
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );

    await tester.tap(find.text('Show search'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-search-empty-state')),
      findsOneWidget,
    );
    expect(find.text('No nodes match “missing”'), findsOneWidget);
    expect(find.byKey(const ValueKey('mindmap-node-note-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mindmap-search-clear-empty')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-search-empty-state')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('mindmap-node-note-1')), findsOneWidget);
  });

  testWidgets('MindmapCanvas type filter chips filter visible nodes', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final task = MindmapNode.create(
      id: 'task-filter',
      type: NodeType.task,
      title: 'Task item',
      day: day,
      position: const CanvasPosition(-80, 0),
      now: DateTime(2026, 6, 18, 8),
    );
    final contact = MindmapNode.create(
      id: 'contact-filter',
      type: NodeType.contact,
      title: 'Contact item',
      day: day,
      position: const CanvasPosition(80, 0),
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: MindmapCanvas(nodes: [task, contact])),
      ),
    );

    await tester.tap(find.text('Show search'));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mindmap-search-filter-task')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-node-task-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mindmap-node-contact-filter')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('mindmap-search-filter-all')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-node-task-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mindmap-node-contact-filter')),
      findsOneWidget,
    );
  });

  testWidgets('MindmapCanvas renders relation count metadata', (tester) async {
    final node = MindmapNode.create(
      id: 'task-linked',
      type: NodeType.task,
      title: 'Connected task',
      day: DateTime(2026, 6, 18),
      relatedNodeIds: const ['note-1', 'goal-1'],
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );

    expect(find.text('2 links'), findsOneWidget);
  });

  testWidgets('MindmapCanvas renders project and area metadata chips', (
    tester,
  ) async {
    final node = MindmapNode.create(
      id: 'task-context',
      type: NodeType.task,
      title: 'Scoped task',
      day: DateTime(2026, 6, 18),
      project: 'Launch App',
      area: 'Work Ops',
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );

    expect(find.text('Project: Launch App'), findsOneWidget);
    expect(find.text('Area: Work Ops'), findsOneWidget);
  });

  testWidgets('MindmapCanvas renders type-specific metadata chips', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final nodes = [
      MindmapNode.create(
        id: 'habit-1',
        type: NodeType.habit,
        title: 'Workout',
        day: day,
        data: const {
          'habit': {
            'recurrence': 'daily',
            'target': '30 min',
            'completions': ['2026-06-16', '2026-06-17', '2026-06-18'],
          },
        },
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'goal-1',
        type: NodeType.goal,
        title: 'Launch v1',
        day: day,
        data: const {
          'goal': {
            'milestones': ['Prototype', 'Beta'],
            'completedMilestones': ['Prototype'],
          },
        },
        now: DateTime(2026, 6, 18, 9),
      ),
      MindmapNode.create(
        id: 'plan-1',
        type: NodeType.plan,
        title: 'Sprint plan',
        day: day,
        data: const {
          'plan': {
            'steps': ['Scope', 'Build'],
          },
        },
        now: DateTime(2026, 6, 18, 10),
      ),
      MindmapNode.create(
        id: 'note-1',
        type: NodeType.note,
        title: 'Reference',
        day: day,
        data: const {
          'note': {'source': 'Spec'},
        },
        now: DateTime(2026, 6, 18, 11),
      ),
      MindmapNode.create(
        id: 'journal-1',
        type: NodeType.journal,
        title: 'Daily journal',
        day: day,
        data: const {
          'journal': {'mood': 4, 'energy': 3, 'isWeeklyReview': true},
        },
        now: DateTime(2026, 6, 18, 12),
      ),
      MindmapNode.create(
        id: 'journal-monthly',
        type: NodeType.journal,
        title: 'Monthly review',
        day: day,
        data: const {
          'journal': {'isMonthlyReview': true},
        },
        now: DateTime(2026, 6, 18, 13),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: MindmapCanvas(nodes: nodes)),
      ),
    );

    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('3 streak'), findsOneWidget);
    expect(find.text('1/2 milestones'), findsOneWidget);
    expect(find.text('2 steps'), findsOneWidget);
    expect(find.text('Source: Spec'), findsOneWidget);
    expect(find.text('Mood 4'), findsOneWidget);
    expect(find.text('Energy 3'), findsOneWidget);
    expect(find.text('Weekly Review'), findsOneWidget);
    expect(find.text('Monthly Review'), findsOneWidget);
  });

  testWidgets('MindmapCanvas renders calendar payload summary', (tester) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'meeting-1',
      type: NodeType.note,
      title: 'Launch sync',
      day: day,
      data: const {
        'calendar_kind': 'meeting',
        'agenda': 'Decide launch scope',
        'attendees': 'Maya\nRafi',
      },
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );

    expect(
      find.byKey(const ValueKey('mindmap-calendar-payload-meeting-1')),
      findsOneWidget,
    );
    expect(find.text('Meeting · 2 attendees'), findsOneWidget);
    expect(find.text('Decide launch scope'), findsOneWidget);
  });

  testWidgets('MindmapCanvas renders kanban columns and advances a card', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    const board = KanbanBoard(
      cards: [
        KanbanCard(id: 'card-1', title: 'Draft copy'),
        KanbanCard(
          id: 'card-2',
          title: 'Review scope',
          column: KanbanColumn.doing,
        ),
        KanbanCard(
          id: 'card-3',
          title: 'Ship update',
          column: KanbanColumn.done,
        ),
      ],
    );
    final node = MindmapNode.create(
      id: 'kanban-1',
      type: NodeType.kanban,
      title: 'Launch board',
      day: day,
      data: {'kanban': board.toJson()},
      now: DateTime(2026, 6, 18, 8),
    );
    String? advancedCardId;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onKanbanCardAdvanced: (_, cardId) {
              advancedCardId = cardId;
            },
          ),
        ),
      ),
    );

    expect(find.text('Todo'), findsOneWidget);
    expect(find.text('Doing'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Draft copy'), findsOneWidget);
    expect(find.text('Review scope'), findsOneWidget);
    expect(find.text('Ship update'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('kanban-advance-kanban-1-card-1')),
    );
    await tester.pump();

    expect(advancedCardId, 'card-1');
  });

  testWidgets('MindmapCanvas does not select a node when advancing a card', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    const board = KanbanBoard(
      cards: [KanbanCard(id: 'card-1', title: 'Draft copy')],
    );
    final node = MindmapNode.create(
      id: 'kanban-1',
      type: NodeType.kanban,
      title: 'Launch board',
      day: day,
      data: {'kanban': board.toJson()},
      now: DateTime(2026, 6, 18, 8),
    );
    String? advancedCardId;
    MindmapNode? selectedNode;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeSelected: (node) {
              selectedNode = node;
            },
            onKanbanCardAdvanced: (_, cardId) {
              advancedCardId = cardId;
            },
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('kanban-advance-kanban-1-card-1')),
    );
    await tester.pump();

    expect(advancedCardId, 'card-1');
    expect(selectedNode, isNull);
  });

  testWidgets(
    'MindmapCanvas triggers onNodeDisconnected when re-linking connected nodes',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final node1 = MindmapNode.create(
        id: 'task-1',
        type: NodeType.task,
        title: 'Task 1',
        day: day,
        position: const CanvasPosition(-100, -100),
        relatedNodeIds: ['task-2'],
        now: day,
      );
      final node2 = MindmapNode.create(
        id: 'task-2',
        type: NodeType.task,
        title: 'Task 2',
        day: day,
        position: const CanvasPosition(100, 100),
        now: day,
      );

      MindmapNode? disconnectedSource;
      MindmapNode? disconnectedTarget;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(
              nodes: [node1, node2],
              onNodeDisconnected: (src, tgt) {
                disconnectedSource = src;
                disconnectedTarget = tgt;
              },
            ),
          ),
        ),
      );

      final nodeFinder = find.byKey(const ValueKey('mindmap-node-task-1'));
      final center = tester.getCenter(nodeFinder);

      // Node is Size(340, 320). Port is at right: -6, top: 88 (center y is 88 + 9 = 97).
      // Center of node is at (170, 160) local.
      // Output port local coordinates: dx = 340 - 9 = 331. dy = 97.
      // Offset from center to output port: dx = 331 - 170 = 161. dy = 97 - 160 = -63.
      final portGlobal = center + const Offset(161, -63);

      final gesture = await tester.startGesture(portGlobal);
      await tester.pump();

      // Drag to node 2 input port. Node 2 is at CanvasPosition(100, 100).
      // Since it's shifted by (200, 200) relative to node 1.
      // Node 2 input port local coordinates: dx = 9. dy = 97.
      // Offset from node 2 center: dx = 9 - 170 = -161. dy = 97 - 160 = -63.
      final node2Finder = find.byKey(const ValueKey('mindmap-node-task-2'));
      final node2Center = tester.getCenter(node2Finder);
      final targetPortGlobal = node2Center + const Offset(-161, -63);

      await gesture.moveTo(targetPortGlobal);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(disconnectedSource?.id, 'task-1');
      expect(disconnectedTarget?.id, 'task-2');
    },
  );
}

Future<void> _pressButton(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  final widget = tester.widget(finder);
  if (widget is ButtonStyleButton) {
    widget.onPressed?.call();
  } else if (widget is IconButton) {
    widget.onPressed?.call();
  } else {
    await tester.tap(finder, warnIfMissed: false);
  }
  await tester.pump();
}

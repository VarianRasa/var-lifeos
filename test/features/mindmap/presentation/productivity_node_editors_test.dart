import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/kanban_board.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/checklist_node_editor.dart';
import 'package:var_app/features/mindmap/presentation/node_type_content.dart';
import 'package:var_app/features/mindmap/presentation/node_type_inline_editor.dart';
import 'package:var_app/features/mindmap/presentation/widgets/sticky_note_card_widget.dart';

void main() {
  const productivityTypes = <NodeType>[
    NodeType.task,
    NodeType.kanban,
    NodeType.plan,
    NodeType.note,
    NodeType.habit,
    NodeType.goal,
    NodeType.routine,
    NodeType.checklist,
    NodeType.timer,
  ];
  const presets = <NodeSizePreset>[
    NodeSizePreset.compact,
    NodeSizePreset.standard,
    NodeSizePreset.large,
    NodeSizePreset.wide,
  ];

  for (final type in productivityTypes) {
    for (final preset in presets) {
      testWidgets('${type.name} renders adaptive ${preset.name} content', (
        tester,
      ) async {
        final node = _node(type);
        await tester.pumpWidget(
          _app(
            buildNodeTypeContent(
              NodeRenderContext(node: node, effectivePreset: preset),
            ),
          ),
        );

        if (type == NodeType.note) {
          expect(find.byType(StickyNoteCardWidget), findsOneWidget);
        } else {
          expect(
            find.byKey(
              ValueKey<String>('productivity-${type.name}-${preset.name}'),
            ),
            findsOneWidget,
          );
        }
        expect(find.text(node.title), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (type == NodeType.note || preset == NodeSizePreset.compact) {
          expect(
            find.byKey(ValueKey<String>('productivity-${type.name}-details')),
            findsNothing,
          );
        } else {
          expect(
            find.byKey(ValueKey<String>('productivity-${type.name}-details')),
            findsOneWidget,
          );
        }
      });
    }
  }

  testWidgets('habit editor updates target recurrence and completion', (
    tester,
  ) async {
    final node = _node(NodeType.habit);
    final payloads = <Object>[];
    final nodeDrafts = <MindmapNode>[];
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          NodeEditContext(
            node: node,
            typedDraft: HabitRoutinePayload.fromNode(node),
            effectivePreset: NodeSizePreset.standard,
            validationErrors: const [],
            onTitleChanged: (_) {},
            onBodyChanged: (_) {},
            onDraftChanged: payloads.add,
            onNodeDraftChanged: nodeDrafts.add,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('productivity-habit-target-field')),
      '45 minutes',
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('productivity-habit-recurrence-weekdays'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('habit-toggle-today')));
    await tester.pump();

    expect((payloads.first as HabitRoutinePayload).target, '45 minutes');
    expect((payloads.last as HabitRoutinePayload).recurrence, 'weekdays');
    expect(nodeDrafts, hasLength(1));
    expect(
      HabitRoutinePayload.fromNode(nodeDrafts.single).completions,
      contains('2026-07-13'),
    );
    expect(find.text('1 / 7 days'), findsOneWidget);
    expect(find.text('1 total'), findsOneWidget);
  });

  testWidgets('goal fixed editor manages milestones without scroll', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = _node(NodeType.goal);
    final payloads = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
        home: Scaffold(
          body: SizedBox(
            width: 760,
            height: 620,
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: GoalPayload.fromNode(node),
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const [],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: payloads.add,
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('productivity-goal-editor')),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('Motivation and outcome'), findsOneWidget);
    expect(find.text('1/2 milestones'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('goal-new-milestone-field')),
      'Launch',
    );
    await tester.tap(find.byKey(const ValueKey('goal-add-milestone')));
    await tester.pump();

    expect((payloads.last as GoalPayload).milestones, contains('Launch'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('goal editor supports unbounded full-page layout', (
    tester,
  ) async {
    final node = _node(NodeType.goal);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: GoalPayload.fromNode(node),
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const [],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (_) {},
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('productivity-goal-editor')),
      findsOneWidget,
    );
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('routine fixed editor exposes controls without scroll', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = _node(NodeType.routine);
    final payloads = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
        home: Scaffold(
          body: SizedBox(
            width: 760,
            height: 560,
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: HabitRoutinePayload.fromNode(node),
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const [],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: payloads.add,
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('productivity-routine-editor')),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('Trigger and steps'), findsOneWidget);
    expect(find.text('Success target'), findsOneWidget);
    expect(find.text('Last 4 weeks'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('routine-four-week-tracker')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('productivity-routine-recurrence-weekly'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('routine-toggle-today')));
    await tester.pump();

    expect((payloads.first as HabitRoutinePayload).recurrence, 'weekly');
    expect(
      (payloads.last as HabitRoutinePayload).completions,
      contains('2026-07-13'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('routine editor supports unbounded full-page layout', (
    tester,
  ) async {
    final node = _node(NodeType.routine);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: HabitRoutinePayload.fromNode(node),
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const [],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (_) {},
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('productivity-routine-editor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('routine-four-week-tracker')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline title editing only emits draft callback', (tester) async {
    final titles = <String>[];
    final payloads = <Object>[];
    final nodeDrafts = <MindmapNode>[];
    final node = _node(NodeType.task);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          NodeEditContext(
            node: node,
            typedDraft: TaskChecklistPayload.fromNode(node),
            effectivePreset: NodeSizePreset.standard,
            validationErrors: const [],
            onTitleChanged: titles.add,
            onBodyChanged: (_) {},
            onDraftChanged: payloads.add,
            onNodeDraftChanged: nodeDrafts.add,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('productivity-task-title-field')),
      'Updated task',
    );
    await tester.pump();

    expect(titles, ['Updated task']);
    expect(payloads, isEmpty);
    expect(nodeDrafts, isEmpty);
  });

  testWidgets('task subtask actions fit a narrow mobile workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final node = _node(NodeType.task).copyWith(
      checklist: const [
        TaskChecklistItem(
          id: 'mobile-subtask',
          title: 'Long mobile subtask title that still needs usable actions',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 760,
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: TaskChecklistPayload.fromNode(node),
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const [],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (_) {},
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final actions = find.byTooltip('Subtask actions');
    await tester.ensureVisible(actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();

    expect(find.text('Edit subtask'), findsOneWidget);
    expect(find.text('Delete subtask'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task editor exposes priority deadline and workspace sections', (
    tester,
  ) async {
    final node = _node(
      NodeType.task,
    ).copyWith(priority: NodePriority.high, dueDate: DateTime(2026, 7, 20));
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          NodeEditContext(
            node: node,
            typedDraft: TaskChecklistPayload.fromNode(node),
            effectivePreset: NodeSizePreset.standard,
            validationErrors: const [],
            onTitleChanged: (_) {},
            onBodyChanged: (_) {},
            onDraftChanged: (_) {},
            onNodeDraftChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Deadline'), findsOneWidget);
    expect(find.text('Subtasks'), findsOneWidget);
    final descriptionField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('productivity-task-body-field')),
        matching: find.byType(TextField),
      ),
    );
    expect(descriptionField.maxLength, isNull);
    expect(descriptionField.inputFormatters, hasLength(1));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(find.text('Assignees'), findsNothing);
    expect(find.text('Attachments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('task fixed workspace keeps all sections reachable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = _node(NodeType.task);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
        home: Scaffold(
          body: SizedBox(
            width: 620,
            height: 650,
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: TaskChecklistPayload.fromNode(node),
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const [],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (_) {},
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final taskEditor = find.byKey(
      const ValueKey<String>('task-inline-editor-task'),
    );
    expect(
      find.descendant(
        of: taskEditor,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Attachments'),
      240,
      scrollable: find
          .descendant(of: taskEditor, matching: find.byType(Scrollable))
          .first,
    );
    expect(find.text('Attachments'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('checklist editor exposes reachable rich controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = _node(NodeType.checklist);
    final emitted = <ChecklistPayload>[];
    const payload = ChecklistPayload(
      items: <ChecklistEntry>[
        ChecklistEntry(id: 'one', title: 'First'),
        ChecklistEntry(id: 'two', title: 'Second', isDone: true),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 900,
            child: ChecklistNodeEditor(
              node: node,
              payload: payload,
              onTitleChanged: (_) {},
              onBodyChanged: (_) {},
              onPayloadChanged: emitted.add,
            ),
          ),
        ),
      ),
    );

    final editor = find.byKey(const ValueKey<String>('checklist-node-editor'));
    expect(
      find.descendant(of: editor, matching: find.byType(SingleChildScrollView)),
      findsOneWidget,
    );
    expect(find.text('1/2 completed'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('checklist-add-field')),
      'Third',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('checklist-add-action')),
    );
    await tester.pump();

    expect(emitted.last.items.map((item) => item.title), contains('Third'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('active checklist reorder preserves completed item slots', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = _node(NodeType.checklist);
    final emitted = <ChecklistPayload>[];
    const payload = ChecklistPayload(
      items: <ChecklistEntry>[
        ChecklistEntry(id: 'active-a', title: 'Active A'),
        ChecklistEntry(id: 'done', title: 'Done', isDone: true),
        ChecklistEntry(id: 'active-b', title: 'Active B'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 900,
            child: ChecklistNodeEditor(
              node: node,
              payload: payload,
              onTitleChanged: (_) {},
              onBodyChanged: (_) {},
              onPayloadChanged: emitted.add,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Active'));
    await tester.pump();
    expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));

    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey<String>('checklist-items')),
    );
    list.onReorderItem!(1, 0);
    await tester.pump();

    expect(emitted.last.items.map((item) => item.id), <String>[
      'active-b',
      'done',
      'active-a',
    ]);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.byType(ReorderableDragStartListener), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('kanban editor renders flexible rich board without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = _node(NodeType.kanban).copyWith(
      data: <String, Object?>{
        'kanban': KanbanBoard(
          cards: <KanbanCard>[
            KanbanCard(
              id: 'rich-card',
              title: 'Prepare release',
              description: 'Verify release scope and supporting assets.',
              priority: KanbanPriority.high,
              dueDate: DateTime(2026, 7, 20),
              labels: const <String>['release'],
              checklist: const <KanbanChecklistItem>[
                KanbanChecklistItem(id: 'review', title: 'Review'),
              ],
              attachments: const <KanbanAttachmentReference>[
                KanbanAttachmentReference(
                  id: 'brief',
                  fileName: 'brief.pdf',
                  mimeType: 'application/pdf',
                  byteLength: 42,
                ),
              ],
            ),
          ],
        ).toJson(),
      },
    );
    final size = InlineNodeWorkspacePolicy.expandedSizeForNode(node);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: KanbanPayload.fromNode(node),
                effectivePreset: NodeSizePreset.wide,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (_) {},
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('kanban-add-column')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('kanban-column-backlog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('kanban-column-in-progress')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('kanban-column-done')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('kanban-card-rich-card')),
      findsOneWidget,
    );
    expect(find.text('High'), findsWidgets);
    expect(find.text('brief.pdf'), findsOneWidget);
    expect(find.text('All cards complete'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('kanban card checklist toggles and attachment opens inline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payloads = <KanbanPayload>[];
    final opened = <KanbanAttachmentReference>[];
    const attachment = KanbanAttachmentReference(
      id: 'brief',
      fileName: 'brief.pdf',
      mimeType: 'application/pdf',
      byteLength: 42,
    );
    final node = _node(NodeType.kanban).copyWith(
      data: <String, Object?>{
        'kanban': const KanbanBoard(
          cards: <KanbanCard>[
            KanbanCard(
              id: 'interactive',
              title: 'Interactive card',
              checklist: <KanbanChecklistItem>[
                KanbanChecklistItem(id: 'review', title: 'Review scope'),
              ],
              attachments: <KanbanAttachmentReference>[attachment],
            ),
          ],
        ).toJson(),
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 720,
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: KanbanPayload.fromNode(node),
                effectivePreset: NodeSizePreset.wide,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (value) => payloads.add(value as KanbanPayload),
                onNodeDraftChanged: (_) {},
                onKanbanAttachmentOpen: (value) async => opened.add(value),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('kanban-checklist-interactive-review')),
    );
    await tester.pump();
    expect(payloads.single.cards.single.checklist.single.isDone, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('kanban-attachment-interactive-brief')),
    );
    await tester.pump();
    expect(opened, <KanbanAttachmentReference>[attachment]);
    expect(find.text('Review scope'), findsOneWidget);
    expect(find.text('brief.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('kanban cards and columns move through horizontal drag', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final payloads = <KanbanPayload>[];
    final node = _node(NodeType.kanban);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 620,
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: KanbanPayload.fromNode(node),
                effectivePreset: NodeSizePreset.wide,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (value) => payloads.add(value as KanbanPayload),
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final cardDraggable = tester.widget<Draggable<String>>(
      find.byKey(const ValueKey<String>('kanban-card-drag-card-1')),
    );
    expect(cardDraggable.axis, isNull);

    await tester.dragFrom(
      tester.getCenter(
        find.byKey(const ValueKey<String>('kanban-card-drag-card-1')),
      ),
      tester.getCenter(
            find.byKey(
              const ValueKey<String>('kanban-column-drop-in-progress'),
            ),
          ) -
          tester.getCenter(
            find.byKey(const ValueKey<String>('kanban-card-drag-card-1')),
          ),
    );
    await tester.pumpAndSettle();

    expect(payloads, isNotEmpty);
    expect(payloads.last.cards.single.columnId, kanbanInProgressColumnId);

    await tester.dragFrom(
      tester.getCenter(
        find.byKey(const ValueKey<String>('kanban-column-drag-backlog')),
      ),
      tester.getCenter(
            find.byKey(const ValueKey<String>('kanban-column-drop-done')),
          ) -
          tester.getCenter(
            find.byKey(const ValueKey<String>('kanban-column-drag-backlog')),
          ),
    );
    await tester.pumpAndSettle();

    expect(payloads.last.columns.last.id, kanbanBacklogColumnId);
    expect(find.text('Move left'), findsNothing);
    expect(find.text('Move right'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('quick actions emit updated drafts through callbacks', (
    tester,
  ) async {
    final payloads = <Object>[];
    final nodeDrafts = <MindmapNode>[];
    final node = _node(NodeType.kanban);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          NodeEditContext(
            node: node,
            typedDraft: KanbanPayload.fromNode(node),
            effectivePreset: NodeSizePreset.wide,
            validationErrors: const [],
            onTitleChanged: (_) {},
            onBodyChanged: (_) {},
            onDraftChanged: payloads.add,
            onNodeDraftChanged: nodeDrafts.add,
          ),
        ),
      ),
    );

    final advance = find.byKey(const ValueKey<String>('kanban-advance-card'));
    await tester.ensureVisible(advance);
    await tester.tap(advance);
    await tester.pump();

    expect(payloads, hasLength(1));
    final payload = payloads.single as KanbanPayload;
    expect(payload.cards.single.column, KanbanColumn.doing);
    expect(nodeDrafts, isEmpty);
  });

  testWidgets('validation errors remain visible without repository access', (
    tester,
  ) async {
    final node = _node(NodeType.note);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          NodeEditContext(
            node: node,
            typedDraft: const <String, Object?>{},
            effectivePreset: NodeSizePreset.large,
            validationErrors: const ['Title is required.'],
            onTitleChanged: (_) {},
            onBodyChanged: (_) {},
            onDraftChanged: (_) {},
            onNodeDraftChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Title is required.'), findsOneWidget);
  });

  testWidgets('editor fields reset when selected node id changes', (
    tester,
  ) async {
    final nodeA = _node(NodeType.note).copyWith(id: 'node-a', title: 'Node A');
    final nodeB = _node(NodeType.note).copyWith(id: 'node-b', title: 'Node B');

    await tester.pumpWidget(_editorApp(nodeA));
    await tester.enterText(
      find.byKey(const ValueKey<String>('productivity-node-a-title-field')),
      'Unsaved A',
    );
    await tester.pumpWidget(_editorApp(nodeB));
    await tester.pump();

    expect(
      tester
          .widget<TextFormField>(
            find.byKey(
              const ValueKey<String>('productivity-node-b-title-field'),
            ),
          )
          .initialValue,
      'Node B',
    );
    expect(find.text('Node B'), findsOneWidget);
    expect(find.text('Unsaved A'), findsNothing);
  });

  testWidgets('task quick action completes latest typed draft item', (
    tester,
  ) async {
    final nodeDrafts = <MindmapNode>[];
    final node = _node(NodeType.task).copyWith(
      checklist: const [
        TaskChecklistItem(
          id: 'persisted',
          title: 'Persisted item',
          isDone: false,
        ),
      ],
    );
    const draft = TaskChecklistPayload(
      items: [
        TaskChecklistItem(id: 'draft', title: 'Draft item', isDone: false),
      ],
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          NodeEditContext(
            node: node,
            typedDraft: draft,
            effectivePreset: NodeSizePreset.standard,
            validationErrors: const [],
            onTitleChanged: (_) {},
            onBodyChanged: (_) {},
            onDraftChanged: (_) {},
            onNodeDraftChanged: nodeDrafts.add,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Complete Draft item'));
    await tester.pump();

    expect(nodeDrafts, hasLength(1));
    expect(nodeDrafts.single.checklist, hasLength(1));
    expect(nodeDrafts.single.checklist.single.id, 'draft');
    expect(nodeDrafts.single.checklist.single.isDone, isTrue);
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
  home: Scaffold(
    body: Center(child: SizedBox(width: 620, height: 480, child: child)),
  ),
);

Widget _editorApp(MindmapNode node) => _app(
  buildNodeTypeInlineEditor(
    NodeEditContext(
      node: node,
      typedDraft: const <String, Object?>{},
      effectivePreset: NodeSizePreset.standard,
      validationErrors: const [],
      onTitleChanged: (_) {},
      onBodyChanged: (_) {},
      onDraftChanged: (_) {},
      onNodeDraftChanged: (_) {},
    ),
  ),
);

MindmapNode _node(NodeType type) {
  final now = DateTime(2026, 7, 13, 9);
  return MindmapNode.create(
    id: type.name,
    type: type,
    title: '${type.label} title',
    body: 'Focused body content',
    day: now,
    now: now,
    checklist: const [TaskChecklistItem(id: 'item-1', title: 'First item')],
    data: {
      'kanban': {
        'cards': [
          {'id': 'card-1', 'title': 'Draft', 'column': 'todo'},
        ],
      },
      'plan': {
        'steps': ['Research', 'Ship'],
        'completedSteps': ['Research'],
      },
      'goal': {
        'milestones': ['First', 'Second'],
        'completedMilestones': ['First'],
      },
      'habit': {
        'target': '30 minutes',
        'recurrence': 'daily',
        'completions': ['2026-07-12'],
      },
      'timerSeconds': 1200,
      'timerInitialSeconds': 1500,
    },
  );
}

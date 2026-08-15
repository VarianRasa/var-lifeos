import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/habit_completion.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/inline_node_workspace.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/media_travel_node_editors.dart';
import 'package:var_app/features/mindmap/presentation/node_type_inline_editor.dart';

void main() {
  test('resource typed draft applies structured data and tags', () {
    final source = _node(
      NodeType.resource,
      data: const <String, Object?>{
        'source': 'https://example.com/original',
        'foreign': true,
      },
    );

    final draft = nodeTypeInlineDraftFor(source);
    expect(draft, isA<ResourcePayload>());
    final updated = applyNodeTypeInlineDraft(
      source,
      (draft as ResourcePayload).copyWith(
        description: 'Updated summary',
        tags: const <String>['research'],
      ),
    );

    expect(ResourcePayload.fromNode(updated).description, 'Updated summary');
    expect(updated.tags, const <String>['research']);
    expect(updated.data['foreign'], isTrue);
    expect(
      nodeTypeInlineDraftFor(_node(NodeType.link)),
      isA<LinkResourcePayload>(),
    );
    expect(
      nodeTypeInlineDraftFor(_node(NodeType.bookmark)),
      isA<LinkResourcePayload>(),
    );
  });

  testWidgets(
    'resource workspace forwards file picker and folder suggestions',
    (tester) async {
      final node = _node(NodeType.resource);
      var chooseCalls = 0;
      final patches = <InlineNodeDraftPatch>[];
      const asset = ResourceAsset(
        id: 'file-1',
        kind: 'file',
        label: 'manual.pdf',
        attachmentId: 'attachment-1',
        mimeType: 'application/pdf',
        sizeBytes: 12,
        fileName: 'manual.pdf',
        extension: 'pdf',
      );

      await tester.pumpWidget(
        _app(
          _workspace(
            node,
            editContext: _editContext(
              node,
              onResourceAssetAdd: () async {
                chooseCalls += 1;
                return asset;
              },
              resourceFolderSuggestions: const <List<String>>[
                <String>['Research'],
              ],
            ),
            onDraftChanged: patches.add,
          ),
          height: 720,
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('resource-primary-choose-file')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-primary-choose-file')),
      );
      await tester.pump();

      expect(chooseCalls, 1);
      expect(patches, isNotEmpty);
      final updated = patches.last.mergeInto(node, _now);
      expect(ResourcePayload.fromNode(updated).primaryAsset?.id, 'file-1');
      expect(find.text('Research'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders fixed workspace chrome and one live save semantic', (
    tester,
  ) async {
    final MindmapNode node = _node(NodeType.note);

    await tester.pumpWidget(
      _app(
        _workspace(node),
        width: InlineNodeWorkspacePolicy.expandedSizeForNode(node).width,
        height: InlineNodeWorkspacePolicy.expandedSizeForNode(node).height,
      ),
    );

    expect(
      find.byKey(const ValueKey('inline-workspace-header-note-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inline-workspace-scroll-note-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inline-workspace-footer-note-1')),
      findsOneWidget,
    );
    final Finder workspace = find.bySemanticsLabel(
      'First note, Note, expanded, saved',
    );
    expect(workspace, findsOneWidget);
    expect(
      tester
          .getSemantics(workspace)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isFalse,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('inline-workspace-save-status-note-1')),
          )
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow workspace header keeps status and collapse separated', (
    tester,
  ) async {
    final MindmapNode node = _node(
      NodeType.note,
    ).copyWith(title: 'A very long professional workspace title');

    await tester.pumpWidget(
      _app(_workspace(node, status: InlineNodeSaveStatus.saving), width: 280),
    );
    await tester.pump();

    final Rect statusRect = tester.getRect(
      find.byKey(const ValueKey('inline-workspace-save-status-note-1')),
    );
    final Rect collapseRect = tester.getRect(
      find.byKey(const ValueKey('inline-workspace-collapse-note-1')),
    );
    expect(statusRect.overlaps(collapseRect), isFalse);
    expect(find.byTooltip('Collapse node'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validation pending is not rendered as save failure', (
    tester,
  ) async {
    final node = _node(NodeType.bookmark);
    const message = 'URL must use http or https.';

    await tester.pumpWidget(
      _app(
        _workspace(
          node,
          status: InlineNodeSaveStatus.dirty,
          editContext: _editContext(
            node,
            validationErrors: const <String>[message],
          ),
        ),
        width: 680,
        height: 840,
      ),
    );
    await tester.pump();

    expect(find.text(message), findsAtLeastNWidgets(1));
    expect(find.text('save failed'), findsNothing);
    expect(
      find.byKey(const ValueKey('inline-workspace-retry-bookmark-1')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus enters workspace and keyboard activates controls', (
    tester,
  ) async {
    final MindmapNode node = _node(NodeType.note);
    var collapseCount = 0;
    var retryCount = 0;

    await tester.pumpWidget(
      _app(
        _workspace(
          node,
          status: InlineNodeSaveStatus.error,
          onCollapse: () => collapseCount += 1,
          onRetrySave: () => retryCount += 1,
        ),
        width: InlineNodeWorkspacePolicy.expandedSizeForNode(node).width,
        height: InlineNodeWorkspacePolicy.expandedSizeForNode(node).height,
      ),
    );
    await tester.pump();

    const collapseKey = ValueKey<String>('inline-workspace-collapse-note-1');
    expect(_primaryFocusHasAncestorKey(collapseKey), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(collapseCount, 1);

    const retryKey = ValueKey<String>('inline-workspace-retry-note-1');
    for (
      var index = 0;
      index < 20 && !_primaryFocusHasAncestorKey(retryKey);
      index++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(_primaryFocusHasAncestorKey(retryKey), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(retryCount, 1);
  });
  testWidgets('workspace detaches safely after focus is cleared', (
    tester,
  ) async {
    final node = _node(NodeType.task);

    await tester.pumpWidget(
      _app(
        _workspace(node),
        width: InlineNodeWorkspacePolicy.expandedSizeForNode(node).width,
        height: InlineNodeWorkspacePolicy.expandedSizeForNode(node).height,
      ),
    );
    await tester.pump();

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pumpWidget(_app(const SizedBox()));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
  testWidgets('routes collapse retry and title draft actions', (tester) async {
    final MindmapNode node = _node(NodeType.note);
    var collapseCount = 0;
    var retryCount = 0;
    final List<InlineNodeDraftPatch> patches = <InlineNodeDraftPatch>[];

    await tester.pumpWidget(
      _app(
        _workspace(
          node,
          status: InlineNodeSaveStatus.error,
          onCollapse: () => collapseCount += 1,
          onRetrySave: () => retryCount += 1,
          onDraftChanged: patches.add,
        ),
        width: InlineNodeWorkspacePolicy.expandedSizeForNode(node).width,
        height: InlineNodeWorkspacePolicy.expandedSizeForNode(node).height,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('inline-workspace-collapse-note-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('inline-workspace-retry-note-1')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('productivity-note-1-title-field')),
      'Changed note',
    );
    await tester.pump();

    expect(collapseCount, 1);
    expect(retryCount, 1);
    expect(patches.last.title, 'Changed note');
  });

  testWidgets('typed kanban payload emits merge-safe data patch', (
    tester,
  ) async {
    final MindmapNode node = _validNode(NodeType.kanban);
    final List<InlineNodeDraftPatch> patches = <InlineNodeDraftPatch>[];
    await tester.pumpWidget(
      _app(_workspace(node, onDraftChanged: patches.add), width: 320),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('kanban-advance-card')),
    );
    await tester.tap(find.byKey(const ValueKey('kanban-advance-card')));
    await tester.pump();

    final MindmapNode latest = node.copyWith(
      data: <String, Object?>{...node.data, 'latestOnly': true},
    );
    final MindmapNode merged = patches.single.mergeInto(
      latest,
      DateTime(2026, 7, 15, 12),
    );
    final KanbanPayload payload = KanbanPayload.fromNode(merged);
    expect(payload.cards, hasLength(1));
    expect(payload.cards.single.id, 'card-1');
    expect(payload.cards.single.title, 'Ship');
    expect(payload.cards.single.column.name, 'doing');
    expect(merged.data['latestOnly'], isTrue);
    _expectSentinels(merged);
  });

  testWidgets('checklist node action emits checklist field patch', (
    tester,
  ) async {
    final MindmapNode node = _validNode(NodeType.task);
    final List<InlineNodeDraftPatch> patches = <InlineNodeDraftPatch>[];
    final size = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    await tester.binding.setSurfaceSize(
      Size(size.width + 40, size.height + 40),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        _workspace(node, onDraftChanged: patches.add),
        width: size.width,
        height: size.height,
      ),
    );

    final action = find.widgetWithText(FilledButton, 'Complete Finish');
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(action.hitTestable(), findsOneWidget);
    await tester.tap(action);
    await tester.pump();

    final MindmapNode merged = patches.single.mergeInto(
      node,
      DateTime(2026, 7, 15, 12),
    );
    expect(merged.checklist, const <TaskChecklistItem>[
      TaskChecklistItem(id: 'item-1', title: 'Finish', isDone: true),
    ]);
    _expectSentinels(merged);
  });

  testWidgets('plan action advances exact payload and preserves sentinels', (
    tester,
  ) async {
    final MindmapNode node = _validNode(NodeType.plan);
    final MindmapNode merged = await _tapAndMerge(
      tester,
      node,
      find.byKey(const ValueKey<String>('plan-task-toggle-legacy-task-0')),
    );

    expect(PlanPayload.fromNode(merged).completedSteps, <String>['Draft']);
    _expectSentinels(merged);
  });

  testWidgets('goal action advances exact payload and preserves sentinels', (
    tester,
  ) async {
    final MindmapNode node = _validNode(NodeType.goal);
    final MindmapNode merged = await _tapAndMerge(
      tester,
      node,
      find.text('Complete Start'),
    );

    expect(GoalPayload.fromNode(merged).completedMilestones, <String>['Start']);
    _expectSentinels(merged);
  });

  testWidgets('habit action records day and preserves sentinels', (
    tester,
  ) async {
    final MindmapNode node = _validNode(NodeType.habit);
    final MindmapNode merged = await _tapAndMerge(
      tester,
      node,
      find.text('Complete today'),
    );

    expect(hasHabitCompletionOn(merged, node.day), isTrue);
    _expectSentinels(merged);
  });

  testWidgets(
    'expense fields round-trip exact payload and preserve sentinels',
    (tester) async {
      final MindmapNode node = _validNode(NodeType.expense);
      final List<InlineNodeDraftPatch> patches = <InlineNodeDraftPatch>[];
      await tester.pumpWidget(
        _app(
          _workspace(
            node,
            editContext: _editContext(node, preset: NodeSizePreset.large),
            onDraftChanged: patches.add,
          ),
          width: InlineNodeWorkspacePolicy.large.width,
          height: InlineNodeWorkspacePolicy.large.height,
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('life-data-expense-amount-field')),
        '42.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('life-data-expense-currency-field')),
        'EUR',
      );
      await tester.enterText(
        find.byKey(const ValueKey('life-data-expense-category-field')),
        'Travel',
      );
      await tester.pump();

      final MindmapNode merged = patches.last.mergeInto(node, _now);
      final ExpensePayload payload = ExpensePayload.fromNode(merged);
      expect(payload.amount, 42.5);
      expect(payload.currency, 'EUR');
      expect(payload.category, 'Travel');
      _expectSentinels(merged);
    },
  );

  testWidgets(
    'contact fields round-trip exact payload and preserve sentinels',
    (tester) async {
      final MindmapNode node = _validNode(NodeType.contact);
      final List<InlineNodeDraftPatch> patches = <InlineNodeDraftPatch>[];
      await tester.pumpWidget(
        _app(
          _workspace(
            node,
            editContext: _editContext(node, preset: NodeSizePreset.large),
            onDraftChanged: patches.add,
          ),
          width: InlineNodeWorkspacePolicy.large.width,
          height: InlineNodeWorkspacePolicy.large.height,
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('life-data-contact-role-field')),
        'Designer',
      );
      await tester.enterText(
        find.byKey(const ValueKey('life-data-contact-company-field')),
        'Var Labs',
      );
      await tester.enterText(
        find.byKey(const ValueKey('life-data-contact-email-field')),
        'design@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('life-data-contact-phone-field')),
        '+12025550123',
      );
      await tester.pump();

      final MindmapNode merged = patches.last.mergeInto(node, _now);
      final ContactPayload payload = ContactPayload.fromNode(merged);
      expect(payload.role, 'Designer');
      expect(payload.company, 'Var Labs');
      expect(payload.email, 'design@example.test');
      expect(payload.phone, '+12025550123');
      _expectSentinels(merged);
    },
  );

  testWidgets(
    'itinerary conversion emits exact action and preserves sentinels',
    (tester) async {
      final MindmapNode node = _validNode(NodeType.itinerary);
      final List<Object> actions = <Object>[];
      await tester.pumpWidget(
        _app(
          buildNodeTypeInlineEditor(
            _editContext(
              node,
              preset: NodeSizePreset.wide,
              onItineraryAction: (Object action) async => actions.add(action),
            ),
          ),
          width: 800,
          height: 900,
        ),
      );

      final Finder convert = find.byTooltip('Convert Museum to task');
      await tester.ensureVisible(convert);
      await tester.tap(convert);
      await tester.pump();
      final ConvertItineraryAgendaAction action =
          actions.single as ConvertItineraryAgendaAction;
      expect(action.target, ItineraryConversionTarget.task);
      expect(action.item.id, 'stop-1');
      expect(action.item.title, 'Museum');
      _expectSentinels(node);
    },
  );

  testWidgets(
    'image actions preserve source sentinels and exact attachment id',
    (tester) async {
      final MindmapNode node = _validNode(NodeType.image);
      final List<Object> actions = <Object>[];
      await tester.pumpWidget(
        _app(
          buildNodeTypeInlineEditor(
            _editContext(
              node,
              preset: NodeSizePreset.large,
              onMediaAction: (Object action) async => actions.add(action),
            ),
          ),
          width: 800,
          height: 900,
        ),
      );

      for (final String label in <String>[
        'Replace',
        'Export',
        'Open externally',
      ]) {
        final Finder action = find.widgetWithText(OutlinedButton, label).first;
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pump();
      }

      expect(actions[0], isA<ReplaceImageAction>());
      expect(
        (actions[1] as ExportImageAction).attachmentId,
        'image-attachment',
      );
      expect(
        (actions[2] as OpenImageExternallyAction).target,
        'https://example.test/image.png',
      );
      _expectSentinels(node);
    },
  );

  testWidgets('empty conversion emits node type patch', (tester) async {
    final MindmapNode node = _node(NodeType.empty);
    final List<InlineNodeDraftPatch> patches = <InlineNodeDraftPatch>[];
    await tester.pumpWidget(
      _app(_workspace(node, onDraftChanged: patches.add)),
    );

    await tester.tap(
      find.byKey(const ValueKey('life-data-empty-convert-task')),
    );
    await tester.pump();

    expect(
      patches.single.mergeInto(node, DateTime(2026, 7, 15, 12)).type,
      NodeType.task,
    );
  });

  testWidgets('async action guard drops duplicate taps and contains failure', (
    tester,
  ) async {
    final MindmapNode node = _validNode(NodeType.kanban);
    final Completer<void> gate = Completer<void>();
    final List<Object> errors = <Object>[];
    var invocations = 0;
    await tester.pumpWidget(
      _app(
        _workspace(
          node,
          editContext: _editContext(
            node,
            onKanbanAction: (Object action) async {
              invocations += 1;
              await gate.future;
              throw StateError('action failed');
            },
            onActionError: (Object error, StackTrace stackTrace) {
              errors.add(error);
            },
          ),
        ),
      ),
    );

    final Finder action = find.byKey(const ValueKey('kanban-advance-card'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.tap(action);
    await tester.pump();
    expect(invocations, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(errors.single, isA<StateError>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('knowledge and itinerary actions disable without callbacks', (
    tester,
  ) async {
    final MindmapNode canvas = _validNode(NodeType.canvas);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _editContext(canvas, preset: NodeSizePreset.large),
        ),
        width: 600,
        height: 500,
      ),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Open canvas'),
          )
          .onPressed,
      isNull,
    );

    final MindmapNode itinerary = _validNode(NodeType.itinerary);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _editContext(itinerary, preset: NodeSizePreset.wide),
        ),
        width: 800,
        height: 900,
      ),
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('itinerary-convert-task-stop-1')),
          )
          .onPressed,
      isNull,
    );
  });

  test('inline draft dispatcher applies dedicated checklist payload', () {
    final node = MindmapNode.create(
      id: 'checklist-draft',
      type: NodeType.checklist,
      title: 'Checklist',
      day: DateTime(2026, 7, 16),
    );
    const draft = ChecklistPayload(
      items: <ChecklistEntry>[
        ChecklistEntry(
          id: 'ship',
          title: 'Ship release',
          priority: ChecklistPriority.high,
        ),
      ],
    );

    expect(nodeTypeInlineDraftFor(node), isA<ChecklistPayload>());
    final applied = applyNodeTypeInlineDraft(node, draft);

    expect(
      ChecklistPayload.fromNode(applied).items.single.title,
      'Ship release',
    );
    expect(
      ChecklistPayload.fromNode(applied).items.single.priority,
      ChecklistPriority.high,
    );
    expect(applied.checklist.single.id, 'ship');
  });
  test('draft bridge rejects actions unknown and wrong-node payloads', () {
    final MindmapNode note = _validNode(NodeType.note);
    expect(
      () => applyNodeTypeInlineDraft(note, const ReplaceImageAction()),
      throwsArgumentError,
    );
    expect(() => applyNodeTypeInlineDraft(note, Object()), throwsArgumentError);
    expect(
      () => applyNodeTypeInlineDraft(note, const GoalPayload()),
      throwsArgumentError,
    );
  });

  testWidgets('action buttons use explicit context callbacks', (tester) async {
    final MindmapNode node = _node(
      NodeType.kanban,
      data: const <String, Object?>{
        'kanban': <String, Object?>{
          'cards': <Object?>[
            <String, Object?>{
              'id': 'card-1',
              'title': 'Ship',
              'column': 'todo',
            },
          ],
        },
      },
    );
    final List<Object> actions = <Object>[];
    final List<InlineNodeDraftPatch> patches = <InlineNodeDraftPatch>[];
    await tester.pumpWidget(
      _app(
        _workspace(
          node,
          editContext: _editContext(
            node,
            onKanbanAction: (Object action) async => actions.add(action),
          ),
          onDraftChanged: patches.add,
        ),
      ),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('kanban-advance-card')),
    );
    await tester.tap(find.byKey(const ValueKey('kanban-advance-card')));
    await tester.pump();

    expect(actions.single, isA<KanbanPayload>());
    expect(patches.single.dataFields, isNotEmpty);
  });

  test('note journal and fallback drafts preserve sentinels', () {
    final MindmapNode note = _validNode(NodeType.note);
    final MindmapNode changedNote = applyNodeTypeInlineDraft(
      note,
      NotePayload.fromNode(note).copyWith(color: 'blue'),
    );
    expect(NotePayload.fromNode(changedNote).color, 'blue');
    _expectSentinels(changedNote);

    final MindmapNode journal = _validNode(NodeType.journal);
    final JournalPayload expectedJournal = JournalPayload(
      date: journal.day,
      mood: 5,
      energy: 4,
      gratitude: const <String>['shipping'],
    );
    final MindmapNode changedJournal = applyNodeTypeInlineDraft(
      journal,
      expectedJournal,
    );
    final JournalPayload actualJournal = JournalPayload.fromNode(
      changedJournal,
    );
    expect(actualJournal.mood, expectedJournal.mood);
    expect(actualJournal.energy, expectedJournal.energy);
    expect(actualJournal.gratitude, expectedJournal.gratitude);
    _expectSentinels(changedJournal);

    final MindmapNode fallback = _validNode(NodeType.quote);
    expect(
      () => applyNodeTypeInlineDraft(fallback, Object()),
      throwsArgumentError,
    );
    _expectSentinels(fallback);
  });

  test('typed draft bridge round-trips every NodeType', () {
    for (final NodeType type in NodeType.values) {
      final MindmapNode node = _validNode(type);
      final Object draft = nodeTypeInlineDraftFor(node);
      final MindmapNode resulting = applyNodeTypeInlineDraft(node, draft);

      expect(resulting.id, node.id, reason: type.name);
      expect(resulting.type, node.type, reason: type.name);
      _expectSentinels(resulting);
    }
  });
  for (final NodeType type in NodeType.values) {
    testWidgets('renders bounded ${type.name} workspace and rebuilds', (
      tester,
    ) async {
      final MindmapNode node = _validNode(type);
      final InlineNodeWorkspaceSize size =
          InlineNodeWorkspacePolicy.expandedSizeForNode(node);
      await tester.binding.setSurfaceSize(
        Size(size.width + 80, size.height + 80),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(_workspace(node), width: size.width, height: size.height),
      );

      final Finder body = find.byKey(
        ValueKey<String>('inline-workspace-scroll-${node.id}'),
      );
      expect(body, findsOneWidget);
      expect(
        find.descendant(
          of: body,
          matching: find.byWidgetPredicate(
            (Widget widget) => switch (widget) {
              final Text text => text.data?.trim().isNotEmpty == true,
              final EditableText field =>
                field.controller.text.trim().isNotEmpty,
              _ => false,
            },
          ),
        ),
        findsWidgets,
        reason: type.name,
      );
      expect(tester.takeException(), isNull, reason: type.name);
    });
  }

  for (final NodeType type in const <NodeType>[
    NodeType.plan,
    NodeType.goal,
    NodeType.habit,
    NodeType.metric,
    NodeType.expense,
    NodeType.contact,
    NodeType.image,
    NodeType.weather,
    NodeType.fit,
  ]) {
    testWidgets('${type.name} uses exact policy size without inflation', (
      tester,
    ) async {
      final MindmapNode node = _validNode(type);
      final InlineNodeWorkspaceSize size =
          InlineNodeWorkspacePolicy.expandedSizeFor(type);
      await tester.binding.setSurfaceSize(
        Size(size.width + 80, size.height + 80),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(_workspace(node), width: size.width, height: size.height),
      );

      expect(
        tester.getSize(find.byType(InlineNodeWorkspace)),
        Size(size.width, size.height),
      );
      expect(tester.takeException(), isNull, reason: type.name);
    });
  }

  testWidgets(
    'video fixed workspace keeps actions visible without fallback scroll',
    (tester) async {
      final node = _validNode(NodeType.video);
      final size = InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.video);
      await tester.binding.setSurfaceSize(
        Size(size.width + 40, size.height + 40),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(_workspace(node), width: size.width, height: size.height),
      );

      expect(
        find.byKey(ValueKey('video-editor-fallback-${node.id}')),
        findsNothing,
      );
      final actions = find.byKey(ValueKey('video-actions-${node.id}'));
      expect(actions, findsOneWidget);
      expect(
        tester.getBottomRight(actions).dy,
        lessThanOrEqualTo(
          tester.getBottomRight(find.byType(InlineNodeWorkspace)).dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final NodeType type in const <NodeType>[
    NodeType.video,
    NodeType.itinerary,
    NodeType.kanban,
  ]) {
    testWidgets('${type.name} stays finite at narrow workspace width', (
      tester,
    ) async {
      final MindmapNode node = _node(type);
      await tester.pumpWidget(_app(_workspace(node), width: 240, height: 200));

      final Size bodySize = tester.getSize(
        find.byKey(ValueKey<String>('inline-workspace-scroll-${node.id}')),
      );
      expect(bodySize.width, lessThanOrEqualTo(240));
      expect(bodySize.height, lessThan(200));
      expect(tester.takeException(), isNull);
    });
  }
}

final DateTime _now = DateTime(2026, 7, 15, 12);

Future<MindmapNode> _tapAndMerge(
  WidgetTester tester,
  MindmapNode node,
  Finder action,
) async {
  final List<InlineNodeDraftPatch> patches = <InlineNodeDraftPatch>[];
  final InlineNodeWorkspaceSize size =
      InlineNodeWorkspacePolicy.expandedSizeFor(node.type);
  await tester.binding.setSurfaceSize(Size(size.width + 40, size.height + 40));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      _workspace(node, onDraftChanged: patches.add),
      width: size.width,
      height: size.height,
    ),
  );
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pump();
  expect(patches, hasLength(1));
  final MindmapNode merged = patches.single.mergeInto(node, _now);
  _expectSentinels(merged);
  return merged;
}

void _expectSentinels(MindmapNode node) {
  expect(node.data['unrelated'], 'keep');
  expect(node.data['attachmentIds'], <String>['attachment-stable']);
}

InlineNodeWorkspace _workspace(
  MindmapNode node, {
  InlineNodeSaveStatus status = InlineNodeSaveStatus.saved,
  VoidCallback? onCollapse,
  VoidCallback? onRetrySave,
  ValueChanged<InlineNodeDraftPatch>? onDraftChanged,
  NodeEditContext? editContext,
}) => InlineNodeWorkspace(
  node: node,
  editContext: editContext ?? _editContext(node),
  saveStatus: status,
  onCollapse: onCollapse ?? () {},
  onRetrySave: onRetrySave ?? () {},
  onDraftChanged: onDraftChanged ?? (_) {},
);

Widget _app(Widget child, {double width = 360, double height = 280}) =>
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );

NodeEditContext _editContext(
  MindmapNode node, {
  NodeAsyncPayloadAction? onKanbanAction,
  NodeAsyncPayloadAction? onMediaAction,
  NodeAsyncPayloadAction? onItineraryAction,
  Future<ResourceAsset?> Function()? onResourceAssetAdd,
  List<List<String>> resourceFolderSuggestions = const <List<String>>[],
  NodeActionErrorCallback? onActionError,
  NodeSizePreset? preset,
  List<String> validationErrors = const <String>[],
}) => NodeEditContext(
  node: node,
  typedDraft: nodeTypeInlineDraftFor(node),
  effectivePreset:
      preset ?? NodePresentationSpec.forType(node.type).defaultPreset,
  validationErrors: validationErrors,
  onTitleChanged: (_) {},
  onBodyChanged: (_) {},
  onDraftChanged: (_) {},
  onNodeDraftChanged: (_) {},
  onKanbanAction: onKanbanAction,
  onMediaAction: onMediaAction,
  onItineraryAction: onItineraryAction,
  onResourceAssetAdd: onResourceAssetAdd,
  resourceFolderSuggestions: resourceFolderSuggestions,
  onActionError: onActionError,
);

bool _primaryFocusHasAncestorKey(Key key) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if ((context as Element).widget.key == key) return true;
  var found = false;
  context.visitAncestorElements((element) {
    if (element.widget.key == key) found = true;
    return !found;
  });
  return found;
}

MindmapNode _validNode(NodeType type) => _node(
  type,
  data: <String, Object?>{
    'unrelated': 'keep',
    'attachmentIds': <String>['attachment-stable'],
    if (type == NodeType.kanban)
      'kanban': <String, Object?>{
        'cards': <Object?>[
          <String, Object?>{'id': 'card-1', 'title': 'Ship', 'column': 'todo'},
        ],
      },
    if (type == NodeType.plan)
      'plan': <String, Object?>{
        'steps': <String>['Draft', 'Ship'],
        'completedSteps': <String>[],
      },
    if (type == NodeType.goal)
      'goal': <String, Object?>{
        'milestones': <String>['Start', 'Finish'],
        'completedMilestones': <String>[],
      },
    if (type == NodeType.habit)
      'habit': <String, Object?>{
        'target': 'Read',
        'recurrence': 'daily',
        'completions': <String>[],
      },
    if (type == NodeType.link ||
        type == NodeType.resource ||
        type == NodeType.bookmark)
      'url': 'https://example.test',
    if (type == NodeType.contact) ...<String, Object?>{
      'email': 'person@example.test',
      'role': 'Owner',
      'company': 'Var',
    },
    if (type == NodeType.metric) ...<String, Object?>{'value': 7, 'unit': 'h'},
    if (type == NodeType.expense) ...<String, Object?>{
      'amount': 12.5,
      'currency': 'USD',
    },
    if (type == NodeType.itinerary)
      'itinerary': <String, Object?>{
        'destination': 'City',
        'startDate': '2026-07-15',
        'endDate': '2026-07-16',
        'timezone': 'UTC',
        'budget': 100,
        'actualCost': 20,
        'currency': 'USD',
        'status': 'planned',
        'agenda': <Object?>[
          <String, Object?>{
            'id': 'stop-1',
            'title': 'Museum',
            'startMinutes': 600,
            'durationMinutes': 60,
            'location': 'Center',
            'notes': '',
            'cost': 10,
            'completed': false,
          },
        ],
      },
    if (type == NodeType.image)
      'image': <String, Object?>{
        'url': 'https://example.test/image.png',
        'attachmentId': 'image-attachment',
        'caption': 'Image caption',
      },
    if (type == NodeType.video) ...<String, Object?>{
      'url': 'https://example.test/video.mp4',
      'attachmentId': 'video-attachment',
      'caption': 'Video caption',
    },
  },
  checklist: type == NodeType.task || type == NodeType.checklist
      ? const <TaskChecklistItem>[
          TaskChecklistItem(id: 'item-1', title: 'Finish'),
        ]
      : const <TaskChecklistItem>[],
);

MindmapNode _node(
  NodeType type, {
  Map<String, Object?> data = const <String, Object?>{},
  List<TaskChecklistItem> checklist = const <TaskChecklistItem>[],
}) => MindmapNode.create(
  id: '${type.name}-1',
  type: type,
  title: 'First ${type.label.toLowerCase()}',
  day: DateTime(2026, 7, 15),
  data: data,
  checklist: checklist,
);

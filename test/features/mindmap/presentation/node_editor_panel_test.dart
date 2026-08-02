import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/inline_node_workspace.dart';
import 'package:var_app/features/mindmap/presentation/node_editor_panel.dart';

void main() {
  String? clipboardText;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final data = call.arguments as Map<Object?, Object?>;
            clipboardText = data['text'] as String?;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': clipboardText};
          }
          return null;
        });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('NodeEditorPanel shows autocomplete list when typing [[', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'node-target',
          type: NodeType.note,
          title: 'Learn Flutter',
          day: today,
        ),
      ],
    );

    final editNode = MindmapNode.create(
      id: 'node-edit',
      type: NodeType.task,
      title: 'Write some code',
      day: today,
    );

    MindmapNode? savedResult;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: editNode,
              onSave: (node) => savedResult = node,
              onClose: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    // Initial load
    await _pumpEditor(tester);

    final bodyFieldFinder = find.byKey(
      const ValueKey('node-editor-body-field'),
    );
    expect(bodyFieldFinder, findsOneWidget);

    // No autocomplete before typing [[
    expect(find.text('Link to Node'), findsNothing);

    // Type [[L
    await tester.enterText(bodyFieldFinder, '[[L');
    await _pumpEditor(tester);

    // Verify autocomplete list shows up and lists "Learn Flutter"
    expect(find.text('Link to Node'), findsOneWidget);
    expect(find.text('Learn Flutter'), findsOneWidget);

    // Tap suggestion
    tester
        .widget<InkWell>(
          find.byKey(const ValueKey('node-editor-link-suggestion-node-target')),
        )
        .onTap
        ?.call();
    await _pumpEditor(tester);

    // Verify text changed to [[Learn Flutter]]
    final textField = tester.widget<TextField>(bodyFieldFinder);
    expect(textField.controller?.text, '[[Learn Flutter]]');
    // And autocomplete closed
    expect(find.text('Link to Node'), findsNothing);

    // Save
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await _pumpEditor(tester);

    // Verify savedResult contains node-target ID in relatedNodeIds
    expect(savedResult, isNotNull);
    expect(savedResult!.relatedNodeIds, contains('node-target'));
  });

  testWidgets(
    'NodeEditorPanel links suggested nodes without relation metadata',
    (tester) async {
      final today = DateTime(2026, 6, 18);
      final target = MindmapNode.create(
        id: 'node-plan',
        type: NodeType.plan,
        title: 'Launch plan',
        day: today,
      );
      final repository = InMemoryMindmapRepository(seedNodes: [target]);
      final editNode = MindmapNode.create(
        id: 'node-task',
        type: NodeType.task,
        title: 'Ship feature',
        day: today,
      );

      MindmapNode? savedResult;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: NodeEditorPanel(
                node: editNode,
                onSave: (node) => savedResult = node,
                onClose: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      );
      await _pumpEditor(tester);
      await _openLinksTab(tester);

      tester
          .widget<ActionChip>(find.widgetWithText(ActionChip, 'Launch plan'))
          .onPressed
          ?.call();
      await _pumpEditor(tester);
      await tester.tap(find.byKey(const ValueKey('save-node')));
      await _pumpEditor(tester);

      expect(savedResult, isNotNull);
      expect(savedResult!.relatedNodeIds, contains('node-plan'));
      expect(savedResult!.data['relations'], [
        {'targetId': 'node-plan', 'label': 'relates to'},
      ]);
    },
  );

  testWidgets(
    'NodeEditorPanel auto-creates placeholder nodes for non-existent links on save',
    (tester) async {
      final today = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(seedNodes: []);

      final editNode = MindmapNode.create(
        id: 'node-edit',
        type: NodeType.task,
        title: 'Brainstorm',
        day: today,
      );

      MindmapNode? savedResult;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: NodeEditorPanel(
                node: editNode,
                onSave: (node) => savedResult = node,
                onClose: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      );

      await _pumpEditor(tester);

      final bodyFieldFinder = find.byKey(
        const ValueKey('node-editor-body-field'),
      );
      await tester.enterText(bodyFieldFinder, 'Please read [[New Novel]]');
      await _pumpEditor(tester);

      // Save
      await tester.tap(find.byKey(const ValueKey('save-node')));
      await _pumpEditor(tester);

      // Verify savedResult is not null
      expect(savedResult, isNotNull);
      expect(savedResult!.relatedNodeIds, isNotEmpty);

      // Verify repository now has a node named "New Novel"
      final allNodes = await repository.listNodes();
      final newNovelNode = allNodes.firstWhere((n) => n.title == 'New Novel');
      expect(newNovelNode, isNotNull);
      expect(newNovelNode.type, NodeType.note);
      expect(savedResult!.relatedNodeIds, contains(newNovelNode.id));
    },
  );

  testWidgets('NodeEditorPanel shows object properties and copies wiki link', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final editNode = MindmapNode.create(
      id: 'node-current',
      type: NodeType.goal,
      title: 'Health Goal',
      day: today,
      project: 'Var',
      area: 'Wellness',
      tags: const ['health', 'daily'],
      relatedNodeIds: const ['node-target'],
    );
    final repository = InMemoryMindmapRepository(seedNodes: [editNode]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: editNode,
              onSave: (_) {},
              onClose: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);

    expect(
      find.byKey(const ValueKey('node-object-properties-panel')),
      findsOneWidget,
    );
    expect(find.text('Type: Goal'), findsOneWidget);
    expect(find.text('Project: Var'), findsOneWidget);
    expect(find.text('Area: Wellness'), findsOneWidget);
    expect(find.text('#health'), findsOneWidget);
    expect(find.text('Links: 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('copy-node-wikilink')));
    await _pumpEditor(tester);
    await tester.pump(const Duration(milliseconds: 250));

    final data = await Clipboard.getData('text/plain');
    expect(data?.text, '[[Health Goal]]');
    expect(find.text('Copied [[Health Goal]]'), findsOneWidget);
  });

  testWidgets('NodeEditorPanel shows backlinks to current node', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final editNode = MindmapNode.create(
      id: 'node-current',
      type: NodeType.note,
      title: 'Daily Review',
      day: today,
    );
    final backlink = MindmapNode.create(
      id: 'node-source',
      type: NodeType.plan,
      title: 'Weekly Plan',
      day: today,
      body: 'See [[Daily Review]]',
    );
    final repository = InMemoryMindmapRepository(
      seedNodes: [editNode, backlink],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: editNode,
              onSave: (_) {},
              onClose: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);
    await _openLinksTab(tester);

    expect(find.text('Backlinks'), findsOneWidget);
    expect(find.text('Weekly Plan - [[link]]'), findsOneWidget);

    tester
        .widget<ActionChip>(
          find.byKey(const ValueKey('backlink-preview-node-source')),
        )
        .onPressed
        ?.call();
    await _pumpEditor(tester);

    expect(find.text('See [[Daily Review]]'), findsOneWidget);
  });

  testWidgets('NodeEditorPanel converts possible link mention', (tester) async {
    final today = DateTime(2026, 6, 18);
    final target = MindmapNode.create(
      id: 'node-target',
      type: NodeType.goal,
      title: 'Health Goal',
      day: today,
    );
    final editNode = MindmapNode.create(
      id: 'node-current',
      type: NodeType.note,
      title: 'Plan day',
      day: today,
      body: 'Review Health Goal today',
    );
    final repository = InMemoryMindmapRepository(seedNodes: [editNode, target]);
    MindmapNode? savedResult;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: editNode,
              onSave: (node) => savedResult = node,
              onClose: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);
    await _openLinksTab(tester);

    expect(find.text('Possible links'), findsOneWidget);
    tester
        .widget<ActionChip>(find.widgetWithText(ActionChip, 'Link Health Goal'))
        .onPressed
        ?.call();
    await _pumpEditor(tester);
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await _pumpEditor(tester);

    expect(savedResult, isNotNull);
    expect(savedResult!.body, 'Review [[Health Goal]] today');
    expect(savedResult!.relatedNodeIds, contains('node-target'));
  });

  testWidgets('NodeEditorPanel related node menu previews and removes link', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final target = MindmapNode.create(
      id: 'node-target',
      type: NodeType.note,
      title: 'Architecture Note',
      day: today,
      body: 'Important system context.',
    );
    final editNode = MindmapNode.create(
      id: 'node-current',
      type: NodeType.task,
      title: 'Ship feature',
      day: today,
      relatedNodeIds: const ['node-target'],
      data: const {
        'relations': [
          {'targetId': 'node-target', 'label': 'references'},
        ],
      },
    );
    final repository = InMemoryMindmapRepository(seedNodes: [editNode, target]);
    MindmapNode? savedResult;
    MindmapNode? openedNode;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: editNode,
              onSave: (node) => savedResult = node,
              onClose: () {},
              onDelete: () {},
              onOpenNode: (node) => openedNode = node,
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);
    await _openLinksTab(tester);

    tester
        .widget<InputChip>(
          find.byKey(const ValueKey('related-node-preview-node-target')),
        )
        .onPressed
        ?.call();
    await _pumpEditor(tester);
    expect(find.text('Important system context.'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('open-node-preview-node-target')),
    );
    await _pumpEditor(tester);
    expect(openedNode?.id, 'node-target');

    tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const ValueKey('related-node-menu-node-target')),
        )
        .onSelected
        ?.call('remove');
    await _pumpEditor(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('save-node')));
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await _pumpEditor(tester);

    expect(savedResult, isNotNull);
    expect(savedResult!.relatedNodeIds, isNot(contains('node-target')));
    expect(savedResult!.data['relations'], isEmpty);
  });

  testWidgets('NodeEditorPanel shows and removes broken related ids', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final editNode = MindmapNode.create(
      id: 'node-current',
      type: NodeType.task,
      title: 'Ship feature',
      day: today,
      relatedNodeIds: const ['missing-node'],
      data: const {
        'relations': [
          {'targetId': 'missing-node', 'label': 'blocks'},
        ],
      },
    );
    final repository = InMemoryMindmapRepository(seedNodes: [editNode]);
    MindmapNode? savedResult;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: editNode,
              onSave: (node) => savedResult = node,
              onClose: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);
    await _openLinksTab(tester);

    expect(find.text('Broken links: missing-node'), findsOneWidget);
    tester
        .widget<TextButton>(
          find.byKey(const ValueKey('remove-broken-related-links')),
        )
        .onPressed
        ?.call();
    await _pumpEditor(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('save-node')));
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await _pumpEditor(tester);

    expect(savedResult, isNotNull);
    expect(savedResult!.relatedNodeIds, isEmpty);
    expect(savedResult!.data['relations'], isEmpty);
  });

  testWidgets('NodeEditorPanel relation label preset updates relation data', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final target = MindmapNode.create(
      id: 'node-target',
      type: NodeType.plan,
      title: 'Launch Plan',
      day: today,
    );
    final editNode = MindmapNode.create(
      id: 'node-current',
      type: NodeType.task,
      title: 'Ship feature',
      day: today,
      relatedNodeIds: const ['node-target'],
      data: const {
        'relations': [
          {'targetId': 'node-target', 'label': 'relates to'},
        ],
      },
    );
    final repository = InMemoryMindmapRepository(seedNodes: [editNode, target]);
    MindmapNode? savedResult;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: editNode,
              onSave: (node) => savedResult = node,
              onClose: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);
    await _openLinksTab(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('related-node-menu-node-target')),
    );
    tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const ValueKey('related-node-menu-node-target')),
        )
        .onSelected
        ?.call('label');
    await _pumpEditor(tester);
    tester
        .widget<ActionChip>(
          find.byKey(const ValueKey('relation-label-preset-blocks')),
        )
        .onPressed
        ?.call();
    await _pumpEditor(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('save-node')));
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await _pumpEditor(tester);

    expect(savedResult, isNotNull);
    expect(savedResult!.data['relations'], [
      {'targetId': 'node-target', 'label': 'blocks'},
    ]);
  });

  testWidgets('NodeEditorPanel creates and links connected node', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final editNode = MindmapNode.create(
      id: 'node-current',
      type: NodeType.task,
      title: 'Ship feature',
      day: today,
      project: 'Var',
      area: 'Product',
      tags: const ['alpha'],
    );
    final repository = InMemoryMindmapRepository(seedNodes: [editNode]);
    MindmapNode? savedResult;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: editNode,
              onSave: (node) => savedResult = node,
              onClose: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);
    await _openLinksTab(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('add-connected-node')),
    );
    await tester.tap(find.byKey(const ValueKey('add-connected-node')));
    await _pumpEditor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('connected-node-title-field')),
      'Follow up note',
    );
    await tester.enterText(
      find.byKey(const ValueKey('connected-node-relation-field')),
      'supports',
    );
    await tester.tap(find.byKey(const ValueKey('connected-node-create')));
    await _pumpEditor(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('save-node')));
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await _pumpEditor(tester);

    final created = (await repository.listNodes()).firstWhere(
      (node) => node.title == 'Follow up note',
    );
    expect(created.project, 'Var');
    expect(created.area, 'Product');
    expect(created.tags, ['alpha']);
    expect(savedResult, isNotNull);
    expect(savedResult!.relatedNodeIds, contains(created.id));
    expect(savedResult!.data['relations'], [
      {'targetId': created.id, 'label': 'supports'},
    ]);
  });

  testWidgets('NodeEditorPanel overflow omits page and tools entries', (
    tester,
  ) async {
    final node = MindmapNode.create(
      id: 'inline-only',
      type: NodeType.note,
      title: 'Inline only',
      day: DateTime(2026, 7, 6),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: node,
              onSave: (_) {},
              onClose: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);

    await tester.tap(find.byKey(const ValueKey('node-editor-overflow-menu')));
    await tester.pumpAndSettle();

    expect(find.text('Open node page'), findsNothing);
    expect(find.text('Node tools'), findsNothing);
    expect(find.text('Delete node'), findsOneWidget);
  });

  testWidgets('NodeEditorPanel starts focus timer from smart actions', (
    tester,
  ) async {
    final today = DateTime(2026, 7, 6);
    final node = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Deep work block',
      day: today,
    );
    MindmapNode? savedResult;

    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: node,
              onSave: (node) => savedResult = node,
              onClose: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);

    final startFocus = find.byKey(const ValueKey('start-focus-timer'));
    await tester.ensureVisible(startFocus);
    await tester.pumpAndSettle();
    await tester.tap(startFocus);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('save-node')));
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await _pumpEditor(tester);

    expect(savedResult?.data['focusTimer'], {
      'status': 'running',
      'elapsedMinutes': 0,
    });
    expect(savedResult?.data['activityLog'], [
      {'action': 'focus_started', 'label': 'Started focus timer'},
    ]);
  });

  testWidgets('NodeEditorPanel converts idea to task from smart actions', (
    tester,
  ) async {
    final today = DateTime(2026, 7, 6);
    final repository = InMemoryMindmapRepository();
    final editNode = MindmapNode.create(
      id: 'idea-1',
      type: NodeType.idea,
      title: 'Turn idea into work',
      day: today,
    );
    MindmapNode? savedResult;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: editNode,
              onSave: (node) => savedResult = node,
              onClose: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);

    final convertToTask = find.byKey(const ValueKey('convert-node-to-task'));
    await tester.ensureVisible(convertToTask);
    await tester.pumpAndSettle();
    await tester.tap(convertToTask);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('save-node')));
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await _pumpEditor(tester);

    expect(savedResult?.type, NodeType.task);
    expect(savedResult?.status, NodeStatus.open);
    expect(savedResult?.effort, NodeEffort.fifteenMinutes);
    expect(savedResult?.contextTags, contains('quick win'));
    expect(savedResult?.data['activityLog'], [
      {'action': 'converted', 'label': 'Converted idea to task'},
    ]);
  });

  const sharedDispatcherCases = <(NodeType, String)>[
    (NodeType.note, 'productivity-shared-1-title-field'),
    (NodeType.resource, 'knowledge-shared-1-title-field'),
    (NodeType.contact, 'life-data-editor-shared-1'),
    (NodeType.itinerary, 'itinerary-editor-wide'),
  ];
  for (final (NodeType type, String editorKey) in sharedDispatcherCases) {
    testWidgets('NodeEditorPanel dispatches ${type.name} type editor', (
      tester,
    ) async {
      final repository = InMemoryMindmapRepository(seedNodes: const []);
      final editNode = MindmapNode.create(
        id: 'shared-1',
        type: type,
        title: type.label,
        day: DateTime(2026, 6, 18),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 560,
                height: 700,
                child: NodeEditorPanel(
                  node: editNode,
                  initialTab: 1,
                  onSave: (_) {},
                  onClose: () {},
                  onDelete: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await _pumpEditor(tester);

      expect(find.byType(InlineNodeWorkspaceSurface), findsOneWidget);
      expect(find.byKey(ValueKey<String>(editorKey)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('NodeEditorPanel type tab uses shared workspace dispatcher', (
    tester,
  ) async {
    final repository = InMemoryMindmapRepository(seedNodes: const []);
    final editNode = MindmapNode.create(
      id: 'contact-1',
      type: NodeType.contact,
      title: 'Ada',
      day: DateTime(2026, 6, 18),
    );

    MindmapNode? savedNode;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 440,
              height: 700,
              child: NodeEditorPanel(
                node: editNode,
                initialTab: 1,
                onSave: (MindmapNode value) => savedNode = value,
                onClose: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);

    expect(find.byType(InlineNodeWorkspaceSurface), findsOneWidget);
    expect(
      find.byKey(const ValueKey('life-data-editor-contact-1')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('life-data-contact-role-field')),
      'Engineer',
    );
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await _pumpEditor(tester);
    expect(savedNode?.data['role'], 'Engineer');
  });
  testWidgets('NodeEditorPanel keeps header actions in overflow menu', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);
    final editNode = MindmapNode.create(
      id: 'node-edit',
      type: NodeType.note,
      title: 'New Note',
      day: today,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: NodeEditorPanel(
                node: editNode,
                onSave: (_) {},
                onClose: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpEditor(tester);

    expect(find.byKey(const ValueKey('open-node-page')), findsNothing);
    expect(find.byKey(const ValueKey('node-tools')), findsNothing);
    expect(find.byKey(const ValueKey('delete-node')), findsNothing);
    expect(
      find.byKey(const ValueKey('node-editor-overflow-menu')),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.byType(InlineNodeWorkspaceScrollBody), findsOneWidget);
    final footerRect = tester.getRect(
      find.byKey(const ValueKey('node-editor-fixed-footer')),
    );
    expect(
      footerRect.bottom,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
  });
}

Future<void> _pumpEditor(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 5; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openLinksTab(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('node-editor-tab-links')));
  await _pumpEditor(tester);
}

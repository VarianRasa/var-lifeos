import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/node_inbox.dart';
import 'package:var_app/features/calendar/day_page.dart';
import 'package:var_app/features/mindmap/application/inline_node_workspace_controller.dart';
import 'package:var_app/features/mindmap/application/media_file_import_service.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/canvas_board_repositories.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/custom_node_template_codec.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/domain/node_ui_state_codec.dart';
import 'package:var_app/features/mindmap/presentation/inline_node_workspace.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';
import 'package:var_app/features/mindmap/presentation/node_shell.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('canvas context menu follows Astryx menu geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 25);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
        ],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    final canvas = find.byKey(const ValueKey('mindmap-canvas'));
    final gesture = await tester.startGesture(
      tester.getTopRight(canvas) - const Offset(40, -40),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Selection'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('canvas-context-folder-view')),
        matching: find.text('View'),
      ),
      findsOneWidget,
    );
    expect(find.text('Layout'), findsOneWidget);
    expect(find.text('Organize'), findsOneWidget);
    expect(find.text('Import/export'), findsOneWidget);
    expect(find.text('Commands'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('canvas-context-folder-create')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create node'), findsOneWidget);
    expect(find.text('Quick task'), findsOneWidget);
    expect(find.text('Quick note'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('canvas-context-folder-create')))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('canvas-context-action-quickTask')),
          )
          .height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('DayPage canvas assistant previews applies and undoes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 28);
    final repository = InMemoryMindmapRepository(
      seedNodes: <MindmapNode>[
        MindmapNode.create(
          id: 'assistant-a',
          type: NodeType.task,
          title: 'TODO: Interview customers',
          day: day,
          now: day,
        ),
        MindmapNode.create(
          id: 'assistant-b',
          type: NodeType.note,
          title: 'Interview customer research',
          day: day,
          now: day,
        ),
      ],
    );
    final canvasRepository = InMemoryCanvasBoardRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          mindmapRepositoryProvider.overrideWithValue(repository),
          canvasBoardRepositoryProvider.overrideWithValue(canvasRepository),
        ],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-assistant')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('canvas-assistant-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('canvas-assistant-preview-node:assistant-a')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('canvas-assistant-apply')),
    );
    await tester.tap(find.byKey(const ValueKey('canvas-assistant-apply')));
    await tester.pumpAndSettle();

    final applied = await canvasRepository.getBoard(dailyCanvasBoardId(day));
    expect(applied, isNotNull);
    expect(applied!.activity.first.type, CanvasActivityType.assistantApplied);
    expect(find.text('Canvas assistant suggestions applied.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final restored = await canvasRepository.getBoard(dailyCanvasBoardId(day));
    expect(restored, isNotNull);
    expect(restored!.activity, isEmpty);
  });

  testWidgets('DayPage persists canvas viewport without undo activity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 29);
    final repository = InMemoryMindmapRepository(
      seedNodes: <MindmapNode>[
        MindmapNode.create(
          id: 'viewport-note',
          type: NodeType.note,
          title: 'Viewport note',
          day: day,
          now: day,
        ),
      ],
    );
    final canvasRepository = InMemoryCanvasBoardRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          mindmapRepositoryProvider.overrideWithValue(repository),
          canvasBoardRepositoryProvider.overrideWithValue(canvasRepository),
        ],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pump();
    await tester.tap(find.byTooltip('Zoom In'));
    await tester.pump(const Duration(milliseconds: 650));

    final board = await canvasRepository.getBoard(dailyCanvasBoardId(day));
    expect(board, isNotNull);
    expect(board!.viewport.scale, greaterThan(1));
    expect(board.activity, isEmpty);
  });

  testWidgets(
    'DayPage reveals an archived node when opened as the highlighted node',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'active-task',
            type: NodeType.task,
            title: 'Active task',
            day: day,
            now: DateTime(2026, 6, 18, 8),
          ),
          MindmapNode.create(
            id: 'archived-note',
            type: NodeType.note,
            title: 'Archived note',
            day: day,
            isArchived: true,
            now: DateTime(2026, 6, 18, 9),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: DayPage(date: day, highlightNodeId: 'archived-note'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active task'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('inline-workspace-archived-note')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mindmap-highlight-archived-note')),
        findsOneWidget,
      );
      expect((await repository.getNode('archived-note'))!.isArchived, isTrue);
    },
  );

  testWidgets('DayPage centers and expands highlighted node after load', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 6, 18);
    final node = _testNode(
      'deep-link-node',
      day,
    ).copyWith(position: const CanvasPosition(2200, 1600));
    final repository = InMemoryMindmapRepository(seedNodes: [node]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: DayPage(date: day, highlightNodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final viewport = tester.getRect(find.byType(InteractiveViewer));
    final sceneCenter = viewer.transformationController!.toScene(
      viewport.center - viewport.topLeft,
    );

    expect(sceneCenter.dx, closeTo(12200, 1));
    expect(sceneCenter.dy, closeTo(8600, 1));
    expect(
      find.byKey(const ValueKey('inline-workspace-deep-link-node')),
      findsOneWidget,
    );
  });

  testWidgets('DayPage keeps canvas visible when highlighted node is missing', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_testNode('existing-node', day)],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: DayPage(date: day, highlightNodeId: 'missing-node'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mindmap-canvas')), findsOneWidget);
    expect(find.text('Node no longer exists'), findsOneWidget);
  });

  testWidgets('DayPage leaves every alphabet key available to inline editors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 16);
    final node = MindmapNode.create(
      id: 'alphabet-note',
      type: NodeType.note,
      title: 'Alphabet note',
      day: day,
      position: const CanvasPosition(1800, 1200),
      now: day,
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: DayPage(date: day, highlightNodeId: node.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(
      const ValueKey('productivity-alphabet-note-title-field'),
    );
    await tester.tap(field);
    await tester.pump();
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasPrimaryFocus, isTrue);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final before = viewer.transformationController!.value.clone();

    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyG,
      LogicalKeyboardKey.keyH,
      LogicalKeyboardKey.keyI,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.keyO,
      LogicalKeyboardKey.keyP,
      LogicalKeyboardKey.keyQ,
      LogicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.keyT,
      LogicalKeyboardKey.keyU,
      LogicalKeyboardKey.keyV,
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyX,
      LogicalKeyboardKey.keyY,
      LogicalKeyboardKey.keyZ,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pump();

    expect(editable.focusNode.hasPrimaryFocus, isTrue);
    expect(viewer.transformationController!.value, equals(before));
    expect(tester.takeException(), isNull);
  });
  testWidgets('DayPage coalesces inline title typing into one autosave', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 15);
    final repository = _ControlledSaveMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'autosave-note',
          type: NodeType.note,
          title: 'Original',
          day: day,
          now: day,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: DayPage(date: day, highlightNodeId: 'autosave-note'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = find.byKey(
      const ValueKey('productivity-autosave-note-title-field'),
    );
    await tester.enterText(title, 'A');
    await tester.enterText(title, 'AB');
    await tester.enterText(title, 'ABC');
    await tester.pump(const Duration(milliseconds: 449));
    expect(repository.saveCount, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(repository.saveCount, 1);
    expect((await repository.getNode('autosave-note'))!.title, 'ABC');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect((await repository.getNode('autosave-note'))!.title, 'Original');
    expect(
      find.byKey(const ValueKey('inline-workspace-autosave-note')),
      findsOneWidget,
    );
  });

  testWidgets('DayPage lifecycle pause flushes latest inline draft', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 15);
    final repository = _ControlledSaveMindmapRepository(
      seedNodes: [_testNode('lifecycle-note', day)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: DayPage(date: day, highlightNodeId: 'lifecycle-note'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-lifecycle-note-title-field')),
      'Paused draft',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect((await repository.getNode('lifecycle-note'))!.title, 'Paused draft');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('DayPage markdown export flushes draft before reading nodes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 15);
    final repository = _ControlledSaveMindmapRepository(
      seedNodes: [_testNode('markdown-note', day)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: DayPage(date: day, highlightNodeId: 'markdown-note'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-markdown-note-title-field')),
      'Exported draft',
    );

    await tester.tap(find.byTooltip('Copy day markdown'));
    await tester.pump();

    expect(
      (await repository.getNode('markdown-note'))!.title,
      'Exported draft',
    );
  });

  testWidgets('DayPage blocks export and highlight switch on invalid draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 15);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_testNode('guard-a', day), _testNode('guard-b', day)],
    );
    var highlight = 'guard-a';
    late StateSetter rebuild;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return DayPage(date: day, highlightNodeId: highlight);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-guard-a-title-field')),
      '   ',
    );
    await tester.tap(find.byTooltip('Copy day markdown'));
    rebuild(() => highlight = 'guard-b');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inline-workspace-guard-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inline-workspace-guard-b')),
      findsNothing,
    );
    expect(find.text('Save draft before continuing'), findsOneWidget);
  });

  testWidgets('DayPage system back saves valid draft then pops once', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 15);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_testNode('back-valid', day)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          DayPage(date: day, highlightNodeId: 'back-valid'),
                    ),
                  ),
                  child: const Text('Open day'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open day'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-back-valid-title-field')),
      'Saved before back',
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Open day'), findsOneWidget);
    expect(
      (await repository.getNode('back-valid'))!.title,
      'Saved before back',
    );
  });

  testWidgets('DayPage system back keeps invalid draft open', (tester) async {
    final day = DateTime(2026, 7, 15);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_testNode('back-invalid', day)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          DayPage(date: day, highlightNodeId: 'back-invalid'),
                    ),
                  ),
                  child: const Text('Open invalid day'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open invalid day'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-back-invalid-title-field')),
      '   ',
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inline-workspace-back-invalid')),
      findsOneWidget,
    );
    expect(find.text('Save draft before continuing'), findsOneWidget);
  });

  testWidgets('DayPage Pulse navigation keeps invalid draft and sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 15);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_testNode('pulse-invalid', day)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pulse').first);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DayPage)),
    );
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion('pulse-invalid');
    controller.updateDraft('pulse-invalid', InlineNodeDraftPatch(title: '   '));
    await tester.tap(find.text('Thu').last);
    await tester.pumpAndSettle();

    expect(find.text('7-day pulse'), findsOneWidget);
    expect((await repository.getNode('pulse-invalid'))!.title, 'pulse-invalid');
    expect(find.text('Save draft before continuing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DayPage opens Life Explorer as sheet on compact canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'compact-note',
          type: NodeType.note,
          title: 'Compact explorer note',
          day: day,
          now: DateTime(2026, 6, 18, 9),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('life-explorer')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('day-life-explorer-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('life-explorer')), findsOneWidget);
    expect(find.text('Compact explorer note'), findsWidgets);
  });

  testWidgets('DayPage exposes Miro rail and creates productivity nodes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add node'), findsNothing);
    expect(
      find.byKey(const ValueKey('canvas-add-node-fab-hover-scale')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mindmap-canvas-tool-rail')),
      findsOneWidget,
    );
    expect(find.byTooltip('Select'), findsOneWidget);
    expect(find.byTooltip('Sticky note'), findsOneWidget);
    expect(find.byTooltip('Text label'), findsOneWidget);
    expect(find.byTooltip('Shape'), findsOneWidget);
    expect(find.byTooltip('Connector'), findsOneWidget);
    expect(find.byTooltip('Freehand pen'), findsOneWidget);
    expect(find.byTooltip('Frame / section'), findsOneWidget);
    expect(find.byTooltip('Comment'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-create-productivity-node')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create node'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'kan');
    await tester.pumpAndSettle();
    expect(find.text('Kanban'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes.single.type, NodeType.kanban);
  });

  testWidgets('DayPage table project edit does not reuse disposed controller', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await SharedPreferencesAsync().setString('day_view_mode', 'table');
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'project-node',
          type: NodeType.task,
          title: 'Project task',
          day: day,
          project: 'old',
          now: DateTime(2026, 6, 18, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('old').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'new');
    await tester.tap(find.text('Save').last);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final nodes = await repository.listNodes(day: day);
    expect(nodes.single.project, 'new');
  });

  testWidgets('DayPage quick create uses typed title instead of "New <type>"', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('day-fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText == 'Node title...'),
      ),
      'My custom task',
    );

    await tester.tap(find.text(NodeType.task.label).at(1));
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.first.title, 'My custom task');
  });

  testWidgets('DayPage canvas command persists priority and tags', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    final canvasState = tester.state<MindmapCanvasState>(
      find.byType(MindmapCanvas),
    );
    await canvasState.runContextAction(CanvasContextAction.commandPalette);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('command-palette-input')),
      '/task Ship beta #high @release @desktop',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.single.title, 'Ship beta');
    expect(nodes.single.priority, NodePriority.high);
    expect(nodes.single.tags, ['release', 'desktop']);
  });
  testWidgets('DayPage quick create allows default title when empty', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('day-fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(NodeType.note.label).last);
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.first.type, NodeType.note);
    expect(nodes.first.title, 'New ${NodeType.note.label}');
  });

  testWidgets('DayPage quick capture parses command input', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('day-fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText == 'Node title...'),
      ),
      'task bayar listrik p1 #home',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.first.type, NodeType.task);
    expect(nodes.first.title, 'bayar listrik');
    expect(nodes.first.priority, NodePriority.high);
    expect(nodes.first.tags, ['home']);
  });

  testWidgets('DayPage floating quick capture creates parsed command', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Quick capture'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('day-quick-capture-field')),
      'note idea aplikasi baru #product',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.first.type, NodeType.note);
    expect(nodes.first.title, 'idea aplikasi baru');
    expect(nodes.first.tags, ['product']);
  });

  testWidgets(
    'DayPage floating quick capture supports hints and fallback note',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(seedNodes: const []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(home: DayPage(date: day)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quick capture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('habit workout daily'));
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('day-quick-capture-field'));
      expect(
        (tester.widget<TextField>(field).controller?.text),
        'habit workout daily',
      );

      await tester.enterText(field, 'random loose thought');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final nodes = await repository.listNodes(day: day);
      expect(nodes, hasLength(1));
      expect(nodes.first.type, NodeType.note);
      expect(nodes.first.title, 'random loose thought');
    },
  );

  testWidgets('DayPage applies day template from smart plan', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal reset'));
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(3));
    expect(nodes.every((node) => node.tags.contains('template')), isTrue);
    expect(
      nodes.every((node) => node.data['dayTemplateId'] == 'personal-reset'),
      isTrue,
    );
  });

  testWidgets('DayPage selects custom template', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);
    await SharedPreferencesAsync().setString(
      customNodeTemplatesPreferenceKey,
      jsonEncode([
        {
          'id': 'custom-focus',
          'label': 'Custom focus',
          'type': 'task',
          'title': 'Focus task',
          'priority': 'high',
          'tags': ['focus'],
        },
      ]),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply template'));
    await tester.pumpAndSettle();
    final customTemplate = find.byKey(
      const ValueKey('day-custom-template-custom-focus'),
    );
    await tester.scrollUntilVisible(
      customTemplate,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(customTemplate);
    await tester.pumpAndSettle();

    final node = (await repository.listNodes(day: day)).single;
    expect(node.title, 'Focus task');
    expect(node.type, NodeType.task);
    expect(node.priority, NodePriority.high);
    expect(node.tags, contains('focus'));
  });

  testWidgets('DayPage disables already applied template', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'template-marker',
          type: NodeType.task,
          title: 'Template marker',
          day: day,
          tags: const ['template'],
          data: const {'dayTemplateId': 'workday'},
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply template'));
    await tester.pumpAndSettle();

    expect(find.text('Already applied'), findsOneWidget);
    final before = await repository.listNodes(day: day);
    await tester.tap(find.text('Workday'));
    await tester.pumpAndSettle();
    final after = await repository.listNodes(day: day);
    expect(after, hasLength(before.length));
  });

  testWidgets('DayPage carry-over sheet moves unfinished prior task', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final yesterday = DateTime(2026, 6, 17);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'old-task',
          type: NodeType.task,
          title: 'Old task',
          day: yesterday,
          dueDate: yesterday,
          now: DateTime(2026, 6, 17, 9),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();

    expect(find.text('Carry over 1 items'), findsOneWidget);

    await tester.tap(find.text('Carry over 1 items'));
    await tester.pumpAndSettle();

    expect(find.text('Carry-over assistant'), findsOneWidget);
    expect(find.text('Old task'), findsWidgets);

    await tester.tap(find.byTooltip('Move to day'));
    await tester.pumpAndSettle();

    final moved = (await repository.listNodes(day: day)).single;
    expect(moved.id, 'old-task');
    expect(moved.day, day);
    expect(moved.dueDate, day);
    expect(await repository.listNodes(day: yesterday), isEmpty);
  });

  testWidgets('DayPage creates tomorrow top tasks from daily review', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final tomorrow = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'review',
          type: NodeType.journal,
          title: 'Daily review ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â 2026-06-18',
          day: day,
          body: '''
## Tomorrow top 3
- Write docs
- Fix sync
- Plan launch
''',
          tags: const ['daily-review'],
          now: DateTime(2026, 6, 18, 18),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();

    expect(find.text('Create tomorrow top 3'), findsOneWidget);

    await tester.tap(find.text('Create tomorrow top 3'));
    await tester.pumpAndSettle();

    final tomorrowNodes = await repository.listNodes(day: tomorrow);
    expect(tomorrowNodes.map((node) => node.title), [
      'Write docs',
      'Fix sync',
      'Plan launch',
    ]);
    expect(tomorrowNodes.first.priority, NodePriority.high);
    expect(tomorrowNodes.skip(1).map((node) => node.priority), [
      NodePriority.medium,
      NodePriority.medium,
    ]);
    expect(
      tomorrowNodes.every((node) => node.relatedNodeIds.contains('review')),
      isTrue,
    );
  });

  testWidgets('DayPage skips existing tomorrow top tasks', (tester) async {
    final day = DateTime(2026, 6, 18);
    final tomorrow = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'review',
          type: NodeType.journal,
          title: 'Daily review ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â 2026-06-18',
          day: day,
          body: '''
## Tomorrow top 3
- Write docs
- Fix sync
''',
          tags: const ['daily-review'],
          now: DateTime(2026, 6, 18, 18),
        ),
        MindmapNode.create(
          id: 'existing',
          type: NodeType.task,
          title: 'Write docs',
          day: tomorrow,
          tags: const ['tomorrow-top-3'],
          now: DateTime(2026, 6, 18, 19),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create tomorrow top 2'));
    await tester.pumpAndSettle();

    final tomorrowNodes = await repository.listNodes(day: tomorrow);
    expect(
      tomorrowNodes.where((node) => node.title == 'Write docs'),
      hasLength(1),
    );
    expect(
      tomorrowNodes.where((node) => node.title == 'Fix sync'),
      hasLength(1),
    );
  });

  testWidgets('DayPage inbox sheet assigns loose capture to today', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final yesterday = DateTime(2026, 6, 17);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'capture',
          type: NodeType.note,
          title: 'Loose capture',
          day: yesterday,
          data: const {inboxNodeDataKey: true},
          now: DateTime(2026, 6, 17, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inbox 1'));
    await tester.pumpAndSettle();

    expect(find.text('Loose capture'), findsOneWidget);
    await tester.tap(find.byTooltip('Assign today'));
    await tester.pumpAndSettle();

    final assigned = (await repository.listNodes(day: day)).single;
    expect(assigned.id, 'capture');
    expect(isInboxNode(assigned), isFalse);
    expect(
      assigned.data[inboxAssignedFromDataKey],
      yesterday.toIso8601String(),
    );
  });

  testWidgets('DayPage inbox sheet archives loose capture', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'capture',
          type: NodeType.note,
          title: 'Loose capture',
          day: day,
          data: const {inboxNodeDataKey: true},
          now: DateTime(2026, 6, 18, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inbox 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();

    final archived = (await repository.listNodes()).single;
    expect(archived.id, 'capture');
    expect(archived.isArchived, isTrue);
  });

  testWidgets('DayPage activity log shows recent created node', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('day-fab')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText == 'Node title...'),
      ),
      'Activity task',
    );
    await tester.tap(find.text(NodeType.task.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Activity log'));
    await tester.pumpAndSettle();

    expect(find.text('Activity log'), findsOneWidget);
    expect(find.text('Created node'), findsOneWidget);
    expect(find.textContaining('Activity task'), findsOneWidget);
  });

  testWidgets('DayPage blank board starter can be hidden', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blank board'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide blank board starters'));
    await tester.pumpAndSettle();

    expect(find.text('Blank board'), findsNothing);
  });

  testWidgets('DayPage empty state starts daily journal', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blank board'), findsOneWidget);
    expect(find.text('Plan my day'), findsOneWidget);
    expect(find.text('Import yesterday leftovers'), findsOneWidget);
    expect(find.text('Start journal'), findsOneWidget);
    expect(find.text('Apply routine'), findsOneWidget);
    expect(find.text('Use template'), findsOneWidget);
    expect(find.text('Quick capture'), findsOneWidget);

    await tester.tap(find.text('Start journal'));
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.single.type, NodeType.journal);
    expect(nodes.single.tags, contains('daily-review'));
  });

  testWidgets('DayPage selected node actions mark done and create follow-up', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task',
          type: NodeType.task,
          title: 'Selected task',
          day: day,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mindmap-node-task')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-task-title-field')),
      'Edited selected task',
    );

    expect(find.byKey(const ValueKey('ribbon-tab-node')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ribbon-node-actions')));
    await tester.pumpAndSettle();

    expect(find.text('Node tools'), findsOneWidget);
    final markDoneAction = find.widgetWithText(ActionChip, 'Mark done');
    expect(markDoneAction, findsOneWidget);
    tester.widget<ActionChip>(markDoneAction).onPressed!();
    await tester.pumpAndSettle();

    final task = (await repository.listNodes(day: day)).single;
    expect(task.isDone, isTrue);
    expect(task.title, 'Edited selected task');

    final followUpAction = find.widgetWithText(ActionChip, 'Follow-up');
    expect(followUpAction, findsOneWidget);
    tester.widget<ActionChip>(followUpAction).onPressed!();
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(
      nodes.map((node) => node.title),
      contains('Follow-up: Edited selected task'),
    );
  });

  testWidgets('expanded task wires attachment repository actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 16);
    final repository = InMemoryMindmapRepository(
      seedNodes: <MindmapNode>[
        MindmapNode.create(
          id: 'attachment-task',
          type: NodeType.task,
          title: 'Attachment task',
          day: day,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          mindmapRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('mindmap-node-attachment-task')),
    );
    await tester.pumpAndSettle();

    final workspace = tester.widget<InlineNodeWorkspace>(
      find.byType(InlineNodeWorkspace),
    );
    expect(workspace.editContext.onTaskAttachmentAdd, isNotNull);
    expect(workspace.editContext.onTaskAttachmentOpen, isNotNull);
    expect(workspace.editContext.onTaskAttachmentRemove, isNotNull);
  });

  testWidgets('expanded image loads local attachment preview bytes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 16);
    final repository = InMemoryMindmapRepository(
      seedNodes: <MindmapNode>[_localImageNode('preview-image', day)],
    );
    final attachments = _RecordingAttachmentRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          mindmapRepositoryProvider.overrideWithValue(repository),
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => attachments,
          ),
        ],
        child: MaterialApp(
          home: DayPage(date: day, highlightNodeId: 'preview-image'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('old.png'), findsOneWidget);
    expect(find.byKey(const ValueKey('image-local-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded resource wires file and open actions', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 16);
    final repository = InMemoryMindmapRepository(
      seedNodes: <MindmapNode>[
        MindmapNode.create(
          id: 'resource-node',
          type: NodeType.resource,
          title: 'Resource node',
          day: day,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          mindmapRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('mindmap-node-resource-node')),
    );
    await tester.pumpAndSettle();

    final workspace = tester.widget<InlineNodeWorkspace>(
      find.byType(InlineNodeWorkspace),
    );
    expect(workspace.editContext.onResourceAssetAdd, isNotNull);
    expect(workspace.editContext.onResourceAssetOpen, isNotNull);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey<String>('resource-primary-choose-file')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('DayPage immediate edit survives move to tomorrow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_testNode('move-now', day)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: DayPage(date: day, highlightNodeId: 'move-now'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-move-now-title-field')),
      'Edited before move',
    );
    await tester.tap(find.byKey(const ValueKey('ribbon-node-actions')));
    await tester.pumpAndSettle();
    tester
        .widget<ActionChip>(find.widgetWithText(ActionChip, 'Tomorrow'))
        .onPressed!();
    await tester.pumpAndSettle();

    final moved = (await repository.listNodes(
      day: day.add(const Duration(days: 1)),
    )).single;
    expect(moved.title, 'Edited before move');
  });

  testWidgets('DayPage JSON export contains immediate draft', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_testNode('json-latest', day)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: DayPage(date: day, highlightNodeId: 'json-latest'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-json-latest-title-field')),
      'Latest JSON title',
    );
    String? exportedJson;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            exportedJson =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.tap(find.byKey(const ValueKey('ribbon-tab-canvas')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More canvas tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy canvas JSON'));
    await tester.pumpAndSettle();

    expect(exportedJson, contains('Latest JSON title'));
  });

  testWidgets(
    'DayPage context Open edit selects inline workspace without detail navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final DateTime day = DateTime(2026, 6, 18);
      final InMemoryMindmapRepository repository = InMemoryMindmapRepository(
        seedNodes: <MindmapNode>[_testNode('context-open', day)],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            mindmapRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(home: DayPage(date: day)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mindmap-node-context-open')),
        buttons: 2,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('canvas-node-menu-open')));
      await tester.pumpAndSettle();

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(DayPage)),
      );
      expect(
        container.read(inlineNodeWorkspaceControllerProvider).expandedNodeId,
        'context-open',
      );
      expect(
        find.byKey(const ValueKey('inline-workspace-context-open')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('productivity-context-open-title-field')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('DayPage immediate edit survives context pin and archive', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_testNode('context-latest', day)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: DayPage(date: day, highlightNodeId: 'context-latest'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-context-latest-title-field')),
      'Edited before context action',
    );
    await tester.tap(find.byKey(const ValueKey('ribbon-clear-node-selection')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-node-context-latest')),
      buttons: 2,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();
    var saved = (await repository.getNode('context-latest'))!;
    expect(saved.title, 'Edited before context action');
    expect(saved.isPinned, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('mindmap-node-context-latest')),
      buttons: 2,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    saved = (await repository.getNode('context-latest'))!;
    expect(saved.title, 'Edited before context action');
    expect(saved.isArchived, isTrue);
  });

  testWidgets('DayPage duplicate clones latest inline draft fields', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final priorDay = day.subtract(const Duration(days: 1));
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'duplicate-latest',
          type: NodeType.task,
          title: 'duplicate-latest',
          day: priorDay,
          dueDate: priorDay,
          now: priorDay,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carry over 1 items'));
    await tester.pumpAndSettle();
    final latest = (await repository.getNode(
      'duplicate-latest',
    ))!.copyWith(title: 'Edited before duplicate');
    await repository.saveNode(latest);
    await tester.tap(find.byTooltip('Duplicate to day'));
    await tester.pumpAndSettle();

    final duplicated = (await repository.listNodes(day: day)).single;
    expect(duplicated.title, 'Edited before duplicate');
  });

  testWidgets(
    'DayPage selection expands one canvas node and collapse clears it',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final day = DateTime(2026, 7, 15);
      final repository = InMemoryMindmapRepository(
        seedNodes: <MindmapNode>[
          MindmapNode.create(
            id: 'expand-a',
            type: NodeType.note,
            title: 'Expand A',
            day: day,
            now: day,
          ),
          MindmapNode.create(
            id: 'expand-b',
            type: NodeType.task,
            title: 'Expand B',
            day: day,
            now: day,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            mindmapRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(home: DayPage(date: day)),
        ),
      );
      await tester.pumpAndSettle();
      await tester
          .state<MindmapCanvasState>(find.byType(MindmapCanvas))
          .selectAndFocusNode((await repository.getNode('expand-a'))!);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('inline-workspace-expand-a')),
        findsOneWidget,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inline-workspace-expand-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inline-workspace-expand-b')),
        findsNothing,
      );
      await tester
          .state<MindmapCanvasState>(find.byType(MindmapCanvas))
          .selectAndFocusNode((await repository.getNode('expand-b'))!);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inline-workspace-expand-a')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('inline-workspace-expand-b')),
        findsOneWidget,
      );
      const collapseKey = ValueKey<String>(
        'inline-workspace-collapse-expand-b',
      );
      expect(_primaryFocusHasAncestorKey(collapseKey), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inline-workspace-expand-b')),
        findsNothing,
      );
      expect(
        _primaryFocusHasAncestorKey(
          const ValueKey<String>('mindmap-node-focus-expand-b'),
        ),
        isTrue,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inline-workspace-expand-b')),
        findsNothing,
      );
    },
  );

  testWidgets('DayPage deletes drag-selected nodes and supports undo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 16);
    final repository = InMemoryMindmapRepository(
      seedNodes: <MindmapNode>[
        MindmapNode.create(
          id: 'delete-selected-a',
          type: NodeType.note,
          title: 'Delete A',
          day: day,
          now: day,
        ),
        MindmapNode.create(
          id: 'delete-selected-b',
          type: NodeType.task,
          title: 'Delete B',
          day: day,
          now: day,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          mindmapRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();
    await tester
        .state<MindmapCanvasState>(find.byType(MindmapCanvas))
        .runContextAction(CanvasContextAction.selectAll);
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await repository.listNodes(day: day), isEmpty);
    expect(find.text('2 selected'), findsNothing);

    for (var index = 0; index < 2; index++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }
    expect(await repository.listNodes(day: day), hasLength(2));
  });

  testWidgets('DayPage context switcher filters visible nodes', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'launch-task',
          type: NodeType.task,
          title: 'Launch task',
          day: day,
          project: 'launch',
        ),
        MindmapNode.create(
          id: 'personal-task',
          type: NodeType.task,
          title: 'Personal task',
          day: day,
          area: 'personal',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Launch task'), findsOneWidget);
    expect(find.text('Personal task'), findsOneWidget);

    await tester.tap(find.byTooltip('Day context'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project: launch').last);
    await tester.pumpAndSettle();

    expect(find.text('Launch task'), findsOneWidget);
    expect(find.text('Personal task'), findsNothing);
    expect(find.text('Context: Project: launch'), findsOneWidget);
  });

  testWidgets('DayPage day tabs navigate without narrow overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = InMemoryMindmapRepository(seedNodes: []);
    final router = GoRouter(
      initialLocation: '/calendar/2026-06-18',
      routes: [
        GoRoute(
          path: '/calendar/:date',
          builder: (context, state) =>
              DayPage(date: DateTime.parse(state.pathParameters['date']!)),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('2026-06-18').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide day tabs'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/calendar/2026-06-19',
    );
    expect(find.byTooltip('Hide day tabs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'DayPage day tabs collapse and selection rail state preservation',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'node-a',
            type: NodeType.task,
            title: 'Node A',
            day: day,
          ),
          MindmapNode.create(
            id: 'node-b',
            type: NodeType.task,
            title: 'Node B',
            day: day,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(home: DayPage(date: day)),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Day tabs start collapsed (showing dayKey title)
      const formattedDayStr = '2026-06-18';
      expect(find.text(formattedDayStr), findsNWidgets(2));
      expect(find.byIcon(Icons.calendar_view_week_rounded), findsOneWidget);

      // Tap to expand day tabs
      await tester.tap(find.text(formattedDayStr).last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hide day tabs'), findsOneWidget);

      // 2. Select node A -> shows compact mobile toolbar.
      await tester
          .state<MindmapCanvasState>(find.byType(MindmapCanvas))
          .selectAndFocusNode((await repository.getNode('node-a'))!);
      await tester.pumpAndSettle();
      expect(find.text('Tools'), findsOneWidget);

      expect(
        find.byKey(const ValueKey('inline-workspace-node-a')),
        findsOneWidget,
      );
      // Open Node tab, then collapse expanded canvas workspace.
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Node'));
      await tester.pumpAndSettle();
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('inline-workspace-collapse-node-a')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Tools'), findsOneWidget);

      // 3. Select node B -> only B expands.
      await tester
          .state<MindmapCanvasState>(find.byType(MindmapCanvas))
          .selectAndFocusNode((await repository.getNode('node-b'))!);
      await tester.pumpAndSettle();
      expect(find.text('Tools'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('inline-workspace-node-a')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('inline-workspace-node-b')),
        findsOneWidget,
      );
    },
  );

  testWidgets('DayPage desktop ribbon changes tools by selected tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'ribbon-node',
          type: NodeType.task,
          title: 'Ribbon node',
          day: day,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Board'), findsWidgets);
    expect(find.textContaining('Pulse'), findsWidgets);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Capture'), findsOneWidget);
    expect(find.byKey(const ValueKey('ribbon-active-tools')), findsOneWidget);
    final homeToolsHeight = tester
        .getSize(find.byKey(const ValueKey('ribbon-active-tools')))
        .height;

    await tester.tap(find.byKey(const ValueKey('ribbon-tab-insert')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('ribbon-active-tools'))).height,
      homeToolsHeight,
    );
    expect(find.text('All types'), findsOneWidget);
    expect(find.text('Task'), findsWidgets);
    expect(find.text('Note'), findsOneWidget);
    final allTypesRect = tester.getRect(
      find.byKey(const ValueKey('ribbon-all-types')),
    );
    await tester.tap(find.byKey(const ValueKey('ribbon-all-types')));
    await tester.pumpAndSettle();
    final ribbonPanelRect = tester.getRect(
      find.byKey(const ValueKey('canvas-add-node-context-panel')),
    );
    expect(ribbonPanelRect.top, greaterThanOrEqualTo(allTypesRect.bottom));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ribbon-tab-canvas')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('ribbon-active-tools'))).height,
      homeToolsHeight,
    );
    expect(find.text('Grid'), findsOneWidget);
    expect(find.text('Snap'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ribbon-tab-view')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('ribbon-active-tools'))).height,
      homeToolsHeight,
    );
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('Minimap'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mindmap-node-ribbon-node')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('ribbon-active-tools'))).height,
      homeToolsHeight,
    );
    expect(
      find.byKey(const ValueKey('ribbon-node-size-presets')),
      findsOneWidget,
    );
    expect(find.text('Edit'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ribbon-node-save-status')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('ribbon-clear-node-selection')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Board'), findsWidgets);
  });

  testWidgets(
    'Task15 contextual Node ribbon persists presets and gates media actions',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final day = DateTime(2026, 7, 13);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'task15-task',
            type: NodeType.task,
            title: 'Task ribbon',
            day: day,
            position: const CanvasPosition(-220, 0),
          ),
          MindmapNode.create(
            id: 'task15-image',
            type: NodeType.image,
            title: 'Image ribbon',
            day: day,
            position: const CanvasPosition(260, 0),
            data: const ImagePayload(
              url: 'https://example.com/image.png',
            ).toData(const {}),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(home: DayPage(date: day)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('mindmap-node-task15-task')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ribbon-tab-node')), findsOneWidget);
      expect(find.byKey(const ValueKey('ribbon-media-replace')), findsNothing);
      expect(
        find.byKey(const ValueKey('productivity-task15-task-title-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('productivity-task15-task-body-field')),
        findsOneWidget,
      );

      await repository.saveNode(
        (await repository.getNode(
          'task15-task',
        ))!.copyWith(body: 'Concurrent body update'),
      );
      await tester.tap(find.text('Wide'));
      await tester.pumpAndSettle();
      final savedTask = await repository.getNode('task15-task');
      expect(NodeUiStateCodec.read(savedTask!).sizePreset.name, 'wide');
      expect(savedTask.body, 'Concurrent body update');

      var semantics = tester.getSemantics(
        find.byKey(const ValueKey('ribbon-node-save-status')),
      );
      expect(semantics.value, 'saved');
      await tester.enterText(
        find.byKey(const ValueKey('productivity-task15-task-title-field')),
        'Task ribbon edited',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      semantics = tester.getSemantics(
        find.byKey(const ValueKey('ribbon-node-save-status')),
      );
      expect(semantics.value, 'saved');
      expect(
        (await repository.getNode('task15-task'))!.title,
        'Task ribbon edited',
      );

      await tester.enterText(
        find.byKey(const ValueKey('productivity-task15-task-title-field')),
        '   ',
      );
      await tester.pumpAndSettle();
      semantics = tester.getSemantics(
        find.byKey(const ValueKey('ribbon-node-save-status')),
      );
      expect(semantics.value, 'error');
      await tester.enterText(
        find.byKey(const ValueKey('productivity-task15-task-title-field')),
        'Task ribbon corrected',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('ribbon-node-save-status')))
            .value,
        'saved',
      );

      await tester.enterText(
        find.byKey(const ValueKey('productivity-task15-task-body-field')),
        'Saved while deselecting',
      );
      await tester.tap(
        find.byKey(const ValueKey('ribbon-clear-node-selection')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Board'), findsWidgets);
      expect(
        (await repository.getNode('task15-task'))!.body,
        'Saved while deselecting',
      );

      final imageRepository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'task15-image-only',
            type: NodeType.image,
            title: 'Image ribbon',
            day: day,
            data: const ImagePayload(
              url: 'https://example.com/image.png',
            ).toData(const {}),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('task15-local-image-scope'),
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(imageRepository),
          ],
          child: MaterialApp(
            home: DayPage(date: day, highlightNodeId: 'task15-image-only'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ribbon-tab-node')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ribbon-media-replace')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ribbon-media-export')), findsOneWidget);
      expect(find.byKey(const ValueKey('ribbon-media-open')), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('ribbon-media-export')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('ribbon-media-open')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('ribbon-media-replace')));
      await tester.pumpAndSettle();
      expect(find.text('Add image'), findsWidgets);
      await imageRepository.saveNode(
        (await imageRepository.getNode('task15-image-only'))!.copyWith(
          data:
              ImagePayload.fromNode(
                    (await imageRepository.getNode('task15-image-only'))!,
                  )
                  .copyWith(caption: 'Concurrent caption')
                  .toData(
                    (await imageRepository.getNode('task15-image-only'))!.data,
                  ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('image-import-url')),
        'https://example.com/replaced.png',
      );
      await tester.tap(find.byKey(const ValueKey('image-import-submit')));
      await tester.pumpAndSettle();
      final replacedImage = await imageRepository.getNode('task15-image-only');
      expect(
        ImagePayload.fromNode(replacedImage!).url,
        'https://example.com/replaced.png',
      );
      expect(
        ImagePayload.fromNode(replacedImage).caption,
        'Concurrent caption',
      );
      await tester.tap(find.byKey(const ValueKey('ribbon-media-open')));
      await tester.pump();

      final attachmentRepository = _RecordingAttachmentRepository();
      var fileExportCalls = 0;
      Future<String> recordExport(Uint8List bytes, String fileName) async {
        fileExportCalls++;
        return 'test-exports/$fileName';
      }

      final localImageRepository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'task15-local-image',
            type: NodeType.image,
            title: 'Local image',
            day: day,
            data: const ImagePayload(
              attachmentId: '11111111-1111-1111-1111-111111111111',
              mimeType: 'image/png',
              fileName: 'task15.png',
            ).toData(const {}),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('task15-local-video-scope'),
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(localImageRepository),
            nodeAttachmentRepositoryProvider.overrideWith(
              (ref) async => attachmentRepository,
            ),
          ],
          child: MaterialApp(
            home: DayPage(
              date: day,
              highlightNodeId: 'task15-local-image',
              mediaFileExporter: recordExport,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ribbon-tab-node')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ribbon-media-export')));
      await tester.pumpAndSettle();
      expect(attachmentRepository.exportCalls, 1);
      expect(fileExportCalls, 1);
      expect(find.textContaining('Exported to'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('ribbon-media-open')),
            )
            .onPressed,
        isNull,
      );

      final localVideoRepository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'task15-local-video',
            type: NodeType.video,
            title: 'Local video',
            day: day,
            data: const VideoPayload(
              attachmentId: '22222222-2222-2222-2222-222222222222',
              mimeType: 'video/mp4',
              fileName: 'task15.mp4',
            ).toData(const {}),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('task15-local-video-scope'),
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(localVideoRepository),
            nodeAttachmentRepositoryProvider.overrideWith(
              (ref) async => attachmentRepository,
            ),
          ],
          child: MaterialApp(
            home: DayPage(
              date: day,
              highlightNodeId: 'task15-local-video',
              mediaFileExporter: recordExport,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('ribbon-tab-node')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('ribbon-media-export')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(attachmentRepository.exportCalls, 2);
      expect(fileExportCalls, 2);
    },
  );

  testWidgets('Task15 contains save failure and retries from Node ribbon', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 13);
    final repository = _FailOnceMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task15-fail',
          type: NodeType.task,
          title: 'Fail once',
          day: day,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-node-task15-fail')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    repository.failNextSave();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-task15-fail-title-field')),
      'Retry succeeds',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('ribbon-node-save-status')))
          .value,
      'error',
    );

    await tester.tap(
      find.byKey(const ValueKey('inline-workspace-retry-task15-fail')),
    );
    await tester.pumpAndSettle();
    expect((await repository.getNode('task15-fail'))!.title, 'Retry succeeds');
  });

  testWidgets('Task15 reports dirty saving and saved transitions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 13);
    final repository = _ControlledSaveMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task15-saving',
          type: NodeType.task,
          title: 'Saving state',
          day: day,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-node-task15-saving')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    repository.holdNextSave();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-task15-saving-title-field')),
      'Saving state edited',
    );
    await tester.pump();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('ribbon-node-save-status')))
          .value,
      'dirty',
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('ribbon-node-save-status')))
          .value,
      'saving',
    );
    repository.completeSave();
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('ribbon-node-save-status')))
          .value,
      'saved',
    );
  });

  testWidgets('Task15 applies only latest async selection transition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 14);
    final repository = _ControlledSaveMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'race-a',
          type: NodeType.task,
          title: 'Race A',
          day: day,
          position: const CanvasPosition(-220, 0),
        ),
        MindmapNode.create(
          id: 'race-b',
          type: NodeType.note,
          title: 'Race B',
          day: day,
          position: const CanvasPosition(0, 0),
        ),
        MindmapNode.create(
          id: 'race-c',
          type: NodeType.goal,
          title: 'Race C',
          day: day,
          position: const CanvasPosition(220, 0),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();
    final canvasState = tester.state<MindmapCanvasState>(
      find.byType(MindmapCanvas),
    );
    await canvasState.selectAndFocusNode(
      (await repository.listNodes(
        day: day,
      )).firstWhere((node) => node.id == 'race-a'),
    );
    await tester.pumpAndSettle();
    repository.holdNextSave();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-race-a-title-field')),
      'Race A edited',
    );
    unawaited(
      canvasState.selectAndFocusNode(
        (await repository.listNodes(
          day: day,
        )).firstWhere((node) => node.id == 'race-b'),
      ),
    );
    unawaited(
      canvasState.selectAndFocusNode(
        (await repository.listNodes(
          day: day,
        )).firstWhere((node) => node.id == 'race-c'),
      ),
    );
    await tester.pump();
    repository.completeSave();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ribbon-active-tools')),
        matching: find.text('Goal'),
      ),
      findsOneWidget,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect((await repository.getNode('race-a'))!.title, 'Race A');
    expect(
      find.byKey(const ValueKey('inline-workspace-race-c')),
      findsOneWidget,
    );

    await canvasState.selectAndFocusNode(
      (await repository.listNodes(
        day: day,
      )).firstWhere((node) => node.id == 'race-a'),
    );
    await tester.pumpAndSettle();
    repository.holdNextSave();
    await tester.enterText(
      find.byKey(const ValueKey('productivity-race-a-body-field')),
      'Clear race draft',
    );
    await tester.tap(find.byKey(const ValueKey('ribbon-clear-node-selection')));
    unawaited(
      canvasState.selectAndFocusNode(
        (await repository.listNodes(
          day: day,
        )).firstWhere((node) => node.id == 'race-b'),
      ),
    );
    await tester.pump();
    repository.completeSave();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ribbon-active-tools')),
        matching: find.text('Note'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('ribbon-node-save-status')))
          .value,
      'idle',
    );
    repository.holdNextSave();
    await tester.enterText(
      find.byKey(const ValueKey('note-markdown-editor')),
      'Escape flush draft',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    repository.completeSave();
    await tester.pumpAndSettle();
    expect(find.textContaining('Board'), findsWidgets);
    expect((await repository.getNode('race-b'))!.body, 'Escape flush draft');
  });

  testWidgets(
    'Task15 Life Explorer flushes old draft before selecting and focusing new node',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final day = DateTime(2026, 7, 14);
      final repository = _ControlledSaveMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'explorer-old',
            type: NodeType.task,
            title: 'Explorer old',
            day: day,
            position: const CanvasPosition(-260, 0),
          ),
          MindmapNode.create(
            id: 'explorer-new',
            type: NodeType.note,
            title: 'Explorer new',
            day: day,
            position: const CanvasPosition(260, 0),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(home: DayPage(date: day)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mindmap-node-explorer-old')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      repository.holdNextSave();
      await tester.enterText(
        find.byKey(const ValueKey('productivity-explorer-old-body-field')),
        'Saved before explorer focus',
      );
      await tester.tap(
        find.byKey(const ValueKey('life-explorer-node-explorer-new')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mindmap-highlight-explorer-new')),
        findsNothing,
      );
      repository.completeSave();
      await tester.pumpAndSettle();

      expect(
        (await repository.getNode('explorer-old'))!.body,
        'Saved before explorer focus',
      );
      expect(
        find.byKey(const ValueKey('mindmap-highlight-explorer-new')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('life-explorer-node-explorer-new')),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('ribbon-node-save-status')))
            .value,
        'idle',
      );
    },
  );

  testWidgets('DayPage All types Image opens reachable URL import', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 13);
    final repository = InMemoryMindmapRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ribbon-tab-insert')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ribbon-all-types')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Search type...',
      ),
      'Image',
    );
    await tester.pumpAndSettle();
    final imageTile = find.ancestor(
      of: find.text('Image'),
      matching: find.byType(InkWell),
    );
    expect(imageTile, findsOneWidget);
    await tester.tap(imageTile);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-import-url')), findsOneWidget);
    expect(find.text('Import local image'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('image-import-url')),
      'https://example.com/photo.png',
    );
    await tester.enterText(
      find.byKey(const ValueKey('image-import-alt')),
      'Accessible photo',
    );
    await tester.tap(find.byKey(const ValueKey('image-import-submit')));
    await tester.pumpAndSettle();
    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.single.type, NodeType.image);
    expect(
      ImagePayload.fromNode(nodes.single).url,
      'https://example.com/photo.png',
    );
  });

  testWidgets('DayPage All types Video opens reachable safe URL import', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 13);
    final repository = InMemoryMindmapRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ribbon-tab-insert')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ribbon-all-types')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Search type...',
      ),
      'Video',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(of: find.text('Video'), matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-import-url')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('video-import-url')),
      'file:///unsafe.mp4',
    );
    await tester.tap(find.byKey(const ValueKey('video-import-submit')));
    await tester.pump();
    expect(
      find.text('Video URL must use HTTPS, or HTTP localhost.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('video-import-url')),
      'https://example.com/demo.mp4',
    );
    await tester.tap(find.byKey(const ValueKey('video-import-submit')));
    await tester.pumpAndSettle();
    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.single.type, NodeType.video);
    expect(
      VideoPayload.fromNode(nodes.single).url,
      'https://example.com/demo.mp4',
    );
  });

  testWidgets(
    'DayPage replaces image and refreshes expanded editor immediately',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final day = DateTime(2026, 7, 15);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'local-image-node',
            type: NodeType.image,
            title: 'Local image',
            day: day,
            position: const CanvasPosition(0, 0),
            data: const ImagePayload(
              attachmentId: '223e4567-e89b-12d3-a456-426614174000',
              mimeType: 'image/png',
              fileName: 'old.png',
              caption: 'Preserved caption',
              altText: 'Preserved alt',
              fitMode: ImageFitMode.cover,
              sourceUrl: 'https://source.example.test/original',
              tags: <String>['reference'],
              rotationQuarterTurns: 1,
              flipHorizontal: true,
              brightness: 0.2,
              contrast: -0.1,
              saturation: 0.3,
              filter: ImageFilterPreset.warm,
              annotations: <ImageAnnotation>[
                ImageAnnotation(
                  id: 'replace-annotation',
                  type: ImageAnnotationType.rectangle,
                ),
              ],
            ).toData(const {'unrelated': 'keep'}),
          ),
        ],
      );
      final attachments = _RecordingAttachmentRepository();
      final importService = MediaFileImportService(
        repository: attachments,
        picker: const _DayPageMediaPicker(
          PickedMediaFile(
            fileName: 'picked.png',
            byteLength: 8,
            mimeType: 'image/png',
            bytes: [137, 80, 78, 71, 13, 10, 26, 10],
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(repository),
            nodeAttachmentRepositoryProvider.overrideWith((ref) async {
              return attachments;
            }),
            mediaFileImportServiceProvider.overrideWith((ref) async {
              return importService;
            }),
          ],
          child: MaterialApp(
            home: DayPage(date: day, highlightNodeId: 'local-image-node'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ribbon-tab-node')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ribbon-media-replace')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('image-import-local')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('image-import-local')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 500));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DayPage)),
      );
      final draft = container
          .read(inlineNodeWorkspaceControllerProvider)
          .nodes['local-image-node']!
          .draft;
      expect(
        ImagePayload.fromNode(draft).attachmentId,
        _RecordingAttachmentRepository.importedId,
      );
      expect(find.text('picked.png'), findsWidgets);
      expect(find.byKey(const ValueKey('image-local-preview')), findsOneWidget);
      expect(
        attachments.readIds,
        contains(_RecordingAttachmentRepository.importedId),
      );

      final saved = await repository.getNode('local-image-node');
      final payload = ImagePayload.fromNode(saved!);
      expect(payload.attachmentId, _RecordingAttachmentRepository.importedId);
      expect(payload.url, isEmpty);
      expect(payload.fileName, 'picked.png');
      expect(payload.mimeType, 'image/png');
      expect(payload.caption, 'Preserved caption');
      expect(payload.altText, 'Preserved alt');
      expect(payload.fitMode, ImageFitMode.cover);
      expect(payload.sourceUrl, 'https://source.example.test/original');
      expect(payload.tags, <String>['reference']);
      expect(payload.rotationQuarterTurns, 1);
      expect(payload.flipHorizontal, isTrue);
      expect(payload.brightness, 0.2);
      expect(payload.contrast, -0.1);
      expect(payload.saturation, 0.3);
      expect(payload.filter, ImageFilterPreset.warm);
      expect(payload.annotations.single.id, 'replace-annotation');
      expect(saved.data['unrelated'], 'keep');
      expect(saved.data.containsKey('bytes'), isFalse);
      expect(saved.data.containsKey('path'), isFalse);
      expect(attachments.importCalls, 1);
      expect(attachments.deletedIds, isNot(contains(_oldAttachmentId)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('DayPage removes new attachment when replace save fails', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 15);
    final repository = _FailOnceMindmapRepository(
      seedNodes: [_localImageNode('save-failure-image', day)],
    );
    final attachments = _RecordingAttachmentRepository();
    await _pumpMediaReplacePage(
      tester,
      day: day,
      nodeId: 'save-failure-image',
      repository: repository,
      attachments: attachments,
      picker: const _DayPageMediaPicker(_validPickedPng),
    );
    repository.failNextSave();

    await tester.tap(find.byKey(const ValueKey('image-import-local')));
    await _pumpAsyncReplace(tester);

    expect(
      attachments.deletedIds,
      contains(_RecordingAttachmentRepository.importedId),
    );
    final saved = await repository.getNode('save-failure-image');
    expect(ImagePayload.fromNode(saved!).attachmentId, _oldAttachmentId);
  });

  testWidgets('DayPage removes new attachment when source changes', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 15);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_localImageNode('source-change-image', day)],
    );
    final attachments = _RecordingAttachmentRepository();
    final picker = _ControlledMediaPicker();
    await _pumpMediaReplacePage(
      tester,
      day: day,
      nodeId: 'source-change-image',
      repository: repository,
      attachments: attachments,
      picker: picker,
    );

    await tester.tap(find.byKey(const ValueKey('image-import-local')));
    await tester.pump();
    final latest = await repository.getNode('source-change-image');
    await repository.saveNode(
      latest!.copyWith(
        data: ImagePayload.fromNode(latest)
            .copyWith(
              url: 'https://example.com/concurrent.png',
              clearAttachment: true,
            )
            .toData(latest.data),
      ),
    );
    picker.complete(_validPickedPng);
    await _pumpAsyncReplace(tester);

    expect(
      attachments.deletedIds,
      contains(_RecordingAttachmentRepository.importedId),
    );
    final saved = await repository.getNode('source-change-image');
    expect(
      ImagePayload.fromNode(saved!).url,
      'https://example.com/concurrent.png',
    );
  });

  testWidgets('DayPage retains old attachment shared by node and thumbnail', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 15);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        _localImageNode('shared-image-first', day),
        _localImageNode('shared-image-second', day),
        MindmapNode.create(
          id: 'shared-video-thumbnail',
          type: NodeType.video,
          title: 'Shared thumbnail',
          day: day,
          data: const VideoPayload(
            url: 'https://example.com/video.mp4',
            thumbnailAttachmentId: _oldAttachmentId,
          ).toData(const {}),
        ),
      ],
    );
    final attachments = _RecordingAttachmentRepository();
    await _pumpMediaReplacePage(
      tester,
      day: day,
      nodeId: 'shared-image-first',
      repository: repository,
      attachments: attachments,
      picker: const _DayPageMediaPicker(_validPickedPng),
    );

    await tester.tap(find.byKey(const ValueKey('image-import-local')));
    await _pumpAsyncReplace(tester);

    expect(attachments.deletedIds, isNot(contains(_oldAttachmentId)));
    expect(
      ImagePayload.fromNode(
        (await repository.getNode('shared-image-second'))!,
      ).attachmentId,
      _oldAttachmentId,
    );
    expect(
      VideoPayload.fromNode(
        (await repository.getNode('shared-video-thumbnail'))!,
      ).thumbnailAttachmentId,
      _oldAttachmentId,
    );
  });

  testWidgets('DayPage direct NodeShell preset persists through canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 15);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'direct-shell-resize',
          type: NodeType.note,
          title: 'Direct resize',
          day: day,
          position: const CanvasPosition(20, 30),
          data: const {
            nodeUiCollapsedSectionsKey: ['details'],
            nodeUiEditorVersionKey: 4,
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: DayPage(date: day, highlightNodeId: 'direct-shell-resize'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ribbon-tab-node')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ribbon-clear-node-selection')));
    await tester.pumpAndSettle();
    final shell = tester.widget<NodeShell>(find.byType(NodeShell));

    shell.onResizeChanged!(
      const NodeResizeChange(
        size: Size(132, 96),
        positionDelta: Offset(12, -8),
        preset: NodeSizePreset.compact,
        phase: NodeResizePhase.commit,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final saved = await repository.getNode('direct-shell-resize');
    final uiState = NodeUiStateCodec.read(saved!);
    expect(uiState.sizePreset, NodeSizePreset.compact);
    expect(saved.position, const CanvasPosition(32, 22));
    expect(uiState.collapsedSections, contains('details'));
    expect(uiState.editorVersion, 4);
  });
}

const _oldAttachmentId = '223e4567-e89b-12d3-a456-426614174000';
const _validPickedPng = PickedMediaFile(
  fileName: 'picked.png',
  byteLength: 8,
  mimeType: 'image/png',
  bytes: [137, 80, 78, 71, 13, 10, 26, 10],
);

MindmapNode _localImageNode(String id, DateTime day) => MindmapNode.create(
  id: id,
  type: NodeType.image,
  title: 'Local image',
  day: day,
  position: const CanvasPosition(0, 0),
  data: const ImagePayload(
    attachmentId: _oldAttachmentId,
    mimeType: 'image/png',
    fileName: 'old.png',
    caption: 'Preserved caption',
  ).toData(const {}),
);

Future<void> _pumpMediaReplacePage(
  WidgetTester tester, {
  required DateTime day,
  required String nodeId,
  required MindmapRepository repository,
  required _RecordingAttachmentRepository attachments,
  required MediaFilePicker picker,
}) async {
  tester.view.physicalSize = const Size(1800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final importService = MediaFileImportService(
    repository: attachments,
    picker: picker,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mindmapRepositoryProvider.overrideWithValue(repository),
        nodeAttachmentRepositoryProvider.overrideWith((ref) async {
          return attachments;
        }),
        mediaFileImportServiceProvider.overrideWith((ref) async {
          return importService;
        }),
      ],
      child: MaterialApp(
        home: DayPage(date: day, highlightNodeId: nodeId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('ribbon-tab-node')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('ribbon-media-replace')));
  await tester.pumpAndSettle();
}

Future<void> _pumpAsyncReplace(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 500));
}

final class _DayPageMediaPicker implements MediaFilePicker {
  const _DayPageMediaPicker(this.file);

  final PickedMediaFile? file;

  @override
  Future<PickedMediaFile?> pick(MediaFileKind kind) async => file;
}

final class _ControlledMediaPicker implements MediaFilePicker {
  final Completer<PickedMediaFile?> _completer = Completer<PickedMediaFile?>();

  void complete(PickedMediaFile? file) => _completer.complete(file);

  @override
  Future<PickedMediaFile?> pick(MediaFileKind kind) => _completer.future;
}

final class _FailOnceMindmapRepository implements MindmapRepository {
  _FailOnceMindmapRepository({required Iterable<MindmapNode> seedNodes})
    : _delegate = InMemoryMindmapRepository(seedNodes: seedNodes);

  final InMemoryMindmapRepository _delegate;
  bool _shouldFail = false;

  void failNextSave() => _shouldFail = true;

  @override
  Future<void> deleteNode(String id) => _delegate.deleteNode(id);

  @override
  Future<MindmapNode?> getNode(String id) => _delegate.getNode(id);

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      _delegate.listNodes(day: day);

  @override
  Future<MindmapNode> saveNode(MindmapNode node) {
    if (_shouldFail) {
      _shouldFail = false;
      return Future<MindmapNode>.error(StateError('save failed'));
    }
    return _delegate.saveNode(node);
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      _delegate.searchNodes(query);
}

final class _RecordingAttachmentRepository implements NodeAttachmentRepository {
  static const importedId = '123e4567-e89b-12d3-a456-426614174000';

  int exportCalls = 0;
  int importCalls = 0;
  final List<String> deletedIds = [];
  final List<String> readIds = [];

  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() async => const [];

  @override
  Future<void> delete(String attachmentId) async {
    deletedIds.add(attachmentId);
  }

  @override
  Future<List<int>?> exportBytes(String attachmentId) async {
    exportCalls++;
    return const [137, 80, 78, 71];
  }

  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    importCalls += 1;
    return NodeAttachment(
      id: importedId,
      fileName: fileName,
      mimeType: mimeType,
      byteLength: bytes.length,
      checksum: 'a' * 64,
      createdAt: DateTime.utc(2026, 7, 15),
    );
  }

  @override
  Future<List<int>?> readBytes(String attachmentId) async {
    readIds.add(attachmentId);
    return const [137, 80, 78, 71];
  }

  @override
  Future<NodeAttachment?> resolve(String attachmentId) async => null;
}

MindmapNode _testNode(String id, DateTime day) => MindmapNode.create(
  id: id,
  type: NodeType.note,
  title: id,
  day: day,
  now: day,
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

final class _ControlledSaveMindmapRepository implements MindmapRepository {
  _ControlledSaveMindmapRepository({required Iterable<MindmapNode> seedNodes})
    : _delegate = InMemoryMindmapRepository(seedNodes: seedNodes);

  final InMemoryMindmapRepository _delegate;
  Completer<void>? _saveGate;
  int saveCount = 0;

  void holdNextSave() => _saveGate = Completer<void>();
  void completeSave() => _saveGate?.complete();

  @override
  Future<void> deleteNode(String id) => _delegate.deleteNode(id);

  @override
  Future<MindmapNode?> getNode(String id) => _delegate.getNode(id);

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      _delegate.listNodes(day: day);

  @override
  Future<MindmapNode> saveNode(MindmapNode node) async {
    saveCount++;
    final gate = _saveGate;
    if (gate != null) {
      await gate.future;
      _saveGate = null;
    }
    return _delegate.saveNode(node);
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      _delegate.searchNodes(query);
}

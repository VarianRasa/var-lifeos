import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/canvas_workshop.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('board reference renders and opens from semantics', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 2, 12);
    final reference = CanvasObject(
      id: 'nested-reference',
      type: CanvasObjectType.boardReference,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 280, height: 180),
      referencedBoardId: 'child-board',
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'parent-board',
      kind: CanvasBoardKind.project,
      title: 'Parent',
      workspaceName: 'Work',
      objects: <CanvasObject>[reference],
      createdAt: now,
      updatedAt: now,
    );
    CanvasObject? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              onBoardReferenceOpened: (object) => opened = object,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('canvas-object-nested-reference')),
      findsOneWidget,
    );
    final center = tester.getCenter(
      find.byKey(const ValueKey('canvas-object-nested-reference')),
    );
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 100));
    expect(opened, reference);
  });

  testWidgets('persisted board geometry overrides legacy node geometry', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'node-1',
      type: NodeType.task,
      title: 'Task',
      day: day,
      now: day,
    );
    final board =
        CanvasBoard.daily(
          day: day,
          nodes: <MindmapNode>[node],
          now: day,
        ).replaceObject(
          CanvasObject(
            id: 'node:${node.id}',
            type: CanvasObjectType.nodeReference,
            geometry: const CanvasGeometry(
              x: 120,
              y: 80,
              width: 420,
              height: 260,
            ),
            mindmapNodeId: node.id,
            createdAt: day,
            updatedAt: day,
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: MindmapCanvas(nodes: <MindmapNode>[node], board: board),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nodeFinder = find.byKey(const ValueKey('mindmap-node-node-1'));
    expect(tester.getSize(nodeFinder), const Size(420, 260));
    final canvasCenter = tester.getCenter(find.byType(MindmapCanvas));
    final nodeTopLeft = tester.getTopLeft(nodeFinder);
    expect(nodeTopLeft.dx, closeTo(canvasCenter.dx + 120, 1));
    expect(nodeTopLeft.dy, closeTo(canvasCenter.dy + 80, 1));
  });

  testWidgets('canvas toolbar exposes enabled undo and disabled redo', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'node-1',
      type: NodeType.task,
      title: 'Task',
      day: day,
      now: day,
    );
    var undoCount = 0;
    var redoCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            canUndo: true,
            onUndo: () => undoCount++,
            canRedo: false,
            onRedo: () => redoCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-undo')));
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-redo')));

    expect(undoCount, 1);
    expect(redoCount, 0);
  });

  testWidgets('Miro rail creates, edits, comments, and routes more tools', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 7, 28);
    var board = CanvasBoard.daily(
      day: day,
      nodes: const <MindmapNode>[],
      now: day,
    );
    Offset? productivityPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectCreated: (object) {
                setState(() {
                  board = board.copyWith(
                    objects: <CanvasObject>[...board.objects, object],
                  );
                });
              },
              onCanvasObjectUpdated: (object) {
                setState(() => board = board.replaceObject(object));
              },
              onProductivityNodeCreateRequested: (position) {
                productivityPosition = position;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mindmap-canvas-tool-rail')),
      findsOneWidget,
    );
    final selectSemantics = tester.getSemantics(
      find.bySemanticsLabel('Select').first,
    );
    expect(
      selectSemantics.flagsCollection.isSelected == ui.Tristate.isTrue,
      isTrue,
    );

    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-create-sticky')),
    );
    await tester.pump();
    final stickySemantics = tester.getSemantics(
      find.bySemanticsLabel('Sticky note').first,
    );
    expect(
      stickySemantics.flagsCollection.isSelected == ui.Tristate.isTrue,
      isTrue,
    );

    final canvasCenter = tester.getCenter(find.byType(MindmapCanvas));
    await tester.tapAt(canvasCenter + const Offset(-160, -80));
    await tester.pumpAndSettle();
    final sticky = board.objects.singleWhere(
      (object) => object.type == CanvasObjectType.stickyNote,
    );
    final editor = find.byKey(ValueKey('canvas-object-editor-${sticky.id}'));
    expect(editor, findsOneWidget);
    final primaryFocusContext = FocusManager.instance.primaryFocus?.context;
    expect(
      primaryFocusContext?.widget is EditableText ||
          primaryFocusContext?.findAncestorWidgetOfExactType<EditableText>() !=
              null,
      isTrue,
    );
    await tester.enterText(editor, 'Brainstorm\nnow');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(board.objectById(sticky.id)!.payload['text'], 'Brainstorm\nnow');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-tool-comment')));
    await tester.pump();
    expect(
      tester
              .getSemantics(find.bySemanticsLabel('Comment').first)
              .flagsCollection
              .isSelected ==
          ui.Tristate.isTrue,
      isTrue,
    );
    final stickyCenter =
        canvasCenter +
        Offset(
          sticky.geometry.x + sticky.geometry.width / 2,
          sticky.geometry.y + sticky.geometry.height / 2,
        );
    await tester.tapAt(stickyCenter);
    await tester.pumpAndSettle();
    expect(find.text('Object comments'), findsOneWidget);
    expect(board.objects, hasLength(1));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    final expectedViewport = tester
        .state<MindmapCanvasState>(find.byType(MindmapCanvas))
        .currentViewport;
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-create-productivity-node')),
    );
    await tester.pumpAndSettle();
    expect(productivityPosition, isNotNull);
    expect(productivityPosition!.dx, closeTo(expectedViewport.x, 1));
    expect(productivityPosition!.dy, closeTo(expectedViewport.y, 1));
  });

  testWidgets('column tool creates renders collapses and detaches children', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 8, 2);
    final child = CanvasObject(
      id: 'child',
      type: CanvasObjectType.stickyNote,
      geometry: const CanvasGeometry(x: -140, y: -40, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:columns',
      kind: CanvasBoardKind.project,
      title: 'Columns',
      objects: <CanvasObject>[child],
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    var detachedChildPersisted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              key: key,
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectCreated: (object) => setState(() {
                board = board.copyWith(
                  objects: <CanvasObject>[...board.objects, object],
                );
              }),
              onCanvasObjectsUpdated: (objects) => setState(() {
                for (final object in objects) {
                  board = board.replaceObject(object);
                  if (object.id == child.id && object.parentColumnId == null) {
                    detachedChildPersisted = true;
                  }
                }
              }),
              onCanvasObjectsDeleted: (objects) => setState(() {
                final ids = objects.map((object) => object.id).toSet();
                board = board.copyWith(
                  objects: board.objects
                      .where((object) => !ids.contains(object.id))
                      .toList(),
                );
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-create-column')),
    );
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(MindmapCanvas)));
    await tester.pumpAndSettle();

    final column = board.objects.singleWhere(
      (object) => object.type == CanvasObjectType.column,
    );
    expect(column.columnTitle, 'Column');
    expect(find.byKey(ValueKey('canvas-column-${column.id}')), findsOneWidget);
    expect(find.text('Column'), findsOneWidget);

    await key.currentState!.setColumnChildren(column.id, <String>[child.id]);
    await tester.pumpAndSettle();
    expect(board.objectById(child.id)!.parentColumnId, column.id);
    expect(
      board.objectById(child.id)!.geometry.width,
      column.geometry.width - 24,
    );

    await tester.tap(
      find.byKey(ValueKey('canvas-column-collapse-${column.id}')),
    );
    await tester.pumpAndSettle();
    expect(board.objectById(column.id)!.isColumnCollapsed, isTrue);
    expect(find.byKey(ValueKey('canvas-object-${child.id}')), findsNothing);

    key.currentState!.selectCanvasObject(column.id);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(board.objectById(column.id), isNull);
    expect(board.objectById(child.id), isNotNull);
    expect(detachedChildPersisted, isTrue);
  });

  testWidgets('collapsed column hides nodeReference and JSON exports board', (
    tester,
  ) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final now = DateTime(2026, 8, 2);
    final node = MindmapNode.create(
      id: 'column-node',
      type: NodeType.note,
      title: 'Column node',
      day: now,
      now: now,
    );
    final column = CanvasObject(
      id: 'collapsed-column',
      type: CanvasObjectType.column,
      geometry: const CanvasGeometry(x: -100, y: -160, width: 300, height: 48),
      payload: const <String, Object?>{
        'title': 'Collapsed',
        'isCollapsed': true,
        'orderedChildIds': <String>['node:column-node'],
      },
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:collapsed',
      kind: CanvasBoardKind.project,
      title: 'Collapsed',
      objects: <CanvasObject>[
        column,
        CanvasObject(
          id: 'node:column-node',
          type: CanvasObjectType.nodeReference,
          geometry: const CanvasGeometry(
            x: -88,
            y: -100,
            width: 276,
            height: 80,
          ),
          parentColumnId: column.id,
          mindmapNodeId: node.id,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: <MindmapNode>[node],
              board: board,
              onCanvasObjectsUpdated: (objects) => setState(() {
                for (final object in objects) {
                  board = board.replaceObject(object);
                }
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mindmap-node-column-node')),
      findsNothing,
    );
    await tester
        .state<MindmapCanvasState>(find.byType(MindmapCanvas))
        .runContextAction(CanvasContextAction.exportJson);
    final exported =
        jsonDecode((await Clipboard.getData(Clipboard.kTextPlain))!.text!)
            as Map<String, Object?>;
    expect((exported['board']! as Map)['id'], board.id);
    expect(((exported['board']! as Map)['objects']! as List), hasLength(2));
    await tester.tap(
      find.byKey(const ValueKey('canvas-column-collapse-collapsed-column')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mindmap-node-column-node')),
      findsOneWidget,
    );
  });

  testWidgets('failed column delete restores detached children', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 2);
    final column = CanvasObject(
      id: 'rollback-column',
      type: CanvasObjectType.column,
      geometry: const CanvasGeometry(x: -100, y: -100, width: 300, height: 300),
      payload: const <String, Object?>{
        'title': 'Rollback',
        'isCollapsed': false,
        'orderedChildIds': <String>['rollback-child'],
      },
      createdAt: now,
      updatedAt: now,
    );
    final child = CanvasObject(
      id: 'rollback-child',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -88, y: -40, width: 276, height: 80),
      parentColumnId: column.id,
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:rollback',
      kind: CanvasBoardKind.project,
      title: 'Rollback',
      objects: <CanvasObject>[column, child],
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectsUpdated: (objects) => setState(() {
                for (final object in objects) {
                  board = board.replaceObject(object);
                }
              }),
              onCanvasObjectsDeleted: (_) => throw StateError('delete failed'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<MindmapCanvasState>(find.byType(MindmapCanvas))
        .selectCanvasObject(column.id);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(board.objectById(child.id)!.parentColumnId, column.id);
  });

  testWidgets('column drag previews nodeReference child before pointer up', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 2);
    final node = MindmapNode.create(
      id: 'preview-node',
      type: NodeType.note,
      title: 'Preview',
      day: now,
      now: now,
    );
    final column = CanvasObject(
      id: 'preview-column',
      type: CanvasObjectType.column,
      geometry: const CanvasGeometry(x: -200, y: -180, width: 360, height: 500),
      payload: const <String, Object?>{
        'title': 'Preview',
        'isCollapsed': false,
        'orderedChildIds': <String>['node:preview-node'],
      },
      createdAt: now,
      updatedAt: now,
    );
    final reference = CanvasObject(
      id: 'node:preview-node',
      type: CanvasObjectType.nodeReference,
      geometry: const CanvasGeometry(x: -188, y: -120, width: 336, height: 120),
      parentColumnId: column.id,
      mindmapNodeId: node.id,
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:preview',
              kind: CanvasBoardKind.project,
              title: 'Preview',
              objects: <CanvasObject>[column, reference],
              createdAt: now,
              updatedAt: now,
            ),
            onCanvasObjectsUpdated: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final columnFinder = find.byKey(
      const ValueKey('canvas-column-preview-column'),
    );
    final nodeFinder = find.byKey(const ValueKey('mindmap-node-preview-node'));
    final columnBefore = tester.getTopLeft(columnFinder);
    final nodeBefore = tester.getTopLeft(nodeFinder);
    final start = columnBefore + const Offset(40, 20);
    final drag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(50, 30));
    await tester.pump();
    expect(
      tester.getTopLeft(columnFinder) - columnBefore,
      const Offset(50, 30),
    );
    expect(tester.getTopLeft(nodeFinder) - nodeBefore, const Offset(50, 30));
    await drag.up();
  });

  testWidgets('column paints before child regardless persisted zIndex', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 2);
    final child = CanvasObject(
      id: 'paint-child',
      type: CanvasObjectType.stickyNote,
      geometry: const CanvasGeometry(x: -88, y: -100, width: 276, height: 100),
      zIndex: 1,
      parentColumnId: 'paint-column',
      createdAt: now,
      updatedAt: now,
    );
    final column = CanvasObject(
      id: 'paint-column',
      type: CanvasObjectType.column,
      geometry: const CanvasGeometry(x: -100, y: -160, width: 300, height: 400),
      zIndex: 99,
      payload: const <String, Object?>{
        'title': 'Paint',
        'isCollapsed': false,
        'orderedChildIds': <String>['paint-child'],
      },
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: const <MindmapNode>[],
            board: CanvasBoard(
              id: 'project:paint',
              kind: CanvasBoardKind.project,
              title: 'Paint',
              objects: <CanvasObject>[child, column],
              createdAt: now,
              updatedAt: now,
            ),
            onCanvasObjectsUpdated: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pointer = TestPointer(91, PointerDeviceKind.mouse);
    final center = tester.getCenter(
      find.byKey(const ValueKey('canvas-object-paint-child')),
    );
    await tester.sendEventToBinding(pointer.down(center));
    await tester.pump();
    await tester.sendEventToBinding(pointer.up());
    await tester.pumpAndSettle();
    expect(key.currentState!.selectedCanvasObjectIds, contains(child.id));
    expect(
      find.byKey(const ValueKey('canvas-object-resize-paint-child')),
      findsOneWidget,
    );
  });

  testWidgets('node drag persists column membership and survives collapse', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 8, 2);
    var nodes = <MindmapNode>[
      MindmapNode.create(
        id: 'drag-node',
        type: NodeType.note,
        title: 'Drag node',
        day: now,
        position: const CanvasPosition(-360, -80),
        now: now,
      ),
    ];
    final column = CanvasObject(
      id: 'node-column',
      type: CanvasObjectType.column,
      geometry: const CanvasGeometry(x: 100, y: -180, width: 360, height: 500),
      payload: const <String, Object?>{
        'title': 'Nodes',
        'isCollapsed': false,
        'orderedChildIds': <String>[],
      },
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:node-column',
      kind: CanvasBoardKind.project,
      title: 'Nodes',
      objects: <CanvasObject>[
        column,
        CanvasObject(
          id: 'node:drag-node',
          type: CanvasObjectType.nodeReference,
          geometry: const CanvasGeometry(
            x: -360,
            y: -80,
            width: 340,
            height: 320,
          ),
          mindmapNodeId: 'drag-node',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    var batchCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: nodes,
              board: board,
              onNodeMoved: (node, position) => setState(() {
                nodes = <MindmapNode>[node.copyWith(position: position)];
              }),
              onCanvasObjectsUpdated: (objects) => setState(() {
                batchCalls++;
                for (final object in objects) {
                  board = board.replaceObject(object);
                }
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final start = tester.getCenter(
      find.byKey(const ValueKey('mindmap-node-drag-node')),
    );
    final target = tester.getCenter(
      find.byKey(const ValueKey('canvas-column-node-column')),
    );
    final drag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy((target - start) / 2);
    await tester.pump();
    await drag.moveTo(target);
    await drag.up();
    await tester.pumpAndSettle();
    expect(batchCalls, greaterThan(0));
    expect(board.objectById('node:drag-node')!.parentColumnId, column.id);
    expect(board.objectById(column.id)!.orderedColumnChildIds, <String>[
      'node:drag-node',
    ]);
    expect(
      board.objectById('node:drag-node')!.geometry.width,
      column.geometry.width - 24,
    );
    expect(
      find.byKey(const ValueKey('mindmap-node-drag-node')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('canvas-column-collapse-node-column')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mindmap-node-drag-node')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('canvas-column-collapse-node-column')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mindmap-node-drag-node')),
      findsOneWidget,
    );
  });

  testWidgets('native pending persistence keeps child rendered in column', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 2);
    final gate = Completer<void>();
    final column = CanvasObject(
      id: 'async-column',
      type: CanvasObjectType.column,
      geometry: const CanvasGeometry(x: 80, y: -180, width: 320, height: 500),
      payload: const <String, Object?>{
        'title': 'Async',
        'isCollapsed': false,
        'orderedChildIds': <String>[],
      },
      createdAt: now,
      updatedAt: now,
    );
    final sticky = CanvasObject(
      id: 'async-sticky',
      type: CanvasObjectType.stickyNote,
      geometry: const CanvasGeometry(x: -360, y: -80, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:async-column',
      kind: CanvasBoardKind.project,
      title: 'Async',
      objects: <CanvasObject>[column, sticky],
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectsUpdated: (objects) async {
                await gate.future;
                setState(() {
                  for (final object in objects) {
                    board = board.replaceObject(object);
                  }
                });
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final start =
        tester.getTopLeft(
          find.byKey(const ValueKey('canvas-object-async-sticky')),
        ) +
        const Offset(8, 8);
    final target = tester.getCenter(
      find.byKey(const ValueKey('canvas-column-async-column')),
    );
    final drag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy((target - start) / 2);
    await tester.pump();
    await drag.moveTo(target);
    await drag.up();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('canvas-object-async-sticky')),
      findsOneWidget,
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(board.objectById(sticky.id)!.parentColumnId, column.id);
    expect(
      find.byKey(const ValueKey('canvas-object-async-sticky')),
      findsOneWidget,
    );
  });

  testWidgets(
    'desktop drag enters reorders exits and rejects column children',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 8, 2);
      CanvasObject object(
        String id,
        CanvasObjectType type,
        CanvasGeometry geometry, {
        bool locked = false,
        String? parentColumnId,
        Map<String, Object?> payload = const <String, Object?>{},
      }) => CanvasObject(
        id: id,
        type: type,
        geometry: geometry,
        isLocked: locked,
        parentColumnId: parentColumnId,
        payload: payload,
        createdAt: now,
        updatedAt: now,
      );
      final column = object(
        'column',
        CanvasObjectType.column,
        const CanvasGeometry(x: 100, y: -200, width: 320, height: 500),
        payload: const <String, Object?>{
          'title': 'Doing',
          'isCollapsed': false,
          'orderedChildIds': <String>['first', 'second'],
        },
      );
      var board = CanvasBoard(
        id: 'project:drag-column',
        kind: CanvasBoardKind.project,
        title: 'Drag column',
        objects: <CanvasObject>[
          column,
          object(
            'first',
            CanvasObjectType.stickyNote,
            const CanvasGeometry(x: 112, y: -140, width: 296, height: 60),
            parentColumnId: column.id,
          ),
          object(
            'second',
            CanvasObjectType.shape,
            const CanvasGeometry(x: 112, y: -72, width: 296, height: 60),
            parentColumnId: column.id,
          ),
          object(
            'eligible',
            CanvasObjectType.stickyNote,
            const CanvasGeometry(x: -360, y: -100, width: 120, height: 70),
          ),
          object(
            'locked',
            CanvasObjectType.stickyNote,
            const CanvasGeometry(x: -360, y: 20, width: 120, height: 70),
            locked: true,
          ),
          object(
            'connector',
            CanvasObjectType.connector,
            const CanvasGeometry(x: -360, y: 120, width: 120, height: 40),
          ),
          object(
            'frame',
            CanvasObjectType.frame,
            const CanvasGeometry(x: -520, y: 180, width: 120, height: 80),
          ),
          object(
            'other-column',
            CanvasObjectType.column,
            const CanvasGeometry(x: -360, y: 280, width: 140, height: 80),
            payload: const <String, Object?>{
              'title': 'Other',
              'isCollapsed': false,
              'orderedChildIds': <String>[],
            },
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MindmapCanvas(
                nodes: const <MindmapNode>[],
                board: board,
                onCanvasObjectsUpdated: (objects) => setState(() {
                  for (final object in objects) {
                    board = board.replaceObject(object);
                  }
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final columnCenter = tester.getCenter(
        find.byKey(const ValueKey('canvas-column-column')),
      );

      final eligibleCenter =
          tester.getTopLeft(
            find.byKey(const ValueKey('canvas-object-eligible')),
          ) +
          const Offset(8, 8);
      final enter = await tester.startGesture(eligibleCenter);
      await enter.moveBy((columnCenter - eligibleCenter) / 2);
      await tester.pump();
      await enter.moveTo(columnCenter);
      await tester.pump();
      await enter.up();
      await tester.pumpAndSettle();
      expect(board.objectById('eligible')!.geometry.x, greaterThan(-100));
      expect(board.objectById('eligible')!.parentColumnId, column.id);
      expect(column.orderedColumnChildIds, isNot(contains('eligible')));
      expect(
        board.objectById(column.id)!.orderedColumnChildIds,
        contains('eligible'),
      );

      final secondCenter =
          tester.getTopLeft(
            find.byKey(const ValueKey('canvas-object-second')),
          ) +
          const Offset(8, 8);
      final reorder = await tester.startGesture(secondCenter);
      await reorder.moveBy(const Offset(0, -50));
      await tester.pump();
      await reorder.moveBy(const Offset(0, -70));
      await reorder.up();
      await tester.pumpAndSettle();
      expect(
        board.objectById(column.id)!.orderedColumnChildIds.first,
        'second',
      );
      expect(
        find.byKey(const ValueKey('canvas-column-insertion-indicator')),
        findsNothing,
      );

      final exitStart =
          tester.getTopLeft(
            find.byKey(const ValueKey('canvas-object-second')),
          ) +
          const Offset(8, 8);
      final exit = await tester.startGesture(exitStart);
      await exit.moveBy(const Offset(-250, 0));
      await tester.pump();
      await exit.moveBy(const Offset(-250, 0));
      await exit.up();
      await tester.pumpAndSettle();
      expect(board.objectById('second')!.parentColumnId, isNull);
      expect(board.objectById('second')!.geometry.x, lessThan(-100));

      for (final id in <String>[
        'locked',
        'connector',
        'frame',
        'other-column',
      ]) {
        final finder = id == 'other-column'
            ? find.byKey(const ValueKey('canvas-column-other-column'))
            : find.byKey(ValueKey('canvas-object-$id'));
        if (finder.evaluate().isEmpty) continue;
        final start = tester.getCenter(finder);
        await tester.dragFrom(start, columnCenter - start);
        await tester.pumpAndSettle();
        expect(board.objectById(id)!.parentColumnId, isNull, reason: id);
      }
    },
  );

  testWidgets(
    'column touch requires long press and locked column never moves',
    (tester) async {
      final now = DateTime(2026, 8, 2);
      CanvasObject makeColumn(String id, double x, {bool locked = false}) =>
          CanvasObject(
            id: id,
            type: CanvasObjectType.column,
            geometry: CanvasGeometry(x: x, y: -120, width: 240, height: 260),
            isLocked: locked,
            payload: const <String, Object?>{
              'title': 'Column',
              'isCollapsed': false,
              'orderedChildIds': <String>[],
            },
            createdAt: now,
            updatedAt: now,
          );
      var board = CanvasBoard(
        id: 'project:column-gestures',
        kind: CanvasBoardKind.project,
        title: 'Gestures',
        objects: <CanvasObject>[
          makeColumn('touch-column', -280),
          makeColumn('locked-column', 80, locked: true),
        ],
        createdAt: now,
        updatedAt: now,
      );
      var updateCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MindmapCanvas(
                nodes: const <MindmapNode>[],
                board: board,
                onCanvasObjectsUpdated: (objects) => setState(() {
                  updateCount++;
                  for (final object in objects) {
                    board = board.replaceObject(object);
                  }
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final touchStart =
          tester.getTopLeft(
            find.byKey(const ValueKey('canvas-column-touch-column')),
          ) +
          const Offset(30, 20);
      final originalX = board.objectById('touch-column')!.geometry.x;
      final shortTouch = await tester.startGesture(
        touchStart,
        kind: PointerDeviceKind.touch,
      );
      await shortTouch.moveBy(const Offset(60, 0));
      await shortTouch.up();
      await tester.pumpAndSettle();
      expect(board.objectById('touch-column')!.geometry.x, originalX);
      final longTouch = await tester.startGesture(
        touchStart,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      await longTouch.moveBy(const Offset(60, 0));
      await longTouch.up();
      await tester.pumpAndSettle();
      expect(
        board.objectById('touch-column')!.geometry.x,
        greaterThan(originalX),
      );
      final beforeLocked = updateCount;
      final lockedStart =
          tester.getTopLeft(
            find.byKey(const ValueKey('canvas-column-locked-column')),
          ) +
          const Offset(30, 20);
      await tester.dragFrom(lockedStart, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(updateCount, beforeLocked);
      expect(board.objectById('locked-column')!.geometry.x, 80);
    },
  );

  testWidgets('moving and resizing column reflows child geometry', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 2);
    final column = CanvasObject(
      id: 'layout-column',
      type: CanvasObjectType.column,
      geometry: const CanvasGeometry(x: -100, y: -160, width: 300, height: 300),
      payload: const <String, Object?>{
        'title': 'Layout',
        'isCollapsed': false,
        'orderedChildIds': <String>['layout-child'],
      },
      createdAt: now,
      updatedAt: now,
    );
    final child = CanvasObject(
      id: 'layout-child',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -88, y: -100, width: 276, height: 80),
      parentColumnId: column.id,
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:column-layout',
      kind: CanvasBoardKind.project,
      title: 'Layout',
      objects: <CanvasObject>[column, child],
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              key: key,
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectsUpdated: (objects) => setState(() {
                for (final object in objects) {
                  board = board.replaceObject(object);
                }
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final originalChild = child.geometry;
    final header =
        tester.getTopLeft(
          find.byKey(const ValueKey('canvas-column-layout-column')),
        ) +
        const Offset(40, 20);
    final move = await tester.startGesture(
      header,
      kind: PointerDeviceKind.mouse,
    );
    await move.moveBy(const Offset(20, 10));
    await tester.pump();
    await move.moveBy(const Offset(20, 10));
    await move.up();
    await tester.pumpAndSettle();
    expect(
      board.objectById(child.id)!.geometry.x,
      greaterThan(originalChild.x),
    );
    expect(
      board.objectById(child.id)!.geometry.y,
      greaterThan(originalChild.y),
    );

    key.currentState!.selectCanvasObject(column.id);
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('canvas-column-resize-layout-column')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    expect(
      board.objectById(child.id)!.geometry.width,
      board.objectById(column.id)!.geometry.width - 24,
    );
  });

  testWidgets('column resize clamps width and normalizes locked child', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 2);
    final column = CanvasObject(
      id: 'minimum-column',
      type: CanvasObjectType.column,
      geometry: const CanvasGeometry(x: -100, y: -160, width: 300, height: 300),
      payload: const <String, Object?>{
        'title': 'Minimum',
        'isCollapsed': false,
        'orderedChildIds': <String>['locked-column-child'],
      },
      createdAt: now,
      updatedAt: now,
    );
    final child = CanvasObject(
      id: 'locked-column-child',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -88, y: -100, width: 276, height: 80),
      parentColumnId: column.id,
      isLocked: true,
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:minimum-column',
      kind: CanvasBoardKind.project,
      title: 'Minimum column',
      objects: <CanvasObject>[column, child],
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              key: key,
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectsUpdated: (objects) => setState(() {
                for (final object in objects) {
                  board = board.replaceObject(object);
                }
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.selectCanvasObject(column.id);
    await tester.pump();
    final resize = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('canvas-column-resize-minimum-column')),
      ),
    );
    await resize.moveBy(const Offset(30, 0));
    await tester.pump();
    for (var index = 0; index < 13; index++) {
      await resize.moveBy(const Offset(-10, 0));
    }
    await resize.up();
    await tester.pumpAndSettle();

    final resizedColumn = board.objectById(column.id)!;
    final resizedChild = board.objectById(child.id)!;
    expect(resizedColumn.geometry.width, 240);
    expect(resizedChild.geometry.width, 216);
    expect(
      resizedChild.geometry.x + resizedChild.geometry.width,
      resizedColumn.geometry.x + resizedColumn.geometry.width - 12,
    );
  });

  testWidgets(
    'mobile long press enters column and empty pan still moves viewport',
    (tester) async {
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 8, 2);
      final column = CanvasObject(
        id: 'mobile-column',
        type: CanvasObjectType.column,
        geometry: const CanvasGeometry(
          x: 100,
          y: -160,
          width: 280,
          height: 420,
        ),
        payload: const <String, Object?>{
          'title': 'Mobile',
          'isCollapsed': false,
          'orderedChildIds': <String>[],
        },
        createdAt: now,
        updatedAt: now,
      );
      final card = CanvasObject(
        id: 'mobile-card',
        type: CanvasObjectType.stickyNote,
        geometry: const CanvasGeometry(x: -300, y: -80, width: 120, height: 80),
        createdAt: now,
        updatedAt: now,
      );
      var board = CanvasBoard(
        id: 'project:mobile-column',
        kind: CanvasBoardKind.project,
        title: 'Mobile',
        objects: <CanvasObject>[column, card],
        createdAt: now,
        updatedAt: now,
      );
      final key = GlobalKey<MindmapCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MindmapCanvas(
                key: key,
                nodes: const <MindmapNode>[],
                board: board,
                onCanvasObjectsUpdated: (objects) => setState(() {
                  for (final object in objects) {
                    board = board.replaceObject(object);
                  }
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final start = tester.getCenter(
        find.byKey(const ValueKey('canvas-object-mobile-card')),
      );
      final target = tester.getCenter(
        find.byKey(const ValueKey('canvas-column-mobile-column')),
      );
      final touch = await tester.startGesture(
        start,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      await touch.moveTo(target);
      await touch.up();
      await tester.pumpAndSettle();
      expect(board.objectById(card.id)!.parentColumnId, column.id);

      final before = key.currentState!.currentViewport;
      final pan = await tester.startGesture(
        const Offset(40, 600),
        kind: PointerDeviceKind.touch,
      );
      await pan.moveBy(const Offset(80, 0));
      await pan.up();
      await tester.pumpAndSettle();
      expect(key.currentState!.currentViewport, isNot(before));
    },
  );

  testWidgets('native objects support create edit style and lock', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'node-1',
      type: NodeType.task,
      title: 'Task',
      day: day,
      now: day,
    );
    var board = CanvasBoard.daily(
      day: day,
      nodes: <MindmapNode>[node],
      now: day,
    );
    CanvasObject? editedObject;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: <MindmapNode>[node],
              board: board,
              onCanvasObjectCreated: (object) {
                setState(() {
                  board = board.copyWith(
                    objects: <CanvasObject>[...board.objects, object],
                  );
                });
              },
              onCanvasObjectUpdated: (object) {
                if (object.payload['text'] == 'Edited sticky') {
                  editedObject = object;
                }
                setState(() => board = board.replaceObject(object));
              },
              onCanvasImageImport: () => const CanvasImageSource(
                attachmentId: 'attachment-image-1',
                fileName: 'board.png',
                mimeType: 'image/png',
                byteLength: 128,
              ),
              loadCanvasAttachmentBytes: (attachmentId) async => null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-create-sticky')),
    );
    await tester.pump();
    final canvasCenter = tester.getCenter(find.byType(MindmapCanvas));
    await tester.tapAt(canvasCenter + const Offset(-250, -180));
    await tester.pumpAndSettle();

    final sticky = board.objects.firstWhere(
      (object) => object.type == CanvasObjectType.stickyNote,
    );
    final stickyFinder = find.byKey(ValueKey('canvas-object-${sticky.id}'));
    expect(stickyFinder, findsOneWidget);

    final stickyCenter =
        canvasCenter +
        Offset(
          sticky.geometry.x + sticky.geometry.width / 2,
          sticky.geometry.y + sticky.geometry.height / 2,
        );
    await tester.tapAt(stickyCenter);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(stickyCenter);
    await tester.pumpAndSettle();
    final editor = find.byKey(ValueKey('canvas-object-editor-${sticky.id}'));
    expect(editor, findsOneWidget);
    await tester.enterText(editor, 'Edited sticky');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(editedObject?.payload['text'], 'Edited sticky');
    expect(find.text('Edited sticky'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-shape')));
    await tester.pumpAndSettle();
    await tester.tapAt(canvasCenter + const Offset(80, -120));
    await tester.pumpAndSettle();
    final shape = board.objects.firstWhere(
      (object) => object.type == CanvasObjectType.shape,
    );
    final shapeFinder = find.byKey(ValueKey('canvas-object-${shape.id}'));
    expect(shapeFinder, findsOneWidget);

    final canvasState = tester.state<MindmapCanvasState>(
      find.byType(MindmapCanvas),
    );
    canvasState.selectCanvasObject(shape.id);
    await tester.pump();
    expect(canvasState.selectedCanvasObjectIds, contains(shape.id));
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-object-color')));
    await tester.pumpAndSettle();
    expect(board.objectById(shape.id)!.payload['color'], 'green');

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-shape-style')));
    await tester.pumpAndSettle();
    expect(board.objectById(shape.id)!.payload['shape'], 'rectangle');

    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-properties')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('canvas-property-fill-color')),
      '#123456',
    );
    await tester.enterText(
      find.byKey(const ValueKey('canvas-property-border-color')),
      '#654321',
    );
    await tester.drag(
      find.byKey(const ValueKey('canvas-property-border-width')),
      const Offset(80, 0),
    );
    await tester.drag(
      find.byKey(const ValueKey('canvas-property-opacity')),
      const Offset(-80, 0),
    );
    await tester.tap(find.byKey(const ValueKey('canvas-property-apply')));
    await tester.pumpAndSettle();
    final styledShape = board.objectById(shape.id)!;
    expect(styledShape.payload['fillColor'], '#123456');
    expect(styledShape.payload['borderColor'], '#654321');
    expect(styledShape.payload['borderWidth'], greaterThan(1));
    expect(styledShape.payload['opacity'], lessThan(1));

    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-actions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-object-lock')));
    await tester.pumpAndSettle();
    expect(board.objectById(shape.id)!.isLocked, isTrue);
    expect(
      find.byKey(ValueKey('canvas-object-resize-${shape.id}')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-actions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-object-lock')));
    await tester.pumpAndSettle();
    expect(board.objectById(shape.id)!.isLocked, isFalse);
  });

  testWidgets('creates connector freehand frame image and link objects', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 28);
    var board = CanvasBoard.daily(
      day: day,
      nodes: const <MindmapNode>[],
      now: day,
    );
    CanvasObject? deletedObject;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectCreated: (object) {
                setState(() {
                  board = board.copyWith(
                    objects: <CanvasObject>[...board.objects, object],
                  );
                });
              },
              onCanvasObjectUpdated: (object) {
                setState(() => board = board.replaceObject(object));
              },
              onCanvasObjectDeleted: (object) {
                deletedObject = object;
                setState(() {
                  board = board.copyWith(
                    objects: board.objects
                        .where((candidate) => candidate.id != object.id)
                        .toList(),
                  );
                });
              },
              onCanvasImageImport: () => const CanvasImageSource(
                attachmentId: 'attachment-image-1',
                fileName: 'board.png',
                mimeType: 'image/png',
                byteLength: 128,
              ),
              loadCanvasAttachmentBytes: (attachmentId) async => null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pumpAndSettle();
    final canvasCenter = tester.getCenter(find.byType(MindmapCanvas));

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-create-connector')),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(canvasCenter + const Offset(-120, 220));
    await tester.pump();
    expect(
      board.objects.where(
        (object) => object.type == CanvasObjectType.connector,
      ),
      isEmpty,
    );
    final sceneListener = find.byKey(const ValueKey('mindmap-scene-listener'));
    final sceneTopLeft = tester.getTopLeft(sceneListener);
    final endLocal = canvasCenter + const Offset(160, 220) - sceneTopLeft;
    final hover = TestPointer(42, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(hover.hover(sceneTopLeft + endLocal));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mindmap-canvas-tool-draft')),
      findsOneWidget,
    );
    await tester.tapAt(canvasCenter + const Offset(160, 220));
    await tester.pumpAndSettle();
    final connector = board.objects.firstWhere(
      (object) => object.type == CanvasObjectType.connector,
    );
    expect(
      find.byKey(ValueKey('canvas-connector-paint-${connector.id}')),
      findsOneWidget,
    );
    expect(connector.payload['arrowEnd'], isTrue);
    expect(connector.geometry.width, greaterThan(180));

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-create-freehand')),
    );
    await tester.pumpAndSettle();
    final strokeStart = canvasCenter + const Offset(-300, 20);
    final strokeGesture = await tester.startGesture(strokeStart);
    await strokeGesture.moveBy(const Offset(35, -12));
    await tester.pump();
    final liveDraft = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('mindmap-canvas-tool-draft')),
    );
    final livePicture = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      liveDraft.painter!.paint(canvas, const Size(20000, 14000));
      return recorder.endRecording();
    });
    expect(livePicture, isNotNull);
    expect(
      board.objects.where((object) => object.type == CanvasObjectType.freehand),
      isEmpty,
    );
    await strokeGesture.moveBy(const Offset(40, 20));
    await strokeGesture.up();
    await tester.pumpAndSettle();
    final freehand = board.objects.firstWhere(
      (object) => object.type == CanvasObjectType.freehand,
    );
    expect(
      find.byKey(ValueKey('canvas-freehand-paint-${freehand.id}')),
      findsOneWidget,
    );
    expect(freehand.payload['points'], isA<List<Object?>>());

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-eraser')));
    await tester.pump();
    await tester.tapAt(strokeStart + const Offset(35, 0));
    await tester.pumpAndSettle();
    expect(board.objectById(freehand.id), isNull);
    expect(deletedObject?.id, freehand.id);

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-frame')));
    await tester.pumpAndSettle();
    final frameCenter = canvasCenter + const Offset(160, 20);
    await tester.tapAt(frameCenter);
    await tester.pumpAndSettle();
    final frame = board.objects.firstWhere(
      (object) => object.type == CanvasObjectType.frame,
    );
    final frameFinder = find.byKey(ValueKey('canvas-object-${frame.id}'));
    expect(frameFinder, findsOneWidget);

    final frameHeader = tester.getTopLeft(frameFinder) + const Offset(40, 30);
    await tester.tapAt(frameHeader);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(frameHeader);
    await tester.pumpAndSettle();
    final frameEditor = find.byKey(
      ValueKey('canvas-object-editor-${frame.id}'),
    );
    expect(frameEditor, findsOneWidget);
    await tester.enterText(frameEditor, 'Project section');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(board.objectById(frame.id)!.payload['text'], 'Project section');

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-shape')));
    await tester.pumpAndSettle();
    await tester.tapAt(frameCenter);
    await tester.pumpAndSettle();
    final framedShape = board.objects.lastWhere(
      (object) => object.type == CanvasObjectType.shape,
    );
    expect(framedShape.parentFrameId, frame.id);

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-image')));
    await tester.pumpAndSettle();
    await tester.tapAt(canvasCenter + const Offset(-300, -210));
    await tester.pumpAndSettle();
    final imageObject = board.objects.firstWhere(
      (object) => object.type == CanvasObjectType.image,
    );
    expect(imageObject.payload['attachmentId'], 'attachment-image-1');
    expect(imageObject.payload['fileName'], 'board.png');
    expect(find.text('board.png'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-create-link-preview')),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(canvasCenter + const Offset(220, 160));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('canvas-link-url')),
      'https://example.com/project',
    );
    await tester.tap(find.byKey(const ValueKey('canvas-link-add')));
    await tester.pumpAndSettle();
    final linkObject = board.objects.firstWhere(
      (object) => object.type == CanvasObjectType.linkPreview,
    );
    expect(linkObject.payload['url'], 'https://example.com/project');
    expect(linkObject.payload['title'], 'example.com');
    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('moving a frame moves contained native objects', (tester) async {
    final day = DateTime(2026, 7, 28);
    final now = day;
    final frame = CanvasObject(
      id: 'frame-1',
      type: CanvasObjectType.frame,
      geometry: const CanvasGeometry(x: -260, y: -170, width: 520, height: 340),
      payload: const <String, Object?>{'text': 'Section'},
      createdAt: now,
      updatedAt: now,
    );
    final child = CanvasObject(
      id: 'shape-1',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -80, y: -50, width: 160, height: 100),
      parentFrameId: frame.id,
      payload: const <String, Object?>{'shape': 'roundedRectangle'},
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:test',
      kind: CanvasBoardKind.project,
      title: 'Test',
      objects: <CanvasObject>[frame, child],
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectUpdated: (object) {
                setState(() => board = board.replaceObject(object));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final frameX = frame.geometry.x;
    final childX = child.geometry.x;
    final canvasCenter = tester.getCenter(find.byType(MindmapCanvas));
    final frameDrag = await tester.startGesture(
      canvasCenter +
          Offset(
            frame.geometry.x + frame.geometry.width / 2,
            frame.geometry.y + 24,
          ),
    );
    await frameDrag.moveBy(const Offset(45, 0));
    await frameDrag.up();
    await tester.pumpAndSettle();
    expect(board.objectById(frame.id)!.geometry.x, greaterThan(frameX));
    expect(board.objectById(child.id)!.geometry.x, greaterThan(childX));
  });

  testWidgets(
    'mixed frame coordinator creates bounds and persistent membership',
    (tester) async {
      final now = DateTime(2026, 7, 28);
      var nodes = <MindmapNode>[
        MindmapNode.create(
          id: 'mixed-node',
          type: NodeType.note,
          title: 'Node',
          day: now,
          position: const CanvasPosition(-220, -100),
          now: now,
        ),
      ];
      final shape = CanvasObject(
        id: 'mixed-shape',
        type: CanvasObjectType.shape,
        geometry: const CanvasGeometry(x: 180, y: 120, width: 100, height: 80),
        createdAt: now,
        updatedAt: now,
      );
      var board = CanvasBoard(
        id: 'project:mixed-frame',
        kind: CanvasBoardKind.project,
        title: 'Mixed frame',
        objects: <CanvasObject>[shape],
        createdAt: now,
        updatedAt: now,
      );
      final key = GlobalKey<MindmapCanvasState>();
      var nodeDeleteCount = 0;
      var nodeMembershipClearCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MindmapCanvas(
                key: key,
                nodes: nodes,
                board: board,
                onNodeUpdated: (updated) => setState(() {
                  if (nodes.single.data['groupId'] != null &&
                      updated.data['groupId'] == null) {
                    nodeMembershipClearCount++;
                  }
                  nodes = <MindmapNode>[updated];
                }),
                onNodesDeleted: (deleted) {
                  nodeDeleteCount += deleted.length;
                },
                onNodeMoved: (node, position) => setState(() {
                  nodes = <MindmapNode>[node.copyWith(position: position)];
                }),
                onCanvasObjectCreated: (object) => setState(() {
                  board = board.copyWith(
                    objects: <CanvasObject>[...board.objects, object],
                  );
                }),
                onCanvasObjectUpdated: (object) =>
                    setState(() => board = board.replaceObject(object)),
                onCanvasObjectDeleted: (object) => setState(() {
                  board = board.copyWith(
                    objects: board.objects
                        .where((value) => value.id != object.id)
                        .toList(),
                  );
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mindmap-node-mixed-node')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      key.currentState!.selectCanvasObject(shape.id);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await key.currentState!.groupSelectedEntities();
      await tester.pumpAndSettle();

      final frame = board.objects.singleWhere(
        (object) => object.type == CanvasObjectType.frame,
      );
      expect(
        frame.geometry,
        const CanvasGeometry(x: -248, y: -128, width: 556, height: 376),
      );
      expect(board.objectById(shape.id)!.parentFrameId, frame.id);
      expect(nodes.single.data['groupId'], frame.id);

      final originalFrameGeometry = frame.geometry;
      final originalNodePosition = nodes.single.position;
      final originalShapeGeometry = board.objectById(shape.id)!.geometry;
      final canvasCenter = tester.getCenter(find.byType(MindmapCanvas));
      final gesture = await tester.startGesture(
        canvasCenter +
            Offset(
              frame.geometry.x + frame.geometry.width / 2,
              frame.geometry.y + 24,
            ),
      );
      await gesture.moveBy(const Offset(40, 20));
      await gesture.up();
      await tester.pumpAndSettle();
      final movedFrame = board.objectById(frame.id)!.geometry;
      final movedShape = board.objectById(shape.id)!.geometry;
      final frameDx = movedFrame.x - originalFrameGeometry.x;
      final frameDy = movedFrame.y - originalFrameGeometry.y;
      expect(nodes.single.position.dx - originalNodePosition.dx, frameDx);
      expect(nodes.single.position.dy - originalNodePosition.dy, frameDy);
      expect(movedShape.x - originalShapeGeometry.x, frameDx);
      expect(movedShape.y - originalShapeGeometry.y, frameDy);

      final nodeBeforeUngroup = nodes.single.position;
      final shapeBeforeUngroup = movedShape;
      await key.currentState!.ungroupFrame(frame.id);
      await tester.pumpAndSettle();
      expect(nodes.single.data['groupId'], isNull);
      expect(board.objectById(shape.id)!.parentFrameId, isNull);
      expect(nodes.single.position, nodeBeforeUngroup);
      expect(board.objectById(shape.id)!.geometry, shapeBeforeUngroup);
      expect(board.objectById(frame.id), isNotNull);

      await key.currentState!.groupEntitiesInFrame(
        frame.id,
        nodeIds: <String>{nodes.single.id},
        objectIds: <String>{shape.id},
      );
      await tester.pump();
      nodeMembershipClearCount = 0;
      key.currentState!.selectCanvasObject(frame.id);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      key.currentState!.selectCanvasObject(shape.id);
      await key.currentState!.selectAndFocusNode(nodes.single);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.text('1 node + 2 objects selected'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.text('Delete selected node?'), findsNothing);
      expect(nodeDeleteCount, 0);
      expect(nodeMembershipClearCount, 1);
      expect(nodes.single.id, 'mixed-node');
      expect(board.objectById(frame.id), isNull);
      expect(board.objectById(shape.id), isNotNull);
      expect(board.objectById(shape.id)!.parentFrameId, isNull);
      expect(nodes.single.data['groupId'], isNull);
    },
  );

  testWidgets('locked mixed frame member stays attached and is not lost', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final frame = CanvasObject(
      id: 'locked-frame',
      type: CanvasObjectType.frame,
      geometry: const CanvasGeometry(x: -260, y: -180, width: 520, height: 360),
      createdAt: now,
      updatedAt: now,
    );
    final locked = CanvasObject(
      id: 'locked-child',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -80, y: -40, width: 120, height: 80),
      parentFrameId: frame.id,
      isLocked: true,
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:locked-frame',
      kind: CanvasBoardKind.project,
      title: 'Locked frame',
      objects: <CanvasObject>[frame, locked],
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              key: key,
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectUpdated: (object) =>
                  setState(() => board = board.replaceObject(object)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final geometry = locked.geometry;
    final canvasCenter = tester.getCenter(find.byType(MindmapCanvas));
    final gesture = await tester.startGesture(
      canvasCenter +
          Offset(
            frame.geometry.x + frame.geometry.width / 2,
            frame.geometry.y + 24,
          ),
    );
    await gesture.moveBy(const Offset(40, 20));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(board.objectById(frame.id)!.geometry, isNot(frame.geometry));
    expect(board.objectById(locked.id), isNotNull);
    expect(board.objectById(locked.id)!.parentFrameId, frame.id);
    expect(board.objectById(locked.id)!.geometry, geometry);

    await key.currentState!.ungroupFrame(frame.id);
    await tester.pumpAndSettle();
    expect(board.objectById(locked.id), isNotNull);
    expect(board.objectById(locked.id)!.parentFrameId, isNull);
    expect(board.objectById(locked.id)!.geometry, geometry);
  });

  testWidgets('combined selection labels typed counts and clears atomically', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final nodes = <MindmapNode>[
      for (var index = 1; index <= 2; index++)
        MindmapNode.create(
          id: 'node-$index',
          type: NodeType.note,
          title: 'Node $index',
          day: now,
          position: CanvasPosition(-260 + index * 180, -120),
          now: now,
        ),
    ];
    final objects = <CanvasObject>[
      CanvasObject(
        id: 'node:node-1',
        type: CanvasObjectType.nodeReference,
        geometry: const CanvasGeometry(x: -80, y: 160, width: 120, height: 80),
        mindmapNodeId: 'node-1',
        createdAt: now,
        updatedAt: now,
      ),
      for (var index = 1; index <= 3; index++)
        CanvasObject(
          id: 'shape-$index',
          type: CanvasObjectType.shape,
          geometry: CanvasGeometry(
            x: -300 + index * 180,
            y: 160,
            width: 120,
            height: 80,
          ),
          createdAt: now,
          updatedAt: now,
        ),
    ];
    final board = CanvasBoard(
      id: 'project:combined-selection',
      kind: CanvasBoardKind.project,
      title: 'Combined selection',
      objects: objects,
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    var cleared = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: nodes,
            board: board,
            onSelectionCleared: () => cleared++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mindmap-node-node-1')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.byKey(const ValueKey('mindmap-node-node-2')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('2 nodes selected'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    for (var index = 1; index <= 3; index++) {
      key.currentState!.selectCanvasObject('shape-$index');
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('2 nodes + 3 objects selected'), findsOneWidget);
    expect(key.currentState!.selectedCanvasObjectIds, hasLength(3));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('2 nodes + 3 objects selected'), findsNothing);
    expect(key.currentState!.selectedCanvasObjectIds, isEmpty);
    expect(cleared, 1);

    await tester.tap(find.byKey(const ValueKey('mindmap-node-node-1')));
    await tester.pump();
    expect(find.text('2 nodes selected'), findsNothing);
  });

  testWidgets(
    'native-only selection has typed label and no node metadata actions',
    (tester) async {
      final now = DateTime(2026, 7, 28);
      final objects = <CanvasObject>[
        for (var index = 1; index <= 3; index++)
          CanvasObject(
            id: 'native-$index',
            type: CanvasObjectType.shape,
            geometry: CanvasGeometry(
              x: -260 + index * 160,
              y: 0,
              width: 120,
              height: 80,
            ),
            createdAt: now,
            updatedAt: now,
          ),
      ];
      final board = CanvasBoard(
        id: 'project:native-selection',
        kind: CanvasBoardKind.project,
        title: 'Native selection',
        objects: objects,
        createdAt: now,
        updatedAt: now,
      );
      final key = GlobalKey<MindmapCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(key: key, nodes: const [], board: board),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      for (final object in objects) {
        key.currentState!.selectCanvasObject(object.id);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(find.text('3 objects selected'), findsOneWidget);
      expect(find.byTooltip('Set selected status'), findsNothing);
      expect(find.byTooltip('Set selected priority'), findsNothing);
      expect(find.byTooltip('Tag selected'), findsNothing);
    },
  );

  testWidgets('plain cross-type selection replaces and control preserves', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'replace-node',
      type: NodeType.note,
      title: 'Replace node',
      day: now,
      now: now,
    );
    final object = CanvasObject(
      id: 'replace-object',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 180, y: 80, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'project:replace-selection',
      kind: CanvasBoardKind.project,
      title: 'Replace selection',
      objects: <CanvasObject>[object],
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: <MindmapNode>[node],
            board: board,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.selectCanvasObject(object.id);
    await tester.tap(find.byKey(const ValueKey('mindmap-node-replace-node')));
    await tester.pump();
    expect(key.currentState!.selectedCanvasObjectIds, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    key.currentState!.selectCanvasObject(object.id);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('1 node + 1 object selected'), findsOneWidget);
  });

  testWidgets('Meta preserves cross-type selection', (tester) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'meta-node',
      type: NodeType.note,
      title: 'Meta node',
      day: now,
      now: now,
    );
    final object = CanvasObject(
      id: 'meta-object',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 180, y: 80, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:meta-selection',
              kind: CanvasBoardKind.project,
              title: 'Meta selection',
              objects: <CanvasObject>[object],
              createdAt: now,
              updatedAt: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-node-meta-node')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    key.currentState!.selectCanvasObject(object.id);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(find.text('1 node + 1 object selected'), findsOneWidget);
  });

  testWidgets('widget updates prune selections whose entities disappeared', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'removed-node',
      type: NodeType.note,
      title: 'Removed node',
      day: now,
      now: now,
    );
    final object = CanvasObject(
      id: 'removed-object',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 180, y: 80, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    late StateSetter rebuild;
    var nodes = <MindmapNode>[node];
    var board = CanvasBoard(
      id: 'project:prune-selection',
      kind: CanvasBoardKind.project,
      title: 'Prune selection',
      objects: <CanvasObject>[object],
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MindmapCanvas(key: key, nodes: nodes, board: board);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-node-removed-node')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    key.currentState!.selectCanvasObject(object.id);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('1 node + 1 object selected'), findsOneWidget);

    rebuild(() {
      nodes = <MindmapNode>[];
      board = board.copyWith(objects: <CanvasObject>[]);
    });
    await tester.pump();

    expect(key.currentState!.selectedCanvasObjectIds, isEmpty);
    expect(find.text('1 node + 1 object selected'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('select all uses visible mixed selection path', (tester) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'select-all-node',
      type: NodeType.note,
      title: 'Visible node',
      day: now,
      now: now,
    );
    final visible = CanvasObject(
      id: 'select-all-visible',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 180, y: 80, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final hidden = CanvasObject(
      id: 'select-all-hidden',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 340, y: 80, width: 120, height: 80),
      isVisible: false,
      createdAt: now,
      updatedAt: now,
    );
    final reference = CanvasObject(
      id: 'node:select-all-node',
      type: CanvasObjectType.nodeReference,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 280, height: 180),
      mindmapNodeId: node.id,
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:select-all-mixed',
              kind: CanvasBoardKind.project,
              title: 'Select all mixed',
              objects: <CanvasObject>[visible, hidden, reference],
              createdAt: now,
              updatedAt: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await key.currentState!.runContextAction(CanvasContextAction.selectAll);
    await tester.pump();

    expect(find.text('1 node + 1 object selected'), findsOneWidget);
    expect(key.currentState!.selectedCanvasObjectIds, <String>{visible.id});

    await key.currentState!.runContextAction(
      CanvasContextAction.clearSelection,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(find.text('1 node + 1 object selected'), findsOneWidget);
    expect(key.currentState!.selectedCanvasObjectIds, <String>{visible.id});
  });

  testWidgets('lasso uses effective connector geometry', (tester) async {
    final now = DateTime(2026, 7, 28);
    final source = CanvasObject(
      id: 'connector-source',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -260, y: -80, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final target = CanvasObject(
      id: 'connector-target',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 180, y: -80, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final connector = CanvasObject(
      id: 'effective-connector',
      type: CanvasObjectType.connector,
      geometry: const CanvasGeometry(x: 700, y: 500, width: 40, height: 40),
      payload: const <String, Object?>{
        'sourceObjectId': 'connector-source',
        'targetObjectId': 'connector-target',
      },
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: const <MindmapNode>[],
            board: CanvasBoard(
              id: 'project:effective-connector-lasso',
              kind: CanvasBoardKind.project,
              title: 'Effective connector lasso',
              objects: <CanvasObject>[source, target, connector],
              createdAt: now,
              updatedAt: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sourceRect = tester.getRect(
      find.byKey(const ValueKey('canvas-object-connector-source')),
    );
    final targetRect = tester.getRect(
      find.byKey(const ValueKey('canvas-object-connector-target')),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(
      Offset(sourceRect.right + 10, sourceRect.center.dy - 10),
    );
    await gesture.moveTo(
      Offset(targetRect.left - 10, targetRect.center.dy + 10),
    );
    await gesture.up();
    await tester.pump();

    expect(key.currentState!.selectedCanvasObjectIds, <String>{connector.id});
  });

  testWidgets('native clipboard and select all create independent copies', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final first = CanvasObject(
      id: 'shape-1',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -180, y: -80, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final second = CanvasObject(
      id: 'shape-2',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 80, y: 40, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:clipboard',
      kind: CanvasBoardKind.project,
      title: 'Clipboard',
      objects: <CanvasObject>[first, second],
      createdAt: now,
      updatedAt: now,
    );
    var createBatchCount = 0;
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectsCreated: (objects) {
                createBatchCount++;
                setState(() {
                  board = board.copyWith(
                    objects: <CanvasObject>[...board.objects, ...objects],
                  );
                });
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(board.objects, hasLength(4));
    expect(createBatchCount, 1);
    final copies = board.objects.skip(2).toList();
    expect(copies.map((object) => object.id), isNot(contains(first.id)));
    expect(copies.first.geometry.x, first.geometry.x + 24);
    expect(copies.first.geometry.y, first.geometry.y + 24);
  });

  testWidgets('mixed copy and duplicate preserve node and native selections', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'mixed-node',
      type: NodeType.note,
      title: 'Mixed node',
      day: now,
      position: const CanvasPosition(-220, -100),
      data: const <String, Object?>{'body': 'preserved'},
      now: now,
    );
    final object = CanvasObject(
      id: 'mixed-shape',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 120, y: 40, width: 160, height: 90),
      payload: const <String, Object?>{'fillColor': '#123456'},
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:mixed-copy',
      kind: CanvasBoardKind.project,
      title: 'Mixed copy',
      objects: <CanvasObject>[object],
      createdAt: now,
      updatedAt: now,
    );
    final createdNodes = <MindmapNode>[];
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: <MindmapNode>[node, ...createdNodes],
              board: board,
              onNodeUpdated: (created) async {
                setState(() => createdNodes.add(created));
              },
              onNodesDeleted: (deleted) async {
                final ids = deleted.map((node) => node.id).toSet();
                setState(
                  () =>
                      createdNodes.removeWhere((node) => ids.contains(node.id)),
                );
              },
              onCanvasObjectsCreated: (created) async {
                setState(() {
                  board = board.copyWith(
                    objects: <CanvasObject>[...board.objects, ...created],
                  );
                });
              },
              onCanvasObjectsDeleted: (deleted) async {
                final ids = deleted.map((object) => object.id).toSet();
                setState(() {
                  board = board.copyWith(
                    objects: board.objects
                        .where((object) => !ids.contains(object.id))
                        .toList(),
                  );
                });
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();

    final clipboard = jsonDecode(clipboardText!) as Map<String, Object?>;
    expect(clipboard['kind'], 'var.mindmap.selection');
    expect(clipboard['nodes'], hasLength(1));
    expect(clipboard['objects'], hasLength(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(createdNodes, hasLength(1));
    expect(createdNodes.single.data['body'], 'preserved');
    expect(createdNodes.single.position.dx, node.position.dx + 42);
    expect(board.objects, hasLength(2));
    expect(board.objects.last.payload['fillColor'], '#123456');
    expect(board.objects.last.geometry.x, object.geometry.x + 42);
  });

  testWidgets('mixed clipboard paste creates node and native copies', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'paste-node',
      type: NodeType.note,
      title: 'Paste node',
      day: now,
      position: const CanvasPosition(-100, -80),
      now: now,
    );
    final object = CanvasObject(
      id: 'paste-shape',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 80, y: 40, width: 120, height: 90),
      createdAt: now,
      updatedAt: now,
    );
    final clipboardText = jsonEncode(<String, Object?>{
      'kind': 'var.mindmap.selection',
      'nodes': <Map<String, Object?>>[node.toJson()],
      'objects': <Map<String, Object?>>[object.toJson()],
    });
    final createdNodes = <MindmapNode>[];
    final createdObjects = <CanvasObject>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, Object?>{'text': clipboardText}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const <MindmapNode>[],
            board: CanvasBoard(
              id: 'project:mixed-paste',
              kind: CanvasBoardKind.project,
              title: 'Mixed paste',
              createdAt: now,
              updatedAt: now,
            ),
            onNodeUpdated: (created) async => createdNodes.add(created),
            onCanvasObjectsCreated: (created) async =>
                createdObjects.addAll(created),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(createdNodes, hasLength(1));
    expect(createdNodes.single.position.dx, node.position.dx + 36);
    expect(createdObjects, hasLength(1));
    expect(createdObjects.single.geometry.x, object.geometry.x + 24);
  });

  testWidgets('mixed toolbar duplicate remaps selected node relationships', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final first = MindmapNode.create(
      id: 'related-first',
      type: NodeType.note,
      title: 'First',
      day: now,
      relatedNodeIds: const <String>['related-second', 'external'],
      data: const <String, Object?>{
        'body': 'preserved',
        'relations': <Map<String, Object?>>[
          <String, Object?>{'targetId': 'related-second', 'label': 'supports'},
          <String, Object?>{'targetId': 'external', 'label': 'references'},
        ],
      },
      now: now,
    );
    final second = MindmapNode.create(
      id: 'related-second',
      type: NodeType.note,
      title: 'Second',
      day: now,
      relatedNodeIds: const <String>['related-first'],
      now: now,
    );
    final object = CanvasObject(
      id: 'toolbar-shape',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: 40, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final createdNodes = <MindmapNode>[];
    final createdObjects = <CanvasObject>[];
    final key = GlobalKey<MindmapCanvasState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: <MindmapNode>[first, second],
            board: CanvasBoard(
              id: 'project:toolbar-mixed',
              kind: CanvasBoardKind.project,
              title: 'Toolbar mixed',
              objects: <CanvasObject>[object],
              createdAt: now,
              updatedAt: now,
            ),
            onNodeUpdated: (created) async => createdNodes.add(created),
            onNodesDeleted: (deleted) async {
              final ids = deleted.map((node) => node.id).toSet();
              createdNodes.removeWhere((node) => ids.contains(node.id));
            },
            onCanvasObjectsCreated: (created) async =>
                createdObjects.addAll(created),
            onCanvasObjectsDeleted: (deleted) async {
              final ids = deleted.map((object) => object.id).toSet();
              createdObjects.removeWhere((object) => ids.contains(object.id));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await key.currentState!.runContextAction(CanvasContextAction.selectAll);
    await tester.pump();
    expect(find.text('2 nodes + 1 object selected'), findsOneWidget);
    await tester.tap(find.byTooltip('More batch edits'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Duplicate').last);
    await tester.tap(find.text('Duplicate').last);
    await tester.pumpAndSettle();

    expect(createdNodes, hasLength(2));
    expect(createdObjects, hasLength(1));
    final firstCopy = createdNodes.singleWhere(
      (node) => node.title == 'First copy',
    );
    final secondCopy = createdNodes.singleWhere(
      (node) => node.title == 'Second copy',
    );
    expect(firstCopy.relatedNodeIds, <String>[secondCopy.id]);
    expect(firstCopy.data['body'], 'preserved');
    expect(firstCopy.data['relations'], <Map<String, Object?>>[
      <String, Object?>{'targetId': secondCopy.id, 'label': 'supports'},
    ]);
    expect(secondCopy.relatedNodeIds, <String>[firstCopy.id]);
  });

  testWidgets('mixed zoom includes selected node and native object', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'zoom-node',
      type: NodeType.note,
      title: 'Zoom node',
      day: now,
      position: const CanvasPosition(-1200, -300),
      now: now,
    );
    final object = CanvasObject(
      id: 'zoom-object',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 1100, y: 260, width: 180, height: 120),
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:mixed-zoom',
              kind: CanvasBoardKind.project,
              title: 'Mixed zoom',
              objects: <CanvasObject>[object],
              createdAt: now,
              updatedAt: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await key.currentState!.runContextAction(CanvasContextAction.selectAll);
    await key.currentState!.runContextAction(
      CanvasContextAction.zoomToSelection,
    );
    await tester.pumpAndSettle();

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final matrix = viewer.transformationController!.value;
    final viewport = tester.getSize(find.byType(InteractiveViewer));
    final origin = Offset(
      MindmapCanvas.canvasSize.width / 2,
      MindmapCanvas.canvasSize.height / 2,
    );
    final nodePoint = MatrixUtils.transformPoint(
      matrix,
      origin + Offset(node.position.dx, node.position.dy),
    );
    final objectPoint = MatrixUtils.transformPoint(
      matrix,
      origin + Offset(object.geometry.x, object.geometry.y),
    );
    for (final point in <Offset>[nodePoint, objectPoint]) {
      expect(point.dx, inInclusiveRange(0, viewport.width));
      expect(point.dy, inInclusiveRange(0, viewport.height));
    }
  });

  testWidgets('mixed keyboard delete removes nodes and unlocked objects', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'delete-node',
      type: NodeType.task,
      title: 'Delete node',
      day: now,
      now: now,
    );
    final unlocked = CanvasObject(
      id: 'delete-unlocked',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: 0, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final locked = CanvasObject(
      id: 'delete-locked',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 240, y: 0, width: 100, height: 80),
      isLocked: true,
      createdAt: now,
      updatedAt: now,
    );
    List<MindmapNode>? deletedNodes;
    final deletedObjects = <CanvasObject>[];
    final messages = <String>[];
    final key = GlobalKey<MindmapCanvasState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:mixed-delete',
              kind: CanvasBoardKind.project,
              title: 'Mixed delete',
              objects: <CanvasObject>[unlocked, locked],
              createdAt: now,
              updatedAt: now,
            ),
            onNodesDeleted: (nodes) async => deletedNodes = nodes,
            onCanvasObjectsDeleted: (objects) async =>
                deletedObjects.addAll(objects),
            onStatusMessage: messages.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await key.currentState!.runContextAction(CanvasContextAction.selectAll);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deletedNodes!.map((item) => item.id), <String>['delete-node']);
    expect(deletedObjects.map((item) => item.id), <String>['delete-unlocked']);
    expect(key.currentState!.selectedCanvasObjectIds, <String>{
      'delete-locked',
    });
    expect(messages, contains('Skipped 1 locked object'));
  });

  testWidgets('mixed delete cancellation performs no membership writes', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'cancel-node',
      type: NodeType.note,
      title: 'Cancel node',
      day: now,
      now: now,
    );
    final frame = CanvasObject(
      id: 'cancel-frame',
      type: CanvasObjectType.frame,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 300, height: 200),
      createdAt: now,
      updatedAt: now,
    );
    final child = CanvasObject(
      id: 'cancel-child',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 40, y: 40, width: 100, height: 80),
      parentFrameId: frame.id,
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    var nodeUpdateCount = 0;
    var objectDeleteCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:cancel-delete',
              kind: CanvasBoardKind.project,
              title: 'Cancel delete',
              objects: <CanvasObject>[frame, child],
              createdAt: now,
              updatedAt: now,
            ),
            onNodeUpdated: (_) async => nodeUpdateCount++,
            onNodesDeleted: (_) async {},
            onCanvasObjectsUpdated: (_) async {},
            onCanvasObjectsDeleted: (_) async => objectDeleteCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await key.currentState!.runContextAction(CanvasContextAction.selectAll);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(nodeUpdateCount, 0);
    expect(objectDeleteCount, 0);
  });

  testWidgets('mixed duplicate preflights native create before node writes', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'preflight-node',
      type: NodeType.note,
      title: 'Preflight node',
      day: now,
      now: now,
    );
    final shape = CanvasObject(
      id: 'preflight-shape',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: 0, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    var nodeUpdateCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:duplicate-preflight',
              kind: CanvasBoardKind.project,
              title: 'Duplicate preflight',
              objects: <CanvasObject>[shape],
              createdAt: now,
              updatedAt: now,
            ),
            onNodeUpdated: (_) async => nodeUpdateCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await key.currentState!.runContextAction(CanvasContextAction.selectAll);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(nodeUpdateCount, 0);
  });

  testWidgets('group failure rolls back exact written members and frame', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    var nodes = <MindmapNode>[
      for (final id in <String>['group-first', 'group-second'])
        MindmapNode.create(
          id: id,
          type: NodeType.note,
          title: id,
          day: now,
          now: now,
        ),
    ];
    final shape = CanvasObject(
      id: 'group-shape',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: 0, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:group-rollback',
      kind: CanvasBoardKind.project,
      title: 'Group rollback',
      objects: <CanvasObject>[shape],
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    var forwardWrites = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              key: key,
              nodes: nodes,
              board: board,
              onNodeUpdated: (updated) async {
                setState(() {
                  nodes = <MindmapNode>[
                    for (final node in nodes)
                      if (node.id == updated.id) updated else node,
                  ];
                });
                if (updated.data['groupId'] != null && forwardWrites++ == 1) {
                  throw StateError('second member failed');
                }
              },
              onCanvasObjectsCreated: (created) async => setState(() {
                board = board.copyWith(
                  objects: <CanvasObject>[...board.objects, ...created],
                );
              }),
              onCanvasObjectsUpdated: (updated) async => setState(() {
                for (final object in updated) {
                  board = board.replaceObject(object);
                }
              }),
              onCanvasObjectsDeleted: (deleted) async => setState(() {
                final ids = deleted.map((object) => object.id).toSet();
                board = board.copyWith(
                  objects: board.objects
                      .where((object) => !ids.contains(object.id))
                      .toList(),
                );
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await key.currentState!.runContextAction(CanvasContextAction.selectAll);
    await key.currentState!.groupSelectedEntities();
    await tester.pumpAndSettle();

    expect(nodes.every((node) => node.data['groupId'] == null), isTrue);
    expect(
      board.objects.where((object) => object.type == CanvasObjectType.frame),
      isEmpty,
    );
    expect(board.objectById(shape.id)!.parentFrameId, isNull);
  });

  testWidgets(
    'frame delete failure recreates frame without detaching members',
    (tester) async {
      final now = DateTime(2026, 7, 28);
      final node = MindmapNode.create(
        id: 'delete-frame-node',
        type: NodeType.note,
        title: 'Node',
        day: now,
        data: const <String, Object?>{'groupId': 'delete-frame'},
        now: now,
      );
      final frame = CanvasObject(
        id: 'delete-frame',
        type: CanvasObjectType.frame,
        geometry: const CanvasGeometry(x: 0, y: 0, width: 300, height: 200),
        createdAt: now,
        updatedAt: now,
      );
      var board = CanvasBoard(
        id: 'project:delete-frame-rollback',
        kind: CanvasBoardKind.project,
        title: 'Delete frame rollback',
        objects: <CanvasObject>[frame],
        createdAt: now,
        updatedAt: now,
      );
      final key = GlobalKey<MindmapCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MindmapCanvas(
                key: key,
                nodes: <MindmapNode>[node],
                board: board,
                onNodeUpdated: (_) async {},
                onCanvasObjectsUpdated: (_) async {},
                onCanvasObjectsDeleted: (deleted) async {
                  setState(
                    () =>
                        board = board.copyWith(objects: const <CanvasObject>[]),
                  );
                  throw StateError('delete failed after persistence');
                },
                onCanvasObjectsCreated: (created) async => setState(() {
                  board = board.copyWith(
                    objects: <CanvasObject>[...board.objects, ...created],
                  );
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(key.currentState!.deleteFrame(frame.id), completes);
      await tester.pumpAndSettle();

      expect(board.objectById(frame.id), frame);
      expect(node.data['groupId'], frame.id);
    },
  );

  testWidgets('duplicate node failure removes created node and object copies', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final originals = <MindmapNode>[
      for (final id in <String>['duplicate-first', 'duplicate-second'])
        MindmapNode.create(
          id: id,
          type: NodeType.note,
          title: id,
          day: now,
          now: now,
        ),
    ];
    final createdNodes = <MindmapNode>[];
    final createdObjects = <CanvasObject>[];
    final shape = CanvasObject(
      id: 'duplicate-shape',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: 0, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final key = GlobalKey<MindmapCanvasState>();
    var nodeWrites = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: originals,
            board: CanvasBoard(
              id: 'project:duplicate-rollback',
              kind: CanvasBoardKind.project,
              title: 'Duplicate rollback',
              objects: <CanvasObject>[shape],
              createdAt: now,
              updatedAt: now,
            ),
            onNodeUpdated: (node) async {
              createdNodes.add(node);
              if (nodeWrites++ == 1) throw StateError('second copy failed');
            },
            onNodesDeleted: (nodes) async {
              final ids = nodes.map((node) => node.id).toSet();
              createdNodes.removeWhere((node) => ids.contains(node.id));
            },
            onCanvasObjectsCreated: (objects) async =>
                createdObjects.addAll(objects),
            onCanvasObjectsDeleted: (objects) async {
              final ids = objects.map((object) => object.id).toSet();
              createdObjects.removeWhere((object) => ids.contains(object.id));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await key.currentState!.runContextAction(CanvasContextAction.selectAll);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(createdNodes, isEmpty);
    expect(createdObjects, isEmpty);
  });

  testWidgets(
    'multi-frame delete failure restores every frame and membership',
    (tester) async {
      final now = DateTime(2026, 7, 28);
      var nodes = <MindmapNode>[
        for (final index in <int>[1, 2])
          MindmapNode.create(
            id: 'multi-node-$index',
            type: NodeType.note,
            title: 'Node $index',
            day: now,
            data: <String, Object?>{'groupId': 'multi-frame-$index'},
            now: now,
          ),
      ];
      final frames = <CanvasObject>[
        for (final index in <int>[1, 2])
          CanvasObject(
            id: 'multi-frame-$index',
            type: CanvasObjectType.frame,
            geometry: CanvasGeometry(
              x: index * 300,
              y: 0,
              width: 240,
              height: 180,
            ),
            createdAt: now,
            updatedAt: now,
          ),
      ];
      final children = <CanvasObject>[
        for (final index in <int>[1, 2])
          CanvasObject(
            id: 'multi-child-$index',
            type: CanvasObjectType.shape,
            geometry: CanvasGeometry(
              x: index * 300 + 40,
              y: 40,
              width: 80,
              height: 60,
            ),
            parentFrameId: 'multi-frame-$index',
            createdAt: now,
            updatedAt: now,
          ),
      ];
      var board = CanvasBoard(
        id: 'project:multi-frame-rollback',
        kind: CanvasBoardKind.project,
        title: 'Multi frame rollback',
        objects: <CanvasObject>[...frames, ...children],
        createdAt: now,
        updatedAt: now,
      );
      final key = GlobalKey<MindmapCanvasState>();
      var clearedNodes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MindmapCanvas(
                key: key,
                nodes: nodes,
                board: board,
                onNodeUpdated: (updated) async {
                  setState(() {
                    nodes = <MindmapNode>[
                      for (final node in nodes)
                        if (node.id == updated.id) updated else node,
                    ];
                  });
                  if (updated.data['groupId'] == null && clearedNodes++ == 1) {
                    throw StateError('second frame membership failed');
                  }
                },
                onCanvasObjectsUpdated: (updated) async => setState(() {
                  for (final object in updated) {
                    board = board.replaceObject(object);
                  }
                }),
                onCanvasObjectsDeleted: (deleted) async => setState(() {
                  final ids = deleted.map((object) => object.id).toSet();
                  board = board.copyWith(
                    objects: board.objects
                        .where((object) => !ids.contains(object.id))
                        .toList(),
                  );
                }),
                onCanvasObjectsCreated: (created) async => setState(() {
                  final ids = created.map((object) => object.id).toSet();
                  board = board.copyWith(
                    objects: <CanvasObject>[
                      ...board.objects.where(
                        (object) => !ids.contains(object.id),
                      ),
                      ...created,
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await key.currentState!.runContextAction(CanvasContextAction.selectAll);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(nodes.map((node) => node.data['groupId']), <String>[
        'multi-frame-1',
        'multi-frame-2',
      ]);
      expect(board.objects.map((object) => object.id).toSet(), <String>{
        ...frames.map((object) => object.id),
        ...children.map((object) => object.id),
      });
      for (final child in children) {
        expect(board.objectById(child.id)!.parentFrameId, child.parentFrameId);
      }
    },
  );

  testWidgets('secondary click opens native object actions', (tester) async {
    final now = DateTime(2026, 7, 28);
    final object = CanvasObject(
      id: 'shape-context',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -120, y: -80, width: 160, height: 100),
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'project:context-menu',
      kind: CanvasBoardKind.project,
      title: 'Context menu',
      objects: <CanvasObject>[object],
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const <MindmapNode>[],
            board: board,
            onCanvasObjectUpdated: (_) {},
            onCanvasObjectDeleted: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(
      find.byKey(const ValueKey('canvas-object-shape-context')),
    );
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mindmap-canvas-object-context-properties')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mindmap-canvas-object-context-delete')),
      findsOneWidget,
    );
  });

  testWidgets('equal-spacing node snap shows label and survives grid finish', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 7, 28);
    final nodes = <MindmapNode>[
      MindmapNode.create(
        id: 'spacing-left',
        type: NodeType.note,
        title: 'Left',
        day: now,
        position: const CanvasPosition(-500, 200),
        now: now,
      ),
      MindmapNode.create(
        id: 'spacing-moving',
        type: NodeType.note,
        title: 'Moving',
        day: now,
        position: const CanvasPosition(20, 200),
        now: now,
      ),
      MindmapNode.create(
        id: 'spacing-right',
        type: NodeType.note,
        title: 'Right',
        day: now,
        position: const CanvasPosition(506, 200),
        now: now,
      ),
    ];
    CanvasPosition? moved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: nodes,
            onNodeMoved: (node, position) async {
              if (node.id == 'spacing-moving') moved = position;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final finder = find.byKey(const ValueKey('mindmap-node-spacing-moving'));
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(-17, 0));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Equal spacing 163 px'), findsOneWidget);
    await gesture.moveTo(start + const Offset(-40, 0));
    await tester.pump();
    expect(find.bySemanticsLabel('Equal spacing 163 px'), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(moved?.dx, -20);
  });

  testWidgets('multi-node grid finish preserves identical translation', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final nodes = <MindmapNode>[
      MindmapNode.create(
        id: 'grid-primary',
        type: NodeType.note,
        title: 'Primary',
        day: now,
        position: const CanvasPosition(-203, -200),
        now: now,
      ),
      MindmapNode.create(
        id: 'grid-secondary',
        type: NodeType.note,
        title: 'Secondary',
        day: now,
        position: const CanvasPosition(34, 200),
        now: now,
      ),
    ];
    final moved = <String, CanvasPosition>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: nodes,
            onNodeMoved: (node, position) async => moved[node.id] = position,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<MindmapCanvasState>(find.byType(MindmapCanvas));
    await state.runContextAction(CanvasContextAction.selectAll);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('mindmap-node-grid-primary')),
      const Offset(10, 0),
    );
    await tester.pumpAndSettle();

    expect(moved['grid-primary']!.dx - nodes[0].position.dx, 3);
    expect(moved['grid-secondary']!.dx - nodes[1].position.dx, 3);
  });

  testWidgets('node drag smart-guides to native object geometry', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'node-to-native',
      type: NodeType.note,
      title: 'Moving node',
      day: now,
      position: const CanvasPosition(-300, -100),
      now: now,
    );
    final anchor = CanvasObject(
      id: 'native-anchor',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'project:node-to-native-guides',
      kind: CanvasBoardKind.project,
      title: 'Node to native guides',
      objects: <CanvasObject>[anchor],
      createdAt: now,
      updatedAt: now,
    );
    CanvasPosition? movedPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            board: board,
            onNodeMoved: (_, position) async => movedPosition = position,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('mindmap-node-node-to-native'));
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    for (var step = 1; step <= 20; step++) {
      await gesture.moveTo(start + Offset(394 * step / 20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(movedPosition?.dx, 100);
    expect(movedPosition?.dy, -100);
  });

  testWidgets('held node smart-guide correction does not compound', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'held-guide-node',
      type: NodeType.note,
      title: 'Moving node',
      day: now,
      position: const CanvasPosition(-300, -100),
      now: now,
    );
    final anchor = CanvasObject(
      id: 'held-guide-anchor',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:held-node-guide',
              kind: CanvasBoardKind.project,
              title: 'Held node guide',
              objects: <CanvasObject>[anchor],
              createdAt: now,
              updatedAt: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('mindmap-node-held-guide-node'));
    final before = tester.getTopLeft(finder);
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(394, 0));
    await tester.pump();
    for (var step = 1; step <= 120; step++) {
      await gesture.moveTo(start + Offset(394 + 10 * step / 120, 0));
      await tester.pump(const Duration(milliseconds: 1));
    }

    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsOneWidget,
    );
    expect(tester.getTopLeft(finder).dx - before.dx, closeTo(404, 8));
    await gesture.up();
  });

  testWidgets('node smart-guide recaptures changed axis target', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'switch-guide-node',
      type: NodeType.note,
      title: 'Moving node',
      day: now,
      position: const CanvasPosition(-300, -100),
      now: now,
    );
    final anchors = <CanvasObject>[
      CanvasObject(
        id: 'switch-guide-first',
        type: CanvasObjectType.shape,
        geometry: const CanvasGeometry(x: 100, y: 200, width: 120, height: 80),
        createdAt: now,
        updatedAt: now,
      ),
      CanvasObject(
        id: 'switch-guide-second',
        type: CanvasObjectType.shape,
        geometry: const CanvasGeometry(x: 105, y: 400, width: 120, height: 80),
        createdAt: now,
        updatedAt: now,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:switch-node-guide',
              kind: CanvasBoardKind.project,
              title: 'Switch node guide',
              objects: anchors,
              createdAt: now,
              updatedAt: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('mindmap-node-switch-guide-node'));
    final before = tester.getTopLeft(finder);
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(394, 0));
    await tester.pump();
    await gesture.moveTo(start + const Offset(403, 0));
    await tester.pump();

    expect(tester.getTopLeft(finder).dx - before.dx, closeTo(405, 0.1));
    await gesture.up();
  });

  testWidgets('node finish clears guides without move callback', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'no-callback-node',
      type: NodeType.note,
      title: 'Moving node',
      day: now,
      position: const CanvasPosition(-300, -100),
      now: now,
    );
    final anchor = CanvasObject(
      id: 'no-callback-node-anchor',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:no-node-callback',
              kind: CanvasBoardKind.project,
              title: 'No node callback',
              objects: <CanvasObject>[anchor],
              createdAt: now,
              updatedAt: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('mindmap-node-no-callback-node'));
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(394, 0));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsNothing,
    );

    final beforeSecond = tester.getTopLeft(finder);
    final secondStart = tester.getCenter(finder);
    final second = await tester.startGesture(secondStart);
    await second.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(tester.getTopLeft(finder).dx - beforeSecond.dx, closeTo(1, 0.1));
    await second.up();
  });

  testWidgets('zoomed node drag converts screen delta before smart guides', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 7, 28);
    var node = MindmapNode.create(
      id: 'zoomed-guide-node',
      type: NodeType.note,
      title: 'Zoomed guide node',
      day: now,
      position: const CanvasPosition(-300, -200),
      now: now,
    );
    final anchor = CanvasObject(
      id: 'zoomed-guide-anchor',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -300, y: 0, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    CanvasPosition? persistedPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: <MindmapNode>[node],
              board: CanvasBoard(
                id: 'project:zoomed-node-guide',
                kind: CanvasBoardKind.project,
                title: 'Zoomed node guide',
                objects: <CanvasObject>[anchor],
                createdAt: now,
                updatedAt: now,
              ),
              onNodeMoved: (_, position) async {
                persistedPosition = position;
                setState(() => node = node.copyWith(position: position));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final canvas = find.byKey(const ValueKey('mindmap-canvas'));
    final viewer = tester.widget<InteractiveViewer>(canvas);
    final controller = viewer.transformationController!;
    final viewportCenter = tester.getSize(canvas).center(Offset.zero);
    final sceneCenter = controller.toScene(viewportCenter);
    controller.value = Matrix4.identity()
      ..translateByDouble(
        viewportCenter.dx - sceneCenter.dx * 2,
        viewportCenter.dy - sceneCenter.dy * 2,
        0,
        1,
      )
      ..scaleByDouble(2, 2, 2, 1);
    await tester.pump();
    final finder = find.byKey(const ValueKey('mindmap-node-zoomed-guide-node'));
    final before = tester.getTopLeft(finder);
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(0, 394));
    await tester.pump();

    final engaged = tester.getTopLeft(finder);
    final engagedPointerOffset = start + const Offset(0, 394) - engaged;
    final guide = find.byKey(const ValueKey('mindmap-canvas-smart-guides'));
    final guideSemantics = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.child?.key ==
              const ValueKey<String>('mindmap-canvas-smart-guides'),
    );
    expect(engaged.dy - before.dy, closeTo(400, 0.1));
    expect((engaged.dy - before.dy - 394).abs(), lessThanOrEqualTo(8));
    expect(guide, findsOneWidget);
    expect(guideSemantics, findsOneWidget);

    await gesture.moveTo(start + const Offset(14, 408));
    await tester.pump();

    final released = tester.getTopLeft(finder);
    final releasedPointerOffset = start + const Offset(14, 408) - released;
    expect(released.dx - engaged.dx, closeTo(14, 0.1));
    expect(released.dy - engaged.dy, closeTo(8, 0.1));
    expect(
      (releasedPointerOffset - engagedPointerOffset).distance,
      lessThanOrEqualTo(8),
    );
    expect(guide, findsNothing);
    expect(guideSemantics, findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(finder).dy, closeTo(released.dy, 0.1));
    expect(persistedPosition, const CanvasPosition(-293, 4));
  });

  testWidgets('node drag uses connector effective geometry target', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 7, 28);
    final source = CanvasObject(
      id: 'connector-source',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -1000, y: 200, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final target = CanvasObject(
      id: 'connector-target',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 1000, y: 200, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final connector = CanvasObject(
      id: 'effective-connector',
      type: CanvasObjectType.connector,
      geometry: const CanvasGeometry(x: 2000, y: 1000, width: 100, height: 40),
      payload: const <String, Object?>{
        'sourceObjectId': 'connector-source',
        'targetObjectId': 'connector-target',
      },
      createdAt: now,
      updatedAt: now,
    );
    final node = MindmapNode.create(
      id: 'connector-snap-node',
      type: NodeType.note,
      title: 'Connector snap',
      day: now,
      position: const CanvasPosition(-500, -200),
      now: now,
    );
    CanvasPosition? moved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:connector-effective',
              kind: CanvasBoardKind.project,
              title: 'Connector effective',
              objects: <CanvasObject>[source, target, connector],
              createdAt: now,
              updatedAt: now,
            ),
            onNodeMoved: (_, position) async => moved = position,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(
      const ValueKey('mindmap-node-connector-snap-node'),
    );
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(383, 0));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(moved?.dx, -110);
  });

  testWidgets('native object drag smart-guides to live node geometry', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'native-to-node',
      type: NodeType.note,
      title: 'Node anchor',
      day: now,
      position: const CanvasPosition(100, 200),
      now: now,
    );
    final moving = CanvasObject(
      id: 'native-moving',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -300, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:native-to-node-guides',
      kind: CanvasBoardKind.project,
      title: 'Native to node guides',
      objects: <CanvasObject>[moving],
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            board: board,
            onCanvasObjectUpdated: (object) {
              board = board.replaceObject(object);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('canvas-object-native-moving'));
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    for (var step = 1; step <= 20; step++) {
      await gesture.moveTo(start + Offset(394 * step / 20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(board.objectById(moving.id)!.geometry.x, 100);
    expect(board.objectById(moving.id)!.geometry.y, -100);
  });

  testWidgets('held native object smart-guide correction does not compound', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'held-native-anchor',
      type: NodeType.note,
      title: 'Anchor',
      day: now,
      position: const CanvasPosition(100, -100),
      now: now,
    );
    final moving = CanvasObject(
      id: 'held-native-moving',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -300, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:held-native-guide',
              kind: CanvasBoardKind.project,
              title: 'Held native guide',
              objects: <CanvasObject>[moving],
              createdAt: now,
              updatedAt: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(
      const ValueKey('canvas-object-held-native-moving'),
    );
    final before = tester.getTopLeft(finder);
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(394, 0));
    await tester.pump();
    for (var step = 1; step <= 120; step++) {
      await gesture.moveTo(start + Offset(394 + 10 * step / 120, 0));
      await tester.pump(const Duration(milliseconds: 1));
    }

    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsOneWidget,
    );
    expect(tester.getTopLeft(finder).dx - before.dx, closeTo(404, 8));
    await gesture.up();
  });

  testWidgets('native smart-guide recaptures changed axis target', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final moving = CanvasObject(
      id: 'switch-native-moving',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -300, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final nodes = <MindmapNode>[
      MindmapNode.create(
        id: 'switch-native-first',
        type: NodeType.note,
        title: 'First',
        day: now,
        position: const CanvasPosition(100, 200),
        now: now,
      ),
      MindmapNode.create(
        id: 'switch-native-second',
        type: NodeType.note,
        title: 'Second',
        day: now,
        position: const CanvasPosition(105, 400),
        now: now,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: nodes,
            board: CanvasBoard(
              id: 'project:switch-native-guide',
              kind: CanvasBoardKind.project,
              title: 'Switch native guide',
              objects: <CanvasObject>[moving],
              createdAt: now,
              updatedAt: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(
      const ValueKey('canvas-object-switch-native-moving'),
    );
    final before = tester.getTopLeft(finder);
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(394, 0));
    await tester.pump();
    await gesture.moveTo(start + const Offset(403, 0));
    await tester.pump();

    expect(tester.getTopLeft(finder).dx - before.dx, closeTo(405, 0.1));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('native and live node guide identities cannot collide', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'x',
      type: NodeType.note,
      title: 'Node anchor',
      day: now,
      position: const CanvasPosition(100, 200),
      now: now,
    );
    final moving = CanvasObject(
      id: 'identity-moving',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -300, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final nativeAnchor = CanvasObject(
      id: 'node:x',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 105, y: 400, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:identity-namespace',
              kind: CanvasBoardKind.project,
              title: 'Identity namespace',
              objects: <CanvasObject>[moving, nativeAnchor],
              createdAt: now,
              updatedAt: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('canvas-object-identity-moving'));
    final before = tester.getTopLeft(finder);
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(397, 0));
    await tester.pump();
    await gesture.moveTo(start + const Offset(403, 0));
    await tester.pump();

    expect(tester.getTopLeft(finder).dx - before.dx, closeTo(405, 0.1));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('released guide allows distinct identity at same coordinate', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final moving = CanvasObject(
      id: 'same-coordinate-moving',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -300, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final first = CanvasObject(
      id: 'same-coordinate-first',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: 200, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final second = CanvasObject(
      id: 'same-coordinate-second',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: 400, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:same-coordinate-release',
      kind: CanvasBoardKind.project,
      title: 'Same coordinate release',
      objects: <CanvasObject>[moving, first, second],
      createdAt: now,
      updatedAt: now,
    );
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MindmapCanvas(nodes: const <MindmapNode>[], board: board);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(
      const ValueKey('canvas-object-same-coordinate-moving'),
    );
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(394, 0));
    await tester.pump();
    await gesture.moveTo(start + const Offset(414, 0));
    await tester.pump();
    update(() {
      board = board.copyWith(
        objects: <CanvasObject>[moving, second],
        updatedAt: now.add(const Duration(seconds: 1)),
      );
    });
    await tester.pump();
    await gesture.moveTo(start + const Offset(394, 0));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('native finish clears guides without update callback', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final moving = CanvasObject(
      id: 'no-update-moving',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -300, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final anchor = CanvasObject(
      id: 'no-update-anchor',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    var canUpdate = true;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MindmapCanvas(
                nodes: const <MindmapNode>[],
                board: CanvasBoard(
                  id: 'project:no-update-callback',
                  kind: CanvasBoardKind.project,
                  title: 'No update callback',
                  objects: <CanvasObject>[moving, anchor],
                  createdAt: now,
                  updatedAt: now,
                ),
                onCanvasObjectUpdated: canUpdate ? (_) {} : null,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('canvas-object-no-update-moving'));
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    for (var step = 1; step <= 20; step++) {
      await gesture.moveTo(start + Offset(394 * step / 20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsOneWidget,
    );
    update(() => canUpdate = false);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsNothing,
    );
  });

  testWidgets('smart guides reengage a distinct guide after release', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final moving = CanvasObject(
      id: 'reengage-moving',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -300, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final anchors = <CanvasObject>[
      CanvasObject(
        id: 'reengage-first',
        type: CanvasObjectType.shape,
        geometry: const CanvasGeometry(x: -100, y: 200, width: 120, height: 80),
        createdAt: now,
        updatedAt: now,
      ),
      CanvasObject(
        id: 'reengage-second',
        type: CanvasObjectType.shape,
        geometry: const CanvasGeometry(x: 200, y: 200, width: 120, height: 80),
        createdAt: now,
        updatedAt: now,
      ),
    ];
    var board = CanvasBoard(
      id: 'project:reengage',
      kind: CanvasBoardKind.project,
      title: 'Reengage',
      objects: <CanvasObject>[moving, ...anchors],
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const <MindmapNode>[],
            board: board,
            onCanvasObjectUpdated: (object) {
              board = board.replaceObject(object);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('canvas-object-reengage-moving'));
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    for (final dx in <double>[100, 116, 140, 260, 380, 394, 400, 500]) {
      await gesture.moveTo(start + Offset(dx, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(board.objectById(moving.id)!.geometry.x, 200);
  });

  testWidgets('node pointer cancel restores position without persistence', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'node-cancel',
      type: NodeType.note,
      title: 'Cancel node',
      day: now,
      position: const CanvasPosition(-200, -100),
      now: now,
    );
    var updates = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            onNodeMoved: (_, _) async => updates++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('mindmap-node-node-cancel'));
    final before = tester.getTopLeft(finder);
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await gesture.moveBy(const Offset(80, 40));
    await tester.pump();
    expect(tester.getTopLeft(finder), isNot(before));

    final listener = tester.widget<Listener>(
      find
          .ancestor(
            of: finder,
            matching: find.byWidgetPredicate(
              (widget) => widget is Listener && widget.onPointerCancel != null,
            ),
          )
          .first,
    );
    expect(listener.onPointerCancel, isNotNull);
    listener.onPointerCancel!(const PointerCancelEvent(pointer: 1));
    await tester.pump();

    expect(tester.getTopLeft(finder), before);
    expect(updates, 0);
  });

  testWidgets('native pointer cancel clears preview without persistence', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final moving = CanvasObject(
      id: 'cancel-moving',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -200, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final anchor = CanvasObject(
      id: 'cancel-anchor',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    var updates = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const <MindmapNode>[],
            board: CanvasBoard(
              id: 'project:cancel',
              kind: CanvasBoardKind.project,
              title: 'Cancel',
              objects: <CanvasObject>[moving, anchor],
              createdAt: now,
              updatedAt: now,
            ),
            onCanvasObjectUpdated: (_) => updates++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('canvas-object-cancel-moving'));
    final before = tester.getTopLeft(finder);
    final start = tester.getCenter(finder);
    final gesture = await tester.startGesture(start);
    for (var step = 1; step <= 20; step++) {
      await gesture.moveTo(start + Offset(294 * step / 20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsOneWidget,
    );
    final detector = tester.widget<GestureDetector>(
      find.descendant(of: finder, matching: find.byType(GestureDetector)).first,
    );
    expect(detector.onPanCancel, isNotNull);
    detector.onPanCancel!();
    await tester.pump();
    await gesture.cancel();

    expect(tester.getTopLeft(finder), before);
    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsNothing,
    );
    expect(updates, 0);
  });

  testWidgets('smart guides release after cumulative small pointer moves', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final moving = CanvasObject(
      id: 'shape-release',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -200, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final stationary = CanvasObject(
      id: 'shape-anchor',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -200, y: 100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:smart-guide-release',
      kind: CanvasBoardKind.project,
      title: 'Smart guide release',
      objects: <CanvasObject>[moving, stationary],
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const <MindmapNode>[],
            board: board,
            onCanvasObjectUpdated: (object) {
              board = board.replaceObject(object);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byKey(const ValueKey('canvas-object-shape-release'));
    final before = tester.getTopLeft(finder);
    final start = before + const Offset(30, 30);
    final gesture = await tester.startGesture(start);
    for (var step = 1; step <= 40; step++) {
      await gesture.moveTo(start + Offset(step.toDouble(), 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    await gesture.up();
    await tester.pumpAndSettle();
    expect(board.objectById(moving.id)!.geometry.x, greaterThan(-185));
  });

  testWidgets('smart guides align persisted geometry after direct drag', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final moving = CanvasObject(
      id: 'shape-moving',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -200, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final stationary = CanvasObject(
      id: 'shape-stationary',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 40, y: -100, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:smart-guides',
      kind: CanvasBoardKind.project,
      title: 'Smart guides',
      objects: <CanvasObject>[moving, stationary],
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: StatefulBuilder(
              builder: (context, setState) => MindmapCanvas(
                nodes: const <MindmapNode>[],
                board: board,
                onCanvasObjectUpdated: (object) {
                  setState(() => board = board.replaceObject(object));
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final movingFinder = find.byKey(
      const ValueKey('canvas-object-shape-moving'),
    );
    const screenDelta = 240.0;
    final dragStart = tester.getTopLeft(movingFinder) + const Offset(30, 30);
    final gesture = await tester.startGesture(dragStart);
    for (var step = 1; step <= 20; step++) {
      await gesture.moveTo(dragStart + Offset(screenDelta * step / 20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsOneWidget,
    );
    await gesture.up();

    await tester.pumpAndSettle();

    expect(board.objectById(moving.id)!.geometry.x, stationary.geometry.x);
    expect(board.objectById(moving.id)!.geometry.y, moving.geometry.y);
    expect(
      find.byKey(const ValueKey('mindmap-canvas-smart-guides')),
      findsNothing,
    );
  });

  testWidgets('alignment skips locked native objects', (tester) async {
    final now = DateTime(2026, 7, 28);
    final objects = <CanvasObject>[
      CanvasObject(
        id: 'shape-1',
        type: CanvasObjectType.shape,
        geometry: const CanvasGeometry(x: -180, y: -80, width: 120, height: 80),
        createdAt: now,
        updatedAt: now,
      ),
      CanvasObject(
        id: 'shape-2',
        type: CanvasObjectType.shape,
        geometry: const CanvasGeometry(x: 40, y: 20, width: 120, height: 80),
        createdAt: now,
        updatedAt: now,
      ),
      CanvasObject(
        id: 'shape-locked',
        type: CanvasObjectType.shape,
        geometry: const CanvasGeometry(x: 220, y: 120, width: 120, height: 80),
        isLocked: true,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    var board = CanvasBoard(
      id: 'project:align',
      kind: CanvasBoardKind.project,
      title: 'Align',
      objects: objects,
      createdAt: now,
      updatedAt: now,
    );
    var updateBatchCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectsUpdated: (objects) {
                updateBatchCount++;
                setState(() {
                  for (final object in objects) {
                    board = board.replaceObject(object);
                  }
                });
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-actions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-align-left')),
    );
    await tester.pumpAndSettle();

    expect(board.objectById('shape-1')!.geometry.x, -180);
    expect(board.objectById('shape-2')!.geometry.x, -180);
    expect(board.objectById('shape-locked')!.geometry.x, 220);
    expect(updateBatchCount, 1);
  });

  testWidgets('keyboard nudges native objects and escape clears selection', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final movable = CanvasObject(
      id: 'shape-movable',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -100, y: -40, width: 120, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final locked = CanvasObject(
      id: 'shape-locked',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 100, y: 40, width: 120, height: 80),
      isLocked: true,
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:keyboard',
      kind: CanvasBoardKind.project,
      title: 'Keyboard',
      objects: <CanvasObject>[movable, locked],
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectUpdated: (object) {
                setState(() => board = board.replaceObject(object));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final canvasState = tester.state<MindmapCanvasState>(
      find.byType(MindmapCanvas),
    );
    canvasState.selectCanvasObject(movable.id);
    await tester.pump();
    expect(canvasState.selectedCanvasObjectIds, contains(movable.id));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(board.objectById(movable.id)!.geometry.x, -99);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(board.objectById(movable.id)!.geometry.y, -30);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(board.objectById(movable.id)!.geometry.x, -99);

    canvasState.selectCanvasObject(locked.id);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(board.objectById(locked.id)!.geometry.x, 100);
  });

  testWidgets('inactive voting hides vote actions', (tester) async {
    final now = DateTime(2026, 7, 28);
    final shape = CanvasObject(
      id: 'shape-vote',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -80, y: -40, width: 160, height: 100),
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'project:voting',
      kind: CanvasBoardKind.project,
      title: 'Voting',
      objects: <CanvasObject>[shape],
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(nodes: const <MindmapNode>[], board: board),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<MindmapCanvasState>(find.byType(MindmapCanvas))
        .selectCanvasObject(shape.id);
    await tester.pump();
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-actions')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add vote'), findsNothing);
    expect(find.text('Remove vote'), findsNothing);
  });

  testWidgets('active voting hides vote actions without workshop permission', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final shape = CanvasObject(
      id: 'shape-vote',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -80, y: -40, width: 160, height: 100),
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'project:voting',
      kind: CanvasBoardKind.project,
      title: 'Voting',
      objects: <CanvasObject>[shape],
      votingSession: CanvasVotingSession(
        sessionId: 'vote-session',
        status: CanvasVotingStatus.active,
      ),
      createdAt: now,
      updatedAt: now,
    );
    final workshopSession = CanvasWorkshopSession().startAgenda(
      sessionId: 'workshop-session',
      hostUid: 'host',
      now: now,
      agenda: <CanvasWorkshopStage>[
        CanvasWorkshopStage(
          id: 'review',
          title: 'Review',
          type: CanvasWorkshopStageType.review,
          durationSeconds: 120,
        ),
      ],
      baselineObjectVersions: const <String, String>{},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const <MindmapNode>[],
            board: board,
            workshopSession: workshopSession,
            workshopViewerUid: 'viewer',
            votingParticipantId: 'viewer',
            onCanvasVoteChanged: (objects, delta) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<MindmapCanvasState>(find.byType(MindmapCanvas))
        .selectCanvasObject(shape.id);
    await tester.pump();
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-actions')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add vote'), findsNothing);
    expect(find.text('Remove vote'), findsNothing);
  });

  testWidgets('active voting toggles only local vote and marks it concealed', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final shape = CanvasObject(
      id: 'shape-vote',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -80, y: -40, width: 160, height: 100),
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:voting',
      kind: CanvasBoardKind.project,
      title: 'Voting',
      objects: <CanvasObject>[shape],
      votingSession: CanvasVotingSession(
        sessionId: 'session',
        status: CanvasVotingStatus.active,
        resultsRevealed: false,
        allocations: const <String, Set<String>>{
          'other': <String>{'shape-vote'},
        },
      ),
      createdAt: now,
      updatedAt: now,
    );
    final changes = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              votingParticipantId: 'local-user',
              onCanvasVoteChanged: (objects, delta) {
                changes.add(delta);
                setState(() {
                  board = board.copyWith(
                    votingSession: board.votingSession.changeVote(
                      participantId: 'local-user',
                      objectId: objects.single.id,
                      add: delta > 0,
                    ),
                  );
                });
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<MindmapCanvasState>(find.byType(MindmapCanvas))
        .selectCanvasObject(shape.id);
    await tester.pump();
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-actions')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add vote'), findsOneWidget);
    expect(find.text('Remove vote'), findsNothing);
    await tester.tap(find.text('Add vote'));
    await tester.pumpAndSettle();

    expect(changes, <int>[1]);
    expect(find.text('Your vote'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('canvas-object-votes-shape-vote')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-actions')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add vote'), findsNothing);
    expect(find.text('Remove vote'), findsOneWidget);
    await tester.tap(find.text('Remove vote'));
    await tester.pumpAndSettle();

    expect(changes, <int>[1, -1]);
    expect(board.votingSession.hasVote('other', shape.id), isTrue);
    expect(board.votingSession.hasVote('local-user', shape.id), isFalse);
    expect(find.text('Your vote'), findsNothing);
  });

  testWidgets('revealed voting shows local marker and total once', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final shape = CanvasObject(
      id: 'shape-vote',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -80, y: -40, width: 160, height: 100),
      payload: <String, Object?>{
        'comments': <Map<String, Object?>>[
          CanvasObjectComment(
            id: 'comment',
            authorName: 'Author',
            body: 'Open',
            createdAt: now,
          ).toJson(),
        ],
      },
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'project:voting',
      kind: CanvasBoardKind.project,
      title: 'Voting',
      objects: <CanvasObject>[shape],
      votingSession: CanvasVotingSession(
        sessionId: 'session',
        status: CanvasVotingStatus.active,
        allocations: const <String, Set<String>>{
          'local-user': <String>{'shape-vote'},
          'other': <String>{'shape-vote'},
        },
      ),
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const <MindmapNode>[],
            board: board,
            votingParticipantId: 'local-user',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your vote'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('canvas-object-votes-shape-vote')),
      findsOneWidget,
    );
    expect(
      tester
          .getRect(find.text('Your vote'))
          .overlaps(
            tester.getRect(
              find.byKey(const ValueKey('canvas-object-comments-shape-vote')),
            ),
          ),
      isFalse,
    );
  });

  testWidgets(
    'narrow object keeps vote and comment badges bounded and separate',
    (tester) async {
      final now = DateTime(2026, 7, 28);
      final shape = CanvasObject(
        id: 'narrow-vote',
        type: CanvasObjectType.shape,
        geometry: const CanvasGeometry(x: -40, y: -40, width: 80, height: 100),
        payload: <String, Object?>{
          'comments': <Map<String, Object?>>[
            CanvasObjectComment(
              id: 'comment',
              authorName: 'Author',
              body: 'Open',
              createdAt: now,
            ).toJson(),
          ],
        },
        createdAt: now,
        updatedAt: now,
      );
      final board = CanvasBoard(
        id: 'project:narrow-voting',
        kind: CanvasBoardKind.project,
        title: 'Narrow voting',
        objects: <CanvasObject>[shape],
        votingSession: CanvasVotingSession(
          sessionId: 'session',
          status: CanvasVotingStatus.active,
          allocations: const <String, Set<String>>{
            'local-user': <String>{'narrow-vote'},
            'other': <String>{'narrow-vote'},
          },
        ),
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              votingParticipantId: 'local-user',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final objectRect = tester.getRect(
        find.byKey(const ValueKey('canvas-object-semantics-narrow-vote')),
      );
      final badgeRects = <Rect>[
        tester.getRect(
          find.byKey(const ValueKey('canvas-object-your-vote-narrow-vote')),
        ),
        tester.getRect(
          find.byKey(const ValueKey('canvas-object-votes-narrow-vote')),
        ),
        tester.getRect(
          find.byKey(const ValueKey('canvas-object-comments-narrow-vote')),
        ),
      ];
      for (final badgeRect in badgeRects) {
        expect(badgeRect.left, greaterThanOrEqualTo(objectRect.left));
        expect(badgeRect.top, greaterThanOrEqualTo(objectRect.top));
        expect(badgeRect.right, lessThanOrEqualTo(objectRect.right));
        expect(badgeRect.bottom, lessThanOrEqualTo(objectRect.bottom));
      }
      for (var first = 0; first < badgeRects.length; first++) {
        for (var second = first + 1; second < badgeRects.length; second++) {
          expect(badgeRects[first].overlaps(badgeRects[second]), isFalse);
        }
      }
    },
  );

  testWidgets('native object comments support reply and resolve', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final shape = CanvasObject(
      id: 'shape-comment',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -80, y: -40, width: 160, height: 100),
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'project:comments',
      kind: CanvasBoardKind.project,
      title: 'Comments',
      objects: <CanvasObject>[shape],
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              onCanvasObjectsUpdated: (objects) {
                setState(() {
                  for (final object in objects) {
                    board = board.replaceObject(object);
                  }
                });
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<MindmapCanvasState>(find.byType(MindmapCanvas))
        .selectCanvasObject(shape.id);
    await tester.pump();
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-actions')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('mindmap-canvas-object-comments')),
    );
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-comments')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('canvas-comment-composer-0')),
      'Please review',
    );
    await tester.tap(find.byKey(const ValueKey('canvas-comment-send')));
    await tester.pumpAndSettle();
    expect(board.objectById(shape.id)!.comments, hasLength(1));
    expect(board.objectById(shape.id)!.openCommentCount, 1);
    expect(find.text('Please review'), findsOneWidget);

    final root = board.objectById(shape.id)!.comments.single;
    await tester.tap(find.byKey(ValueKey('canvas-comment-reply-${root.id}')));
    await tester.enterText(
      find.byKey(const ValueKey('canvas-comment-composer-1')),
      'Reviewed',
    );
    await tester.tap(find.byKey(const ValueKey('canvas-comment-send')));
    await tester.pumpAndSettle();
    expect(board.objectById(shape.id)!.comments, hasLength(2));
    expect(find.text('You: Reviewed'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('canvas-comment-resolve-${root.id}')));
    await tester.pumpAndSettle();
    expect(board.objectById(shape.id)!.openCommentCount, 0);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('canvas-object-comments-shape-comment')),
      findsNothing,
    );
  });

  testWidgets('collaboration comments persist without mutating board objects', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 28);
    final shape = CanvasObject(
      id: 'shape-collaboration-comment',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: -80, y: -40, width: 160, height: 100),
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'project:collaboration-comments',
      kind: CanvasBoardKind.project,
      title: 'Collaboration comments',
      objects: <CanvasObject>[shape],
      createdAt: now,
      updatedAt: now,
    );
    var comments = const <String, List<CanvasObjectComment>>{};
    var boardMutationCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: board,
              collaborationBoardComments: comments,
              onCollaborationBoardCommentsChanged: (objectId, nextComments) {
                setState(() {
                  comments = <String, List<CanvasObjectComment>>{
                    ...comments,
                    objectId: nextComments,
                  };
                });
              },
              onCanvasObjectsUpdated: (_) => boardMutationCount += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .state<MindmapCanvasState>(find.byType(MindmapCanvas))
        .selectCanvasObject(shape.id);
    await tester.pump();
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-actions')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('mindmap-canvas-object-comments')),
    );
    await tester.tap(
      find.byKey(const ValueKey('mindmap-canvas-object-comments')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('canvas-comment-composer-0')),
      'Remote review',
    );
    await tester.tap(find.byKey(const ValueKey('canvas-comment-send')));
    await tester.pumpAndSettle();

    expect(comments[shape.id], hasLength(1));
    expect(comments[shape.id]!.single.body, 'Remote review');
    expect(board.objectById(shape.id)!.comments, isEmpty);
    expect(boardMutationCount, 0);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('canvas-object-comments-shape-collaboration-comment'),
      ),
      findsOneWidget,
    );
  });
}

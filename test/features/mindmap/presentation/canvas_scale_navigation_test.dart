import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/canvas_workshop.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';
import 'package:var_app/features/mindmap/presentation/node_shell.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  CanvasObject sticky(String id, String text, double x, {double y = 0}) {
    final now = DateTime(2026, 7, 29);
    return CanvasObject(
      id: id,
      type: CanvasObjectType.stickyNote,
      geometry: CanvasGeometry(x: x, y: y, width: 180, height: 120),
      payload: <String, Object?>{'text': text},
      createdAt: now,
      updatedAt: now,
    );
  }

  CanvasBoard boardWith(
    List<CanvasObject> objects, {
    CanvasViewport? viewport,
  }) {
    final now = DateTime(2026, 7, 29);
    return CanvasBoard(
      id: 'scale-board',
      kind: CanvasBoardKind.project,
      title: 'Scale board',
      viewport: viewport ?? const CanvasViewport(),
      objects: objects,
      createdAt: now,
      updatedAt: now,
    );
  }

  testWidgets('search lists and focuses native canvas objects', (tester) async {
    final board = boardWith(<CanvasObject>[
      sticky('research', 'Customer evidence', 0),
      sticky('other', 'Roadmap', 320),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 900,
            child: MindmapCanvas(nodes: const <MindmapNode>[], board: board),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'customer evidence');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-search-result-object:research')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('canvas-object-research')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('canvas-object-other')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('mindmap-search-result-object:research')),
    );
    await tester.pumpAndSettle();

    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('canvas-object-semantics-research')),
    );
    expect(
      semantics.getSemanticsData().flagsCollection.isSelected.name,
      'isTrue',
    );
  });

  testWidgets(
    'legacy object beyond old right bottom edge renders and selects',
    (tester) async {
      final key = GlobalKey<MindmapCanvasState>();
      final board = boardWith(<CanvasObject>[
        sticky('outside', 'Outside', 10100, y: 7100),
      ], viewport: const CanvasViewport(x: 10200, y: 7160));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: MindmapCanvas(
                key: key,
                nodes: const <MindmapNode>[],
                board: board,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final outside = find.byKey(const ValueKey('canvas-object-outside'));
      expect(outside, findsOneWidget);
      expect(outside.hitTestable(), findsOneWidget);
      await tester.tap(outside);
      await tester.pump(const Duration(milliseconds: 400));
      expect(key.currentState!.selectedCanvasObjectIds, <String>{'outside'});
      expect(key.currentState!.currentViewport.x, closeTo(10200, 0.1));
      expect(key.currentState!.currentViewport.y, closeTo(7160, 0.1));
    },
  );

  testWidgets('legacy left top object keeps restored world viewport', (
    tester,
  ) async {
    final key = GlobalKey<MindmapCanvasState>();
    final board = boardWith(<CanvasObject>[
      sticky('outside-left', 'Outside left', -10800, y: -7800),
    ], viewport: const CanvasViewport(x: -10600, y: -7600, scale: 0.8));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: MindmapCanvas(
              key: key,
              nodes: const <MindmapNode>[],
              board: board,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('canvas-object-outside-left')).hitTestable(),
      findsOneWidget,
    );
    expect(key.currentState!.currentViewport.x, closeTo(-10600, 0.1));
    expect(key.currentState!.currentViewport.y, closeTo(-7600, 0.1));
    expect(key.currentState!.currentViewport.scale, closeTo(0.8, 0.001));
  });

  testWidgets('legacy custom node size expands scene beyond right edge', (
    tester,
  ) async {
    final day = DateTime(2026, 8, 2);
    final node = MindmapNode.create(
      id: 'outside-node',
      type: NodeType.note,
      title: 'Outside node',
      day: day,
      position: const CanvasPosition(9700, 0),
      data: const <String, Object?>{
        'uiSizePreset': 'custom',
        'uiWidth': 780.0,
        'uiHeight': 420.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            board: boardWith(
              const <CanvasObject>[],
              viewport: const CanvasViewport(x: 10100),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mindmap-node-outside-node')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mindmap-node-outside-node'))),
      const Size(780, 420),
    );
  });

  testWidgets('updated custom node size expands scene using new size', (
    tester,
  ) async {
    final key = GlobalKey<MindmapCanvasState>();
    final day = DateTime(2026, 8, 2);
    var width = 300.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              final node = MindmapNode.create(
                id: 'growing-node',
                type: NodeType.note,
                title: 'Growing node',
                day: day,
                position: const CanvasPosition(9000, 0),
                data: <String, Object?>{
                  'uiSizePreset': 'custom',
                  'uiWidth': width,
                  'uiHeight': 300.0,
                },
                now: day,
              );
              return Column(
                children: <Widget>[
                  TextButton(
                    onPressed: () => setState(() => width = 780),
                    child: const Text('Grow'),
                  ),
                  Expanded(
                    child: MindmapCanvas(
                      key: key,
                      nodes: <MindmapNode>[node],
                      board: boardWith(const <CanvasObject>[]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.sceneWorldBounds.right, 10000);

    await tester.tap(find.text('Grow'));
    await tester.pumpAndSettle();

    expect(key.currentState!.sceneWorldBounds.right, 12000);
  });

  testWidgets('keyboard nudge expands scene without parent rebuild', (
    tester,
  ) async {
    final key = GlobalKey<MindmapCanvasState>();
    final board = boardWith(<CanvasObject>[
      sticky('edge-nudge', 'Edge', -9400),
    ], viewport: const CanvasViewport(x: -9300));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: const <MindmapNode>[],
            board: board,
            onCanvasObjectUpdated: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.selectCanvasObject('edge-nudge');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 100));

    expect(key.currentState!.sceneWorldBounds.left, -12000);
    expect(
      find.byKey(const ValueKey('canvas-object-edge-nudge')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('minimap bounds include live native and node overrides', (
    tester,
  ) async {
    final key = GlobalKey<MindmapCanvasState>();
    final day = DateTime(2026, 8, 2);
    final node = MindmapNode.create(
      id: 'live-node',
      type: NodeType.note,
      title: 'Live node',
      day: day,
      position: const CanvasPosition(0, 0),
      now: day,
    );
    final board = boardWith(<CanvasObject>[
      sticky('live-object', 'Live object', -10800, y: -7800),
    ], viewport: const CanvasViewport(x: -10600, y: -7600));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: <MindmapNode>[node],
            board: board,
            onCanvasObjectUpdated: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bounds = key.currentState!.minimapWorldBoundsForTest();
    expect(bounds.left, lessThanOrEqualTo(-10800));
    expect(bounds.top, lessThanOrEqualTo(-7800));
    expect(bounds.right, greaterThanOrEqualTo(340));
  });

  testWidgets('heavy canvas culls offscreen objects', (tester) async {
    final objects = <CanvasObject>[
      sticky('visible', 'Visible', 0),
      for (var index = 1; index < 1000; index++)
        sticky('far-$index', 'Far $index', 7000.0 + index, y: 5000),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: boardWith(objects),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('canvas-object-visible')), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-object-far-999')), findsNothing);
  });

  testWidgets('restores and emits viewport changes with epsilon debounce', (
    tester,
  ) async {
    final key = GlobalKey<MindmapCanvasState>();
    final emitted = <CanvasViewport>[];
    final board = boardWith(<CanvasObject>[
      sticky('one', 'One', 0),
    ], viewport: const CanvasViewport(x: 420, y: -180, scale: 0.8));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: MindmapCanvas(
              key: key,
              nodes: const <MindmapNode>[],
              board: board,
              onViewportChanged: emitted.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    emitted.clear();

    expect(key.currentState!.currentViewport.x, closeTo(420, 0.01));
    expect(key.currentState!.currentViewport.y, closeTo(-180, 0.01));
    expect(key.currentState!.currentViewport.scale, closeTo(0.8, 0.001));

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final controller = viewer.transformationController!;
    controller.value = Matrix4.translationValues(10, 0, 0);
    controller.value = Matrix4.translationValues(20, 0, 0);
    controller.value = Matrix4.translationValues(30, 0, 0);
    await tester.pump(const Duration(milliseconds: 500));

    expect(emitted, hasLength(1));
    final last = emitted.single;
    controller.value = Matrix4.translationValues(30.001, 0, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(emitted, hasLength(1));
    expect(emitted.single, last);
  });

  testWidgets('Ctrl+Arrow navigates spatially across canvas objects', (
    tester,
  ) async {
    final key = GlobalKey<MindmapCanvasState>();
    final board = boardWith(<CanvasObject>[
      sticky('left', 'Left', -280),
      sticky('right', 'Right', 280),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: const <MindmapNode>[],
            board: board,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('canvas-object-left')));
    await tester.pump(const Duration(milliseconds: 400));
    final target = key.currentState!.navigateSpatially(
      LogicalKeyboardKey.arrowRight,
    );
    expect(key.currentState!.selectedCanvasObjectIds, <String>{'right'});
    await tester.pumpAndSettle();

    expect(target, 'object:right');
    expect(key.currentState!.selectedCanvasObjectIds, <String>{'right'});
  });

  testWidgets('canvas controls and minimap share bottom alignment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const <MindmapNode>[],
            board: boardWith(<CanvasObject>[sticky('one', 'One', 0)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final controls = find.byTooltip('Show canvas controls');
    final minimap = find.byKey(const ValueKey('mindmap-minimap-anchor'));
    final controlsRect = tester.getRect(controls);
    final minimapRect = tester.getRect(minimap);

    expect(minimapRect.bottom, closeTo(controlsRect.bottom, 0.1));
    expect(minimapRect.right, closeTo(984, 0.1));
    expect(controlsRect.right, lessThan(minimapRect.left));
  });

  testWidgets('minimap keeps bottom-right anchor while expanding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const <MindmapNode>[],
            board: boardWith(<CanvasObject>[sticky('one', 'One', 0)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final anchor = find.byKey(const ValueKey('mindmap-minimap-anchor'));
    final collapsedBottomRight = tester.getBottomRight(anchor);
    await tester.tap(find.byTooltip('Show minimap'));
    await tester.pumpAndSettle();
    final expandedBottomRight = tester.getBottomRight(anchor);

    expect(expandedBottomRight.dx, closeTo(collapsedBottomRight.dx, 0.1));
    expect(expandedBottomRight.dy, closeTo(collapsedBottomRight.dy, 0.1));
  });

  testWidgets('mobile minimap uses adaptive compact size', (tester) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const <MindmapNode>[],
            board: boardWith(<CanvasObject>[sticky('one', 'One', 0)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show minimap'));
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const ValueKey('mindmap-minimap-semantics'))),
      const Size(134, 94),
    );
  });

  testWidgets('reduced motion focuses search result without animation', (
    tester,
  ) async {
    final key = GlobalKey<MindmapCanvasState>();
    final board = boardWith(<CanvasObject>[
      sticky('target', 'Target item', 900, y: 400),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: MindmapCanvas(
              key: key,
              nodes: const <MindmapNode>[],
              board: board,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    key.currentState!.navigateSpatially(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(key.currentState!.currentViewport.x, greaterThan(800));
  });

  testWidgets(
    'native drag beyond left top old edge stays selectable and drags back',
    (tester) async {
      final key = GlobalKey<MindmapCanvasState>();
      var board = boardWith(<CanvasObject>[
        sticky('native-left', 'Left', -9800, y: -6800),
      ], viewport: const CanvasViewport(x: -9700, y: -6700));
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
      final object = find.byKey(const ValueKey('canvas-object-native-left'));
      final before = board.objectById('native-left')!.geometry;
      await tester.dragFrom(
        tester.getCenter(object),
        const Offset(-320, -220),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final outside = board.objectById('native-left')!.geometry;
      expect(outside.x, lessThan(-10000));
      expect(outside.y, lessThan(0));
      expect(object.hitTestable(), findsOneWidget);
      await tester.tapAt(tester.getCenter(object));
      await tester.pump();
      expect(key.currentState!.selectedCanvasObjectIds, <String>{
        'native-left',
      });
      await tester.dragFrom(
        tester.getCenter(object),
        const Offset(320, 220),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final returned = board.objectById('native-left')!.geometry;
      expect(returned.x, closeTo(before.x, 1));
      expect(returned.y, closeTo(before.y, 1));
    },
  );

  testWidgets('native drag beyond right bottom old edge selects directly', (
    tester,
  ) async {
    final key = GlobalKey<MindmapCanvasState>();
    var board = boardWith(<CanvasObject>[
      sticky('native-right', 'Right', 9700, y: 6700),
    ], viewport: const CanvasViewport(x: 9800, y: 6800));
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
    final object = find.byKey(const ValueKey('canvas-object-native-right'));
    await tester.dragFrom(
      tester.getCenter(object),
      const Offset(220, 220),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final geometry = board.objectById('native-right')!.geometry;
    expect(geometry.x + geometry.width, greaterThan(10000));
    expect(geometry.y + geometry.height, greaterThan(7000));
    expect(object.hitTestable(), findsOneWidget);
    await tester.tapAt(tester.getCenter(object));
    await tester.pump(const Duration(milliseconds: 50));
    expect(key.currentState!.selectedCanvasObjectIds, <String>{'native-right'});
  });

  testWidgets('node drag outside old bounds stays selectable and draggable', (
    tester,
  ) async {
    final day = DateTime(2026, 8, 2);
    var node = MindmapNode.create(
      id: 'drag-outside-node',
      type: NodeType.note,
      title: 'Outside node',
      day: day,
      position: const CanvasPosition(9700, 6700),
      now: day,
    );
    var selections = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: <MindmapNode>[node],
              board: boardWith(
                const <CanvasObject>[],
                viewport: const CanvasViewport(x: 9800, y: 6800),
              ),
              onNodeSelected: (_) => selections++,
              onNodeMoved: (source, position) =>
                  setState(() => node = source.copyWith(position: position)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final nodeFinder = find.byKey(
      const ValueKey('mindmap-node-drag-outside-node'),
    );
    await tester.dragFrom(
      tester.getCenter(nodeFinder),
      const Offset(40, 40),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final outsideSize = tester.getSize(nodeFinder);
    expect(node.position.dx + outsideSize.width, greaterThan(10000));
    expect(node.position.dy + outsideSize.height, greaterThan(7000));
    expect(nodeFinder.hitTestable(), findsOneWidget);
    await tester.tapAt(tester.getCenter(nodeFinder));
    await tester.pump();
    expect(selections, greaterThan(0));
    final outside = node.position;
    await tester.dragFrom(
      tester.getCenter(nodeFinder),
      const Offset(-120, -80),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(node.position.dx, lessThan(outside.dx));
    expect(node.position.dy, lessThan(outside.dy));
  });

  testWidgets('native and node resize expand hit test scene', (tester) async {
    final key = GlobalKey<MindmapCanvasState>();
    final day = DateTime(2026, 8, 2);
    var node = MindmapNode.create(
      id: 'resize-node',
      type: NodeType.note,
      title: 'Resize node',
      day: day,
      position: const CanvasPosition(9500, 100),
      now: day,
    );
    var board = boardWith(<CanvasObject>[
      sticky('resize-native', 'Resize', 9500),
    ], viewport: const CanvasViewport(x: 9700, y: 200));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              key: key,
              nodes: <MindmapNode>[node],
              board: board,
              highlightedNodeId: node.id,
              onCanvasObjectUpdated: (object) =>
                  setState(() => board = board.replaceObject(object)),
              onNodeResize: (source, change) => setState(() {
                node = source.copyWith(
                  data: <String, Object?>{
                    ...source.data,
                    'uiSizePreset': 'custom',
                    'uiWidth': change.size.width,
                    'uiHeight': change.size.height,
                  },
                );
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final native = find.byKey(const ValueKey('canvas-object-resize-native'));
    await tester.tap(native);
    await tester.pump();
    final nativeResize = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('canvas-object-resize-resize-native')),
    );
    nativeResize.onPanUpdate!(
      DragUpdateDetails(
        globalPosition: const Offset(900, 0),
        delta: const Offset(900, 0),
      ),
    );
    nativeResize.onPanEnd!(DragEndDetails());
    await tester.pumpAndSettle();
    expect(key.currentState!.sceneWorldBounds.right, greaterThan(10000));
    expect(native.hitTestable(), findsOneWidget);

    final nodeFinder = find.byKey(const ValueKey('mindmap-node-resize-node'));
    final nodeShell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    nodeShell.onResizeChanged!(
      const NodeResizeChange(
        size: Size(1300, 320),
        positionDelta: Offset.zero,
        preset: NodeSizePreset.custom,
        phase: NodeResizePhase.commit,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      key.currentState!.sceneWorldBounds.right,
      greaterThanOrEqualTo(12000),
    );
    expect(nodeFinder.hitTestable(), findsOneWidget);
  });

  testWidgets(
    'left top expansion preserves world center and emitted viewport',
    (tester) async {
      final key = GlobalKey<MindmapCanvasState>();
      final emitted = <CanvasViewport>[];
      var board = boardWith(<CanvasObject>[
        sticky('viewport-left', 'Left', -9700, y: -6800),
      ], viewport: const CanvasViewport(x: -9600, y: -6700));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MindmapCanvas(
                key: key,
                nodes: const <MindmapNode>[],
                board: board,
                onViewportChanged: emitted.add,
                onCanvasObjectUpdated: (object) =>
                    setState(() => board = board.replaceObject(object)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = key.currentState!.currentViewport;
      final object = find.byKey(const ValueKey('canvas-object-viewport-left'));
      await tester.dragFrom(
        tester.getCenter(object),
        const Offset(-320, -220),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final after = key.currentState!.currentViewport;
      expect(after.x, closeTo(before.x, 0.1));
      expect(after.y, closeTo(before.y, 0.1));
      await tester.tap(find.byTooltip('Show canvas controls'));
      await tester.pump();
      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(emitted, isNotEmpty);
      expect(emitted.last.x, closeTo(after.x, 0.1));
      expect(emitted.last.y, closeTo(after.y, 0.1));
    },
  );

  testWidgets('minimap click maps target after left top origin shift', (
    tester,
  ) async {
    final key = GlobalKey<MindmapCanvasState>();
    final board = boardWith(<CanvasObject>[
      sticky('minimap-left', 'Left target', -10800, y: -7800),
      sticky('minimap-right', 'Right target', 800, y: 400),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: const <MindmapNode>[],
            board: board,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show minimap'));
    await tester.pumpAndSettle();
    final minimap = find.byKey(const ValueKey('mindmap-minimap-semantics'));
    final semantics = tester.getSemantics(minimap);
    expect(semantics.label, contains('2 canvas objects'));
    expect(semantics.label, contains('Tap to move viewport'));
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    final rect = tester.getRect(minimap);
    await tester.tapAt(Offset(rect.right - 4, rect.bottom - 4));
    await tester.pumpAndSettle();
    expect(key.currentState!.currentViewport.x, greaterThan(0));
    expect(key.currentState!.currentViewport.y, greaterThan(0));
  });

  testWidgets('private workshop objects stay hidden until reveal', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 7, 29, 9);
    final stage = CanvasWorkshopStage(
      id: 'ideas',
      title: 'Ideas',
      type: CanvasWorkshopStageType.brainstorm,
      durationSeconds: 300,
    );
    var session = CanvasWorkshopSession().startAgenda(
      sessionId: 'session',
      hostUid: 'owner',
      now: start,
      agenda: <CanvasWorkshopStage>[stage],
      baselineObjectVersions: const <String, String>{},
    );
    final privateObject = sticky('private', 'Secret proposal', 0).copyWith(
      payload: const <String, Object?>{
        'text': 'Secret proposal',
        'workshopPrivate': true,
        'workshopStageId': 'ideas',
        'workshopAuthorUid': 'editor-a',
      },
    );
    final board = boardWith(<CanvasObject>[privateObject]);

    Future<void> pumpFor(String viewerUid, {bool isHost = false}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MindmapCanvas(
                nodes: const <MindmapNode>[],
                board: board,
                workshopSession: session,
                workshopViewerUid: viewerUid,
                isWorkshopHost: isHost,
              ),
            ),
          ),
        );

    await pumpFor('editor-b');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('canvas-object-private')), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'secret proposal');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mindmap-search-result-object:private')),
      findsNothing,
    );

    await pumpFor('editor-a');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('canvas-object-private')), findsOneWidget);

    session = session.revealActiveStage();
    await pumpFor('editor-b');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('canvas-object-private')), findsOneWidget);
  });
}

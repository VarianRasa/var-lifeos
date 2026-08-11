import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .views
        .first
        .physicalSize = const Size(
      1400,
      900,
    );
    TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .views
            .first
            .devicePixelRatio =
        1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetPhysicalSize();
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetDevicePixelRatio();
  });

  Future<void> invokeLayout(
    WidgetTester tester, {
    required String label,
  }) async {
    await tester.pump();
    await tester.tap(find.byTooltip('Arrange selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('mixed horizontal align uses node and native object bounds', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: <MindmapNode>[_node('node', const CanvasPosition(0, 0))],
      objects: <CanvasObject>[
        _nodeReference('node', x: 0, y: 0, width: 100, height: 120),
        _shape('shape', x: 220, y: 160, width: 80, height: 40),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();

    await invokeLayout(tester, label: 'Align horizontal');

    expect(harness.nodes.single.position.dy, 40);
    expect(harness.board.objectById('shape')!.geometry.y, 80);
  });

  testWidgets('mixed vertical align uses node and native object bounds', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: <MindmapNode>[_node('node', const CanvasPosition(0, 0))],
      objects: <CanvasObject>[
        _nodeReference('node', x: 0, y: 0, width: 100, height: 120),
        _shape('shape', x: 220, y: 160, width: 80, height: 40),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();

    await invokeLayout(tester, label: 'Align vertical');

    expect(harness.nodes.single.position.dx, 100);
    expect(harness.board.objectById('shape')!.geometry.x, 110);
  });

  testWidgets('mixed distribute uses combined effective geometry', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: <MindmapNode>[
        _node('first', const CanvasPosition(0, 0)),
        _node('last', const CanvasPosition(400, 0)),
      ],
      objects: <CanvasObject>[
        _nodeReference('first', x: 0, y: 0, width: 100, height: 120),
        _shape('middle', x: 140, y: 0, width: 80, height: 40),
        _nodeReference('last', x: 400, y: 0, width: 100, height: 120),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();

    await invokeLayout(tester, label: 'Distribute horizontal');

    expect(harness.board.objectById('middle')!.geometry.x, 210);
    expect(harness.nodes.first.position.dx, 0);
    expect(harness.nodes.last.position.dx, 400);
  });

  testWidgets('arrange hides when selected node cannot persist', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: <MindmapNode>[_node('node', const CanvasPosition(0, 0))],
      objects: <CanvasObject>[
        _nodeReference('node', x: 0, y: 0, width: 100, height: 120),
        _shape('shape', x: 220, y: 160, width: 80, height: 40),
      ],
      enableNodeMutations: false,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();

    expect(find.byTooltip('Arrange selected'), findsNothing);
  });

  testWidgets('arrange hides when selected mutable native cannot persist', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: <MindmapNode>[_node('node', const CanvasPosition(0, 0))],
      objects: <CanvasObject>[
        _nodeReference('node', x: 0, y: 0, width: 100, height: 120),
        _shape('shape', x: 220, y: 160, width: 80, height: 40),
      ],
      enableObjectMutations: false,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();

    expect(find.byTooltip('Arrange selected'), findsNothing);
  });

  testWidgets('mixed vertical distribute uses combined geometry', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: <MindmapNode>[
        _node('first', const CanvasPosition(0, 0)),
        _node('last', const CanvasPosition(0, 400)),
      ],
      objects: <CanvasObject>[
        _nodeReference('first', x: 0, y: 0, width: 100, height: 120),
        _shape('middle', x: 0, y: 140, width: 80, height: 40),
        _nodeReference('last', x: 0, y: 400, width: 100, height: 120),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();

    await invokeLayout(tester, label: 'Distribute vertical');

    expect(harness.board.objectById('middle')!.geometry.y, 240);
    expect(harness.nodes.first.position.dy, 0);
    expect(harness.nodes.last.position.dy, 400);
  });

  testWidgets('locked native object anchors distribution without moving', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: <MindmapNode>[
        _node('middle', const CanvasPosition(140, 0)),
        _node('last', const CanvasPosition(400, 0)),
      ],
      objects: <CanvasObject>[
        _nodeReference('middle', x: 140, y: 0, width: 100, height: 120),
        _shape('locked', x: 0, y: 0, width: 80, height: 40, locked: true),
        _nodeReference('last', x: 400, y: 0, width: 100, height: 120),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();

    await invokeLayout(tester, label: 'Distribute horizontal');

    expect(harness.nodes.first.position.dx, 190);
    expect(harness.nodes.last.position.dx, 400);
    expect(harness.board.objectById('locked')!.geometry.x, 0);
    expect(harness.objectUpdateCount, 0);
  });

  testWidgets('locked native object anchors mixed alignment without moving', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: <MindmapNode>[_node('node', const CanvasPosition(0, 0))],
      objects: <CanvasObject>[
        _nodeReference('node', x: 0, y: 0, width: 100, height: 120),
        _shape('locked', x: 300, y: 120, width: 80, height: 40, locked: true),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();

    await invokeLayout(tester, label: 'Align horizontal');

    expect(harness.nodes.single.position.dy, 20);
    expect(harness.board.objectById('locked')!.geometry.y, 120);
    expect(harness.objectUpdateCount, 0);
  });

  testWidgets('selection toolbar follows node object mixed action matrix', (
    tester,
  ) async {
    final node = _node('node', const CanvasPosition(0, 0));
    final secondNode = _node('node-2', const CanvasPosition(120, 0));
    final shape = _shape('shape', x: 220, y: 160, width: 80, height: 40);
    final harness = _Harness(
      nodes: <MindmapNode>[node, secondNode],
      objects: <CanvasObject>[
        _nodeReference('node', x: 0, y: 0, width: 100, height: 120),
        _nodeReference('node-2', x: 120, y: 0, width: 100, height: 120),
        shape,
        _shape('shape-2', x: 340, y: 160, width: 80, height: 40),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    await harness.key.currentState!.selectAndFocusNode(node);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await harness.key.currentState!.selectAndFocusNode(secondNode);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byTooltip('Set selected priority'), findsOneWidget);

    harness.key.currentState!.selectCanvasObject(shape.id);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    harness.key.currentState!.selectCanvasObject('shape-2');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byTooltip('Set selected priority'), findsNothing);
    expect(find.byTooltip('Object actions'), findsOneWidget);
    expect(find.byTooltip('Delete selected'), findsOneWidget);

    await harness.key.currentState!.selectAndFocusNode(node);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    harness.key.currentState!.selectCanvasObject(shape.id);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byTooltip('Set priority for 1 node'), findsOneWidget);
    expect(find.byTooltip('Object actions for 1 object'), findsOneWidget);
    expect(find.byTooltip('Copy selected'), findsOneWidget);
    expect(find.byTooltip('Delete selected'), findsOneWidget);
    expect(find.text('Group in frame'), findsOneWidget);
  });

  testWidgets('object-only Copy and Duplicate execute native behavior', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: const <MindmapNode>[],
      objects: <CanvasObject>[
        _shape('shape', x: 20, y: 40, width: 80, height: 60),
        _shape('shape-2', x: 160, y: 40, width: 80, height: 60),
      ],
    );
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
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();
    await tester.pump();

    await tester.tap(find.byTooltip('Copy selected'));
    await tester.pump();
    final copied = jsonDecode(clipboardText!) as Map<String, Object?>;
    expect(copied['nodes'], isEmpty);
    expect(copied['objects'], hasLength(2));

    await tester.tap(find.byTooltip('Object actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(harness.board.objects, hasLength(4));
    expect(harness.board.objects[2].geometry.x, 62);
    expect(harness.board.objects[3].geometry.x, 202);
  });

  testWidgets('node-only metadata and common actions execute', (tester) async {
    final harness = _Harness(
      nodes: <MindmapNode>[
        _node('node', const CanvasPosition(0, 0)),
        _node('node-2', const CanvasPosition(120, 0)),
      ],
      objects: const <CanvasObject>[],
    );
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
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();
    await tester.pump();

    await tester.tap(find.byTooltip('Set selected priority'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(NodePriority.high.label));
    await tester.pumpAndSettle();
    expect(
      harness.nodes.every((node) => node.priority == NodePriority.high),
      isTrue,
    );

    await tester.tap(find.byTooltip('Copy selected'));
    await tester.pump();
    final copied = jsonDecode(clipboardText!) as Map<String, Object?>;
    expect(copied['nodes'], hasLength(2));
    expect(copied['objects'], isEmpty);
  });

  testWidgets('capability-specific native and node actions stay hidden', (
    tester,
  ) async {
    final nodeHarness = _Harness(
      nodes: <MindmapNode>[
        _node('node', const CanvasPosition(0, 0)),
        _node('node-2', const CanvasPosition(120, 0)),
      ],
      objects: const <CanvasObject>[],
      enableNodeUpdates: false,
    );
    await tester.pumpWidget(nodeHarness.build());
    await tester.pumpAndSettle();
    await nodeHarness.selectAll();
    await tester.pump();
    expect(find.byTooltip('Set selected priority'), findsNothing);

    final objectHarness = _Harness(
      nodes: const <MindmapNode>[],
      objects: <CanvasObject>[
        _shape('shape', x: 20, y: 40, width: 80, height: 60),
        _shape('shape-2', x: 160, y: 40, width: 80, height: 60),
      ],
      enableObjectUpdates: false,
      enableObjectCreates: false,
    );
    await tester.pumpWidget(objectHarness.build());
    await tester.pumpAndSettle();
    await objectHarness.selectAll();
    await tester.pump();
    expect(find.byTooltip('Object properties'), findsNothing);
    expect(find.byTooltip('Object actions'), findsNothing);
    expect(find.byTooltip('Copy selected'), findsOneWidget);
  });

  testWidgets('mixed Group in frame dispatches real frame coordinator', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: <MindmapNode>[_node('node', const CanvasPosition(0, 0))],
      objects: <CanvasObject>[
        _nodeReference('node', x: 0, y: 0, width: 100, height: 120),
        _shape('shape', x: 220, y: 160, width: 80, height: 40),
      ],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();
    await tester.pump();

    await tester.tap(find.text('Group in frame'));
    await tester.pumpAndSettle();

    final frame = harness.board.objects.singleWhere(
      (object) => object.type == CanvasObjectType.frame,
    );
    expect(harness.nodes.single.data['groupId'], frame.id);
    expect(harness.board.objectById('shape')!.parentFrameId, frame.id);
  });

  testWidgets('unsupported actions are hidden instead of visible no-ops', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: <MindmapNode>[
        _node('node', const CanvasPosition(0, 0)),
        _node('node-2', const CanvasPosition(120, 0)),
      ],
      objects: <CanvasObject>[
        _shape('shape', x: 200, y: 100, width: 80, height: 40),
      ],
      enableMutations: false,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();
    await tester.pump();

    expect(find.byTooltip('Set selected priority'), findsNothing);
    expect(find.byTooltip('Object properties for 1 object'), findsNothing);
    expect(find.byTooltip('Object actions for 1 object'), findsNothing);
    expect(find.byTooltip('Arrange selected'), findsNothing);
    expect(find.text('Group in frame'), findsNothing);
    expect(find.byTooltip('Archive selected'), findsNothing);
    expect(find.byTooltip('Delete selected'), findsNothing);
    expect(find.byTooltip('Copy selected'), findsOneWidget);
  });

  testWidgets(
    'combined arrange hides when mutable node subset cannot persist',
    (tester) async {
      final harness = _Harness(
        nodes: <MindmapNode>[_node('node', const CanvasPosition(0, 0))],
        objects: <CanvasObject>[
          _shape('shape', x: 200, y: 100, width: 80, height: 40),
        ],
        enableNodeMutations: false,
        enableObjectMutations: true,
      );
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      await harness.selectAll();
      await tester.pump();

      expect(find.byTooltip('Arrange selected'), findsNothing);
    },
  );

  testWidgets('combined arrange uses locked native object as anchor', (
    tester,
  ) async {
    final harness = _Harness(
      nodes: <MindmapNode>[_node('node', const CanvasPosition(0, 0))],
      objects: <CanvasObject>[
        _shape('locked', x: 200, y: 100, width: 80, height: 40, locked: true),
      ],
      enableObjectMutations: false,
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();
    await tester.pump();

    expect(find.byTooltip('Arrange selected'), findsOneWidget);
  });

  testWidgets('mixed multi-selection drags nodes and native objects together', (
    WidgetTester tester,
  ) async {
    final harness = _Harness(
      nodes: [_node('node-a', const CanvasPosition(100, 100))],
      objects: [_shape('obj-a', x: 300, y: 100, width: 100, height: 50)],
    );
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    await harness.selectAll();
    await tester.pump();

    expect(find.text('1 node + 1 object selected'), findsOneWidget);

    final nodeFinder = find.text('node-a');
    expect(nodeFinder, findsOneWidget);

    await tester.drag(nodeFinder, const Offset(50, 50));
    await tester.pumpAndSettle();

    expect(harness.nodes.first.position.dx, greaterThan(100));
    expect(harness.board.objects.first.geometry.x, greaterThan(300));
  });

  testWidgets('Group in frame requires every selected membership path', (
    tester,
  ) async {
    final objects = <CanvasObject>[
      _shape('shape', x: 200, y: 100, width: 80, height: 40),
    ];
    for (final capabilities in <(bool, bool, bool)>[
      (false, true, true),
      (true, false, true),
      (true, true, false),
    ]) {
      final harness = _Harness(
        nodes: <MindmapNode>[_node('node', const CanvasPosition(0, 0))],
        objects: objects,
        enableNodeUpdates: capabilities.$1,
        enableObjectCreates: capabilities.$2,
        enableObjectUpdates: capabilities.$3,
      );
      await tester.pumpWidget(harness.build());
      await tester.pumpAndSettle();
      await harness.selectAll();
      await tester.pump();

      expect(find.text('Group in frame'), findsNothing);
    }
  });
}

MindmapNode _node(String id, CanvasPosition position) {
  final now = DateTime(2026, 8, 2);
  return MindmapNode.create(
    id: id,
    type: NodeType.note,
    title: id,
    day: now,
    position: position,
    now: now,
  );
}

CanvasObject _nodeReference(
  String nodeId, {
  required double x,
  required double y,
  required double width,
  required double height,
}) {
  final now = DateTime(2026, 8, 2);
  return CanvasObject(
    id: 'node:$nodeId',
    type: CanvasObjectType.nodeReference,
    geometry: CanvasGeometry(x: x, y: y, width: width, height: height),
    mindmapNodeId: nodeId,
    createdAt: now,
    updatedAt: now,
  );
}

CanvasObject _shape(
  String id, {
  required double x,
  required double y,
  required double width,
  required double height,
  bool locked = false,
}) {
  final now = DateTime(2026, 8, 2);
  return CanvasObject(
    id: id,
    type: CanvasObjectType.shape,
    geometry: CanvasGeometry(x: x, y: y, width: width, height: height),
    isLocked: locked,
    createdAt: now,
    updatedAt: now,
  );
}

class _Harness {
  _Harness({
    required this.nodes,
    required List<CanvasObject> objects,
    bool enableMutations = true,
    bool? enableNodeMutations,
    bool? enableObjectMutations,
    bool? enableNodeUpdates,
    bool? enableObjectCreates,
    bool? enableObjectUpdates,
  }) : enableNodeMutations = enableNodeMutations ?? enableMutations,
       enableObjectMutations = enableObjectMutations ?? enableMutations,
       enableNodeUpdates =
           enableNodeUpdates ?? enableNodeMutations ?? enableMutations,
       enableObjectCreates =
           enableObjectCreates ?? enableObjectMutations ?? enableMutations,
       enableObjectUpdates =
           enableObjectUpdates ?? enableObjectMutations ?? enableMutations,
       board = CanvasBoard(
         id: 'project:mixed-layout',
         kind: CanvasBoardKind.project,
         title: 'Mixed layout',
         objects: objects,
         createdAt: DateTime(2026, 8, 2),
         updatedAt: DateTime(2026, 8, 2),
       );

  final GlobalKey<MindmapCanvasState> key = GlobalKey<MindmapCanvasState>();
  final bool enableNodeMutations;
  final bool enableObjectMutations;
  final bool enableNodeUpdates;
  final bool enableObjectCreates;
  final bool enableObjectUpdates;
  List<MindmapNode> nodes;
  CanvasBoard board;
  int objectUpdateCount = 0;

  Widget build() {
    return MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => MindmapCanvas(
            key: key,
            nodes: nodes,
            board: board,
            onNodeUpdated: enableNodeUpdates
                ? (updated) async {
                    setState(() {
                      nodes = <MindmapNode>[
                        for (final current in nodes)
                          current.id == updated.id ? updated : current,
                      ];
                    });
                  }
                : null,
            onNodesDeleted: enableNodeMutations
                ? (deleted) {
                    setState(() {
                      final ids = deleted.map((node) => node.id).toSet();
                      nodes = nodes
                          .where((node) => !ids.contains(node.id))
                          .toList();
                    });
                  }
                : null,
            onNodeMoved: enableNodeMutations
                ? (node, position) async {
                    setState(() {
                      nodes = <MindmapNode>[
                        for (final current in nodes)
                          current.id == node.id
                              ? current.copyWith(position: position)
                              : current,
                      ];
                    });
                  }
                : null,
            onCanvasObjectsCreated: enableObjectCreates
                ? (objects) {
                    setState(() {
                      board = board.copyWith(
                        objects: <CanvasObject>[...board.objects, ...objects],
                      );
                    });
                  }
                : null,
            onCanvasObjectsDeleted: enableObjectMutations
                ? (objects) {
                    setState(() {
                      final ids = objects.map((object) => object.id).toSet();
                      board = board.copyWith(
                        objects: board.objects
                            .where((object) => !ids.contains(object.id))
                            .toList(),
                      );
                    });
                  }
                : null,
            onCanvasObjectsUpdated: enableObjectUpdates
                ? (objects) {
                    objectUpdateCount++;
                    setState(() {
                      for (final object in objects) {
                        board = board.replaceObject(object);
                      }
                    });
                  }
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> selectAll() async {
    await key.currentState!.runContextAction(CanvasContextAction.selectAll);
  }
}

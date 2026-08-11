import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/graph/presentation/graph_physics_canvas.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_graph.dart';

void main() {
  testWidgets('physics canvas labels container and retains child actions', (
    tester,
  ) async {
    final node = MindmapNode.create(
      id: 'node-1',
      type: NodeType.note,
      title: 'Physics note',
      day: DateTime(2026, 8, 9),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphPhysicsCanvas(
            nodes: [node],
            graph: NodeGraph.fromNodes([node]),
            onNodeTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('Physics graph canvas, 1 nodes'),
      findsOneWidget,
    );
    final child = find.bySemanticsLabel('Physics note');
    expect(child, findsOneWidget);
    final semantics = tester.getSemantics(child);
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets('physics canvas respects reduced motion', (tester) async {
    final node = MindmapNode.create(
      id: 'node-1',
      type: NodeType.note,
      title: 'Physics note',
      day: DateTime(2026, 8, 9),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: GraphPhysicsCanvas(
              nodes: [node],
              graph: NodeGraph.fromNodes([node]),
              onNodeTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.bySemanticsLabel('Physics note'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('physics node exposes 44 target and invokes node tap', (
    tester,
  ) async {
    final node = MindmapNode.create(
      id: 'node-1',
      type: NodeType.note,
      title: 'Physics note',
      day: DateTime(2026, 8, 9),
    );
    String? tappedNodeId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphPhysicsCanvas(
            nodes: [node],
            graph: NodeGraph.fromNodes([node]),
            onNodeTap: (nodeId) => tappedNodeId = nodeId,
          ),
        ),
      ),
    );
    await tester.pump();

    final target = find.bySemanticsLabel('Physics note');
    expect(target, findsOneWidget);
    expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    await tester.tap(target);
    await tester.pump();
    expect(tappedNodeId, 'node-1');
  });

  testWidgets('physics node keeps 44 screen target at minimum zoom', (
    tester,
  ) async {
    final node = MindmapNode.create(
      id: 'node-1',
      type: NodeType.note,
      title: 'Physics note',
      day: DateTime(2026, 8, 9),
    );
    String? tappedNodeId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GraphPhysicsCanvas(
            nodes: [node],
            graph: NodeGraph.fromNodes([node]),
            onNodeTap: (nodeId) => tappedNodeId = nodeId,
          ),
        ),
      ),
    );
    await tester.pump();

    final canvas = find.byType(GraphPhysicsCanvas);
    final center = tester.getCenter(canvas);
    final gesture = await tester.createGesture();
    await gesture.addPointer(location: center);
    await gesture.down(center);
    final second = await tester.createGesture();
    await second.addPointer(location: center + const Offset(100, 0));
    await second.down(center + const Offset(100, 0));
    await gesture.moveTo(center + const Offset(40, 0));
    await second.moveTo(center + const Offset(60, 0));
    await tester.pump();
    await gesture.up();
    await second.up();
    await tester.pump();

    final target = find.bySemanticsLabel('Physics note');
    final renderBox = tester.renderObject<RenderBox>(target);
    final topLeft = renderBox.localToGlobal(Offset.zero);
    final bottomRight = renderBox.localToGlobal(
      renderBox.size.bottomRight(Offset.zero),
    );
    expect(bottomRight.dx - topLeft.dx, greaterThanOrEqualTo(44));
    expect(bottomRight.dy - topLeft.dy, greaterThanOrEqualTo(44));
    await tester.tap(target);
    await tester.pump();
    expect(tappedNodeId, 'node-1');
  });
}

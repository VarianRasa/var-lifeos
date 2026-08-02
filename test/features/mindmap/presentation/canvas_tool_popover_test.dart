import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/presentation/canvas_tool_popover.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';

void main() {
  testWidgets('close control works without tooltip overlay under follower', (
    tester,
  ) async {
    final link = LayerLink();
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CompositedTransformTarget(
                link: link,
                child: const SizedBox(width: 40, height: 40),
              ),
              CompositedTransformFollower(
                link: link,
                child: CanvasToolPopover(
                  title: 'Shape',
                  onClose: () => closed = true,
                  child: const Text('Settings'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final close = find.byKey(const ValueKey('canvas-tool-popover-close'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(close));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Close tool settings'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Close tool settings')),
      matchesSemantics(label: 'Close tool settings', isButton: true),
    );

    await tester.tap(close);
    await tester.pump();

    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shape settings avoid tooltip overlay under follower', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(nodes: const [], onCanvasObjectCreated: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mindmap-canvas-create-shape')));
    await tester.pump();

    final rectangle = find.byKey(const ValueKey('canvas-shape-rectangle'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(rectangle));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('rectangle'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('canvas-shape-ellipse')));
    await tester.pump();

    expect(
      tester.getSemantics(find.bySemanticsLabel('ellipse')),
      matchesSemantics(
        label: 'ellipse',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
  });
}

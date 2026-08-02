import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/canvas_document_renderer.dart';

void main() {
  testWidgets('canvas renderer paints every supported element without errors', (
    tester,
  ) async {
    const payload = CanvasPayload(
      background: 'grid',
      elements: <CanvasElement>[
        CanvasStroke(
          id: 'stroke',
          color: 'blue',
          points: <CanvasPoint>[CanvasPoint(0.1, 0.1), CanvasPoint(0.8, 0.8)],
        ),
        CanvasTextElement(
          id: 'text',
          color: 'neutral',
          position: CanvasPoint(0.2, 0.2),
          text: 'Label',
        ),
        CanvasStickyElement(
          id: 'sticky',
          color: 'neutral',
          position: CanvasPoint(0.5, 0.2),
          text: 'Note',
        ),
        CanvasShapeElement(
          id: 'shape',
          color: 'green',
          shape: 'ellipse',
          start: CanvasPoint(0.2, 0.5),
          end: CanvasPoint(0.5, 0.8),
        ),
        CanvasArrowElement(
          id: 'arrow',
          color: 'rose',
          start: CanvasPoint(0.5, 0.7),
          end: CanvasPoint(0.9, 0.4),
        ),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 300,
            child: CanvasDocumentView(
              payload: payload,
              selectedElementId: 'shape',
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('canvas-document-renderer')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('canvas hit testing prefers topmost element and movement clamps', () {
    const size = Size(100, 100);
    const bottom = CanvasShapeElement(
      id: 'bottom',
      color: 'blue',
      shape: 'rectangle',
      start: CanvasPoint(0.1, 0.1),
      end: CanvasPoint(0.8, 0.8),
    );
    const top = CanvasStickyElement(
      id: 'top',
      color: 'neutral',
      position: CanvasPoint(0.2, 0.2),
      text: 'Top',
      width: 0.4,
      height: 0.4,
    );

    expect(
      hitTestCanvasElement(
        <CanvasElement>[bottom, top],
        const Offset(30, 30),
        size,
      )?.id,
      'top',
    );
    final moved = moveCanvasElement(top, const Offset(200, 200), size);
    expect((moved as CanvasStickyElement).position.x, closeTo(0.6, 0.000001));
    expect(moved.position.y, closeTo(0.6, 0.000001));
  });
}

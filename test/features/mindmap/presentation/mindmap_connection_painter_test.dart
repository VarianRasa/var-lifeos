import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_data.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_connection_painter.dart';

void main() {
  test('ConnectionRenderItem stores data', () {
    const item = ConnectionRenderItem(
      id: 'c1',
      start: Offset.zero,
      end: Offset(100, 100),
      metadata: ConnectionMetadata(label: 'test'),
    );
    expect(item.id, 'c1');
    expect(item.metadata.label, 'test');
  });

  test('Bezier helpers evaluate horizontal line', () {
    final (c1, c2) = computeBezierControlPoints(
      Offset.zero,
      const Offset(100, 0),
    );
    expect(c1, const Offset(50, 0));
    expect(c2, const Offset(50, 0));
    expect(
      computeBezierPoint(
        Offset.zero,
        const Offset(25, 0),
        const Offset(75, 0),
        const Offset(100, 0),
        0.5,
      ),
      const Offset(50, 0),
    );
  });

  testWidgets('MindmapConnectionPainter attaches to CustomPaint', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CustomPaint(
          painter: MindmapConnectionPainter(
            connections: [
              ConnectionRenderItem(
                id: 'conn-1',
                start: Offset(100, 100),
                end: Offset(300, 300),
                metadata: ConnectionMetadata(
                  label: 'Test Link',
                  lineStyle: 'dashed',
                  arrowStyle: 'both',
                  color: 'blue',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter is MindmapConnectionPainter,
      ),
      findsOneWidget,
    );
  });
}

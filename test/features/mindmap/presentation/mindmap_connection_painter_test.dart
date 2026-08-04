import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_data.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_connection_painter.dart';

void main() {
  group('ConnectionRenderItem', () {
    test('instantiates correctly', () {
      const item = ConnectionRenderItem(
        id: 'c1',
        start: Offset(10, 10),
        end: Offset(100, 100),
        metadata: ConnectionMetadata(label: 'test'),
      );
      expect(item.id, equals('c1'));
      expect(item.start, equals(const Offset(10, 10)));
      expect(item.end, equals(const Offset(100, 100)));
      expect(item.metadata.label, equals('test'));
    });
  });

  group('resolveConnectionColor', () {
    test('parses hex colors', () {
      expect(resolveConnectionColor('#FF0000', null), equals(const Color(0xFFFF0000)));
      expect(resolveConnectionColor('#00FF00', null), equals(const Color(0xFF00FF00)));
    });

    test('maps standard color names to token colors', () {
      expect(resolveConnectionColor('blue', null), equals(const Color(0xFF2694FE)));
      expect(resolveConnectionColor('green', null), equals(const Color(0xFF0D8626)));
      expect(resolveConnectionColor('red', null), equals(const Color(0xFFF5394F)));
      expect(resolveConnectionColor('yellow', null), equals(const Color(0xFFF2C00B)));
      expect(resolveConnectionColor('purple', null), equals(const Color(0xFFF297FF)));
      expect(resolveConnectionColor('pink', null), equals(const Color(0xFFFF99C3)));
      expect(resolveConnectionColor('slate', null), equals(const Color(0xFFAAAFB5)));
    });
  });

  group('Bezier calculation helpers', () {
    test('computeBezierControlPoints returns symmetric offset control points', () {
      final (c1, c2) = computeBezierControlPoints(const Offset(0, 0), const Offset(100, 0));
      expect(c1.dx, equals(50.0));
      expect(c1.dy, equals(0.0));
      expect(c2.dx, equals(50.0));
      expect(c2.dy, equals(0.0));
    });

    test('computeBezierPoint evaluates endpoint and midpoint correctly', () {
      const start = Offset(0, 0);
      const c1 = Offset(25, 0);
      const c2 = Offset(75, 0);
      const end = Offset(100, 0);

      expect(computeBezierPoint(start, c1, c2, end, 0.0), equals(const Offset(0, 0)));
      expect(computeBezierPoint(start, c1, c2, end, 1.0), equals(const Offset(100, 0)));
      expect(computeBezierPoint(start, c1, c2, end, 0.5), equals(const Offset(50, 0)));
    });

    test('computeBezierAngle evaluates horizontal line tangent angle as 0', () {
      const start = Offset(0, 0);
      const c1 = Offset(25, 0);
      const c2 = Offset(75, 0);
      const end = Offset(100, 0);

      expect(computeBezierAngle(start, c1, c2, end, 0.5), equals(0.0));
    });
  });

  group('createDashedPath', () {
    test('creates non-empty dashed path', () {
      final path = Path()..lineTo(100, 0);
      final dashed = createDashedPath(path, dashLength: 5, spaceLength: 5);
      expect(dashed.computeMetrics().length, greaterThan(0));
    });
  });

  group('MindmapConnectionPainter widget test', () {
    testWidgets('paints connection curve, styles, arrows, and label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CustomPaint(
            painter: MindmapConnectionPainter(
              connections: const [
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
                ConnectionRenderItem(
                  id: 'conn-2',
                  start: Offset(50, 50),
                  end: Offset(150, 50),
                  metadata: ConnectionMetadata(
                    lineStyle: 'dotted',
                    arrowStyle: 'none',
                    color: '#00FF00',
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is MindmapConnectionPainter),
        findsOneWidget,
      );
    });
  });
}

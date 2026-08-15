import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_object_style.dart';

void main() {
  test('legacy connector and pen payloads keep compatible defaults', () {
    final connector = CanvasConnectorAppearance.fromPayload(
      const <String, Object?>{'arrowEnd': false, 'strokeWidth': 3},
    );
    expect(connector.style, CanvasConnectorStyle.elbow);
    expect(connector.pattern, CanvasLinePattern.solid);
    expect(connector.endArrow, CanvasArrowhead.none);

    final pen = CanvasPenAppearance.fromPayload(const <String, Object?>{
      'color': 'green',
      'strokeWidth': 3,
    });
    expect(pen.strokeColor, '#4CAF50');
    expect(pen.style, CanvasPenStyle.pen);
  });

  test('style codecs clamp malformed payload values', () {
    final shape = CanvasShapeStyle.fromPayload(const <String, Object?>{
      'shape': 'unknown',
      'borderWidth': 99,
      'opacity': -1,
    });
    expect(shape.kind, CanvasShapeKind.roundedRectangle);
    expect(shape.borderWidth, 12);
    expect(shape.opacity, 0.1);

    final text = CanvasTextStyle.fromPayload(const <String, Object?>{
      'fontSize': 1000,
      'textPadding': -1,
    });
    expect(text.fontSize, 96);
    expect(text.padding, 0);
  });

  test('new style values round trip through additive payload', () {
    const source = CanvasConnectorAppearance(
      style: CanvasConnectorStyle.curved,
      pattern: CanvasLinePattern.dashed,
      startArrow: CanvasArrowhead.circle,
      endArrow: CanvasArrowhead.filled,
      strokeColor: '#123456',
      strokeWidth: 7,
      opacity: 0.6,
      label: 'Depends on',
    );

    final decoded = CanvasConnectorAppearance.fromPayload(source.toPayload());
    expect(decoded.style, source.style);
    expect(decoded.pattern, source.pattern);
    expect(decoded.startArrow, source.startArrow);
    expect(decoded.endArrow, source.endArrow);
    expect(decoded.strokeColor, source.strokeColor);
    expect(decoded.strokeWidth, source.strokeWidth);
    expect(decoded.opacity, source.opacity);
    expect(decoded.label, source.label);
  });

  test('style copyWith preserves untouched values', () {
    const text = CanvasTextStyle(isBold: true, textColor: '#123456');
    expect(text.copyWith(fontSize: 32).isBold, isTrue);
    expect(text.copyWith(fontSize: 32).textColor, '#123456');

    const connector = CanvasConnectorAppearance(
      pattern: CanvasLinePattern.dashed,
      startArrow: CanvasArrowhead.circle,
    );
    expect(
      connector.copyWith(strokeWidth: 8).pattern,
      CanvasLinePattern.dashed,
    );
    expect(
      connector.copyWith(strokeWidth: 8).startArrow,
      CanvasArrowhead.circle,
    );
  });
}

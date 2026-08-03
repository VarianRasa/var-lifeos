import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/image_annotation.dart';

void main() {
  group('ImageAnnotationData', () {
    test(
      'serializes and deserializes pins and strokes using relative ratios',
      () {
        const data = ImageAnnotationData(
          pins: [
            ImageAnnotationPin(
              id: 'pin-1',
              xRatio: 0.4,
              yRatio: 0.6,
              text: 'Check shadow details',
            ),
          ],
          strokes: [
            ImageAnnotationStroke(
              colorValue: 0xFFFF0000,
              strokeWidth: 3.0,
              points: [
                ImageAnnotationPoint(xRatio: 0.1, yRatio: 0.2),
                ImageAnnotationPoint(xRatio: 0.15, yRatio: 0.25),
              ],
            ),
          ],
        );

        final json = data.toJson();
        final restored = ImageAnnotationData.fromJson(json);

        expect(restored.pins.length, equals(1));
        expect(restored.pins.first.id, equals('pin-1'));
        expect(restored.pins.first.xRatio, equals(0.4));
        expect(restored.pins.first.yRatio, equals(0.6));
        expect(restored.pins.first.text, equals('Check shadow details'));
        expect(restored.strokes.length, equals(1));
        expect(restored.strokes.first.colorValue, equals(0xFFFF0000));
        expect(restored.strokes.first.strokeWidth, equals(3.0));
        expect(restored.strokes.first.points.length, equals(2));
        expect(restored.strokes.first.points.first.xRatio, equals(0.1));
        expect(restored.strokes.first.points.first.yRatio, equals(0.2));
      },
    );
  });
}

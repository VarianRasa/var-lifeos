import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/image_annotation_controller.dart';
import 'package:var_app/features/mindmap/domain/image_annotation.dart';
import 'package:var_app/features/mindmap/presentation/image_annotation_overlay.dart';

void main() {
  group('ImageAnnotationOverlay & Controller Fixes', () {
    testWidgets('renders numbered pin badge at relative ratio position', (
      tester,
    ) async {
      const data = ImageAnnotationData(
        pins: [
          ImageAnnotationPin(
            id: 'pin-1',
            xRatio: 0.5,
            yRatio: 0.5,
            text: 'Center Note',
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: ImageAnnotationOverlay(
                annotationData: data,
                isAnnotating: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets(
      'triggers onPinTap when tapping pin badge, regardless of isAnnotating',
      (tester) async {
        ImageAnnotationPin? tappedPin;
        const data = ImageAnnotationData(
          pins: [
            ImageAnnotationPin(
              id: 'pin-1',
              xRatio: 0.5,
              yRatio: 0.5,
              text: 'Tap Me',
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 200,
                child: ImageAnnotationOverlay(
                  annotationData: data,
                  isAnnotating: true,
                  onPinTap: (pin) => tappedPin = pin,
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('1'));
        await tester.pump();

        expect(tappedPin?.id, equals('pin-1'));
      },
    );

    testWidgets('triggers onTapToAddPin only when isAnnotating is true', (
      tester,
    ) async {
      Offset? addedOffset;
      const data = ImageAnnotationData();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: ImageAnnotationOverlay(
                annotationData: data,
                isAnnotating: false,
                onTapToAddPin: (offset) => addedOffset = offset,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ImageAnnotationOverlay));
      await tester.pump();
      expect(addedOffset, isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: ImageAnnotationOverlay(
                annotationData: data,
                isAnnotating: true,
                onTapToAddPin: (offset) => addedOffset = offset,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ImageAnnotationOverlay));
      await tester.pump();
      expect(addedOffset, isNotNull);
    });

    testWidgets(
      'supports drawing pan gestures converting local offsets to clamped ratios',
      (tester) async {
        final controller = ImageAnnotationController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 100,
                child: ImageAnnotationOverlay(
                  annotationData: controller.data,
                  isAnnotating: true,
                  controller: controller,
                  strokeColorValue: 0xFFFF0000,
                  strokeWidth: 3.0,
                ),
              ),
            ),
          ),
        );

        final gesture = await tester.startGesture(const Offset(20, 20));
        await tester.pump();
        expect(controller.data.strokes.length, equals(1));
        expect(
          controller.data.strokes.first.points.first.xRatio,
          closeTo(0.1, 0.01),
        );
        expect(
          controller.data.strokes.first.points.first.yRatio,
          closeTo(0.2, 0.01),
        );

        await gesture.moveBy(
          const Offset(200, 200),
        ); // Out of bounds -> clamped to 1.0, 1.0
        await tester.pump();
        expect(controller.data.strokes.first.points.last.xRatio, equals(1.0));
        expect(controller.data.strokes.first.points.last.yRatio, equals(1.0));

        await gesture.up();
        await tester.pump();
        expect(controller.canUndo, isTrue);
      },
    );

    testWidgets(
      'pin badge scales position accurately across multiple overlay sizes',
      (tester) async {
        const data = ImageAnnotationData(
          pins: [
            ImageAnnotationPin(
              id: 'pin-1',
              xRatio: 0.5,
              yRatio: 0.5,
              text: 'Scaled Pin',
            ),
          ],
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 200,
                child: ImageAnnotationOverlay(
                  annotationData: data,
                  isAnnotating: false,
                ),
              ),
            ),
          ),
        );

        final pinFinder = find.ancestor(
          of: find.text('1'),
          matching: find.byType(Positioned),
        );
        final positionedWidget = tester.widget<Positioned>(pinFinder);
        expect(positionedWidget.left, equals(400 * 0.5 - 12));
        expect(positionedWidget.top, equals(200 * 0.5 - 12));
      },
    );

    test('clamps ratios at controller boundary', () {
      final controller = ImageAnnotationController();

      controller.addPin(xRatio: -0.5, yRatio: 1.5, text: 'Clamped');
      expect(controller.data.pins.first.xRatio, equals(0.0));
      expect(controller.data.pins.first.yRatio, equals(1.0));

      controller.startStroke(
        colorValue: 0xFF000000,
        strokeWidth: 2.0,
        xRatio: -0.1,
        yRatio: 0.5,
      );
      expect(controller.data.strokes.first.points.first.xRatio, equals(0.0));

      controller.addPointToCurrentStroke(xRatio: 1.2, yRatio: 0.5);
      expect(controller.data.strokes.first.points.last.xRatio, equals(1.0));
    });

    test(
      'tracks single active stroke and safe endStroke / startStroke transition',
      () {
        final controller = ImageAnnotationController();

        controller.startStroke(
          colorValue: 0xFF000000,
          strokeWidth: 2.0,
          xRatio: 0.1,
          yRatio: 0.1,
        );
        expect(controller.isDrawing, isTrue);

        controller.endStroke();
        expect(controller.isDrawing, isFalse);
        expect(controller.data.strokes.length, equals(1));

        // Duplicate end stroke is no-op
        controller.endStroke();
        expect(controller.data.strokes.length, equals(1));

        // Starting new stroke while active auto-ends previous stroke
        controller.startStroke(
          colorValue: 0xFF000000,
          strokeWidth: 2.0,
          xRatio: 0.2,
          yRatio: 0.2,
        );
        expect(controller.isDrawing, isTrue);
        controller.startStroke(
          colorValue: 0xFF000000,
          strokeWidth: 2.0,
          xRatio: 0.3,
          yRatio: 0.3,
        );
        expect(controller.data.strokes.length, equals(3));
        expect(controller.isDrawing, isTrue);
      },
    );

    test('updateData clears and rebuilds undo/redo history safely', () {
      final controller = ImageAnnotationController();

      controller.startStroke(
        colorValue: 0xFF000000,
        strokeWidth: 2.0,
        xRatio: 0.1,
        yRatio: 0.1,
      );
      controller.endStroke();
      expect(controller.canUndo, isTrue);

      const newData = ImageAnnotationData(
        strokes: [
          ImageAnnotationStroke(
            colorValue: 0xFF000000,
            strokeWidth: 2.0,
            points: [ImageAnnotationPoint(xRatio: 0.5, yRatio: 0.5)],
          ),
        ],
      );

      controller.updateData(newData);
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isFalse);
      expect(controller.data.strokes.length, equals(1));
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/image_annotation_controller.dart';
import 'package:var_app/features/mindmap/domain/image_annotation.dart';
import 'package:var_app/features/mindmap/presentation/image_annotation_overlay.dart';

void main() {
  group('ImageAnnotationOverlay & ImageAnnotationController', () {
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

    testWidgets('triggers onPinTap when tapping existing pin badge', (
      tester,
    ) async {
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
                isAnnotating: false,
                onPinTap: (pin) => tappedPin = pin,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('1'));
      await tester.pump();

      expect(tappedPin?.id, equals('pin-1'));
    });

    test(
      'ImageAnnotationController adds pin, draws stroke, undoes and redoes stroke',
      () {
        final controller = ImageAnnotationController();

        expect(controller.data.pins, isEmpty);
        expect(controller.data.strokes, isEmpty);

        // Add pin
        controller.addPin(xRatio: 0.3, yRatio: 0.4, text: 'Pin test');
        expect(controller.data.pins.length, equals(1));
        expect(controller.data.pins.first.text, equals('Pin test'));

        // Remove pin
        final pinId = controller.data.pins.first.id;
        controller.removePin(pinId);
        expect(controller.data.pins, isEmpty);

        // Start, update, end stroke
        controller.startStroke(
          colorValue: 0xFFFF0000,
          strokeWidth: 4.0,
          startPoint: const ImageAnnotationPoint(xRatio: 0.1, yRatio: 0.1),
        );
        expect(controller.data.strokes.length, equals(1));

        controller.addPointToCurrentStroke(
          const ImageAnnotationPoint(xRatio: 0.2, yRatio: 0.2),
        );
        expect(controller.data.strokes.first.points.length, equals(2));

        controller.endStroke();

        // Undo stroke
        expect(controller.canUndo, isTrue);
        controller.undoStroke();
        expect(controller.data.strokes, isEmpty);
        expect(controller.canRedo, isTrue);

        // Redo stroke
        controller.redoStroke();
        expect(controller.data.strokes.length, equals(1));

        // Clear all
        controller.clear();
        expect(controller.data.strokes, isEmpty);
      },
    );
  });
}

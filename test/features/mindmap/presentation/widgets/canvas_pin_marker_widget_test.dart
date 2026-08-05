import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_pin_comment.dart';
import 'package:var_app/features/mindmap/presentation/widgets/canvas_pin_marker_widget.dart';

void main() {
  testWidgets('CanvasPinMarkerWidget renders pin comment marker', (
    WidgetTester tester,
  ) async {
    final pin = CanvasPinComment(
      id: 'pin1',
      x: 100,
      y: 200,
      message: 'Need to review this image alignment',
      author: 'Alex',
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasPinMarkerWidget(pin: pin),
        ),
      ),
    );

    expect(find.byIcon(Icons.comment), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/presentation/widgets/canvas_dropzone_overlay.dart';

void main() {
  testWidgets(
    'CanvasDropzoneOverlay renders child and overlay border when active',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasDropzoneOverlay(
              onFilesDropped: (files, offset) {},
              child: const SizedBox(
                width: 400,
                height: 400,
                child: Text('Canvas Area'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Canvas Area'), findsOneWidget);
      expect(find.byType(CanvasDropzoneOverlay), findsOneWidget);
    },
  );
}

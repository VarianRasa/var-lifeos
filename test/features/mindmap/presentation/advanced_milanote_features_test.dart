import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/presentation/canvas_presentation_mode_dialog.dart';
import 'package:var_app/features/mindmap/presentation/widgets/image_crop_mask_widget.dart';
import 'package:var_app/features/mindmap/presentation/widgets/nested_board_portal_widget.dart';

void main() {
  testWidgets('NestedBoardPortalWidget renders title and element count', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NestedBoardPortalWidget(
            boardId: 'sub1',
            title: 'Design System Sub-Board',
            elementCount: 12,
          ),
        ),
      ),
    );

    expect(find.text('Design System Sub-Board'), findsOneWidget);
    expect(find.text('12 elements inside'), findsOneWidget);
  });

  testWidgets('ImageCropMaskWidget renders with rounded shape', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImageCropMaskWidget(
            imageUrl: 'https://example.com/demo.jpg',
            shape: ImageCropShape.rounded,
          ),
        ),
      ),
    );

    expect(find.byType(ImageCropMaskWidget), findsOneWidget);
  });

  testWidgets('CanvasPresentationModeDialog renders frame title', (
    WidgetTester tester,
  ) async {
    const frames = [
      CanvasPresentationFrame(
        id: 'f1',
        title: 'Intro Slide',
        contentSummary: 'Overview of Var App',
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CanvasPresentationModeDialog(frames: frames),
        ),
      ),
    );

    expect(find.text('Intro Slide'), findsAtLeast(1));
    expect(find.text('Overview of Var App'), findsOneWidget);
  });
}

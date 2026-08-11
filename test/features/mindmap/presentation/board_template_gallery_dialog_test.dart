import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_snap_align.dart';
import 'package:var_app/features/mindmap/presentation/board_template_gallery_dialog.dart';

void main() {
  test('CanvasSnapAlign snaps position when within threshold', () {
    final result = CanvasSnapAlign.computeSnap(
      targetX: 102,
      targetY: 198,
      otherNodes: [(x: 100.0, y: 200.0)],
    );

    expect(result.snappedX, equals(100.0));
    expect(result.snappedY, equals(200.0));
    expect(result.guidelines.length, equals(2));
  });

  testWidgets('BoardTemplateGalleryDialog renders built-in templates', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BoardTemplateGalleryDialog())),
    );

    expect(find.text('Template Gallery'), findsOneWidget);
    expect(find.text('Project Plan'), findsOneWidget);
  });
}

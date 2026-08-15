import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/presentation/widgets/canvas_dropzone_overlay.dart';

void main() {
  testWidgets(
    'CanvasDropzoneOverlay renders child, DropTarget, and handles callbacks',
    (WidgetTester tester) async {
      List<XFile>? droppedFiles;
      Offset? dropOffset;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CanvasDropzoneOverlay(
              onFilesDropped: (files, offset) {
                droppedFiles = files;
                dropOffset = offset;
              },
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
      expect(find.byType(DropTarget), findsOneWidget);

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      final testFile = DropItemFile(
        'dummy/path/test_doc.png',
        name: 'test_doc.png',
        length: 3,
        lastModified: DateTime.now(),
      );

      dropTarget.onDragDone?.call(
        DropDoneDetails(
          files: [testFile],
          localPosition: const Offset(120, 150),
          globalPosition: const Offset(120, 150),
        ),
      );
      await tester.pumpAndSettle();

      expect(droppedFiles, isNotNull);
      expect(droppedFiles!.first.name, contains('test_doc.png'));
      expect(dropOffset, const Offset(120, 150));
    },
  );
}

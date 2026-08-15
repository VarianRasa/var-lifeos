import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/presentation/widgets/file_card_widget.dart';

void main() {
  testWidgets('FileCardWidget displays filename, icon, and formatted size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FileCardWidget(
            fileName: 'document.pdf',
            fileSize: 2450000,
            fileExtension: 'pdf',
          ),
        ),
      ),
    );

    expect(find.text('document.pdf'), findsOneWidget);
    expect(find.text('2.3 MB'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
  });
}

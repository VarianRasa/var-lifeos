import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/link_metadata.dart';
import 'package:var_app/features/mindmap/presentation/widgets/link_preview_card_widget.dart';

void main() {
  testWidgets('LinkPreviewCardWidget renders banner style correctly', (
    WidgetTester tester,
  ) async {
    final metadata = LinkMetadata(
      url: 'https://milanote.com',
      title: 'Milanote Visual Board',
      description: 'Organize your ideas visually',
      fetchedAt: DateTime(2026, 1, 1),
      style: LinkPreviewStyle.banner,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LinkPreviewCardWidget(metadata: metadata)),
      ),
    );

    expect(find.text('Milanote Visual Board'), findsOneWidget);
    expect(find.text('Organize your ideas visually'), findsOneWidget);
  });
}

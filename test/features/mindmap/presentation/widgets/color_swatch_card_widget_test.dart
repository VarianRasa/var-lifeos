import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/presentation/widgets/color_swatch_card_widget.dart';

void main() {
  test('NodeType.swatch has proper label', () {
    expect(NodeType.swatch.label, equals('Color Swatch'));
  });

  testWidgets('ColorSwatchCardWidget renders hex color and label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ColorSwatchCardWidget(
            hexColor: '#4F7CFF',
            label: 'Brand Primary Blue',
            palette: ['#4F7CFF', '#FFC247', '#4CAF50'],
          ),
        ),
      ),
    );

    expect(find.text('Brand Primary Blue'), findsOneWidget);
    expect(find.text('#4F7CFF'), findsOneWidget);
  });
}

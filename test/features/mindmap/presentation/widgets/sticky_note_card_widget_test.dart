import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/theme/app_sticky_colors.dart';
import 'package:var_app/features/mindmap/presentation/widgets/sticky_note_card_widget.dart';

void main() {
  testWidgets('StickyNoteCardWidget renders title, body, and color theme', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StickyNoteCardWidget(
            title: 'Meeting Ideas',
            body: 'Brainstorm session at 3 PM',
            colorOption: StickyColorOption.yellow,
          ),
        ),
      ),
    );

    expect(find.text('Meeting Ideas'), findsOneWidget);
    expect(find.text('Brainstorm session at 3 PM'), findsOneWidget);
  });

  testWidgets('StickyNoteCardWidget triggers onColorChanged when menu item selected', (tester) async {
    StickyColorOption? selectedColor;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StickyNoteCardWidget(
            title: 'Meeting Ideas',
            body: 'Brainstorm session at 3 PM',
            colorOption: StickyColorOption.yellow,
            onColorChanged: (color) {
              selectedColor = color;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('blue').last);
    await tester.pumpAndSettle();

    expect(selectedColor, StickyColorOption.blue);
  });
}

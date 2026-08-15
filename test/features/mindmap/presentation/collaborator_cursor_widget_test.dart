import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/presentation/collaborator_cursor_widget.dart';

void main() {
  for (final colorCase in <({Color background, Color foreground})>[
    (background: Colors.black, foreground: Colors.white),
    (background: Colors.yellow, foreground: const Color(0xFF0A1317)),
  ]) {
    testWidgets('cursor label keeps contrast for ${colorCase.background}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              CollaboratorCursorWidget(
                name: 'Peer',
                color: colorCase.background,
                position: Offset.zero,
              ),
            ],
          ),
        ),
      );

      final label = tester.widget<Text>(find.text('Peer'));
      expect(label.style?.color, colorCase.foreground);
    });
  }
}

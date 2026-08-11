import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/connection_style.dart';
import 'package:var_app/features/mindmap/presentation/widgets/connection_style_bar.dart';

void main() {
  testWidgets('ConnectionStyleBar renders and triggers callbacks', (
    tester,
  ) async {
    ConnectionStyle currentStyle = const ConnectionStyle();
    bool deletePressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionStyleBar(
            style: currentStyle,
            onStyleChanged: (newStyle) => currentStyle = newStyle,
            onDelete: () => deletePressed = true,
          ),
        ),
      ),
    );

    expect(find.byType(ConnectionStyleBar), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    expect(deletePressed, isTrue);
  });
}

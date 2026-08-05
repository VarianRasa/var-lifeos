import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/presentation/widgets/frame_container_widget.dart';

void main() {
  test('NodeType.frame has proper label', () {
    expect(NodeType.frame.label, equals('Frame'));
  });

  testWidgets('FrameContainerWidget renders correctly with title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FrameContainerWidget(
            title: 'Design Ideas Container',
            width: 400,
            height: 300,
          ),
        ),
      ),
    );

    expect(find.text('Design Ideas Container'), findsOneWidget);
  });
}

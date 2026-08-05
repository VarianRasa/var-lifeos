import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/calendar/widgets/day_canvas_tab_header.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';

void main() {
  testWidgets('DayCanvasTabHeader renders tabs and triggers onSelectBoard and onAddBoard', (
    WidgetTester tester,
  ) async {
    String? selectedId = 'b1';
    var addCalled = false;
    final now = DateTime(2026, 8, 5);

    final boards = <CanvasBoard>[
      CanvasBoard(
        id: 'b1',
        title: 'Main Canvas',
        kind: CanvasBoardKind.daily,
        createdAt: now,
        updatedAt: now,
        isPrimaryDayBoard: true,
      ),
      CanvasBoard(
        id: 'b2',
        title: 'Project Board',
        kind: CanvasBoardKind.project,
        createdAt: now,
        updatedAt: now,
        isPrimaryDayBoard: false,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayCanvasTabHeader(
            boards: boards,
            activeBoardId: selectedId,
            onSelectBoard: (id) => selectedId = id,
            onAddBoard: () => addCalled = true,
          ),
        ),
      ),
    );

    expect(find.text('Main Canvas'), findsOneWidget);
    expect(find.text('Project Board'), findsOneWidget);

    await tester.tap(find.text('Project Board'));
    await tester.pump();
    expect(selectedId, equals('b2'));

    final addButton = find.byIcon(Icons.add);
    expect(addButton, findsOneWidget);
    await tester.tap(addButton);
    await tester.pump();
    expect(addCalled, isTrue);
  });
}

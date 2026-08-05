import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/calendar/widgets/day_canvas_tab_header.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';

void main() {
  testWidgets('DayCanvasTabHeader renders workspace action icons for Assistant, Voting, and Workshop', (
    WidgetTester tester,
  ) async {
    var assistantTapped = false;
    var votingTapped = false;
    var workshopTapped = false;
    final now = DateTime(2026, 8, 5);

    final boards = <CanvasBoard>[
      CanvasBoard(
        id: 'b1',
        title: 'Main Board',
        kind: CanvasBoardKind.daily,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayCanvasTabHeader(
            boards: boards,
            activeBoardId: 'b1',
            onSelectBoard: (_) {},
            onAddBoard: () {},
            onAssistantRequested: () => assistantTapped = true,
            onVotingRequested: () => votingTapped = true,
            onWorkshopRequested: () => workshopTapped = true,
          ),
        ),
      ),
    );

    final assistantBtn = find.byIcon(Icons.auto_awesome_outlined);
    final votingBtn = find.byIcon(Icons.how_to_vote_outlined);
    final workshopBtn = find.byIcon(Icons.present_to_all_outlined);

    expect(assistantBtn, findsOneWidget);
    expect(votingBtn, findsOneWidget);
    expect(workshopBtn, findsOneWidget);

    await tester.tap(assistantBtn);
    await tester.tap(votingBtn);
    await tester.tap(workshopBtn);
    await tester.pump();

    expect(assistantTapped, isTrue);
    expect(votingTapped, isTrue);
    expect(workshopTapped, isTrue);
  });
}

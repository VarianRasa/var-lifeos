import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_version_history.dart';
import 'package:var_app/features/mindmap/presentation/widgets/board_voting_reaction_widget.dart';
import 'package:var_app/features/mindmap/presentation/widgets/canvas_minimap_widget.dart';

void main() {
  test('CanvasVersionHistoryEngine records snapshot and rolls back', () {
    final engine = CanvasVersionHistoryEngine();
    engine.recordSnapshot(label: 'Initial Board', nodes: []);

    expect(engine.history.length, equals(1));
    final snapshotId = engine.history.first.id;

    final rolledBackNodes = engine.rollbackToVersion(snapshotId);
    expect(rolledBackNodes, isNotNull);
  });

  testWidgets('CanvasMinimapWidget renders minimap canvas', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CanvasMinimapWidget(
            nodeDots: [MinimapNodeDot(x: 100, y: 100)],
            viewportRect: Rect.fromLTWH(0, 0, 400, 300),
          ),
        ),
      ),
    );

    expect(find.byType(CanvasMinimapWidget), findsOneWidget);
  });

  testWidgets('BoardVotingReactionWidget renders votes and reactions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BoardVotingReactionWidget(initialVotes: 5),
        ),
      ),
    );

    expect(find.text('5'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

  testWidgets('minimap semantics distinguish enabled navigation', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CanvasMinimapWidget(
                nodeDots: const [MinimapNodeDot(x: 100, y: 100)],
                viewportRect: const Rect.fromLTWH(0, 0, 400, 300),
                onTapMinimap: (_) => tapped = true,
              ),
              const CanvasMinimapWidget(
                nodeDots: [MinimapNodeDot(x: 200, y: 200)],
                viewportRect: Rect.fromLTWH(0, 0, 400, 300),
              ),
            ],
          ),
        ),
      ),
    );

    final minimaps = find.byType(CanvasMinimapWidget);
    final enabled = tester.getSemantics(minimaps.first);
    expect(enabled.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    enabled.owner!.performAction(enabled.id, SemanticsAction.tap);
    await tester.pump();
    expect(tapped, isTrue);
    final disabled = tester.getSemantics(minimaps.last);
    expect(disabled.label, '1 canvas objects');
    expect(disabled.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
  });

  testWidgets('BoardVotingReactionWidget renders votes and reactions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BoardVotingReactionWidget(initialVotes: 5)),
      ),
    );

    expect(find.text('5'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });
}

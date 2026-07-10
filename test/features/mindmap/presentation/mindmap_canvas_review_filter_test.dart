import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';

void main() {
  testWidgets('MindmapCanvas filters nodes by review state', (tester) async {
    final day = DateTime(2026, 7, 6);
    final nodes = [
      MindmapNode.create(
        id: 'review-1',
        type: NodeType.task,
        title: 'Review launch plan',
        day: day,
        position: const CanvasPosition(-80, 0),
        priority: NodePriority.high,
        effort: NodeEffort.fifteenMinutes,
        reviewState: NodeReviewState.needsReview,
        now: day,
      ),
      MindmapNode.create(
        id: 'active-1',
        type: NodeType.note,
        title: 'Active note',
        day: day,
        position: const CanvasPosition(80, 0),
        reviewState: NodeReviewState.someday,
        now: day,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: MindmapCanvas(nodes: nodes)),
      ),
    );

    await tester.tap(find.text('Show search'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mindmap-review-filter-needsReview')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review launch plan'), findsOneWidget);
    expect(find.text('Active note'), findsNothing);
  });

  testWidgets('MindmapCanvas filters next-action candidates', (tester) async {
    final day = DateTime(2026, 7, 6);
    final nodes = [
      MindmapNode.create(
        id: 'next-1',
        type: NodeType.task,
        title: 'Ship important fix',
        day: day,
        position: const CanvasPosition(-80, 0),
        priority: NodePriority.urgent,
        effort: NodeEffort.fiveMinutes,
        now: day,
      ),
      MindmapNode.create(
        id: 'later-1',
        type: NodeType.idea,
        title: 'Someday idea',
        day: day,
        position: const CanvasPosition(80, 0),
        reviewState: NodeReviewState.someday,
        now: day,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: MindmapCanvas(nodes: nodes)),
      ),
    );

    await tester.tap(find.text('Show search'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mindmap-next-action-filter')));
    await tester.pumpAndSettle();

    expect(find.text('Ship important fix'), findsOneWidget);
    expect(find.text('Someday idea'), findsNothing);
  });
}

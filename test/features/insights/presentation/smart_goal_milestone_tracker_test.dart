import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/insights/presentation/smart_goal_milestone_tracker.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  testWidgets('SmartGoalMilestoneTracker renders goal metrics and milestones', (
    tester,
  ) async {
    final goalNode = MindmapNode.create(
      id: 'goal-1',
      type: NodeType.goal,
      title: 'Kuasai Flutter 3.11',
      day: DateTime(2026, 7, 24),
      now: DateTime(2026, 7, 24),
      data: {
        'goal': {
          'milestones': ['Belajar Widget', 'Belajar Riverpod', 'Rilis App'],
          'completedMilestones': ['Belajar Widget'],
        },
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SmartGoalMilestoneTracker(
                nodes: [goalNode],
                today: DateTime(2026, 7, 24),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Audit Target & Milestone OS'), findsOneWidget);
    expect(find.text('Total Target'), findsOneWidget);
    expect(find.text('Kuasai Flutter 3.11'), findsOneWidget);
    expect(find.text('Milestone berikut: Belajar Riverpod'), findsOneWidget);
  });
}

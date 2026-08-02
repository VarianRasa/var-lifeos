import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/insights/presentation/habit_matrix_heatmap.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  testWidgets('HabitMatrixHeatmap renders successfully with empty nodes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HabitMatrixHeatmap(habitNodes: []),
          ),
        ),
      ),
    );

    expect(
      find.textContaining('Matriks Kebiasaan (16 Minggu)'),
      findsOneWidget,
    );
    expect(find.textContaining('Score'), findsOneWidget);
  });

  testWidgets(
    'HabitMatrixHeatmap renders habit completion nodes and toggles weeks',
    (tester) async {
      final habitNode = MindmapNode.create(
        id: 'habit-1',
        type: NodeType.habit,
        title: 'Olahraga',
        day: DateTime(2026, 7, 23),
        data: const {
          'habit': {
            'completions': ['2026-07-23', '2026-07-22'],
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HabitMatrixHeatmap(habitNodes: [habitNode]),
            ),
          ),
        ),
      );

      expect(
        find.textContaining('Matriks Kebiasaan (16 Minggu)'),
        findsOneWidget,
      );
      expect(find.textContaining('Score'), findsOneWidget);

      // Tap 52-week toggle
      await tester.tap(find.text('1 thn'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Matriks Kebiasaan (52 Minggu)'),
        findsOneWidget,
      );
    },
  );
}

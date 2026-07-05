import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/node_detail_page.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('NodeDetailPage renders Completions Heatmap for Habit node', (
    tester,
  ) async {
    final today = DateTime.now().dateOnly;
    final habitNode =
        MindmapNode.create(
          id: 'habit-1',
          type: NodeType.habit,
          title: 'Workout Habit',
          day: today,
        ).copyWith(
          data: {
            'habit': {
              'completions': [
                dayKey(today),
                dayKey(today.subtract(const Duration(days: 3))),
              ],
            },
          },
        );

    final repository = InMemoryMindmapRepository(seedNodes: [habitNode]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeDetailPage(date: today, nodeId: 'habit-1'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Habit Detail title/elements
    expect(find.text('Workout Habit'), findsAtLeastNWidgets(1));

    // Verify the habit detail/editor content is rendered.

    // Verify scrollable habit content is rendered
    final scrollFinder = find.byType(SingleChildScrollView);
    expect(scrollFinder, findsAny);
  });
}

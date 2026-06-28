import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test(
    'automationSuggestionsProvider previews due routine suggestions',
    () async {
      final monday = DateTime(2026, 6, 22);
      final repository = InMemoryMindmapRepository();
      final container = ProviderContainer(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(monday),
        ],
      );
      addTearDown(container.dispose);

      final suggestions = await container.read(
        automationSuggestionsProvider.future,
      );

      expect(suggestions.readyCount, 4);
      expect(suggestions.blockedCount, 1);
      expect(suggestions.items.map((item) => item.routineId), [
        'daily-plan',
        'daily-journal',
        'workout-habit',
        'weekly-review',
      ]);
    },
  );

  test(
    'automationSuggestionsProvider exposes completed routine history',
    () async {
      final monday = DateTime(2026, 6, 22);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'routine-daily-plan-2026-06-22',
            type: NodeType.plan,
            title: 'Daily plan',
            day: monday,
            data: const {
              'automation': {'routineId': 'daily-plan'},
            },
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(monday),
        ],
      );
      addTearDown(container.dispose);

      final suggestions = await container.read(
        automationSuggestionsProvider.future,
      );

      expect(suggestions.completedCount, 1);
      expect(suggestions.completedItems.single.routineId, 'daily-plan');
      expect(suggestions.completedItems.single.title, 'Daily plan');
      expect(suggestions.primaryActionLabel, 'Review 3 automations');
    },
  );
}

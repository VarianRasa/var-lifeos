import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test(
    'lifeOsSummaryProvider exposes Life OS metrics from all nodes',
    () async {
      final today = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'habit-1',
            type: NodeType.habit,
            title: 'Workout',
            day: today,
            data: const {
              'habit': {
                'completions': ['2026-06-17', '2026-06-18'],
              },
            },
            now: DateTime(2026, 6, 18, 8),
          ),
          MindmapNode.create(
            id: 'journal-1',
            type: NodeType.journal,
            title: 'Daily journal',
            day: today,
            data: const {
              'journal': {'mood': 5, 'energy': 4},
            },
            now: DateTime(2026, 6, 18, 9),
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
      );
      addTearDown(container.dispose);

      final summary = await container.read(lifeOsSummaryProvider.future);

      expect(summary.bestHabitStreak, 2);
      expect(summary.averageMood, 5);
      expect(summary.averageEnergy, 4);
    },
  );
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('insightsSummaryProvider exposes analytics for all nodes', () async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'done-task',
          type: NodeType.task,
          title: 'Done task',
          day: today,
          isDone: true,
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'open-task',
          type: NodeType.task,
          title: 'Open task',
          day: today,
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

    final summary = await container.read(insightsSummaryProvider.future);

    expect(summary.taskCompletionRate, 0.5);
    expect(summary.activeDayCount, 1);
  });
}

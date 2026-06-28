import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/domain/time_block.dart';
import 'package:var_app/features/mindmap/application/mindmap_mutation_controller.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_data.dart';

void main() {
  test('saveNode persists through repository', () async {
    final repository = InMemoryMindmapRepository();
    final container = ProviderContainer(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final node = MindmapNode.create(
      id: 'saved-node',
      type: NodeType.note,
      title: 'Saved',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18),
    );

    final saved = await container
        .read(mindmapMutationControllerProvider)
        .saveNode(node);

    expect(saved.title, 'Saved');
    expect(await repository.getNode('saved-node'), saved);
  });

  test('schedule and unschedule node update time block data', () async {
    final node = MindmapNode.create(
      id: 'schedule-node',
      type: NodeType.task,
      title: 'Schedule',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final container = ProviderContainer(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final scheduled = await container
        .read(mindmapMutationControllerProvider)
        .scheduleNode(
          node,
          const TimeBlock(startMinute: 9 * 60, endMinute: 10 * 60),
        );

    expect(timeBlockForNode(scheduled).block?.rangeLabel, '09:00 - 10:00');

    final unscheduled = await container
        .read(mindmapMutationControllerProvider)
        .unscheduleNode(scheduled);

    expect(timeBlockForNode(unscheduled).isUnscheduled, isTrue);
  });

  test(
    'rescheduleNode moves node to target day and preserves content',
    () async {
      final originalDay = DateTime(2026, 6, 18);
      final targetDay = DateTime(2026, 6, 21);
      final node = MindmapNode.create(
        id: 'reschedule-node',
        type: NodeType.task,
        title: 'Reschedule',
        body: 'Keep details',
        tags: ['plan'],
        project: 'Launch',
        day: originalDay,
        now: DateTime(2026, 6, 18, 8),
      );
      final repository = InMemoryMindmapRepository(seedNodes: [node]);
      final container = ProviderContainer(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final moved = await container
          .read(mindmapMutationControllerProvider)
          .rescheduleNode(node, day: targetDay);

      expect(moved.day, targetDay);
      expect(moved.title, node.title);
      expect(moved.body, node.body);
      expect(moved.tags, node.tags);
      expect(moved.project, node.project);
      expect(moved.updatedAt.isAfter(node.updatedAt), isTrue);
      expect(await repository.listNodes(day: originalDay), isEmpty);
      expect(await repository.listNodes(day: targetDay), [moved]);
    },
  );

  test('rescheduleNodeById loads node and reports missing ids', () async {
    final node = MindmapNode.create(
      id: 'reschedule-by-id-node',
      type: NodeType.note,
      title: 'Move by id',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final container = ProviderContainer(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final moved = await container
        .read(mindmapMutationControllerProvider)
        .rescheduleNodeById(nodeId: node.id, day: DateTime(2026, 6, 22));

    expect(moved.day, DateTime(2026, 6, 22));
    await expectLater(
      container
          .read(mindmapMutationControllerProvider)
          .rescheduleNodeById(nodeId: 'missing', day: DateTime(2026, 6, 23)),
      throwsStateError,
    );
  });

  test('link and unlink nodes update relation ids', () async {
    final source = MindmapNode.create(
      id: 'source-node',
      type: NodeType.note,
      title: 'Source',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18),
    );
    final target = MindmapNode.create(
      id: 'target-node',
      type: NodeType.note,
      title: 'Target',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [source, target]);
    final container = ProviderContainer(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final linked = await container
        .read(mindmapMutationControllerProvider)
        .linkNodes(source: source, targetNodeId: target.id);
    expect(linked.relatedNodeIds, [target.id]);

    final unlinked = await container
        .read(mindmapMutationControllerProvider)
        .unlinkNodes(source: linked, targetNodeId: target.id);
    expect(unlinked.relatedNodeIds, isEmpty);
  });
}

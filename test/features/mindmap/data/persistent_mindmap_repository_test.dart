import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/persistent_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('persists saved nodes and restores them in a new repository', () async {
    final store = _MemoryMindmapNodeStore();
    final repository = PersistentMindmapRepository(store: store);
    final node = MindmapNode.create(
      id: 'note-1',
      type: NodeType.note,
      title: 'Persistent note',
      body: 'Survives refresh',
      project: 'Launch App',
      area: 'Work',
      day: DateTime(2026, 6, 18, 21),
      now: DateTime(2026, 6, 18, 9),
    );

    await repository.saveNode(node);

    final restoredRepository = PersistentMindmapRepository(store: store);

    expect(await restoredRepository.getNode('note-1'), node);
    expect((await restoredRepository.listNodes()).single, node);
    expect((await restoredRepository.searchNodes('launch app')).single, node);
    expect((await restoredRepository.searchNodes('work')).single, node);
  });

  test(
    'persists deletes so removed nodes do not return after reload',
    () async {
      final store = _MemoryMindmapNodeStore();
      final repository = PersistentMindmapRepository(store: store);
      final node = MindmapNode.create(
        id: 'task-1',
        type: NodeType.task,
        title: 'Temporary task',
        day: DateTime(2026, 6, 18),
        now: DateTime(2026, 6, 18, 9),
      );

      await repository.saveNode(node);
      await repository.deleteNode(node.id);

      final restoredRepository = PersistentMindmapRepository(store: store);

      expect(await restoredRepository.getNode(node.id), isNull);
      expect(await restoredRepository.listNodes(), isEmpty);
    },
  );

  test('uses seed nodes only when storage has not been initialized', () async {
    final store = _MemoryMindmapNodeStore();
    final seed = MindmapNode.create(
      id: 'seed-note',
      type: NodeType.note,
      title: 'Seed note',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 8),
    );
    final userNode = MindmapNode.create(
      id: 'user-note',
      type: NodeType.note,
      title: 'User note',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 9),
    );

    final repository = PersistentMindmapRepository(
      store: store,
      seedNodes: [seed],
    );

    expect((await repository.listNodes()).map((node) => node.id), [
      'seed-note',
    ]);

    await repository.saveNode(userNode);
    await repository.deleteNode(seed.id);

    final restoredRepository = PersistentMindmapRepository(
      store: store,
      seedNodes: [seed],
    );

    expect((await restoredRepository.listNodes()).map((node) => node.id), [
      'user-note',
    ]);
  });
}

final class _MemoryMindmapNodeStore implements MindmapNodeStore {
  String? nodesJson;

  @override
  Future<String?> readNodesJson() async => nodesJson;

  @override
  Future<void> writeNodesJson(String value) async {
    nodesJson = value;
  }
}

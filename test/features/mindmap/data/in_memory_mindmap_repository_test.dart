import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('lists nodes for a normalized calendar day', () async {
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'today-task',
          type: NodeType.task,
          title: 'Today task',
          day: DateTime(2026, 6, 18, 17),
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'tomorrow-note',
          type: NodeType.note,
          title: 'Tomorrow note',
          day: DateTime(2026, 6, 19),
          now: DateTime(2026, 6, 18, 9),
        ),
      ],
    );

    final nodes = await repository.listNodes(day: DateTime(2026, 6, 18, 23));

    expect(nodes.map((node) => node.id), ['today-task']);
  });

  test('upserts, fetches, searches, and deletes nodes by id', () async {
    final repository = InMemoryMindmapRepository();
    final node = MindmapNode.create(
      id: 'note-1',
      type: NodeType.note,
      title: 'Launch notes',
      body: 'HTTP sync later',
      project: 'Launch App',
      area: 'Work',
      tags: const ['work', 'release'],
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 10),
    );

    await repository.saveNode(node);

    expect(await repository.getNode('note-1'), node);
    expect((await repository.searchNodes('http')).single.id, 'note-1');
    expect((await repository.searchNodes('launch app')).single.id, 'note-1');
    expect((await repository.searchNodes('work')).single.id, 'note-1');
    expect((await repository.searchNodes('release')).single.id, 'note-1');

    await repository.deleteNode('note-1');

    expect(await repository.getNode('note-1'), isNull);
    expect(await repository.listNodes(), isEmpty);
  });
}

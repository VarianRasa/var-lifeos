import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/sembast_mindmap_node_database.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  late Database database;
  late SembastMindmapNodeDatabase nodeDatabase;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'mindmap-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    nodeDatabase = SembastMindmapNodeDatabase(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('upserts, lists, fetches, and deletes nodes', () async {
    final node = _node(
      id: 'note-1',
      type: NodeType.note,
      title: 'Persistent note',
      day: DateTime(2026, 6, 18, 21),
      now: DateTime(2026, 6, 18, 9),
    );

    final saved = await nodeDatabase.upsertNode(node);

    expect(saved.day, DateTime(2026, 6, 18));
    expect(await nodeDatabase.getNode('note-1'), saved);
    expect(await nodeDatabase.listNodes(), [saved]);

    final updated = saved.copyWith(
      title: 'Updated note',
      updatedAt: DateTime(2026, 6, 18, 10),
    );
    await nodeDatabase.upsertNode(updated);

    expect((await nodeDatabase.listNodes()).single.title, 'Updated note');

    await nodeDatabase.deleteNode('note-1');

    expect(await nodeDatabase.getNode('note-1'), isNull);
    expect(await nodeDatabase.listNodes(), isEmpty);
  });

  test('filters nodes by denormalized day key', () async {
    final first = _node(
      id: 'task-1',
      type: NodeType.task,
      title: 'Today task',
      day: DateTime(2026, 6, 18, 14),
      now: DateTime(2026, 6, 18, 8),
    );
    final second = _node(
      id: 'task-2',
      type: NodeType.task,
      title: 'Tomorrow task',
      day: DateTime(2026, 6, 19),
      now: DateTime(2026, 6, 18, 9),
    );

    await nodeDatabase.upsertNode(second);
    await nodeDatabase.upsertNode(first);

    expect(
      (await nodeDatabase.listNodes(
        day: DateTime(2026, 6, 18),
      )).map((n) => n.id),
      ['task-1'],
    );
    expect(
      (await nodeDatabase.listNodes(
        day: DateTime(2026, 6, 19),
      )).map((n) => n.id),
      ['task-2'],
    );
  });

  test(
    'searches across title, body, type, status, priority, and contexts',
    () async {
      final note = _node(
        id: 'note-1',
        type: NodeType.note,
        title: 'Draft launch memo',
        body: 'Deep market analysis',
        project: 'Launch App',
        area: 'Strategy',
        tags: ['Research', 'Memo'],
        status: NodeStatus.planned,
        priority: NodePriority.high,
        day: DateTime(2026, 6, 18),
        now: DateTime(2026, 6, 18, 9),
      );
      final task = _node(
        id: 'task-1',
        type: NodeType.task,
        title: 'Pay invoice',
        day: DateTime(2026, 6, 18),
        now: DateTime(2026, 6, 18, 10),
      );

      await nodeDatabase.upsertNode(note);
      await nodeDatabase.upsertNode(task);

      expect(
        (await nodeDatabase.searchNodes('launch app')).single.id,
        'note-1',
      );
      expect((await nodeDatabase.searchNodes('market')).single.id, 'note-1');
      expect((await nodeDatabase.searchNodes('research')).single.id, 'note-1');
      expect((await nodeDatabase.searchNodes('planned')).single.id, 'note-1');
      expect((await nodeDatabase.searchNodes('high')).single.id, 'note-1');
    },
  );

  test('persists initialization state in database metadata', () async {
    expect(await nodeDatabase.isInitialized, isFalse);

    await nodeDatabase.markInitialized();

    final reopened = SembastMindmapNodeDatabase(database: database);
    expect(await reopened.isInitialized, isTrue);
  });
}

MindmapNode _node({
  required String id,
  required NodeType type,
  required String title,
  required DateTime day,
  required DateTime now,
  String body = '',
  String project = '',
  String area = '',
  List<String> tags = const [],
  NodeStatus status = NodeStatus.open,
  NodePriority priority = NodePriority.none,
}) {
  return MindmapNode.create(
    id: id,
    type: type,
    title: title,
    body: body,
    project: project,
    area: area,
    tags: tags,
    status: status,
    priority: priority,
    day: day,
    now: now,
  );
}

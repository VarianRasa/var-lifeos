import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/sembast_mindmap_node_database.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_revision.dart';

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

  test(
    'records create update noop delete restore and monotonic sequence',
    () async {
      final node = _node(
        id: 'history-1',
        type: NodeType.note,
        title: 'Original',
        day: DateTime(2026, 6, 18),
        now: DateTime(2026, 6, 18, 8),
      );
      await nodeDatabase.upsertNode(node);
      final updated = node.copyWith(
        title: 'Updated',
        updatedAt: DateTime(2026, 6, 18, 9),
      );
      await nodeDatabase.upsertNode(updated);
      await nodeDatabase.upsertNode(updated);
      await nodeDatabase.deleteNode(node.id);

      var revisions = await nodeDatabase.listRevisions(node.id);
      expect(revisions.map((revision) => revision.kind), [
        MindmapNodeRevisionKind.deleted,
        MindmapNodeRevisionKind.updated,
        MindmapNodeRevisionKind.created,
      ]);
      final restored = await nodeDatabase.restoreRevision(
        revisions.last.id,
        now: DateTime(2026, 6, 18, 10),
      );
      revisions = await nodeDatabase.listRevisions(node.id);
      expect(restored.title, 'Original');
      expect(revisions.first.kind, MindmapNodeRevisionKind.restored);
      expect(revisions.map((revision) => revision.sequence), [4, 3, 2, 1]);
    },
  );

  test('adds baseline when existing node has no revision head', () async {
    final node = _node(
      id: 'legacy-1',
      type: NodeType.note,
      title: 'Legacy',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 8),
    );
    final store = stringMapStoreFactory.store('mindmap_nodes');
    await store.record(node.id).put(database, {
      'node': node.toJson(),
      'day': '2026-06-18',
    });

    await nodeDatabase.upsertNode(
      node.copyWith(title: 'Changed', updatedAt: DateTime(2026, 6, 18, 9)),
    );

    final revisions = await nodeDatabase.listRevisions(node.id);
    expect(revisions.last.kind, MindmapNodeRevisionKind.baseline);
    expect(revisions.last.snapshot.title, 'Legacy');
    expect(revisions.first.kind, MindmapNodeRevisionKind.updated);
  });

  test('retains latest 50 revisions and head survives reopen', () async {
    var node = _node(
      id: 'retention-1',
      type: NodeType.note,
      title: '0',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 8),
    );
    await nodeDatabase.upsertNode(node);
    for (var index = 1; index <= 55; index++) {
      node = node.copyWith(
        title: '$index',
        updatedAt: DateTime(2026, 6, 18, 8, index),
      );
      await nodeDatabase.upsertNode(node);
    }
    final reopened = SembastMindmapNodeDatabase(database: database);
    final revisions = await reopened.listRevisions(node.id);

    expect(revisions, hasLength(50));
    expect(revisions.first.sequence, 56);
    expect(revisions.last.sequence, 7);
    await reopened.deleteNode(node.id);
    expect((await reopened.listRevisions(node.id)).first.sequence, 57);
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

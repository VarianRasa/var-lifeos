import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/local_database_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/persistent_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/sembast_mindmap_node_database.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  late Database database;
  late SembastMindmapNodeDatabase nodeDatabase;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase(
      'repository-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    nodeDatabase = SembastMindmapNodeDatabase(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('uses seed nodes only before the database is initialized', () async {
    final seed = _node(
      id: 'seed-note',
      type: NodeType.note,
      title: 'Seed note',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 8),
    );
    final userNode = _node(
      id: 'user-note',
      type: NodeType.note,
      title: 'User note',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 9),
    );

    final repository = LocalDatabaseMindmapRepository(
      database: nodeDatabase,
      seedNodes: [seed],
    );

    expect((await repository.listNodes()).map((node) => node.id), [
      'seed-note',
    ]);

    await repository.saveNode(userNode);
    await repository.deleteNode(seed.id);

    final restoredRepository = LocalDatabaseMindmapRepository(
      database: SembastMindmapNodeDatabase(database: database),
      seedNodes: [seed],
    );

    expect((await restoredRepository.listNodes()).map((node) => node.id), [
      'user-note',
    ]);
  });

  test('migrates legacy JSON storage before applying seed nodes', () async {
    final legacyNode = _node(
      id: 'legacy-note',
      type: NodeType.note,
      title: 'Legacy note',
      project: 'Archive',
      day: DateTime(2026, 6, 17),
      now: DateTime(2026, 6, 17, 9),
    );
    final seed = _node(
      id: 'seed-note',
      type: NodeType.note,
      title: 'Seed note',
      day: DateTime(2026, 6, 18),
      now: DateTime(2026, 6, 18, 8),
    );
    final legacyStore = _MemoryMindmapNodeStore()
      ..nodesJson = jsonEncode({
        'version': 1,
        'nodes': [legacyNode.toJson()],
      });

    final repository = LocalDatabaseMindmapRepository(
      database: nodeDatabase,
      legacyStore: legacyStore,
      seedNodes: [seed],
    );

    expect((await repository.listNodes()).map((node) => node.id), [
      'legacy-note',
    ]);
    expect(await repository.getNode(seed.id), isNull);
    expect(await nodeDatabase.isInitialized, isTrue);

    final restoredRepository = LocalDatabaseMindmapRepository(
      database: SembastMindmapNodeDatabase(database: database),
      legacyStore: _MemoryMindmapNodeStore(),
      seedNodes: [seed],
    );

    expect(
      (await restoredRepository.searchNodes('archive')).single,
      legacyNode,
    );
  });

  test(
    'archives legacy JSON after a successful local database migration',
    () async {
      final legacyNode = _node(
        id: 'legacy-note',
        type: NodeType.note,
        title: 'Legacy note',
        day: DateTime(2026, 6, 17),
        now: DateTime(2026, 6, 17, 9),
      );
      final legacyStore = _MemoryMindmapNodeStore()
        ..nodesJson = jsonEncode({
          'version': 1,
          'nodes': [legacyNode.toJson()],
        });

      final repository = LocalDatabaseMindmapRepository(
        database: nodeDatabase,
        legacyStore: legacyStore,
      );

      expect((await repository.listNodes()).single, legacyNode);

      final archived =
          jsonDecode(legacyStore.nodesJson!) as Map<String, Object?>;
      expect(archived['version'], 2);
      expect(archived['migratedToLocalDatabase'], isTrue);
      expect(archived['nodes'], isEmpty);
    },
  );

  test(
    'persists saved nodes and restores them from the local database',
    () async {
      final repository = LocalDatabaseMindmapRepository(database: nodeDatabase);
      final node = _node(
        id: 'task-1',
        type: NodeType.task,
        title: 'Persistent task',
        body: 'Survives refresh',
        project: 'Launch App',
        area: 'Work',
        day: DateTime(2026, 6, 18, 21),
        now: DateTime(2026, 6, 18, 9),
      );

      await repository.saveNode(node);

      final restoredRepository = LocalDatabaseMindmapRepository(
        database: SembastMindmapNodeDatabase(database: database),
      );

      expect(await restoredRepository.getNode('task-1'), node);
      expect(
        (await restoredRepository.listNodes(day: DateTime(2026, 6, 18))).single,
        node,
      );
      expect((await restoredRepository.searchNodes('launch app')).single, node);
      expect((await restoredRepository.searchNodes('work')).single, node);
    },
  );

  test(
    'persists deletes so removed nodes do not return after reload',
    () async {
      final repository = LocalDatabaseMindmapRepository(database: nodeDatabase);
      final node = _node(
        id: 'task-1',
        type: NodeType.task,
        title: 'Temporary task',
        day: DateTime(2026, 6, 18),
        now: DateTime(2026, 6, 18, 9),
      );

      await repository.saveNode(node);
      await repository.deleteNode(node.id);

      final restoredRepository = LocalDatabaseMindmapRepository(
        database: SembastMindmapNodeDatabase(database: database),
      );

      expect(await restoredRepository.getNode(node.id), isNull);
      expect(await restoredRepository.listNodes(), isEmpty);
    },
  );
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
}) {
  return MindmapNode.create(
    id: id,
    type: type,
    title: title,
    body: body,
    project: project,
    area: area,
    tags: tags,
    day: day,
    now: now,
  );
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

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/data/sembast_sync_restore_point_store.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';
import 'package:var_app/features/sync/domain/sync_restore_point.dart';

void main() {
  test('stores recent restore points newest first and reads by id', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'sync-restore-points.db',
    );
    addTearDown(database.close);
    final store = SembastSyncRestorePointStore(database: database);
    final older = _point(
      id: 'older',
      title: 'Older note',
      createdAt: DateTime(2026, 6, 20, 9),
    );
    final newer = _point(
      id: 'newer',
      title: 'Newer note',
      createdAt: DateTime(2026, 6, 20, 11),
    );

    await store.add(older);
    await store.add(newer);

    final recent = await store.recent(limit: 1);
    final found = await store.read('older');

    expect(recent.single.id, 'newer');
    expect(found?.document.nodes.single.title, 'Older note');
  });

  test('deletes restore points and prunes old snapshots', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'sync-restore-points-delete.db',
    );
    addTearDown(database.close);
    final store = SembastSyncRestorePointStore(database: database);
    final oldest = _point(
      id: 'oldest',
      title: 'Oldest note',
      createdAt: DateTime(2026, 6, 20, 9),
    );
    final middle = _point(
      id: 'middle',
      title: 'Middle note',
      createdAt: DateTime(2026, 6, 20, 10),
    );
    final newest = _point(
      id: 'newest',
      title: 'Newest note',
      createdAt: DateTime(2026, 6, 20, 11),
    );

    await store.add(oldest);
    await store.add(middle);
    await store.add(newest);

    await store.delete('middle');
    await store.prune(keepLatest: 1);

    expect(await store.read('middle'), isNull);
    expect(await store.read('oldest'), isNull);
    expect((await store.recent()).map((point) => point.id), ['newest']);
  });
}

SyncRestorePoint _point({
  required String id,
  required String title,
  required DateTime createdAt,
}) {
  return SyncRestorePoint(
    id: id,
    label: title,
    createdAt: createdAt,
    document: MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      exportedAt: createdAt,
      nodes: [
        MindmapNode.create(
          id: id,
          type: NodeType.note,
          title: title,
          day: DateTime(2026, 6, 20),
          now: DateTime(2026, 6, 20, 8),
        ),
      ],
    ),
  );
}

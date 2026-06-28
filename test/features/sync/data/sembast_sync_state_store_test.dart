import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/data/sembast_sync_state_store.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';
import 'package:var_app/features/sync/domain/sync_account.dart';
import 'package:var_app/features/sync/domain/sync_state_store.dart';

void main() {
  test('persists sync snapshots per user', () async {
    final database = await databaseFactoryMemory.openDatabase('sync-state.db');
    addTearDown(database.close);
    final store = SembastSyncStateStore(database: database);
    const user = SyncUser(id: 'user-1', email: 'user@example.com');
    const otherUser = SyncUser(id: 'user-2', email: 'other@example.com');
    final baseline = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      exportedAt: DateTime(2026, 6, 18, 12),
      nodes: [
        MindmapNode.create(
          id: 'note-1',
          type: NodeType.note,
          title: 'Synced note',
          day: DateTime(2026, 6, 18),
          now: DateTime(2026, 6, 18, 9),
        ),
      ],
    );
    final snapshot = SyncSnapshot(
      userId: user.id,
      syncedAt: DateTime(2026, 6, 18, 12, 5),
      baseline: baseline,
    );

    await store.saveSnapshot(user, snapshot);

    final restored = await SembastSyncStateStore(
      database: database,
    ).readSnapshot(user);

    expect(restored?.userId, 'user-1');
    expect(restored?.syncedAt, DateTime(2026, 6, 18, 12, 5));
    expect(restored?.baseline.nodes.single.title, 'Synced note');
    expect(await store.readSnapshot(otherUser), isNull);
  });

  test('clears a stored sync snapshot', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'sync-state-clear.db',
    );
    addTearDown(database.close);
    final store = SembastSyncStateStore(database: database);
    const user = SyncUser(id: 'user-1', email: 'user@example.com');
    final snapshot = SyncSnapshot(
      userId: user.id,
      syncedAt: DateTime(2026, 6, 18, 12),
      baseline: MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
        exportedAt: DateTime(2026, 6, 18, 12),
        nodes: const [],
      ),
    );

    await store.saveSnapshot(user, snapshot);
    await store.clearSnapshot(user);

    expect(await store.readSnapshot(user), isNull);
  });
}

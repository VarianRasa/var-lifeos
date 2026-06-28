import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/sync/data/sembast_sync_activity_store.dart';
import 'package:var_app/features/sync/domain/sync_activity.dart';

void main() {
  test('stores recent sync activity newest first with a limit', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'sync-activity.db',
    );
    addTearDown(database.close);
    final store = SembastSyncActivityStore(database: database);

    await store.add(_entry(id: 'old', minute: 1, message: 'Old sync'));
    await store.add(_entry(id: 'middle', minute: 2, message: 'Middle sync'));
    await store.add(_entry(id: 'new', minute: 3, message: 'New sync'));

    final recent = await SembastSyncActivityStore(
      database: database,
    ).recent(limit: 2);

    expect(recent.map((entry) => entry.id), ['new', 'middle']);
    expect(recent.first.message, 'New sync');
  });

  test('clears stored sync activity entries', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'sync-activity-clear.db',
    );
    addTearDown(database.close);
    final store = SembastSyncActivityStore(database: database);

    await store.add(_entry(id: 'entry', minute: 1, message: 'Sync'));
    await store.clear();

    expect(await store.recent(), isEmpty);
  });
}

SyncActivityEntry _entry({
  required String id,
  required int minute,
  required String message,
}) {
  return SyncActivityEntry(
    id: id,
    action: SyncActivityAction.pull,
    status: SyncActivityStatus.success,
    message: message,
    occurredAt: DateTime(2026, 6, 19, 12, minute),
    savedCount: minute,
    deletedCount: 0,
    conflictCount: 0,
  );
}

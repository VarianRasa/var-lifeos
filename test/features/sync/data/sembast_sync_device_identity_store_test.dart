import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/sync/data/sembast_sync_device_identity_store.dart';

void main() {
  test('creates and persists a stable device identity', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'sync-device-identity.db',
    );
    addTearDown(database.close);
    var generatedCount = 0;
    final store = SembastSyncDeviceIdentityStore(
      database: database,
      idGenerator: () {
        generatedCount += 1;
        return 'device-fixed';
      },
      defaultLabel: 'Work laptop',
    );

    final created = await store.readOrCreateIdentity();
    final restored = await SembastSyncDeviceIdentityStore(
      database: database,
      idGenerator: () {
        generatedCount += 1;
        return 'device-other';
      },
    ).readOrCreateIdentity();

    expect(created.id, 'device-fixed');
    expect(created.label, 'Work laptop');
    expect(restored, created);
    expect(generatedCount, 1);
  });

  test('updates the persisted device label', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'sync-device-identity-label.db',
    );
    addTearDown(database.close);
    final store = SembastSyncDeviceIdentityStore(
      database: database,
      idGenerator: () => 'device-fixed',
    );

    await store.readOrCreateIdentity();
    final updated = await store.updateLabel('  Travel phone  ');
    final restored = await store.readOrCreateIdentity();

    expect(updated.id, 'device-fixed');
    expect(updated.label, 'Travel phone');
    expect(restored.label, 'Travel phone');
  });
}

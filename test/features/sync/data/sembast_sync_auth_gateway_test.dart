import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/sync/data/sembast_sync_auth_gateway.dart';
import 'package:var_app/features/sync/domain/sync_account.dart';

void main() {
  test('persists signed-in account across gateway instances', () async {
    final database = await databaseFactoryMemory.openDatabase('sync-auth.db');
    addTearDown(database.close);
    final gateway = SembastSyncAuthGateway(database: database);

    final signedIn = await gateway.signIn(
      email: 'USER@example.com',
      displayName: 'User',
    );

    expect(signedIn.status, SyncAuthStatus.signedIn);
    expect(signedIn.user?.email, 'user@example.com');

    final restored = await SembastSyncAuthGateway(
      database: database,
    ).currentState();

    expect(restored.status, SyncAuthStatus.signedIn);
    expect(restored.user?.id, 'local-user@example.com');
    expect(restored.user?.displayName, 'User');
  });

  test('clears persisted account on sign out', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'sync-auth-sign-out.db',
    );
    addTearDown(database.close);
    final gateway = SembastSyncAuthGateway(database: database);

    await gateway.signIn(email: 'user@example.com');
    await gateway.signOut();

    final restored = await SembastSyncAuthGateway(
      database: database,
    ).currentState();

    expect(restored.status, SyncAuthStatus.signedOut);
    expect(restored.user, isNull);
  });
}

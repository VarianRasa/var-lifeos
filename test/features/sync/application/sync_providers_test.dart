import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/application/sync_providers.dart';
import 'package:var_app/features/sync/data/http_sync_remote_backup_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_remote_backup_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_state_store.dart';
import 'package:var_app/features/sync/data/local_sync_auth_gateway.dart';
import 'package:var_app/features/sync/data/sembast_sync_auth_gateway.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';

void main() {
  test(
    'cloudSyncServiceProvider wires repository, auth, remote, and state',
    () async {
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'note-1',
            type: NodeType.note,
            title: 'Provider note',
            day: DateTime(2026, 6, 18),
            now: DateTime(2026, 6, 18, 9),
          ),
        ],
      );
      final authGateway = LocalSyncAuthGateway();
      final remoteStore = InMemorySyncRemoteBackupStore();
      final syncStateStore = InMemorySyncStateStore();
      final container = ProviderContainer(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          syncAuthGatewayProvider.overrideWithValue(authGateway),
          syncRemoteBackupStoreProvider.overrideWithValue(remoteStore),
          syncStateStoreProvider.overrideWithValue(syncStateStore),
          syncDeviceIdentityProvider.overrideWithValue(
            const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
          ),
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 18, 12)),
        ],
      );
      addTearDown(container.dispose);
      final account = await authGateway.signIn(email: 'user@example.com');

      final document = await container
          .read(cloudSyncServiceProvider)
          .pushBackup();

      expect(document.sourceDevice.id, 'device-test');
      expect(
        (await remoteStore.fetchLatestBackup(account.user!))?.nodes.length,
        1,
      );
      expect(
        (await syncStateStore.readSnapshot(
          account.user!,
        ))?.baseline.nodes.length,
        1,
      );
    },
  );

  test(
    'syncAuthGatewayProvider uses a persistent auth gateway by default',
    () async {
      final database = await databaseFactoryMemory.openDatabase(
        'sync-provider-auth.db',
      );
      addTearDown(database.close);

      final container = ProviderContainer(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
          mindmapDatabaseProvider.overrideWithValue(Future.value(database)),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(syncAuthGatewayProvider),
        isA<SembastSyncAuthGateway>(),
      );
    },
  );

  test(
    'syncDeviceIdentityProvider creates a persistent device identity',
    () async {
      final database = await databaseFactoryMemory.openDatabase(
        'sync-provider-device-identity.db',
      );
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [
          mindmapDatabaseProvider.overrideWithValue(Future.value(database)),
        ],
      );
      addTearDown(container.dispose);

      final identity = await Future.value(
        container.read(syncDeviceIdentityProvider),
      );

      expect(identity.id, isNot('local-device'));
      expect(identity.id, startsWith('device-'));
      expect(identity.label, 'This device');
    },
  );

  test('syncRemoteBackupStoreProvider uses in-memory storage by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(syncRemoteBackupStoreProvider),
      isA<InMemorySyncRemoteBackupStore>(),
    );
  });

  test('syncRemoteBackupStoreProvider uses HTTP storage when configured', () {
    final container = ProviderContainer(
      overrides: [
        syncRemoteConfigProvider.overrideWithValue(
          SyncRemoteConfig(
            endpoint: Uri.parse('https://api.var.app/sync'),
            accessToken: 'token-123',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(syncRemoteBackupStoreProvider),
      isA<HttpSyncRemoteBackupStore>(),
    );
  });

  test(
    'configured HTTP sync uses the signed-in session token for backup',
    () async {
      final database = await databaseFactoryMemory.openDatabase(
        'sync-provider-http-auth.db',
      );
      addTearDown(database.close);
      http.Request? backupRequest;
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'note-1',
            type: NodeType.note,
            title: 'HTTP sync note',
            day: DateTime(2026, 6, 19),
            now: DateTime(2026, 6, 19, 9),
          ),
        ],
      );
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/auth/sign-in')) {
          return http.Response(
            jsonEncode({
              'user': {'id': 'user-1', 'email': 'user@example.com'},
              'accessToken': 'session-token-123',
            }),
            200,
          );
        }

        backupRequest = request;
        return http.Response('', 204);
      });
      final container = ProviderContainer(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          mindmapDatabaseProvider.overrideWithValue(Future.value(database)),
          syncRemoteConfigProvider.overrideWithValue(
            SyncRemoteConfig(endpoint: Uri.parse('https://api.var.app/sync')),
          ),
          syncHttpClientProvider.overrideWithValue(client),
          syncDeviceIdentityProvider.overrideWithValue(
            const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
          ),
          syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 19, 12)),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(syncAuthGatewayProvider)
          .signIn(email: 'user@example.com');
      await container.read(cloudSyncServiceProvider).pushBackup();

      final request = backupRequest;
      expect(request, isNotNull);
      expect(request!.headers['authorization'], 'Bearer session-token-123');
    },
  );
}

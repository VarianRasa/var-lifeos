import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/application/sync_providers.dart';
import 'package:var_app/features/sync/data/firebase_remote_attachment_store.dart';
import 'package:var_app/features/sync/data/firestore_sync_remote_backup_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_remote_backup_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_state_store.dart';
import 'package:var_app/features/sync/data/local_sync_auth_gateway.dart';
import 'package:var_app/features/sync/data/sembast_attachment_sync_progress_store.dart';
import 'package:var_app/features/sync/domain/attachment_sync.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';
import 'package:var_app/features/sync/domain/sync_account.dart';

void main() {
  test('attachment progress provider uses persistent Sembast store', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'attachment-progress-provider.db',
    );
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [
        mindmapDatabaseProvider.overrideWithValue(Future.value(database)),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(attachmentSyncProgressStoreProvider),
      isA<SembastAttachmentSyncProgressStore>(),
    );
  });

  test('Firebase attachment provider stays lazy when ineligible', () async {
    final gateway = _CountingFirebaseStorageGateway();
    final container = ProviderContainer(
      overrides: [
        firebaseAttachmentEligibilityProvider.overrideWithValue(false),
        firebaseStorageGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    expect(
      (await container.read(
        attachmentSyncAdapterProvider.future,
      )).attachmentSyncCapability,
      AttachmentSyncCapability.localOnly,
    );
    expect(gateway.accessCount, 0);
  });

  test(
    'eligible Firebase attachment provider exposes supported adapter',
    () async {
      final gateway = _CountingFirebaseStorageGateway();
      final container = ProviderContainer(
        overrides: [
          firebaseAttachmentEligibilityProvider.overrideWithValue(true),
          firebaseAttachmentUserIdProvider.overrideWithValue('user_123'),
          firebaseStorageGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(attachmentSyncAdapterProvider.future),
        isA<FirebaseRemoteAttachmentStore>(),
      );
      expect(
        (await container.read(
          attachmentSyncAdapterProvider.future,
        )).attachmentSyncCapability,
        AttachmentSyncCapability.supported,
      );
      expect(gateway.accessCount, 0);
    },
  );

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

  test('syncAuthGatewayProvider uses Firebase auth', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(syncAuthGatewayProvider), isA<SyncAuthGateway>());
    expect(
      container.read(syncAuthGatewayProvider).runtimeType.toString(),
      contains('RevisionTrackingSyncAuthGateway'),
    );
  });

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

  test('syncRemoteBackupStoreProvider uses Firestore', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(syncRemoteBackupStoreProvider),
      isA<FirestoreSyncRemoteBackupStore>(),
    );
  });
}

final class _CountingFirebaseStorageGateway implements FirebaseStorageGateway {
  int accessCount = 0;

  @override
  Future<FirebaseStorageObject?> get(
    String key, {
    required int maxBytes,
  }) async {
    accessCount++;
    return null;
  }

  @override
  Future<FirebaseStorageObjectMetadata?> head(String key) async {
    accessCount++;
    return null;
  }

  @override
  Future<void> put({
    required String key,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
  }) async {
    accessCount++;
  }
}

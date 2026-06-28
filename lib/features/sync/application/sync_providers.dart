/// Riverpod graph for sync, backup, auth, and remote adapters.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/runtime_config.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../data/http_sync_auth_gateway.dart';
import '../data/http_sync_remote_backup_store.dart';
import '../data/in_memory_sync_remote_backup_store.dart';
import '../data/sembast_sync_activity_store.dart';
import '../data/sembast_sync_auth_gateway.dart';
import '../data/sembast_sync_device_identity_store.dart';
import '../data/sembast_sync_restore_point_store.dart';
import '../data/sembast_sync_state_store.dart';
import '../domain/mindmap_backup_document.dart';
import '../domain/sync_account.dart';
import '../domain/sync_activity.dart';
import '../domain/sync_device_identity_store.dart';
import '../domain/sync_restore_point.dart';
import '../domain/sync_state_store.dart';
import 'cloud_sync_service.dart';
import 'mindmap_backup_service.dart';
import 'portable_backup_codec.dart';

final class SyncRemoteConfig {
  const SyncRemoteConfig({this.endpoint, this.accessToken});

  final Uri? endpoint;
  final String? accessToken;

  bool get hasEndpoint => endpoint != null;
}

final syncRemoteConfigProvider = Provider<SyncRemoteConfig>((ref) {
  final config = ref.watch(runtimeConfigProvider);
  return SyncRemoteConfig(endpoint: config.syncEndpoint);
});

final syncHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final syncAuthGatewayProvider = Provider<SyncAuthGateway>((ref) {
  final config = ref.watch(syncRemoteConfigProvider);
  final endpoint = config.endpoint;
  if (endpoint != null) {
    return HttpSyncAuthGateway(
      endpoint: endpoint,
      database: ref.watch(mindmapDatabaseProvider),
      client: ref.watch(syncHttpClientProvider),
    );
  }

  return SembastSyncAuthGateway(database: ref.watch(mindmapDatabaseProvider));
});

final syncRemoteBackupStoreProvider = Provider<SyncRemoteBackupStore>((ref) {
  final config = ref.watch(syncRemoteConfigProvider);
  final endpoint = config.endpoint;
  if (endpoint != null) {
    return HttpSyncRemoteBackupStore(
      endpoint: endpoint,
      client: ref.watch(syncHttpClientProvider),
      tokenProvider: () async {
        final configuredToken = config.accessToken?.trim() ?? '';
        if (configuredToken.isNotEmpty) return configuredToken;
        return (await ref.read(syncAuthGatewayProvider).currentState())
            .accessToken;
      },
    );
  }

  return InMemorySyncRemoteBackupStore();
});

final syncStateStoreProvider = Provider<SyncStateStore>((ref) {
  return SembastSyncStateStore(database: ref.watch(mindmapDatabaseProvider));
});

final syncActivityStoreProvider = Provider<SyncActivityStore>((ref) {
  return SembastSyncActivityStore(database: ref.watch(mindmapDatabaseProvider));
});

final syncRestorePointStoreProvider = Provider<SyncRestorePointStore>((ref) {
  return SembastSyncRestorePointStore(
    database: ref.watch(mindmapDatabaseProvider),
  );
});

final syncDeviceIdentityStoreProvider = Provider<SyncDeviceIdentityStore>((
  ref,
) {
  return SembastSyncDeviceIdentityStore(
    database: ref.watch(mindmapDatabaseProvider),
  );
});

final syncDeviceIdentityProvider = Provider<FutureOr<SyncDeviceIdentity>>((
  ref,
) {
  return ref.watch(syncDeviceIdentityStoreProvider).readOrCreateIdentity();
});

final syncNowProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

final portableBackupCodecProvider = Provider<PortableMindmapBackupCodec>((ref) {
  return PortableMindmapBackupCodec();
});

final mindmapBackupServiceProvider = Provider<MindmapBackupService>((ref) {
  return MindmapBackupService(
    repository: ref.watch(mindmapRepositoryProvider),
    sourceDevice: ref.watch(syncDeviceIdentityProvider),
    now: ref.watch(syncNowProvider),
    portableCodec: ref.watch(portableBackupCodecProvider),
  );
});

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  return CloudSyncService(
    repository: ref.watch(mindmapRepositoryProvider),
    authGateway: ref.watch(syncAuthGatewayProvider),
    remoteStore: ref.watch(syncRemoteBackupStoreProvider),
    syncStateStore: ref.watch(syncStateStoreProvider),
    sourceDevice: ref.watch(syncDeviceIdentityProvider),
    now: ref.watch(syncNowProvider),
    backupService: ref.watch(mindmapBackupServiceProvider),
  );
});

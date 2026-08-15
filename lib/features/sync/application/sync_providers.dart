/// Riverpod graph for sync, backup, auth, and remote adapters.
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mindmap/application/mindmap_providers.dart';
import '../application/attachment_sync_executor.dart';
import '../data/firebase_remote_attachment_store.dart';
import '../data/firebase_sync_auth_gateway.dart';
import '../data/firestore_sync_remote_backup_store.dart';
import '../data/sembast_attachment_sync_progress_store.dart';
import '../data/sembast_sync_activity_store.dart';
import '../data/sembast_sync_device_identity_store.dart';
import '../data/sembast_sync_restore_point_store.dart';
import '../data/sembast_sync_state_store.dart';
import '../domain/attachment_sync.dart';
import '../domain/attachment_sync_progress.dart';
import '../domain/mindmap_backup_document.dart';
import '../domain/remote_attachment_store.dart';
import '../domain/sync_account.dart';
import '../domain/sync_activity.dart';
import '../domain/sync_device_identity_store.dart';
import '../domain/sync_restore_point.dart';
import '../domain/sync_state_store.dart';
import 'cloud_sync_service.dart';
import 'mindmap_backup_service.dart';
import 'portable_backup_codec.dart';

final syncAuthRevisionProvider = StateProvider<int>((ref) => 0);

final syncAuthGatewayProvider = Provider<SyncAuthGateway>((ref) {
  return _RevisionTrackingSyncAuthGateway(
    delegate: FirebaseSyncAuthGateway(),
    onChanged: () {
      ref.read(syncAuthRevisionProvider.notifier).state++;
    },
  );
});

final syncRemoteBackupStoreProvider = Provider<SyncRemoteBackupStore>((ref) {
  return FirestoreSyncRemoteBackupStore();
});

final attachmentSyncAdapterProvider = FutureProvider<AttachmentSyncAdapter>((
  ref,
) async {
  if (ref.watch(firebaseAttachmentEligibilityProvider)) {
    return FirebaseRemoteAttachmentStore(
      gateway: ref.watch(firebaseStorageGatewayProvider),
      userIdProvider: () => ref.read(firebaseAttachmentUserIdProvider),
    );
  }
  return const UnsupportedAttachmentSyncAdapter(
    AttachmentSyncCapability.localOnly,
  );
});

final firebaseAttachmentPlatformSupportedProvider = Provider<bool>((ref) {
  if (kIsWeb) return true;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.linux || TargetPlatform.fuchsia => false,
  };
});

final firebaseInitializedProvider = Provider<bool>((ref) {
  return Firebase.apps.isNotEmpty;
});

final firebaseAttachmentAuthStateProvider = StreamProvider<String?>((ref) {
  if (!ref.watch(firebaseInitializedProvider)) {
    return Stream<String?>.value(null);
  }
  return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
});

final firebaseAttachmentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(firebaseAttachmentAuthStateProvider).value;
});

final firebaseAttachmentEligibilityProvider = Provider<bool>((ref) {
  return ref.watch(firebaseAttachmentPlatformSupportedProvider) &&
      ref.watch(firebaseInitializedProvider) &&
      ref.watch(firebaseAttachmentUserIdProvider) != null;
});

final firebaseStorageGatewayProvider = Provider<FirebaseStorageGateway>((ref) {
  return FirebaseStorageGatewayImpl();
});

final class _RevisionTrackingSyncAuthGateway implements SyncAuthGateway {
  const _RevisionTrackingSyncAuthGateway({
    required SyncAuthGateway delegate,
    required void Function() onChanged,
  }) : _delegate = delegate,
       _onChanged = onChanged;

  final SyncAuthGateway _delegate;
  final void Function() _onChanged;

  @override
  Future<SyncAuthState> currentState() => _delegate.currentState();

  @override
  Future<SyncAuthState> signIn({
    required String email,
    String password = '',
    String displayName = '',
  }) async {
    final state = await _delegate.signIn(
      email: email,
      password: password,
      displayName: displayName,
    );
    _onChanged();
    return state;
  }

  @override
  Future<SyncAuthState> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    final state = await _delegate.register(
      email: email,
      password: password,
      displayName: displayName,
    );
    _onChanged();
    return state;
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) =>
      _delegate.sendPasswordResetEmail(email: email);

  @override
  Future<void> signOut() async {
    await _delegate.signOut();
    _onChanged();
  }
}

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

final attachmentSyncProgressStoreProvider =
    Provider<AttachmentSyncProgressStore>((ref) {
      return SembastAttachmentSyncProgressStore(
        database: ref.watch(mindmapDatabaseProvider),
      );
    });

final attachmentSyncExecutorProvider = FutureProvider<AttachmentSyncExecutor?>((
  ref,
) async {
  final adapter = await ref.watch(attachmentSyncAdapterProvider.future);
  if (adapter is! RemoteAttachmentStore) return null;
  final remoteStore = adapter as RemoteAttachmentStore;
  return AttachmentSyncExecutor(
    mindmapRepository: ref.watch(mindmapRepositoryProvider),
    attachmentRepository: await ref.watch(
      nodeAttachmentRepositoryProvider.future,
    ),
    remoteStore: remoteStore,
    progressStore: ref.watch(attachmentSyncProgressStoreProvider),
    remoteStoreKind: AttachmentRemoteStoreKind.firebase,
    now: ref.watch(syncNowProvider),
  );
});

final attachmentSyncRunnerProvider =
    Provider<Future<AttachmentSyncExecutionReport> Function()>((ref) {
      return () async {
        final executor = await ref.read(attachmentSyncExecutorProvider.future);
        if (executor == null) {
          return const AttachmentSyncExecutionReport(
            warnings: ['Attachment sync is unavailable.'],
          );
        }
        return executor.run();
      };
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
    attachmentRepositoryLoader: () =>
        ref.read(nodeAttachmentRepositoryProvider.future),
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

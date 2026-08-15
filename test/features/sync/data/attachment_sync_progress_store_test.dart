import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/sync/data/sembast_attachment_sync_progress_store.dart';
import 'package:var_app/features/sync/domain/attachment_sync.dart';
import 'package:var_app/features/sync/domain/attachment_sync_progress.dart';

void main() {
  test(
    'Sembast progress survives store recreation without sensitive data',
    () async {
      final database = await databaseFactoryMemory.openDatabase('progress.db');
      addTearDown(database.close);
      final first = SembastAttachmentSyncProgressStore(database: database);
      const progress = AttachmentSyncProgress(
        attachmentId: '123e4567-e89b-42d3-a456-426614174000',
        direction: AttachmentSyncDirection.upload,
        remoteStoreKind: AttachmentRemoteStoreKind.http,
        attempt: 2,
        state: AttachmentSyncProgressState.waitingRetry,
        lastError: 'Offline.',
      );

      await first.write(progress);
      final restored = await SembastAttachmentSyncProgressStore(
        database: database,
      ).readAll();

      expect(restored.single.toJson(), progress.toJson());
      expect(restored.single.toJson().keys, isNot(contains('bytes')));
      expect(restored.single.toJson().keys, isNot(contains('path')));
      expect(restored.single.toJson().keys, isNot(contains('token')));
    },
  );

  test(
    'migrates legacy key atomically and preserves pending progress',
    () async {
      final database = await databaseFactoryMemory.openDatabase(
        'legacy-progress.db',
      );
      addTearDown(database.close);
      final rawStore = stringMapStoreFactory.store(
        'attachment_sync_progress_v1',
      );
      const progress = AttachmentSyncProgress(
        attachmentId: '123e4567-e89b-42d3-a456-426614174000',
        direction: AttachmentSyncDirection.upload,
        remoteStoreKind: AttachmentRemoteStoreKind.http,
        attempt: 2,
        state: AttachmentSyncProgressState.waitingRetry,
        lastError: 'Offline.',
      );
      await rawStore
          .record('upload:123e4567-e89b-42d3-a456-426614174000')
          .put(database, progress.toJson());

      final restored = await SembastAttachmentSyncProgressStore(
        database: database,
      ).readAll();
      final records = await rawStore.find(database);

      expect(restored, hasLength(1));
      expect(restored.single.key, progress.key);
      expect(restored.single.state, AttachmentSyncProgressState.waitingRetry);
      expect(records, hasLength(1));
      expect(records.single.key, progress.key);
    },
  );

  test(
    'canonical record wins legacy collision without duplicate progress',
    () async {
      final database = await databaseFactoryMemory.openDatabase(
        'legacy-collision.db',
      );
      addTearDown(database.close);
      final rawStore = stringMapStoreFactory.store(
        'attachment_sync_progress_v1',
      );
      const legacy = AttachmentSyncProgress(
        attachmentId: '123e4567-e89b-42d3-a456-426614174000',
        direction: AttachmentSyncDirection.upload,
        remoteStoreKind: AttachmentRemoteStoreKind.firebase,
        attempt: 5,
        state: AttachmentSyncProgressState.waitingRetry,
        lastError: 'Legacy.',
      );
      const current = AttachmentSyncProgress(
        attachmentId: '123e4567-e89b-42d3-a456-426614174000',
        direction: AttachmentSyncDirection.upload,
        remoteStoreKind: AttachmentRemoteStoreKind.firebase,
        attempt: 1,
        state: AttachmentSyncProgressState.waitingAuth,
        lastError: 'Current.',
      );
      await rawStore
          .record('upload:123e4567-e89b-42d3-a456-426614174000')
          .put(database, legacy.toJson());
      await rawStore.record(current.key).put(database, current.toJson());

      final restored = await SembastAttachmentSyncProgressStore(
        database: database,
      ).readAll();
      final records = await rawStore.find(database);

      expect(restored, hasLength(1));
      expect(restored.single.attempt, 1);
      expect(restored.single.state, AttachmentSyncProgressState.waitingAuth);
      expect(records, hasLength(1));
      expect(records.single.key, current.key);
    },
  );
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/application/portable_backup_codec.dart';
import 'package:var_app/features/sync/application/sync_controller.dart';
import 'package:var_app/features/sync/application/sync_providers.dart';
import 'package:var_app/features/sync/data/http_sync_remote_backup_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_activity_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_device_identity_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_remote_backup_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_restore_point_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_state_store.dart';
import 'package:var_app/features/sync/data/local_sync_auth_gateway.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';
import 'package:var_app/features/sync/domain/sync_account.dart';
import 'package:var_app/features/sync/domain/sync_activity.dart';

void main() {
  test('signs in and pushes a backup through the controller', () async {
    final repository = InMemoryMindmapRepository(
      seedNodes: [_node(id: 'note-1', title: 'Cloud note')],
    );
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final syncStateStore = InMemorySyncStateStore();
    final container = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: syncStateStore,
    );
    addTearDown(container.dispose);

    await container
        .read(syncControllerProvider.notifier)
        .signIn(email: 'USER@example.com', displayName: 'User');
    await container.read(syncControllerProvider.notifier).pushBackup();

    final state = container.read(syncControllerProvider);
    final account = await authGateway.currentState();

    expect(state.isSignedIn, isTrue);
    expect(state.email, 'user@example.com');
    expect(state.lastMessage, 'Backup pushed');
    expect(state.lastSavedCount, 1);
    expect(
      (await remoteStore.fetchLatestBackup(account.user!))?.nodes.length,
      1,
    );
    expect(
      (await syncStateStore.readSnapshot(account.user!))?.baseline.nodes.length,
      1,
    );
  });

  test('pulls remote changes and reports conflict counts', () async {
    final baseline = _node(id: 'shared', title: 'Shared');
    final local = baseline.copyWith(
      title: 'Local edit',
      updatedAt: DateTime(2026, 6, 18, 10),
    );
    final remote = baseline.copyWith(
      title: 'Remote edit',
      updatedAt: DateTime(2026, 6, 18, 11),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [baseline]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final syncStateStore = InMemorySyncStateStore();
    final container = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: syncStateStore,
    );
    addTearDown(container.dispose);

    await container
        .read(syncControllerProvider.notifier)
        .signIn(email: 'user@example.com');
    await container.read(syncControllerProvider.notifier).pushBackup();
    await repository.saveNode(local);
    final account = await authGateway.currentState();
    await remoteStore.uploadBackup(
      account.user!,
      MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
        exportedAt: DateTime(2026, 6, 18, 13),
        nodes: [remote],
      ),
    );

    await container.read(syncControllerProvider.notifier).pullBackup();

    final state = container.read(syncControllerProvider);
    expect(state.lastMessage, 'Sync blocked by conflicts');
    expect(state.lastConflictCount, 1);
    expect(state.pendingConflicts, hasLength(1));
    expect(state.pendingConflicts.single.nodeId, 'shared');
    expect(state.pendingConflicts.single.kindLabel, 'Both edited');
    expect(state.pendingConflicts.single.baselineTitle, 'Shared');
    expect(state.pendingConflicts.single.localTitle, 'Local edit');
    expect(state.pendingConflicts.single.remoteTitle, 'Remote edit');
    expect(
      state.pendingConflicts.single.baselineDetail,
      'Note / 2026-06-18 / Open / Updated 2026-06-18 09:00',
    );
    expect(
      state.pendingConflicts.single.localDetail,
      'Note / 2026-06-18 / Open / Updated 2026-06-18 10:00',
    );
    expect(
      state.pendingConflicts.single.remoteDetail,
      'Note / 2026-06-18 / Open / Updated 2026-06-18 11:00',
    );
    expect((await repository.getNode('shared'))?.title, 'Local edit');
  });

  test('resolves pending conflicts by applying the remote version', () async {
    final baseline = _node(id: 'shared', title: 'Shared');
    final local = baseline.copyWith(
      title: 'Local edit',
      updatedAt: DateTime(2026, 6, 18, 10),
    );
    final remote = baseline.copyWith(
      title: 'Remote edit',
      updatedAt: DateTime(2026, 6, 18, 11),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [baseline]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final syncStateStore = InMemorySyncStateStore();
    final container = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: syncStateStore,
    );
    addTearDown(container.dispose);

    await container
        .read(syncControllerProvider.notifier)
        .signIn(email: 'user@example.com');
    await container.read(syncControllerProvider.notifier).pushBackup();
    await repository.saveNode(local);
    final account = await authGateway.currentState();
    await remoteStore.uploadBackup(
      account.user!,
      MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
        exportedAt: DateTime(2026, 6, 18, 13),
        nodes: [remote],
      ),
    );

    await container.read(syncControllerProvider.notifier).pullBackup();
    await container
        .read(syncControllerProvider.notifier)
        .resolveConflictsWithRemote();

    final state = container.read(syncControllerProvider);
    expect(state.lastMessage, 'Remote version applied');
    expect(state.lastConflictCount, 0);
    expect(state.pendingConflicts, isEmpty);
    expect((await repository.getNode('shared'))?.title, 'Remote edit');
  });

  test(
    'resolves one pending conflict by applying its remote version',
    () async {
      final baseline = _node(id: 'shared', title: 'Shared');
      final local = baseline.copyWith(
        title: 'Local edit',
        updatedAt: DateTime(2026, 6, 18, 10),
      );
      final remote = baseline.copyWith(
        title: 'Remote edit',
        updatedAt: DateTime(2026, 6, 18, 11),
      );
      final repository = InMemoryMindmapRepository(seedNodes: [baseline]);
      final authGateway = LocalSyncAuthGateway();
      final remoteStore = InMemorySyncRemoteBackupStore();
      final syncStateStore = InMemorySyncStateStore();
      final container = _container(
        repository: repository,
        authGateway: authGateway,
        remoteStore: remoteStore,
        syncStateStore: syncStateStore,
      );
      addTearDown(container.dispose);

      await container
          .read(syncControllerProvider.notifier)
          .signIn(email: 'user@example.com');
      await container.read(syncControllerProvider.notifier).pushBackup();
      await repository.saveNode(local);
      final account = await authGateway.currentState();
      await remoteStore.uploadBackup(
        account.user!,
        MindmapBackupDocument.create(
          sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
          exportedAt: DateTime(2026, 6, 18, 13),
          nodes: [remote],
        ),
      );

      await container.read(syncControllerProvider.notifier).pullBackup();
      await container
          .read(syncControllerProvider.notifier)
          .resolveConflictWithRemote('shared');

      final state = container.read(syncControllerProvider);
      final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
      expect(state.lastMessage, 'Remote version applied');
      expect(state.lastConflictCount, 0);
      expect(state.pendingConflicts, isEmpty);
      expect((await repository.getNode('shared'))?.title, 'Remote edit');
      expect(remoteDocument?.nodes.single.title, 'Remote edit');
    },
  );

  test('resolves pending conflicts by keeping the local version', () async {
    final baseline = _node(id: 'shared', title: 'Shared');
    final local = baseline.copyWith(
      title: 'Local edit',
      updatedAt: DateTime(2026, 6, 18, 10),
    );
    final remote = baseline.copyWith(
      title: 'Remote edit',
      updatedAt: DateTime(2026, 6, 18, 11),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [baseline]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final syncStateStore = InMemorySyncStateStore();
    final container = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: syncStateStore,
    );
    addTearDown(container.dispose);

    await container
        .read(syncControllerProvider.notifier)
        .signIn(email: 'user@example.com');
    await container.read(syncControllerProvider.notifier).pushBackup();
    await repository.saveNode(local);
    final account = await authGateway.currentState();
    await remoteStore.uploadBackup(
      account.user!,
      MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
        exportedAt: DateTime(2026, 6, 18, 13),
        nodes: [remote],
      ),
    );

    await container.read(syncControllerProvider.notifier).pullBackup();
    await container
        .read(syncControllerProvider.notifier)
        .resolveConflictsWithLocal();

    final state = container.read(syncControllerProvider);
    final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
    expect(state.lastMessage, 'Local version kept');
    expect(state.lastConflictCount, 0);
    expect(state.pendingConflicts, isEmpty);
    expect((await repository.getNode('shared'))?.title, 'Local edit');
    expect(remoteDocument?.nodes.single.title, 'Local edit');
  });

  test('resolves one pending conflict by keeping its local version', () async {
    final baseline = _node(id: 'shared', title: 'Shared');
    final local = baseline.copyWith(
      title: 'Local edit',
      updatedAt: DateTime(2026, 6, 18, 10),
    );
    final remote = baseline.copyWith(
      title: 'Remote edit',
      updatedAt: DateTime(2026, 6, 18, 11),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [baseline]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final syncStateStore = InMemorySyncStateStore();
    final container = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: syncStateStore,
    );
    addTearDown(container.dispose);

    await container
        .read(syncControllerProvider.notifier)
        .signIn(email: 'user@example.com');
    await container.read(syncControllerProvider.notifier).pushBackup();
    await repository.saveNode(local);
    final account = await authGateway.currentState();
    await remoteStore.uploadBackup(
      account.user!,
      MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
        exportedAt: DateTime(2026, 6, 18, 13),
        nodes: [remote],
      ),
    );

    await container.read(syncControllerProvider.notifier).pullBackup();
    await container
        .read(syncControllerProvider.notifier)
        .resolveConflictWithLocal('shared');

    final state = container.read(syncControllerProvider);
    final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
    expect(state.lastMessage, 'Local version kept');
    expect(state.lastConflictCount, 0);
    expect(state.pendingConflicts, isEmpty);
    expect((await repository.getNode('shared'))?.title, 'Local edit');
    expect(remoteDocument?.nodes.single.title, 'Local edit');
  });

  test(
    'stages per-node conflict choices until every pending conflict is selected',
    () async {
      final remoteWinsBaseline = _node(id: 'remote-wins', title: 'Remote wins');
      final localWinsBaseline = _node(id: 'local-wins', title: 'Local wins');
      final remoteWinner = remoteWinsBaseline.copyWith(
        title: 'Remote selected',
        updatedAt: DateTime(2026, 6, 18, 11),
      );
      final localOlder = remoteWinsBaseline.copyWith(
        title: 'Local older',
        updatedAt: DateTime(2026, 6, 18, 10),
      );
      final localWinner = localWinsBaseline.copyWith(
        title: 'Local selected',
        updatedAt: DateTime(2026, 6, 18, 12),
      );
      final remoteOlder = localWinsBaseline.copyWith(
        title: 'Remote older',
        updatedAt: DateTime(2026, 6, 18, 9),
      );
      final repository = InMemoryMindmapRepository(
        seedNodes: [remoteWinsBaseline, localWinsBaseline],
      );
      final authGateway = LocalSyncAuthGateway();
      final remoteStore = InMemorySyncRemoteBackupStore();
      final syncStateStore = InMemorySyncStateStore();
      final container = _container(
        repository: repository,
        authGateway: authGateway,
        remoteStore: remoteStore,
        syncStateStore: syncStateStore,
      );
      addTearDown(container.dispose);

      await container
          .read(syncControllerProvider.notifier)
          .signIn(email: 'user@example.com');
      await container.read(syncControllerProvider.notifier).pushBackup();
      await repository.saveNode(localOlder);
      await repository.saveNode(localWinner);
      final account = await authGateway.currentState();
      await remoteStore.uploadBackup(
        account.user!,
        MindmapBackupDocument.create(
          sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
          exportedAt: DateTime(2026, 6, 18, 13),
          nodes: [remoteWinner, remoteOlder],
        ),
      );

      await container.read(syncControllerProvider.notifier).pullBackup();
      await container
          .read(syncControllerProvider.notifier)
          .resolveConflictWithRemote('remote-wins');

      var state = container.read(syncControllerProvider);
      expect(state.lastMessage, 'Resolution selected');
      expect(state.lastConflictCount, 2);
      expect(state.pendingConflicts, hasLength(2));
      expect(
        state.pendingConflicts
            .singleWhere((conflict) => conflict.nodeId == 'remote-wins')
            .selectedResolutionLabel,
        'Remote',
      );
      expect((await repository.getNode('remote-wins'))?.title, 'Local older');

      await container
          .read(syncControllerProvider.notifier)
          .resolveConflictWithLocal('local-wins');

      state = container.read(syncControllerProvider);
      final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
      expect(state.lastMessage, 'Selected versions applied');
      expect(state.lastConflictCount, 0);
      expect(state.pendingConflicts, isEmpty);
      expect(
        (await repository.getNode('remote-wins'))?.title,
        'Remote selected',
      );
      expect((await repository.getNode('local-wins'))?.title, 'Local selected');
      expect(
        remoteDocument?.nodes.map((node) => node.title),
        unorderedEquals(['Remote selected', 'Local selected']),
      );
    },
  );

  test(
    'records conflict sync activity while keeping the newest versions',
    () async {
      final activityStore = InMemorySyncActivityStore();
      final remoteWinsBaseline = _node(id: 'remote-wins', title: 'Remote wins');
      final localWinsBaseline = _node(id: 'local-wins', title: 'Local wins');
      final remoteWinner = remoteWinsBaseline.copyWith(
        title: 'Remote newest',
        updatedAt: DateTime(2026, 6, 18, 11),
      );
      final localOlder = remoteWinsBaseline.copyWith(
        title: 'Local older',
        updatedAt: DateTime(2026, 6, 18, 10),
      );
      final localWinner = localWinsBaseline.copyWith(
        title: 'Local newest',
        updatedAt: DateTime(2026, 6, 18, 12),
      );
      final remoteOlder = localWinsBaseline.copyWith(
        title: 'Remote older',
        updatedAt: DateTime(2026, 6, 18, 9),
      );
      final repository = InMemoryMindmapRepository(
        seedNodes: [remoteWinsBaseline, localWinsBaseline],
      );
      final authGateway = LocalSyncAuthGateway();
      final remoteStore = InMemorySyncRemoteBackupStore();
      final syncStateStore = InMemorySyncStateStore();
      final container = _container(
        repository: repository,
        authGateway: authGateway,
        remoteStore: remoteStore,
        syncStateStore: syncStateStore,
        activityStore: activityStore,
      );
      addTearDown(container.dispose);

      await container
          .read(syncControllerProvider.notifier)
          .signIn(email: 'user@example.com');
      await container.read(syncControllerProvider.notifier).pushBackup();
      await repository.saveNode(localOlder);
      await repository.saveNode(localWinner);
      final account = await authGateway.currentState();
      await remoteStore.uploadBackup(
        account.user!,
        MindmapBackupDocument.create(
          sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
          exportedAt: DateTime(2026, 6, 18, 13),
          nodes: [remoteWinner, remoteOlder],
        ),
      );

      await container.read(syncControllerProvider.notifier).pullBackup();
      expect(container.read(syncControllerProvider).lastConflictCount, 2);

      await container
          .read(syncControllerProvider.notifier)
          .resolveConflictsWithNewest();

      final state = container.read(syncControllerProvider);
      final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
      final activityLog = await activityStore.recent();
      expect(state.lastMessage, 'Newest versions kept');
      expect(state.lastConflictCount, 0);
      expect(state.pendingConflicts, isEmpty);
      expect((await repository.getNode('remote-wins'))?.title, 'Remote newest');
      expect((await repository.getNode('local-wins'))?.title, 'Local newest');
      expect(
        remoteDocument?.nodes.map((node) => node.title),
        unorderedEquals(['Remote newest', 'Local newest']),
      );
      expect(activityLog.take(3).map((entry) => entry.action), [
        SyncActivityAction.resolveNewest,
        SyncActivityAction.pull,
        SyncActivityAction.push,
      ]);
      expect(activityLog.take(3).map((entry) => entry.status), [
        SyncActivityStatus.success,
        SyncActivityStatus.blocked,
        SyncActivityStatus.success,
      ]);
      expect(activityLog.first.message, 'Newest versions kept');
      expect(activityLog.elementAt(1).conflictCount, 2);
    },
  );

  test(
    'syncs now and uploads a merged backup through the controller',
    () async {
      final baseline = _node(id: 'shared', title: 'Shared');
      final localNote = _node(id: 'local-note', title: 'Local note');
      final remoteNote = _node(id: 'remote-note', title: 'Remote note');
      final repository = InMemoryMindmapRepository(seedNodes: [baseline]);
      final authGateway = LocalSyncAuthGateway();
      final remoteStore = InMemorySyncRemoteBackupStore();
      final syncStateStore = InMemorySyncStateStore();
      final container = _container(
        repository: repository,
        authGateway: authGateway,
        remoteStore: remoteStore,
        syncStateStore: syncStateStore,
      );
      addTearDown(container.dispose);

      await container
          .read(syncControllerProvider.notifier)
          .signIn(email: 'user@example.com');
      await container.read(syncControllerProvider.notifier).pushBackup();
      await repository.saveNode(localNote);
      final account = await authGateway.currentState();
      await remoteStore.uploadBackup(
        account.user!,
        MindmapBackupDocument.create(
          sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
          exportedAt: DateTime(2026, 6, 18, 13),
          nodes: [baseline, remoteNote],
        ),
      );

      await container.read(syncControllerProvider.notifier).syncNow();

      final state = container.read(syncControllerProvider);
      final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
      expect(state.lastMessage, 'Sync complete');
      expect(state.lastSavedCount, 1);
      expect(state.lastDeletedCount, 0);
      expect(state.lastConflictCount, 0);
      expect(
        remoteDocument?.nodes.map((node) => node.id),
        unorderedEquals(['shared', 'local-note', 'remote-note']),
      );
    },
  );

  test('records recent sync activity after sync actions', () async {
    final activityStore = InMemorySyncActivityStore();
    final repository = InMemoryMindmapRepository(
      seedNodes: [_node(id: 'note-1', title: 'Activity note')],
    );
    final container = _container(
      repository: repository,
      authGateway: LocalSyncAuthGateway(),
      remoteStore: InMemorySyncRemoteBackupStore(),
      syncStateStore: InMemorySyncStateStore(),
      activityStore: activityStore,
    );
    addTearDown(container.dispose);

    await container
        .read(syncControllerProvider.notifier)
        .signIn(email: 'user@example.com');
    await container.read(syncControllerProvider.notifier).syncNow();

    final state = container.read(syncControllerProvider);
    final stored = await activityStore.recent();
    expect(state.activityLog, hasLength(1));
    expect(state.activityLog.single.action, SyncActivityAction.syncNow);
    expect(state.activityLog.single.status, SyncActivityStatus.success);
    expect(state.activityLog.single.message, 'Sync complete');
    expect(state.activityLog.single.savedCount, 1);
    expect(stored.single.id, state.activityLog.single.id);
  });

  test('loads and renames the local sync device identity', () async {
    final deviceStore = InMemorySyncDeviceIdentityStore(
      const SyncDeviceIdentity(id: 'device-laptop', label: 'Work laptop'),
    );
    final container = _container(
      repository: InMemoryMindmapRepository(),
      authGateway: LocalSyncAuthGateway(),
      remoteStore: InMemorySyncRemoteBackupStore(),
      syncStateStore: InMemorySyncStateStore(),
      deviceStore: deviceStore,
    );
    addTearDown(container.dispose);

    await container.read(syncControllerProvider.notifier).load();
    expect(
      container.read(syncControllerProvider).deviceIdentity?.label,
      'Work laptop',
    );

    await container
        .read(syncControllerProvider.notifier)
        .renameDevice('  Studio desktop  ');

    final state = container.read(syncControllerProvider);
    final stored = await deviceStore.readOrCreateIdentity();
    expect(state.deviceIdentity?.id, 'device-laptop');
    expect(state.deviceIdentity?.label, 'Studio desktop');
    expect(state.lastMessage, 'Device renamed');
    expect(stored.label, 'Studio desktop');
  });

  test(
    'exports and imports a portable backup through the controller',
    () async {
      final repository = InMemoryMindmapRepository(
        seedNodes: [_node(id: 'portable-note', title: 'Portable private note')],
      );
      final container = _container(
        repository: repository,
        authGateway: LocalSyncAuthGateway(),
        remoteStore: InMemorySyncRemoteBackupStore(),
        syncStateStore: InMemorySyncStateStore(),
      );
      addTearDown(container.dispose);

      await container
          .read(syncControllerProvider.notifier)
          .exportPortableBackup(passphrase: 'shared-secret');
      final package = container
          .read(syncControllerProvider)
          .lastPortablePackage;
      await repository.deleteNode('portable-note');
      await container
          .read(syncControllerProvider.notifier)
          .importPortableBackup(package: package, passphrase: 'shared-secret');

      final state = container.read(syncControllerProvider);
      expect(package, isNot(contains('Portable private note')));
      expect(state.lastMessage, 'Portable backup imported');
      expect(state.lastSavedCount, 1);
      expect(state.activityLog.take(2).map((entry) => entry.action), [
        SyncActivityAction.importPortable,
        SyncActivityAction.exportPortable,
      ]);
      expect(
        (await repository.getNode('portable-note'))?.title,
        'Portable private note',
      );
    },
  );

  test('records and restores local restore points', () async {
    final restorePointStore = InMemorySyncRestorePointStore();
    final original = _node(id: 'restore-note', title: 'Original snapshot');
    final repository = InMemoryMindmapRepository(seedNodes: [original]);
    final container = _container(
      repository: repository,
      authGateway: LocalSyncAuthGateway(),
      remoteStore: InMemorySyncRemoteBackupStore(),
      syncStateStore: InMemorySyncStateStore(),
      restorePointStore: restorePointStore,
    );
    addTearDown(container.dispose);

    await container
        .read(syncControllerProvider.notifier)
        .exportPortableBackup(passphrase: 'shared-secret');
    final point = container.read(syncControllerProvider).restorePoints.single;

    await repository.saveNode(
      original.copyWith(
        title: 'Changed after backup',
        updatedAt: DateTime(2026, 6, 18, 13),
      ),
    );
    await repository.saveNode(_node(id: 'extra-note', title: 'Extra note'));

    await container
        .read(syncControllerProvider.notifier)
        .restorePoint(point.id);

    final state = container.read(syncControllerProvider);
    final storedPoints = await restorePointStore.recent();
    expect(state.lastMessage, 'Restore point applied');
    expect(state.lastSavedCount, 1);
    expect(state.lastDeletedCount, 1);
    expect(state.restorePoints, hasLength(2));
    expect(state.restorePoints.first.label, 'Before restore');
    expect(state.restorePoints.first.document.nodes.map((node) => node.title), [
      'Changed after backup',
      'Extra note',
    ]);
    expect(state.restorePoints.last.id, point.id);
    expect(storedPoints, hasLength(2));
    expect(storedPoints.first.label, 'Before restore');
    expect(
      (await repository.getNode('restore-note'))?.title,
      'Original snapshot',
    );
    expect(await repository.getNode('extra-note'), isNull);
    expect(state.activityLog.first.action, SyncActivityAction.restorePoint);
  });

  test('deletes restore points from the controller state and store', () async {
    final restorePointStore = InMemorySyncRestorePointStore();
    final repository = InMemoryMindmapRepository(
      seedNodes: [_node(id: 'delete-restore-note', title: 'Delete restore')],
    );
    final container = _container(
      repository: repository,
      authGateway: LocalSyncAuthGateway(),
      remoteStore: InMemorySyncRemoteBackupStore(),
      syncStateStore: InMemorySyncStateStore(),
      restorePointStore: restorePointStore,
    );
    addTearDown(container.dispose);

    await container
        .read(syncControllerProvider.notifier)
        .exportPortableBackup(passphrase: 'shared-secret');
    final pointId = container
        .read(syncControllerProvider)
        .restorePoints
        .single
        .id;

    await container
        .read(syncControllerProvider.notifier)
        .deleteRestorePoint(pointId);

    final state = container.read(syncControllerProvider);
    expect(state.lastMessage, 'Restore point deleted');
    expect(state.restorePoints, isEmpty);
    expect(await restorePointStore.read(pointId), isNull);
  });

  test('keeps only the latest five restore points', () async {
    final restorePointStore = InMemorySyncRestorePointStore();
    final repository = InMemoryMindmapRepository(
      seedNodes: [_node(id: 'retained-note', title: 'Retained note')],
    );
    final container = _container(
      repository: repository,
      authGateway: LocalSyncAuthGateway(),
      remoteStore: InMemorySyncRemoteBackupStore(),
      syncStateStore: InMemorySyncStateStore(),
      restorePointStore: restorePointStore,
    );
    addTearDown(container.dispose);

    for (var index = 0; index < 6; index++) {
      await container
          .read(syncControllerProvider.notifier)
          .exportPortableBackup(passphrase: 'shared-secret');
    }

    final state = container.read(syncControllerProvider);
    final stored = await restorePointStore.recent(limit: 10);
    expect(state.restorePoints, hasLength(5));
    expect(stored, hasLength(5));
    expect(
      stored.map((point) => point.id).any((id) => id.endsWith('-0')),
      isFalse,
    );
  });

  test(
    'reports sign-in failures without leaving the controller busy',
    () async {
      final container = _container(
        repository: InMemoryMindmapRepository(),
        authGateway: _FailingAuthGateway(),
        remoteStore: InMemorySyncRemoteBackupStore(),
        syncStateStore: InMemorySyncStateStore(),
      );
      addTearDown(container.dispose);

      await container
          .read(syncControllerProvider.notifier)
          .signIn(email: 'user@example.com');

      final state = container.read(syncControllerProvider);
      expect(state.isBusy, isFalse);
      expect(state.isSignedIn, isFalse);
      expect(state.lastMessage, 'Email or password is incorrect.');
    },
  );

  test('reports push failures without leaving the controller busy', () async {
    final authGateway = LocalSyncAuthGateway();
    final activityStore = InMemorySyncActivityStore();
    final container = _container(
      repository: InMemoryMindmapRepository(
        seedNodes: [_node(id: 'note-1', title: 'Unsynced note')],
      ),
      authGateway: authGateway,
      remoteStore: _FailingRemoteBackupStore(),
      syncStateStore: InMemorySyncStateStore(),
      activityStore: activityStore,
    );
    addTearDown(container.dispose);

    await container
        .read(syncControllerProvider.notifier)
        .signIn(email: 'user@example.com');
    await container.read(syncControllerProvider.notifier).pushBackup();

    final state = container.read(syncControllerProvider);
    expect(state.isBusy, isFalse);
    expect(state.lastMessage, 'Remote sync request was rejected.');
    expect(state.lastSavedCount, 0);
    expect(state.lastConflictCount, 0);
    expect(state.activityLog.single.action, SyncActivityAction.push);
    expect(state.activityLog.single.status, SyncActivityStatus.failed);
    expect(
      state.activityLog.single.message,
      'Remote sync request was rejected.',
    );
  });
}

ProviderContainer _container({
  required InMemoryMindmapRepository repository,
  required SyncAuthGateway authGateway,
  required SyncRemoteBackupStore remoteStore,
  required InMemorySyncStateStore syncStateStore,
  InMemorySyncActivityStore? activityStore,
  InMemorySyncDeviceIdentityStore? deviceStore,
  InMemorySyncRestorePointStore? restorePointStore,
}) {
  return ProviderContainer(
    overrides: [
      mindmapRepositoryProvider.overrideWithValue(repository),
      syncAuthGatewayProvider.overrideWithValue(authGateway),
      syncRemoteBackupStoreProvider.overrideWithValue(remoteStore),
      syncStateStoreProvider.overrideWithValue(syncStateStore),
      syncActivityStoreProvider.overrideWithValue(
        activityStore ?? InMemorySyncActivityStore(),
      ),
      syncDeviceIdentityStoreProvider.overrideWithValue(
        deviceStore ??
            InMemorySyncDeviceIdentityStore(
              const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
            ),
      ),
      syncDeviceIdentityProvider.overrideWithValue(
        const SyncDeviceIdentity(id: 'device-test', label: 'Test device'),
      ),
      syncRestorePointStoreProvider.overrideWithValue(
        restorePointStore ?? InMemorySyncRestorePointStore(),
      ),
      syncNowProvider.overrideWithValue(() => DateTime(2026, 6, 18, 12)),
      portableBackupCodecProvider.overrideWithValue(
        PortableMindmapBackupCodec(
          iterations: 2,
          randomBytes: _deterministicRandomBytes(),
        ),
      ),
    ],
  );
}

MindmapNode _node({required String id, required String title}) {
  return MindmapNode.create(
    id: id,
    type: NodeType.note,
    title: title,
    day: DateTime(2026, 6, 18),
    now: DateTime(2026, 6, 18, 9),
  );
}

List<int> Function(int) _deterministicRandomBytes() {
  var call = 0;
  return (length) {
    call += 1;
    return List<int>.generate(length, (index) => (call * 37 + index) % 256);
  };
}

final class _FailingAuthGateway implements SyncAuthGateway {
  @override
  Future<SyncAuthState> currentState() async => const SyncAuthState.signedOut();

  @override
  Future<SyncAuthState> signIn({
    required String email,
    String password = '',
    String displayName = '',
  }) async {
    throw const SyncAuthException('Email or password is incorrect.');
  }

  @override
  Future<SyncAuthState> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    throw const SyncRemoteStoreException('Remote auth request was rejected.');
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    throw const SyncRemoteStoreException('Remote auth request was rejected.');
  }

  @override
  Future<void> signOut() async {}
}

final class _FailingRemoteBackupStore implements SyncRemoteBackupStore {
  @override
  Future<MindmapBackupDocument?> fetchLatestBackup(SyncUser user) async {
    throw const SyncRemoteStoreException('Remote sync request was rejected.');
  }

  @override
  Future<void> uploadBackup(
    SyncUser user,
    MindmapBackupDocument document,
  ) async {
    throw const SyncRemoteStoreException('Remote sync request was rejected.');
  }
}

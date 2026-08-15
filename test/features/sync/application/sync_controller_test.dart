import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/inline_node_workspace_controller.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_ui_state_codec.dart';
import 'package:var_app/features/mindmap/presentation/inline_node_workspace.dart';
import 'package:var_app/features/sync/application/attachment_sync_executor.dart';
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
import 'package:var_app/features/sync/domain/sync_restore_point.dart';

void main() {
  test('mandatory flush commits draft before sync upload', () async {
    final repository = InMemoryMindmapRepository(
      seedNodes: [_node(id: 'note-1', title: 'Persisted before edit')],
    );
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final container = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: InMemorySyncStateStore(),
      autosaveScheduler: (delay, callback) => () {},
    );
    addTearDown(container.dispose);
    final workspace = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    expect(await workspace.requestExpansion('note-1'), isTrue);
    workspace.updateDraft(
      'note-1',
      InlineNodeDraftPatch(title: 'Committed by mandatory flush'),
    );
    expect(
      container
          .read(inlineNodeWorkspaceControllerProvider)
          .nodes['note-1']
          ?.status,
      InlineNodeSaveStatus.dirty,
    );

    expect(await workspace.flush('note-1'), isTrue);
    expect(
      (await repository.getNode('note-1'))?.title,
      'Committed by mandatory flush',
    );
    await container
        .read(syncControllerProvider.notifier)
        .signIn(email: 'user@example.com');
    await container.read(syncControllerProvider.notifier).syncNow();

    final account = await authGateway.currentState();
    final remote = await remoteStore.fetchLatestBackup(account.user!);
    expect(remote?.nodes.single.title, 'Committed by mandatory flush');
    final payloadKeys = _allMapKeys(remote!.toJson());
    final forbiddenKeys = <String>{
      'expandedNodeId',
      'dirty',
      'saveGeneration',
      'scroll',
      'debounce',
      inlineWorkspaceExpandedNodeIdKey,
      inlineWorkspaceDraftKey,
      inlineWorkspaceDirtyKey,
      inlineWorkspaceSaveStatusKey,
      inlineWorkspaceScrollKey,
      inlineWorkspaceDebounceKey,
    };
    expect(payloadKeys.intersection(forbiddenKeys), isEmpty);
  });

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

  test('metadata push stays successful when attachment sync fails', () async {
    final repository = InMemoryMindmapRepository(
      seedNodes: [_node(id: 'note-1', title: 'Cloud note')],
    );
    final container = _container(
      repository: repository,
      authGateway: LocalSyncAuthGateway(),
      remoteStore: InMemorySyncRemoteBackupStore(),
      syncStateStore: InMemorySyncStateStore(),
      attachmentSyncRunner: () async => throw StateError('offline'),
    );
    addTearDown(container.dispose);

    await container
        .read(syncControllerProvider.notifier)
        .signIn(email: 'user@example.com');
    await container.read(syncControllerProvider.notifier).pushBackup();

    final state = container.read(syncControllerProvider);
    expect(state.lastMessage, 'Backup pushed');
    expect(state.activityLog.first.status, SyncActivityStatus.success);
    expect(state.attachmentWarnings, isNotEmpty);
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

  test('runs overdue auto backup during controller load', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    await preferences.setBool('auto_backup_enabled', true);
    await preferences.setString('auto_backup_frequency', 'daily');
    final authGateway = LocalSyncAuthGateway();
    await authGateway.signIn(email: 'auto@example.com');
    final activityStore = InMemorySyncActivityStore();
    await activityStore.add(
      SyncActivityEntry(
        id: 'old-sync',
        action: SyncActivityAction.syncNow,
        status: SyncActivityStatus.success,
        message: 'Old sync',
        occurredAt: DateTime(2026, 6, 16, 12),
        accountEmail: 'auto@example.com',
      ),
    );
    final remoteStore = InMemorySyncRemoteBackupStore();
    final repository = InMemoryMindmapRepository(
      seedNodes: [_node(id: 'auto-note', title: 'Catch-up backup')],
    );
    final container = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: InMemorySyncStateStore(),
      activityStore: activityStore,
    );
    addTearDown(container.dispose);

    await container.read(syncControllerProvider.notifier).load();

    final account = await authGateway.currentState();
    final remote = await remoteStore.fetchLatestBackup(account.user!);
    final state = container.read(syncControllerProvider);
    expect(remote?.nodes.single.id, 'auto-note');
    expect(state.lastMessage, 'Sync complete');
    expect(state.lastSyncedAt, DateTime(2026, 6, 18, 12));
    expect(state.activityLog.first.action, SyncActivityAction.syncNow);
    expect(state.activityLog.first.occurredAt, DateTime(2026, 6, 18, 12));
  });

  test('auto backup due calculation handles missing and fresh syncs', () {
    final now = DateTime(2026, 6, 18, 12);
    expect(
      autoBackupIsDue(
        now: now,
        lastSyncedAt: null,
        interval: const Duration(days: 1),
      ),
      isTrue,
    );
    expect(
      autoBackupIsDue(
        now: now,
        lastSyncedAt: DateTime(2026, 6, 18, 8),
        interval: const Duration(days: 1),
      ),
      isFalse,
    );
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

  test('portable import requires preview confirmation', () async {
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
    final package = container.read(syncControllerProvider).lastPortablePackage;
    await repository.deleteNode('portable-note');

    await expectLater(
      container
          .read(syncControllerProvider.notifier)
          .importPortableBackup(package: package, passphrase: 'shared-secret'),
      throwsArgumentError,
    );
    expect(await repository.getNode('portable-note'), isNull);
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
          .importPortableBackup(
            package: package,
            passphrase: 'shared-secret',
            previewConfirmed: true,
          );

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

  test('persists offline sync intent and retries it after restart', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    final authGateway = LocalSyncAuthGateway();
    await authGateway.signIn(email: 'offline@example.com');
    final repository = InMemoryMindmapRepository(
      seedNodes: [_node(id: 'offline-note', title: 'Retry after restart')],
    );
    final offlineContainer = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: _OfflineRemoteBackupStore(),
      syncStateStore: InMemorySyncStateStore(),
    );

    await offlineContainer.read(syncControllerProvider.notifier).syncNow();

    expect(
      offlineContainer.read(syncControllerProvider).lastMessage,
      'Sync queued (Offline)',
    );
    final pendingRaw = await preferences.getString('sync_pending_operation');
    expect(pendingRaw, isNotNull);
    final pending = jsonDecode(pendingRaw!) as Map<String, Object?>;
    expect(pending['operation'], 'sync');
    expect(pending['accountEmail'], 'offline@example.com');
    offlineContainer.dispose();

    final recoveredRemote = InMemorySyncRemoteBackupStore();
    final recoveredContainer = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: recoveredRemote,
      syncStateStore: InMemorySyncStateStore(),
    );
    addTearDown(recoveredContainer.dispose);

    await recoveredContainer.read(syncControllerProvider.notifier).load();

    final account = await authGateway.currentState();
    final remote = await recoveredRemote.fetchLatestBackup(account.user!);
    expect(remote?.nodes.single.id, 'offline-note');
    expect(
      recoveredContainer.read(syncControllerProvider).lastMessage,
      'Sync complete',
    );
    expect(await preferences.getBool('sync_pending_offline_retry'), isNull);
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

  test('ignores sync while a push is still running', () async {
    final authGateway = LocalSyncAuthGateway();
    await authGateway.signIn(email: 'race@example.com');
    final remoteStore = _BlockingRemoteBackupStore(blockUpload: true);
    final container = _container(
      repository: InMemoryMindmapRepository(
        seedNodes: [_node(id: 'race-note', title: 'Race guard')],
      ),
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: InMemorySyncStateStore(),
    );
    addTearDown(container.dispose);

    final push = container.read(syncControllerProvider.notifier).pushBackup();
    await remoteStore.uploadStarted.future;
    await container.read(syncControllerProvider.notifier).syncNow();

    expect(remoteStore.uploadCount, 1);
    expect(remoteStore.fetchCount, 0);
    expect(container.read(syncControllerProvider).isBusy, isTrue);

    remoteStore.releaseUpload();
    await push;
    expect(container.read(syncControllerProvider).isBusy, isFalse);
  });

  test('ignores push while a pull is still running', () async {
    final authGateway = LocalSyncAuthGateway();
    await authGateway.signIn(email: 'race@example.com');
    final remoteStore = _BlockingRemoteBackupStore(blockFetch: true);
    final container = _container(
      repository: InMemoryMindmapRepository(),
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: InMemorySyncStateStore(),
    );
    addTearDown(container.dispose);

    final pull = container.read(syncControllerProvider.notifier).pullBackup();
    await remoteStore.fetchStarted.future;
    await container.read(syncControllerProvider.notifier).pushBackup();

    expect(remoteStore.fetchCount, 1);
    expect(remoteStore.uploadCount, 0);
    expect(container.read(syncControllerProvider).isBusy, isTrue);

    remoteStore.releaseFetch();
    await pull;
    expect(container.read(syncControllerProvider).isBusy, isFalse);
  });
  test('retries queued push after restart', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    final authGateway = LocalSyncAuthGateway();
    await authGateway.signIn(email: 'push@example.com');
    final repository = InMemoryMindmapRepository(
      seedNodes: [_node(id: 'push-note', title: 'Queued push')],
    );
    final remoteStore = _RecoverableRemoteBackupStore();
    final offlineContainer = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: InMemorySyncStateStore(),
    );
    await offlineContainer.read(syncControllerProvider.notifier).pushBackup();
    expect(
      offlineContainer.read(syncControllerProvider).lastMessage,
      'Push queued (Offline)',
    );
    final pendingRaw = await preferences.getString('sync_pending_operation');
    expect(
      (jsonDecode(pendingRaw!) as Map<String, Object?>)['operation'],
      'push',
    );
    offlineContainer.dispose();

    remoteStore.isOffline = false;
    final recoveredContainer = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: InMemorySyncStateStore(),
    );
    addTearDown(recoveredContainer.dispose);
    await recoveredContainer.read(syncControllerProvider.notifier).load();
    final account = await authGateway.currentState();
    expect(
      (await remoteStore.fetchLatestBackup(account.user!))?.nodes.single.id,
      'push-note',
    );
    expect(
      recoveredContainer.read(syncControllerProvider).lastMessage,
      'Backup pushed',
    );
    expect(await preferences.getString('sync_pending_operation'), isNull);
  });

  test('retries queued pull after restart', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    final authGateway = LocalSyncAuthGateway();
    await authGateway.signIn(email: 'pull@example.com');
    final repository = InMemoryMindmapRepository();
    final remoteStore = _RecoverableRemoteBackupStore();
    final offlineContainer = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: InMemorySyncStateStore(),
    );
    await offlineContainer.read(syncControllerProvider.notifier).pullBackup();
    expect(
      offlineContainer.read(syncControllerProvider).lastMessage,
      'Pull queued (Offline)',
    );
    final pendingRaw = await preferences.getString('sync_pending_operation');
    expect(
      (jsonDecode(pendingRaw!) as Map<String, Object?>)['operation'],
      'pull',
    );
    offlineContainer.dispose();

    final account = await authGateway.currentState();
    remoteStore.seed(
      account.user!,
      MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(
          id: 'remote-device',
          label: 'Remote device',
        ),
        nodes: [_node(id: 'pulled-note', title: 'Recovered pull')],
        exportedAt: DateTime(2026, 6, 18, 11),
      ),
    );
    remoteStore.isOffline = false;
    final recoveredContainer = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: InMemorySyncStateStore(),
    );
    addTearDown(recoveredContainer.dispose);
    await recoveredContainer.read(syncControllerProvider.notifier).load();
    expect((await repository.getNode('pulled-note'))?.title, 'Recovered pull');
    expect(
      recoveredContainer.read(syncControllerProvider).lastMessage,
      'Backup pulled',
    );
    expect(await preferences.getString('sync_pending_operation'), isNull);
  });
  test('clears queued operation for a different account', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      'sync_pending_operation',
      jsonEncode({'operation': 'push', 'accountEmail': 'old@example.com'}),
    );
    final authGateway = LocalSyncAuthGateway();
    await authGateway.signIn(email: 'new@example.com');
    final remoteStore = _RecoverableRemoteBackupStore()..isOffline = false;
    final container = _container(
      repository: InMemoryMindmapRepository(
        seedNodes: [_node(id: 'local-note', title: 'Do not push')],
      ),
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: InMemorySyncStateStore(),
    );
    addTearDown(container.dispose);
    await container.read(syncControllerProvider.notifier).load();
    expect(remoteStore.uploadCount, 0);
    expect(remoteStore.fetchCount, 0);
    expect(await preferences.getString('sync_pending_operation'), isNull);
  });

  test('migrates legacy offline retry intent', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    await preferences.setBool('sync_pending_offline_retry', true);
    final authGateway = LocalSyncAuthGateway();
    await authGateway.signIn(email: 'legacy@example.com');
    final remoteStore = _RecoverableRemoteBackupStore()..isOffline = false;
    final container = _container(
      repository: InMemoryMindmapRepository(
        seedNodes: [_node(id: 'legacy-note', title: 'Legacy retry')],
      ),
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: InMemorySyncStateStore(),
    );
    addTearDown(container.dispose);
    await container.read(syncControllerProvider.notifier).load();
    expect(remoteStore.uploadCount, 1);
    expect(await preferences.getBool('sync_pending_offline_retry'), isNull);
    expect(await preferences.getString('sync_pending_operation'), isNull);
  });
  test('ignores conflict resolution while a push is running', () async {
    final authGateway = LocalSyncAuthGateway();
    await authGateway.signIn(email: 'race@example.com');
    final remoteStore = _BlockingRemoteBackupStore(blockUpload: true);
    final container = _container(
      repository: InMemoryMindmapRepository(
        seedNodes: [_node(id: 'race-conflict', title: 'Race conflict')],
      ),
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: InMemorySyncStateStore(),
    );
    addTearDown(container.dispose);

    final push = container.read(syncControllerProvider.notifier).pushBackup();
    await remoteStore.uploadStarted.future;
    await container
        .read(syncControllerProvider.notifier)
        .resolveConflictsWithLocal();

    expect(remoteStore.uploadCount, 1);
    remoteStore.releaseUpload();
    await push;
  });

  test('exposes and cancels queued sync intent', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    final authGateway = LocalSyncAuthGateway();
    await authGateway.signIn(email: 'queued@example.com');
    final container = _container(
      repository: InMemoryMindmapRepository(),
      authGateway: authGateway,
      remoteStore: _OfflineRemoteBackupStore(),
      syncStateStore: InMemorySyncStateStore(),
    );
    addTearDown(container.dispose);

    await container.read(syncControllerProvider.notifier).pullBackup();
    expect(container.read(syncControllerProvider).pendingOperation, 'pull');
    expect(
      container.read(syncControllerProvider).pendingAccountEmail,
      'queued@example.com',
    );

    await container
        .read(syncControllerProvider.notifier)
        .cancelPendingOperation();
    expect(container.read(syncControllerProvider).hasPendingOperation, isFalse);
    expect(await preferences.getString('sync_pending_operation'), isNull);
  });

  test(
    'loads activity and restore points only for the signed-in account',
    () async {
      final authGateway = LocalSyncAuthGateway();
      await authGateway.signIn(email: 'current@example.com');
      final activityStore = InMemorySyncActivityStore();
      await activityStore.add(
        SyncActivityEntry(
          id: 'current-activity',
          action: SyncActivityAction.syncNow,
          status: SyncActivityStatus.success,
          message: 'Current',
          occurredAt: DateTime(2026, 6, 18, 10),
          accountEmail: 'current@example.com',
        ),
      );
      await activityStore.add(
        SyncActivityEntry(
          id: 'other-activity',
          action: SyncActivityAction.syncNow,
          status: SyncActivityStatus.success,
          message: 'Other',
          occurredAt: DateTime(2026, 6, 18, 11),
          accountEmail: 'other@example.com',
        ),
      );
      final restoreStore = InMemorySyncRestorePointStore();
      for (final email in ['current@example.com', 'other@example.com']) {
        await restoreStore.add(
          SyncRestorePoint(
            id: email,
            label: email,
            createdAt: DateTime(2026, 6, 18, 12),
            accountEmail: email,
            document: MindmapBackupDocument.create(
              sourceDevice: const SyncDeviceIdentity(
                id: 'test-device',
                label: 'Test device',
              ),
              exportedAt: DateTime(2026, 6, 18, 12),
              nodes: const [],
            ),
          ),
        );
      }
      final container = _container(
        repository: InMemoryMindmapRepository(),
        authGateway: authGateway,
        remoteStore: InMemorySyncRemoteBackupStore(),
        syncStateStore: InMemorySyncStateStore(),
        activityStore: activityStore,
        restorePointStore: restoreStore,
      );
      addTearDown(container.dispose);

      await container.read(syncControllerProvider.notifier).load();

      expect(
        container.read(syncControllerProvider).activityLog.single.id,
        'current-activity',
      );
      expect(
        container.read(syncControllerProvider).restorePoints.single.id,
        'current@example.com',
      );
    },
  );
  test('rejects restore point operations for another account', () async {
    final authGateway = LocalSyncAuthGateway();
    await authGateway.signIn(email: 'current@example.com');
    final local = _node(id: 'local', title: 'Keep local');
    final repository = InMemoryMindmapRepository(seedNodes: [local]);
    final restoreStore = InMemorySyncRestorePointStore();
    final foreign = SyncRestorePoint(
      id: 'foreign',
      label: 'Foreign snapshot',
      createdAt: DateTime(2026, 6, 18, 12),
      accountEmail: 'other@example.com',
      document: MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(
          id: 'other-device',
          label: 'Other device',
        ),
        exportedAt: DateTime(2026, 6, 18, 12),
        nodes: [_node(id: 'foreign-node', title: 'Foreign')],
      ),
    );
    await restoreStore.add(foreign);
    final container = _container(
      repository: repository,
      authGateway: authGateway,
      remoteStore: InMemorySyncRemoteBackupStore(),
      syncStateStore: InMemorySyncStateStore(),
      restorePointStore: restoreStore,
    );
    addTearDown(container.dispose);
    final controller = container.read(syncControllerProvider.notifier);
    await controller.load();

    await expectLater(
      controller.previewRestorePoint(foreign.id),
      throwsArgumentError,
    );
    await controller.restorePoint(foreign.id);
    expect(
      container.read(syncControllerProvider).lastMessage,
      'Restore point was not found.',
    );
    await controller.deleteRestorePoint(foreign.id);

    expect(
      container.read(syncControllerProvider).lastMessage,
      'Restore point was not found.',
    );
    expect(await repository.listNodes(), [local]);
    expect(await restoreStore.read(foreign.id), foreign);
  });

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
  Future<AttachmentSyncExecutionReport> Function()? attachmentSyncRunner,
  InlineNodeAutosaveScheduler? autosaveScheduler,
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
          iterations: PortableMindmapBackupCodec.minKdfIterations,
          randomBytes: _deterministicRandomBytes(),
        ),
      ),
      if (autosaveScheduler != null)
        inlineNodeAutosaveSchedulerProvider.overrideWithValue(
          autosaveScheduler,
        ),
      if (attachmentSyncRunner != null)
        attachmentSyncRunnerProvider.overrideWithValue(attachmentSyncRunner),
    ],
  );
}

Set<String> _allMapKeys(Object? value) {
  final keys = <String>{};
  void visit(Object? item) {
    if (item is Map<Object?, Object?>) {
      for (final entry in item.entries) {
        if (entry.key is String) keys.add(entry.key! as String);
        visit(entry.value);
      }
    } else if (item is Iterable<Object?>) {
      for (final child in item) {
        visit(child);
      }
    }
  }

  visit(value);
  return keys;
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

final class _OfflineRemoteBackupStore implements SyncRemoteBackupStore {
  @override
  Future<MindmapBackupDocument?> fetchLatestBackup(SyncUser user) async {
    throw const SyncRemoteStoreException('Network error');
  }

  @override
  Future<void> uploadBackup(
    SyncUser user,
    MindmapBackupDocument document,
  ) async {
    throw const SyncRemoteStoreException('Network error');
  }
}

final class _BlockingRemoteBackupStore implements SyncRemoteBackupStore {
  _BlockingRemoteBackupStore({
    this.blockFetch = false,
    this.blockUpload = false,
  });

  final bool blockFetch;
  final bool blockUpload;
  final Completer<void> fetchStarted = Completer<void>();
  final Completer<void> uploadStarted = Completer<void>();
  final Completer<void> _fetchRelease = Completer<void>();
  final Completer<void> _uploadRelease = Completer<void>();
  int fetchCount = 0;
  int uploadCount = 0;

  void releaseFetch() {
    if (!_fetchRelease.isCompleted) _fetchRelease.complete();
  }

  void releaseUpload() {
    if (!_uploadRelease.isCompleted) _uploadRelease.complete();
  }

  @override
  Future<MindmapBackupDocument?> fetchLatestBackup(SyncUser user) async {
    fetchCount += 1;
    if (!fetchStarted.isCompleted) fetchStarted.complete();
    if (blockFetch) await _fetchRelease.future;
    return null;
  }

  @override
  Future<void> uploadBackup(
    SyncUser user,
    MindmapBackupDocument document,
  ) async {
    uploadCount += 1;
    if (!uploadStarted.isCompleted) uploadStarted.complete();
    if (blockUpload) await _uploadRelease.future;
  }
}

final class _RecoverableRemoteBackupStore implements SyncRemoteBackupStore {
  final Map<String, MindmapBackupDocument> _documentsByUserId = {};

  void seed(SyncUser user, MindmapBackupDocument document) {
    _documentsByUserId[user.id] = document;
  }

  bool isOffline = true;
  int fetchCount = 0;
  int uploadCount = 0;

  @override
  Future<MindmapBackupDocument?> fetchLatestBackup(SyncUser user) async {
    fetchCount += 1;
    if (isOffline) {
      throw const SyncRemoteStoreException('Network error');
    }
    return _documentsByUserId[user.id];
  }

  @override
  Future<void> uploadBackup(
    SyncUser user,
    MindmapBackupDocument document,
  ) async {
    uploadCount += 1;
    if (isOffline) {
      throw const SyncRemoteStoreException('Network error');
    }
    _documentsByUserId[user.id] = document;
  }
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

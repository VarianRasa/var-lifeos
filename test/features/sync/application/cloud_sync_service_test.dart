import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/application/cloud_sync_service.dart';
import 'package:var_app/features/sync/data/in_memory_sync_remote_backup_store.dart';
import 'package:var_app/features/sync/data/in_memory_sync_state_store.dart';
import 'package:var_app/features/sync/data/local_sync_auth_gateway.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';
import 'package:var_app/features/sync/domain/mindmap_sync_planner.dart';

void main() {
  test('requires a signed-in account before pushing a backup', () async {
    final repository = InMemoryMindmapRepository();
    final service = CloudSyncService(
      repository: repository,
      authGateway: LocalSyncAuthGateway(),
      remoteStore: InMemorySyncRemoteBackupStore(),
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );

    expect(service.pushBackup, throwsA(isA<SyncAuthRequiredException>()));
  });

  test('pushes a backup document for the signed-in user', () async {
    final node = _node(
      id: 'note-1',
      title: 'Cloud note',
      now: DateTime(2026, 6, 18, 9),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final service = CloudSyncService(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );
    final user = await authGateway.signIn(
      email: 'user@example.com',
      displayName: 'User',
    );

    final document = await service.pushBackup();
    final remoteDocument = await remoteStore.fetchLatestBackup(user.user!);

    expect(document.nodes, [node]);
    expect(remoteDocument?.nodes, [node]);
    expect(remoteDocument?.sourceDevice.id, 'device-a');
  });

  test('stores a local sync baseline after pushing a backup', () async {
    final node = _node(
      id: 'note-1',
      title: 'Cloud note',
      now: DateTime(2026, 6, 18, 9),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final authGateway = LocalSyncAuthGateway();
    final syncStateStore = InMemorySyncStateStore();
    final service = CloudSyncService(
      repository: repository,
      authGateway: authGateway,
      remoteStore: InMemorySyncRemoteBackupStore(),
      syncStateStore: syncStateStore,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );
    final account = await authGateway.signIn(email: 'user@example.com');

    await service.pushBackup();

    final snapshot = await syncStateStore.readSnapshot(account.user!);
    expect(snapshot?.syncedAt, DateTime(2026, 6, 18, 12));
    expect(snapshot?.baseline.nodes, [node]);
  });

  test('pulls a remote backup through conflict-aware import', () async {
    final base = _node(
      id: 'shared',
      title: 'Shared',
      now: DateTime(2026, 6, 18, 9),
    );
    final stale = _node(
      id: 'stale',
      title: 'Remote deleted',
      now: DateTime(2026, 6, 18, 9),
    );
    final remote = base.copyWith(
      title: 'Shared from phone',
      updatedAt: DateTime(2026, 6, 18, 11),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [base, stale]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final service = CloudSyncService(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );
    final account = await authGateway.signIn(email: 'user@example.com');
    await remoteStore.uploadBackup(
      account.user!,
      MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Phone'),
        exportedAt: DateTime(2026, 6, 18, 13),
        nodes: [remote],
      ),
    );

    final report = await service.pullBackup(baselineNodes: [base, stale]);

    expect(report.blockedByConflicts, isFalse);
    expect(report.savedNodeIds, ['shared']);
    expect(report.deletedNodeIds, ['stale']);
    expect((await repository.getNode('shared'))?.title, 'Shared from phone');
    expect(await repository.getNode('stale'), isNull);
  });

  test('uses the stored baseline when pulling remote changes', () async {
    final base = _node(
      id: 'shared',
      title: 'Shared',
      now: DateTime(2026, 6, 18, 9),
    );
    final stale = _node(
      id: 'stale',
      title: 'Remote deleted',
      now: DateTime(2026, 6, 18, 9),
    );
    final remote = base.copyWith(
      title: 'Shared from phone',
      updatedAt: DateTime(2026, 6, 18, 11),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [base, stale]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final syncStateStore = InMemorySyncStateStore();
    final service = CloudSyncService(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: syncStateStore,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );
    final account = await authGateway.signIn(email: 'user@example.com');
    await service.pushBackup();
    await remoteStore.uploadBackup(
      account.user!,
      MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Phone'),
        exportedAt: DateTime(2026, 6, 18, 13),
        nodes: [remote],
      ),
    );

    final report = await service.pullBackup();

    expect(report.blockedByConflicts, isFalse);
    expect(report.savedNodeIds, ['shared']);
    expect(report.deletedNodeIds, ['stale']);
    expect((await repository.getNode('shared'))?.title, 'Shared from phone');
    expect(await repository.getNode('stale'), isNull);
    final snapshot = await syncStateStore.readSnapshot(account.user!);
    expect(snapshot?.baseline.nodes, [remote]);
  });

  test('keeps the stored baseline when pull is blocked by conflicts', () async {
    final baseline = _node(
      id: 'shared',
      title: 'Shared',
      now: DateTime(2026, 6, 18, 9),
    );
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
    final service = CloudSyncService(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: syncStateStore,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );
    final account = await authGateway.signIn(email: 'user@example.com');
    await service.pushBackup();
    await repository.saveNode(local);
    await remoteStore.uploadBackup(
      account.user!,
      MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Phone'),
        exportedAt: DateTime(2026, 6, 18, 13),
        nodes: [remote],
      ),
    );

    final report = await service.pullBackup();

    expect(report.blockedByConflicts, isTrue);
    final snapshot = await syncStateStore.readSnapshot(account.user!);
    expect(snapshot?.baseline.nodes, [baseline]);
  });

  test(
    'previewPull is read-only and keeps remote and baseline intact',
    () async {
      final baseline = _node(
        id: 'shared',
        title: 'Shared',
        now: DateTime(2026, 6, 18, 9),
      );
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
      final service = CloudSyncService(
        repository: repository,
        authGateway: authGateway,
        remoteStore: remoteStore,
        syncStateStore: syncStateStore,
        sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
        now: () => DateTime(2026, 6, 18, 12),
      );
      final account = await authGateway.signIn(email: 'user@example.com');
      await service.pushBackup();
      await repository.saveNode(local);
      final remoteDocument = MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Phone'),
        exportedAt: DateTime(2026, 6, 18, 13),
        nodes: [remote],
      );
      await remoteStore.uploadBackup(account.user!, remoteDocument);

      final preview = await service.previewPull(
        conflictStrategy: SyncConflictStrategy.keepRemote,
      );

      expect(preview.plan.nodesToSave.single.title, 'Remote edit');
      expect(preview.plan.resolvedConflicts, hasLength(1));
      expect((await repository.getNode('shared'))?.title, 'Local edit');
      expect(
        (await remoteStore.fetchLatestBackup(
          account.user!,
        ))?.nodes.single.title,
        'Remote edit',
      );
      expect(
        (await syncStateStore.readSnapshot(
          account.user!,
        ))?.baseline.nodes.single.title,
        'Shared',
      );
    },
  );

  test('returns an empty pull report when no remote backup exists', () async {
    final repository = InMemoryMindmapRepository();
    final authGateway = LocalSyncAuthGateway();
    final service = CloudSyncService(
      repository: repository,
      authGateway: authGateway,
      remoteStore: InMemorySyncRemoteBackupStore(),
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );
    await authGateway.signIn(email: 'user@example.com');

    final report = await service.pullBackup();

    expect(report.blockedByConflicts, isFalse);
    expect(report.savedNodeIds, isEmpty);
    expect(report.deletedNodeIds, isEmpty);
  });

  test('syncNow pushes local data when no remote backup exists', () async {
    final node = _node(
      id: 'local-note',
      title: 'Local only',
      now: DateTime(2026, 6, 18, 9),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [node]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final syncStateStore = InMemorySyncStateStore();
    final service = CloudSyncService(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: syncStateStore,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );
    final account = await authGateway.signIn(email: 'user@example.com');

    final report = await service.syncNow();

    final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
    final snapshot = await syncStateStore.readSnapshot(account.user!);
    expect(report.remoteWasMissing, isTrue);
    expect(report.blockedByConflicts, isFalse);
    expect(report.importReport.savedNodeIds, isEmpty);
    expect(report.pushedDocument?.nodes, [node]);
    expect(remoteDocument?.nodes, [node]);
    expect(snapshot?.baseline.nodes, [node]);
  });

  test('syncNow pulls remote changes then uploads merged local data', () async {
    final baseline = _node(
      id: 'shared',
      title: 'Shared',
      now: DateTime(2026, 6, 18, 9),
    );
    final remoteEdit = baseline.copyWith(
      title: 'Shared from phone',
      updatedAt: DateTime(2026, 6, 18, 11),
    );
    final localNote = _node(
      id: 'local-note',
      title: 'Created locally',
      now: DateTime(2026, 6, 18, 10),
    );
    final remoteNote = _node(
      id: 'remote-note',
      title: 'Created remotely',
      now: DateTime(2026, 6, 18, 11),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [baseline]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final syncStateStore = InMemorySyncStateStore();
    final service = CloudSyncService(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      syncStateStore: syncStateStore,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
      now: () => DateTime(2026, 6, 18, 12),
    );
    final account = await authGateway.signIn(email: 'user@example.com');
    await service.pushBackup();
    await repository.saveNode(localNote);
    await remoteStore.uploadBackup(
      account.user!,
      MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Phone'),
        exportedAt: DateTime(2026, 6, 18, 13),
        nodes: [remoteEdit, remoteNote],
      ),
    );

    final report = await service.syncNow();

    final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
    final snapshot = await syncStateStore.readSnapshot(account.user!);
    expect(report.remoteWasMissing, isFalse);
    expect(report.blockedByConflicts, isFalse);
    expect(report.importReport.savedNodeIds, ['shared', 'remote-note']);
    expect(report.pushedDocument?.nodes, [remoteEdit, localNote, remoteNote]);
    expect(remoteDocument?.nodes, [remoteEdit, localNote, remoteNote]);
    expect(snapshot?.baseline.nodes, [remoteEdit, localNote, remoteNote]);
  });

  test(
    'syncNow reports conflicts without overwriting the remote backup',
    () async {
      final baseline = _node(
        id: 'shared',
        title: 'Shared',
        now: DateTime(2026, 6, 18, 9),
      );
      final localEdit = baseline.copyWith(
        title: 'Local edit',
        updatedAt: DateTime(2026, 6, 18, 10),
      );
      final remoteEdit = baseline.copyWith(
        title: 'Remote edit',
        updatedAt: DateTime(2026, 6, 18, 11),
      );
      final repository = InMemoryMindmapRepository(seedNodes: [baseline]);
      final authGateway = LocalSyncAuthGateway();
      final remoteStore = InMemorySyncRemoteBackupStore();
      final syncStateStore = InMemorySyncStateStore();
      final service = CloudSyncService(
        repository: repository,
        authGateway: authGateway,
        remoteStore: remoteStore,
        syncStateStore: syncStateStore,
        sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
        now: () => DateTime(2026, 6, 18, 12),
      );
      final account = await authGateway.signIn(email: 'user@example.com');
      await service.pushBackup();
      await repository.saveNode(localEdit);
      await remoteStore.uploadBackup(
        account.user!,
        MindmapBackupDocument.create(
          sourceDevice: const SyncDeviceIdentity(
            id: 'device-b',
            label: 'Phone',
          ),
          exportedAt: DateTime(2026, 6, 18, 13),
          nodes: [remoteEdit],
        ),
      );

      final report = await service.syncNow();

      final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
      final snapshot = await syncStateStore.readSnapshot(account.user!);
      expect(report.blockedByConflicts, isTrue);
      expect(report.pushedDocument, isNull);
      expect((await repository.getNode('shared'))?.title, 'Local edit');
      expect(remoteDocument?.nodes.single.title, 'Remote edit');
      expect(snapshot?.baseline.nodes, [baseline]);
    },
  );

  test('pull rejects changed remote revision without local mutation', () async {
    final local = _node(
      id: 'local',
      title: 'Keep local',
      now: DateTime(2026, 6, 18, 9),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [local]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final service = CloudSyncService(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
    );
    final account = await authGateway.signIn(email: 'user@example.com');
    final previewed = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Phone'),
      exportedAt: DateTime(2026, 6, 18, 13),
      nodes: [
        _node(
          id: 'previewed',
          title: 'Previewed remote',
          now: DateTime(2026, 6, 18, 10),
        ),
      ],
    );
    await remoteStore.uploadBackup(account.user!, previewed);
    final preview = await service.previewPull();
    final changed = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Phone'),
      exportedAt: DateTime(2026, 6, 18, 14),
      nodes: [
        _node(
          id: 'changed',
          title: 'Changed remote',
          now: DateTime(2026, 6, 18, 11),
        ),
      ],
    );
    await remoteStore.uploadBackup(account.user!, changed);

    await expectLater(
      service.pullBackup(expectedRemoteDocument: preview.remoteDocument),
      throwsA(isA<StateError>()),
    );

    expect(await repository.listNodes(), [local]);
    expect(await remoteStore.fetchLatestBackup(account.user!), same(changed));
  });

  test('syncNow rejects remote appearing after missing preview', () async {
    final local = _node(
      id: 'local',
      title: 'Keep local',
      now: DateTime(2026, 6, 18, 9),
    );
    final repository = InMemoryMindmapRepository(seedNodes: [local]);
    final authGateway = LocalSyncAuthGateway();
    final remoteStore = InMemorySyncRemoteBackupStore();
    final service = CloudSyncService(
      repository: repository,
      authGateway: authGateway,
      remoteStore: remoteStore,
      sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
    );
    final account = await authGateway.signIn(email: 'user@example.com');
    final preview = await service.previewPull();
    expect(preview.remoteWasMissing, isTrue);
    final appeared = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'device-b', label: 'Phone'),
      exportedAt: DateTime(2026, 6, 18, 13),
      nodes: [
        _node(
          id: 'remote',
          title: 'Appeared remotely',
          now: DateTime(2026, 6, 18, 10),
        ),
      ],
    );
    await remoteStore.uploadBackup(account.user!, appeared);

    await expectLater(
      service.syncNow(expectedRemoteWasMissing: preview.remoteWasMissing),
      throwsA(isA<StateError>()),
    );

    expect(await repository.listNodes(), [local]);
    expect(await remoteStore.fetchLatestBackup(account.user!), same(appeared));
  });

  test(
    'resolves conflicts with the newest node versions and uploads them',
    () async {
      final remoteWinsBaseline = _node(
        id: 'remote-wins',
        title: 'Remote wins',
        now: DateTime(2026, 6, 18, 8),
      );
      final localWinsBaseline = _node(
        id: 'local-wins',
        title: 'Local wins',
        now: DateTime(2026, 6, 18, 8),
      );
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
      final service = CloudSyncService(
        repository: repository,
        authGateway: authGateway,
        remoteStore: remoteStore,
        syncStateStore: syncStateStore,
        sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
        now: () => DateTime(2026, 6, 18, 13),
      );
      final account = await authGateway.signIn(email: 'user@example.com');
      await service.pushBackup();
      await repository.saveNode(localOlder);
      await repository.saveNode(localWinner);
      await remoteStore.uploadBackup(
        account.user!,
        MindmapBackupDocument.create(
          sourceDevice: const SyncDeviceIdentity(
            id: 'device-b',
            label: 'Phone',
          ),
          exportedAt: DateTime(2026, 6, 18, 14),
          nodes: [remoteWinner, remoteOlder],
        ),
      );

      final report = await service.resolveConflictsWithLatest();

      final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
      final snapshot = await syncStateStore.readSnapshot(account.user!);
      expect(report.blockedByConflicts, isFalse);
      expect((await repository.getNode('remote-wins'))?.title, 'Remote newest');
      expect((await repository.getNode('local-wins'))?.title, 'Local newest');
      expect(
        remoteDocument?.nodes.map((node) => node.title),
        unorderedEquals(['Remote newest', 'Local newest']),
      );
      expect(
        snapshot?.baseline.nodes.map((node) => node.title),
        unorderedEquals(['Remote newest', 'Local newest']),
      );
    },
  );

  test(
    'syncNow resolves explicit per-node conflict decisions and uploads them',
    () async {
      final remoteWinsBaseline = _node(
        id: 'remote-wins',
        title: 'Remote wins',
        now: DateTime(2026, 6, 18, 8),
      );
      final localWinsBaseline = _node(
        id: 'local-wins',
        title: 'Local wins',
        now: DateTime(2026, 6, 18, 8),
      );
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
      final service = CloudSyncService(
        repository: repository,
        authGateway: authGateway,
        remoteStore: remoteStore,
        syncStateStore: syncStateStore,
        sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
        now: () => DateTime(2026, 6, 18, 13),
      );
      final account = await authGateway.signIn(email: 'user@example.com');
      await service.pushBackup();
      await repository.saveNode(localOlder);
      await repository.saveNode(localWinner);
      await remoteStore.uploadBackup(
        account.user!,
        MindmapBackupDocument.create(
          sourceDevice: const SyncDeviceIdentity(
            id: 'device-b',
            label: 'Phone',
          ),
          exportedAt: DateTime(2026, 6, 18, 14),
          nodes: [remoteWinner, remoteOlder],
        ),
      );

      final report = await service.syncNow(
        conflictResolutions: {
          'remote-wins': SyncResolution.useRemote,
          'local-wins': SyncResolution.useLocal,
        },
      );

      final remoteDocument = await remoteStore.fetchLatestBackup(account.user!);
      final snapshot = await syncStateStore.readSnapshot(account.user!);
      expect(report.blockedByConflicts, isFalse);
      expect(report.importReport.plan.resolvedConflicts, hasLength(2));
      expect(
        (await repository.getNode('remote-wins'))?.title,
        'Remote selected',
      );
      expect((await repository.getNode('local-wins'))?.title, 'Local selected');
      expect(
        remoteDocument?.nodes.map((node) => node.title),
        unorderedEquals(['Remote selected', 'Local selected']),
      );
      expect(
        snapshot?.baseline.nodes.map((node) => node.title),
        unorderedEquals(['Remote selected', 'Local selected']),
      );
    },
  );
}

MindmapNode _node({
  required String id,
  required String title,
  required DateTime now,
}) {
  return MindmapNode.create(
    id: id,
    type: NodeType.note,
    title: title,
    day: DateTime(2026, 6, 18),
    now: now,
  );
}

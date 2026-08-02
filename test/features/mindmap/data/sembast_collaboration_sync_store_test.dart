import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:uuid/uuid.dart';
import 'package:var_app/features/mindmap/data/sembast_collaboration_sync_store.dart';
import 'package:var_app/features/mindmap/domain/collaboration_node_sync.dart';

void main() {
  test('bind uniqueness, coalesce, acknowledge, and revision', () async {
    final db = await databaseFactoryMemory.openDatabase('collaboration.db');
    final store = SembastCollaborationSyncStore(database: db);
    const binding = CollaborationNodeBinding(
      roomId: 'room',
      localNodeId: 'local',
      remoteNodeId: 'remote',
      dayKey: '2026-07-28',
      revision: 0,
    );
    await store.bind(binding);
    expect(
      () => store.bind(
        const CollaborationNodeBinding(
          roomId: 'room',
          localNodeId: 'other',
          remoteNodeId: 'remote',
          dayKey: '2026-07-28',
          revision: 0,
        ),
      ),
      throwsStateError,
    );
    final first = CollaborationPendingMutation(
      mutationId: const Uuid().v4(),
      roomId: 'room',
      localNodeId: 'local',
      remoteNodeId: 'remote',
      dayKey: '2026-07-28',
      baseRevision: 0,
      kind: CollaborationMutationKind.upsert,
      payload: const {'id': 'remote'},
      updatedByUid: 'uid',
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 28),
      updatedAt: DateTime.utc(2026, 7, 28),
      nextAttemptAt: DateTime.utc(2026, 7, 28),
      lastAttemptAt: null,
      lastErrorCode: null,
      deliveryState: CollaborationDeliveryState.pending,
    );
    await store.enqueue(first);
    await store.enqueue(
      CollaborationPendingMutation(
        mutationId: const Uuid().v4(),
        roomId: 'room',
        localNodeId: 'local',
        remoteNodeId: 'remote',
        dayKey: '2026-07-28',
        baseRevision: 0,
        kind: CollaborationMutationKind.delete,
        payload: null,
        updatedByUid: 'uid',
        attemptCount: 0,
        createdAt: DateTime.utc(2026, 7, 28),
        updatedAt: DateTime.utc(2026, 7, 28),
        nextAttemptAt: DateTime.utc(2026, 7, 28),
        lastAttemptAt: null,
        lastErrorCode: null,
        deliveryState: CollaborationDeliveryState.pending,
      ),
    );
    final pending = await store.pendingForRoom('room');
    expect(pending, hasLength(1));
    expect(pending.single.kind, CollaborationMutationKind.delete);
    await store.acknowledge(pending.single, 1);
    expect(await store.pendingForRoom('room'), isEmpty);
    expect((await store.getBindingByRemote('room', 'remote'))!.revision, 1);
    await db.close();
  });

  test('detach is atomic, room scoped, and bind clears marker', () async {
    final db = await databaseFactoryMemory.openDatabase('detach.db');
    final store = SembastCollaborationSyncStore(database: db);
    const binding = CollaborationNodeBinding(
      roomId: 'room-a',
      localNodeId: 'local',
      remoteNodeId: 'remote',
      dayKey: '2026-07-28',
      revision: 1,
    );
    await store.bind(binding);
    await store.enqueue(
      CollaborationPendingMutation(
        mutationId: const Uuid().v4(),
        roomId: 'room-a',
        localNodeId: 'local',
        remoteNodeId: 'remote',
        dayKey: '2026-07-28',
        baseRevision: 1,
        kind: CollaborationMutationKind.upsert,
        payload: {'id': 'local'},
        updatedByUid: 'uid',
        attemptCount: 0,
        createdAt: DateTime.utc(2026, 7, 28),
        updatedAt: DateTime.utc(2026, 7, 28),
        nextAttemptAt: DateTime.utc(2026, 7, 28),
        lastAttemptAt: null,
        lastErrorCode: null,
        deliveryState: CollaborationDeliveryState.pending,
      ),
    );
    await store.markConflict(
      const CollaborationNodeConflict(
        roomId: 'room-a',
        localNodeId: 'local',
        remoteNodeId: 'remote',
        localBaseRevision: 1,
        remoteRevision: 2,
        remoteEnvelope: null,
      ),
    );
    await store.detach(binding);
    expect(await store.getBindingByLocal('room-a', 'local'), isNull);
    expect(await store.pendingForRoom('room-a'), isEmpty);
    expect(await store.getConflict('room-a', 'local'), isNull);
    expect(await store.isDetachedRemote('room-a', 'remote'), isTrue);
    expect(await store.isDetachedRemote('room-b', 'remote'), isFalse);
    await store.bind(binding);
    expect(await store.isDetachedRemote('room-a', 'remote'), isFalse);
    await db.close();
  });

  test('stale status and ack preserve newer mutation', () async {
    final db = await databaseFactoryMemory.openDatabase('race.db');
    final store = SembastCollaborationSyncStore(database: db);
    await store.bind(
      const CollaborationNodeBinding(
        roomId: 'room',
        localNodeId: 'local',
        remoteNodeId: 'remote',
        dayKey: '2026-07-28',
        revision: 0,
      ),
    );
    CollaborationPendingMutation mutation(String id, String title) =>
        CollaborationPendingMutation(
          mutationId: id,
          roomId: 'room',
          localNodeId: 'local',
          remoteNodeId: 'remote',
          dayKey: '2026-07-28',
          baseRevision: 0,
          kind: CollaborationMutationKind.upsert,
          payload: {'id': 'remote', 'title': title},
          updatedByUid: 'uid',
          attemptCount: 0,
          createdAt: DateTime.utc(2026, 7, 28),
          updatedAt: DateTime.utc(2026, 7, 28),
          nextAttemptAt: DateTime.utc(2026, 7, 28),
          lastAttemptAt: null,
          lastErrorCode: null,
          deliveryState: CollaborationDeliveryState.pending,
        );
    final first = mutation('first', 'First');
    await store.enqueue(first);
    final attempted = await store.markAttempt(first, DateTime.utc(2026, 7, 28));
    await store.enqueue(mutation('second', 'Second'));
    expect(
      await store.scheduleRetry(
        attempted!,
        DateTime.utc(2026, 7, 28, 0, 1),
        'unavailable',
      ),
      isFalse,
    );
    await store.acknowledgeIfCurrent(attempted, 1);
    final current = (await store.pendingForRoom('room')).single;
    expect(current.mutationId, 'second');
    expect(current.payload!['title'], 'Second');
    expect(current.baseRevision, 1);
    await store.acknowledgeIfCurrent(attempted, 0);
    expect((await store.getBindingByLocal('room', 'local'))!.revision, 1);
    await db.close();
  });

  test('retry attempt metadata persists', () async {
    final db = await databaseFactoryMemory.openDatabase('retry.db');
    final store = SembastCollaborationSyncStore(database: db);
    final mutation = CollaborationPendingMutation(
      mutationId: 'mutation',
      roomId: 'room',
      localNodeId: 'local',
      remoteNodeId: 'remote',
      dayKey: '2026-07-28',
      baseRevision: 0,
      kind: CollaborationMutationKind.delete,
      payload: null,
      updatedByUid: 'uid',
      attemptCount: 0,
      createdAt: DateTime.utc(2026, 7, 28),
      updatedAt: DateTime.utc(2026, 7, 28),
      nextAttemptAt: DateTime.utc(2026, 7, 28),
      lastAttemptAt: null,
      lastErrorCode: null,
      deliveryState: CollaborationDeliveryState.pending,
    );
    await store.enqueue(mutation);
    final attempted = await store.markAttempt(
      mutation,
      DateTime.utc(2026, 7, 28, 0, 1),
    );
    await store.scheduleRetry(
      attempted!,
      DateTime.utc(2026, 7, 28, 0, 2),
      'unavailable',
    );
    final restored = (await SembastCollaborationSyncStore(
      database: db,
    ).pendingForRoom('room')).single;
    expect(restored.attemptCount, 1);
    expect(restored.lastErrorCode, 'unavailable');
    expect(restored.deliveryState, CollaborationDeliveryState.retryWaiting);
    expect(restored.nextAttemptAt, DateTime.utc(2026, 7, 28, 0, 2));
    await db.close();
  });

  test('conflict persists, clears, and pending mutation rebases', () async {
    final db = await databaseFactoryMemory.openDatabase('conflicts.db');
    final store = SembastCollaborationSyncStore(database: db);
    final envelope = CollaborationNodeEnvelope(
      remoteNodeId: 'remote',
      dayKey: '2026-07-28',
      revision: 2,
      deleted: false,
      payload: const {'id': 'remote', 'day': '2026-07-28', 'title': 'Remote'},
      createdByUid: 'owner',
      updatedByUid: 'peer',
      lastMutationId: 'remote-mutation',
    );
    final conflict = CollaborationNodeConflict(
      roomId: 'room',
      localNodeId: 'local',
      remoteNodeId: 'remote',
      localBaseRevision: 1,
      remoteRevision: 2,
      remoteEnvelope: envelope,
    );
    await store.markConflict(conflict);
    final restored = await store.getConflict('room', 'local');
    expect(restored!.remoteEnvelope!.payload!['title'], 'Remote');
    await store.enqueue(
      CollaborationPendingMutation(
        mutationId: const Uuid().v4(),
        roomId: 'room',
        localNodeId: 'local',
        remoteNodeId: 'remote',
        dayKey: '2026-07-28',
        baseRevision: 1,
        kind: CollaborationMutationKind.upsert,
        payload: const {'mine': true},
        updatedByUid: 'me',
        attemptCount: 0,
        createdAt: DateTime.utc(2026, 7, 28),
        updatedAt: DateTime.utc(2026, 7, 28),
        nextAttemptAt: DateTime.utc(2026, 7, 28),
        lastAttemptAt: null,
        lastErrorCode: null,
        deliveryState: CollaborationDeliveryState.pending,
      ),
    );
    await store.rebasePending('room', 'local', 2);
    final pending = (await store.pendingForRoom('room')).single;
    expect(pending.baseRevision, 2);
    expect(pending.payload, const {'mine': true});
    await store.clearConflict('room', 'local');
    expect(await store.getConflict('room', 'local'), isNull);
    await db.close();
  });
}

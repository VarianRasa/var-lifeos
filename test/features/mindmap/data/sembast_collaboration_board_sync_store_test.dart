import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/mindmap/data/sembast_collaboration_board_sync_store.dart';
import 'package:var_app/features/mindmap/domain/collaboration_board_sync.dart';

void main() {
  CollaborationPendingBoardMutation mutation(String id, String title) =>
      CollaborationPendingBoardMutation(
        mutationId: id,
        roomId: 'room',
        boardId: 'board',
        baseRevision: 0,
        payload: <String, Object?>{
          'id': 'board',
          'kind': 'project',
          'title': title,
        },
        updatedByUid: 'editor',
        attemptCount: 0,
        createdAt: DateTime.utc(2026, 7, 28),
        updatedAt: DateTime.utc(2026, 7, 28),
        nextAttemptAt: DateTime.utc(2026, 7, 28),
        lastAttemptAt: null,
        lastErrorCode: null,
        deliveryState: CollaborationBoardDeliveryState.pending,
      );

  test('coalesces and preserves newer mutation on stale ack', () async {
    final db = await databaseFactoryMemory.openDatabase('board-sync.db');
    final store = SembastCollaborationBoardSyncStore(database: db);
    final first = mutation('first', 'First');
    await store.enqueue(first);
    final attempted = await store.markAttempt(first, DateTime.utc(2026, 7, 28));
    await store.enqueue(mutation('second', 'Second'));
    expect(
      await store.scheduleRetry(attempted!, DateTime.utc(2026, 7, 29), 'x'),
      isFalse,
    );
    expect(await store.acknowledgeIfCurrent(attempted, 1), isFalse);
    final current = (await store.pendingForRoom('room')).single;
    expect(current.mutationId, 'second');
    expect(current.baseRevision, 1);
    expect(await store.revision('room', 'board'), 1);
    await db.close();
  });

  test('persists retry and conflict state', () async {
    final db = await databaseFactoryMemory.openDatabase('board-conflict.db');
    final store = SembastCollaborationBoardSyncStore(database: db);
    final pending = mutation('local', 'Local');
    await store.enqueue(pending);
    final attempted = await store.markAttempt(
      pending,
      DateTime.utc(2026, 7, 28),
    );
    await store.scheduleRetry(
      attempted!,
      DateTime.utc(2026, 7, 29),
      'unavailable',
    );
    expect((await store.pendingForRoom('room')).single.attemptCount, 1);
    final remote = CollaborationBoardEnvelope(
      boardId: 'board',
      revision: 2,
      payload: const <String, Object?>{'id': 'board', 'kind': 'project'},
      createdByUid: 'owner',
      updatedByUid: 'peer',
      lastMutationId: 'remote',
    );
    await store.markConflict(
      CollaborationBoardConflict(
        roomId: 'room',
        boardId: 'board',
        localBaseRevision: 0,
        remoteRevision: 2,
        remoteEnvelope: remote,
      ),
    );
    expect(
      (await store.pendingForRoom('room')).single.deliveryState,
      CollaborationBoardDeliveryState.conflict,
    );
    expect((await store.getConflict('room', 'board'))!.remoteRevision, 2);
    await store.rebasePending('room', 'board', 2);
    expect((await store.pendingForRoom('room')).single.baseRevision, 2);
    await store.discardPending('room', 'board');
    expect(await store.pendingForRoom('room'), isEmpty);
    await store.clearConflict('room', 'board');
    expect(await store.getConflict('room', 'board'), isNull);
    await db.close();
  });
}

import 'dart:async';

import 'package:sembast/sembast.dart';

import '../domain/collaboration_board_sync.dart';

final class SembastCollaborationBoardSyncStore {
  SembastCollaborationBoardSyncStore({required FutureOr<Database> database})
    : _databaseSource = database;

  final FutureOr<Database> _databaseSource;
  final _revisions = stringMapStoreFactory.store(
    'collaboration_board_revisions',
  );
  final _pending = stringMapStoreFactory.store('collaboration_board_pending');
  final _conflicts = stringMapStoreFactory.store(
    'collaboration_board_conflicts',
  );
  final _changes = StreamController<void>.broadcast();
  Database? _database;

  Future<Database> get _db async =>
      _database ??= await Future<Database>.value(_databaseSource);
  Stream<void> get changes => _changes.stream;
  String _key(String roomId, String boardId) => '$roomId|$boardId';
  void _changed() => _changes.add(null);

  Future<int> revision(String roomId, String boardId) async {
    final value = await _revisions.record(_key(roomId, boardId)).get(await _db);
    return value?['revision'] as int? ?? 0;
  }

  Future<void> enqueue(CollaborationPendingBoardMutation mutation) async {
    final record = _pending.record(_key(mutation.roomId, mutation.boardId));
    final stored = await record.get(await _db);
    final existing = stored == null
        ? null
        : CollaborationPendingBoardMutation.fromJson(stored);
    final next = existing == null
        ? mutation
        : CollaborationPendingBoardMutation(
            mutationId: mutation.mutationId,
            roomId: mutation.roomId,
            boardId: mutation.boardId,
            baseRevision: existing.baseRevision,
            payload: mutation.payload,
            updatedByUid: mutation.updatedByUid,
            attemptCount: 0,
            createdAt: existing.createdAt,
            updatedAt: mutation.updatedAt,
            nextAttemptAt: mutation.updatedAt,
            lastAttemptAt: null,
            lastErrorCode: null,
            deliveryState: CollaborationBoardDeliveryState.pending,
          );
    await record.put(await _db, next.toJson());
    _changed();
  }

  Future<List<CollaborationPendingBoardMutation>> pendingForRoom(
    String roomId,
  ) async => List.unmodifiable(
    (await _pending.find(
      await _db,
      finder: Finder(filter: Filter.equals('roomId', roomId)),
    )).map(
      (record) => CollaborationPendingBoardMutation.fromJson(record.value),
    ),
  );

  Future<List<CollaborationPendingBoardMutation>> due(
    String roomId,
    DateTime now,
  ) async => (await pendingForRoom(roomId))
      .where(
        (mutation) =>
            (mutation.deliveryState ==
                    CollaborationBoardDeliveryState.pending ||
                mutation.deliveryState ==
                    CollaborationBoardDeliveryState.retryWaiting) &&
            !mutation.nextAttemptAt.isAfter(now.toUtc()),
      )
      .toList(growable: false);

  Future<CollaborationPendingBoardMutation?> markAttempt(
    CollaborationPendingBoardMutation mutation,
    DateTime now,
  ) async {
    final current = await _current(mutation);
    if (current == null) return null;
    final next = current.copyWith(
      attemptCount: current.attemptCount + 1,
      updatedAt: now,
      lastAttemptAt: now,
      deliveryState: CollaborationBoardDeliveryState.pending,
    );
    await _put(next);
    return next;
  }

  Future<bool> scheduleRetry(
    CollaborationPendingBoardMutation mutation,
    DateTime nextAttemptAt,
    String errorCode,
  ) => _updateCurrent(
    mutation,
    mutation.copyWith(
      updatedAt: DateTime.now().toUtc(),
      nextAttemptAt: nextAttemptAt,
      lastErrorCode: errorCode,
      deliveryState: CollaborationBoardDeliveryState.retryWaiting,
    ),
  );

  Future<bool> markBlocked(
    CollaborationPendingBoardMutation mutation,
    String errorCode,
  ) => _updateCurrent(
    mutation,
    mutation.copyWith(
      updatedAt: DateTime.now().toUtc(),
      lastErrorCode: errorCode,
      deliveryState: CollaborationBoardDeliveryState.blocked,
    ),
  );

  Future<bool> markFailed(
    CollaborationPendingBoardMutation mutation,
    String errorCode,
  ) => _updateCurrent(
    mutation,
    mutation.copyWith(
      updatedAt: DateTime.now().toUtc(),
      lastErrorCode: errorCode,
      deliveryState: CollaborationBoardDeliveryState.failed,
    ),
  );

  Future<bool> acknowledgeIfCurrent(
    CollaborationPendingBoardMutation mutation,
    int revision,
  ) async {
    final db = await _db;
    var removed = false;
    await db.transaction((transaction) async {
      final key = _key(mutation.roomId, mutation.boardId);
      final stored = await _pending.record(key).get(transaction);
      if (stored != null) {
        final current = CollaborationPendingBoardMutation.fromJson(stored);
        if (current.mutationId == mutation.mutationId) {
          await _pending.record(key).delete(transaction);
          removed = true;
        } else if (revision > current.baseRevision) {
          await _pending
              .record(key)
              .put(
                transaction,
                current.copyWith(baseRevision: revision).toJson(),
              );
        }
      }
      final oldRevision =
          (await _revisions.record(key).get(transaction))?['revision']
              as int? ??
          0;
      if (revision > oldRevision) {
        await _revisions.record(key).put(transaction, {
          'roomId': mutation.roomId,
          'boardId': mutation.boardId,
          'revision': revision,
        });
      }
    });
    _changed();
    return removed;
  }

  Future<bool> applyRemoteRevision(
    String roomId,
    String boardId,
    int revision,
  ) async {
    if (revision <= await this.revision(roomId, boardId)) return false;
    await _revisions.record(_key(roomId, boardId)).put(await _db, {
      'roomId': roomId,
      'boardId': boardId,
      'revision': revision,
    });
    _changed();
    return true;
  }

  Future<void> markConflict(CollaborationBoardConflict conflict) async {
    final key = _key(conflict.roomId, conflict.boardId);
    final db = await _db;
    await db.transaction((transaction) async {
      await _conflicts.record(key).put(transaction, conflict.toJson());
      final stored = await _pending.record(key).get(transaction);
      if (stored != null) {
        final pending = CollaborationPendingBoardMutation.fromJson(stored);
        await _pending
            .record(key)
            .put(
              transaction,
              pending
                  .copyWith(
                    deliveryState: CollaborationBoardDeliveryState.conflict,
                  )
                  .toJson(),
            );
      }
    });
    _changed();
  }

  Future<CollaborationBoardConflict?> getConflict(
    String roomId,
    String boardId,
  ) async {
    final value = await _conflicts.record(_key(roomId, boardId)).get(await _db);
    return value == null ? null : CollaborationBoardConflict.fromJson(value);
  }

  Future<void> clearConflict(String roomId, String boardId) async {
    await _conflicts.record(_key(roomId, boardId)).delete(await _db);
    _changed();
  }

  Future<void> discardPending(String roomId, String boardId) async {
    await _pending.record(_key(roomId, boardId)).delete(await _db);
    _changed();
  }

  Future<void> rebasePending(
    String roomId,
    String boardId,
    int revision,
  ) async {
    CollaborationPendingBoardMutation? pending;
    for (final mutation in await pendingForRoom(roomId)) {
      if (mutation.boardId == boardId) pending = mutation;
    }
    if (pending == null) throw StateError('Pending board mutation is missing.');
    final now = DateTime.now().toUtc();
    await _put(
      pending.copyWith(
        baseRevision: revision,
        updatedAt: now,
        nextAttemptAt: now,
        clearError: true,
        deliveryState: CollaborationBoardDeliveryState.pending,
      ),
    );
  }

  Future<CollaborationPendingBoardMutation?> _current(
    CollaborationPendingBoardMutation mutation,
  ) async {
    final value = await _pending
        .record(_key(mutation.roomId, mutation.boardId))
        .get(await _db);
    if (value == null) return null;
    final current = CollaborationPendingBoardMutation.fromJson(value);
    return current.mutationId == mutation.mutationId ? current : null;
  }

  Future<bool> _updateCurrent(
    CollaborationPendingBoardMutation expected,
    CollaborationPendingBoardMutation next,
  ) async {
    if (await _current(expected) == null) return false;
    await _put(next);
    return true;
  }

  Future<void> _put(CollaborationPendingBoardMutation mutation) async {
    await _pending
        .record(_key(mutation.roomId, mutation.boardId))
        .put(await _db, mutation.toJson());
    _changed();
  }
}

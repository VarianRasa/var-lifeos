import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/collaboration_canvas_board_repository.dart';
import '../data/sembast_collaboration_board_sync_store.dart';
import '../domain/canvas_board.dart';
import '../domain/collaboration_board_sync.dart';

final class CollaborationBoardSyncService {
  CollaborationBoardSyncService({
    required FirebaseFirestore firestore,
    required SembastCollaborationBoardSyncStore store,
    required CollaborationCanvasBoardRepository repository,
    this.onRemoteApplied,
  }) : _firestore = firestore,
       _store = store,
       _repository = repository;

  final FirebaseFirestore _firestore;
  final SembastCollaborationBoardSyncStore _store;
  final CollaborationCanvasBoardRepository _repository;
  final FutureOr<void> Function()? onRemoteApplied;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _remoteSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _ballotSub;
  StreamSubscription<void>? _storeSub;
  Timer? _retryTimer;
  String? _roomId;
  bool _writeStopped = false;
  Future<void>? _draining;

  Future<void> start({
    required String roomId,
    required String boardId,
    required String uid,
  }) async {
    await stop();
    _roomId = roomId;
    _writeStopped = false;
    final initialSnapshot = await _reference(roomId, boardId).get();
    final initialData = initialSnapshot.data();
    if (!initialSnapshot.exists || initialData == null) {
      throw StateError('Shared project board is missing.');
    }
    final initialEnvelope = CollaborationBoardEnvelope.fromJson(
      Map<String, Object?>.from(initialData)..remove('updatedAt'),
    );
    if (initialEnvelope.boardId != boardId) {
      throw const FormatException('Shared project board identity mismatch.');
    }
    await _applyRemote(roomId, initialEnvelope);
    _remoteSub = _reference(roomId, boardId).snapshots().listen((
      snapshot,
    ) async {
      final data = snapshot.data();
      if (data == null) return;
      try {
        await _applyRemote(
          roomId,
          CollaborationBoardEnvelope.fromJson(
            Map<String, Object?>.from(data)..remove('updatedAt'),
          ),
        );
      } on FormatException {
        return;
      }
    });
    _ballotSub = _reference(roomId, boardId)
        .collection('ballots')
        .doc(uid)
        .snapshots()
        .listen((snapshot) async {
          final data = snapshot.data();
          if (data == null) return;
          final objectIds = data['objectIds'];
          final sessionId = data['sessionId'];
          if (objectIds is! List || sessionId is! String) return;
          await _repository.applyLocalBallot(
            boardId,
            uid: uid,
            sessionId: sessionId,
            objectIds: objectIds.whereType<String>(),
          );
          await onRemoteApplied?.call();
        });
    _storeSub = _store.changes.listen((_) => wake());
    await drain();
  }

  Future<void> stop({bool stopWrites = false}) async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _remoteSub?.cancel();
    await _ballotSub?.cancel();
    await _storeSub?.cancel();
    _remoteSub = null;
    _ballotSub = null;
    _storeSub = null;
    _writeStopped = stopWrites;
    if (!stopWrites) {
      _roomId = null;
    }
  }

  Future<List<CollaborationBoardConflict>> listConflicts(String roomId) async {
    final conflicts = <CollaborationBoardConflict>[];
    for (final mutation in await _store.pendingForRoom(roomId)) {
      final conflict = await _store.getConflict(roomId, mutation.boardId);
      if (conflict != null) conflicts.add(conflict);
    }
    return List.unmodifiable(conflicts);
  }

  Future<void> resolveKeepRemote(CollaborationBoardConflict conflict) async {
    final envelope = await _freshRemote(conflict);
    await _repository.applyRemoteBoard(
      CanvasBoard.fromJson(envelope.payload),
      roomId: conflict.roomId,
      revision: envelope.revision,
    );
    await _store.discardPending(conflict.roomId, conflict.boardId);
    await _store.clearConflict(conflict.roomId, conflict.boardId);
    await onRemoteApplied?.call();
  }

  Future<void> resolveKeepMine(CollaborationBoardConflict conflict) async {
    final envelope = await _freshRemote(conflict);
    await _store.rebasePending(
      conflict.roomId,
      conflict.boardId,
      envelope.revision,
    );
    await _store.clearConflict(conflict.roomId, conflict.boardId);
    await drain();
  }

  Future<CollaborationBoardEnvelope> _freshRemote(
    CollaborationBoardConflict conflict,
  ) async {
    final snapshot = await _reference(conflict.roomId, conflict.boardId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw StateError('Remote collaboration board is missing.');
    }
    final envelope = CollaborationBoardEnvelope.fromJson(
      Map<String, Object?>.from(data)..remove('updatedAt'),
    );
    if (envelope.boardId != conflict.boardId ||
        envelope.revision < conflict.remoteRevision) {
      throw StateError('Remote collaboration board identity changed.');
    }
    return envelope;
  }

  Future<void> setWritePermission(bool allowed, String reason) async {
    _writeStopped = !allowed;
    final roomId = _roomId;
    if (roomId == null) return;
    if (allowed) {
      for (final mutation in await _store.pendingForRoom(roomId)) {
        if (mutation.deliveryState == CollaborationBoardDeliveryState.blocked) {
          await _store.rebasePending(
            mutation.roomId,
            mutation.boardId,
            mutation.baseRevision,
          );
        }
      }
      wake();
      return;
    }
    for (final mutation in await _store.pendingForRoom(roomId)) {
      if (mutation.deliveryState == CollaborationBoardDeliveryState.pending ||
          mutation.deliveryState ==
              CollaborationBoardDeliveryState.retryWaiting) {
        await _store.markBlocked(mutation, reason);
      }
    }
  }

  Future<void> drain() =>
      _draining ??= _drain().whenComplete(() => _draining = null);

  void wake() {
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(drain());
  }

  Future<void> _drain() async {
    final roomId = _roomId;
    if (roomId == null || _writeStopped) return;
    for (final mutation in await _store.due(roomId, DateTime.now())) {
      final attempted = await _store.markAttempt(mutation, DateTime.now());
      if (attempted == null) continue;
      try {
        final revision = await _commit(attempted);
        await _store.acknowledgeIfCurrent(attempted, revision);
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' ||
            error.code == 'unauthenticated') {
          await _store.markBlocked(attempted, error.code);
        } else if (_transientCodes.contains(error.code)) {
          final nextAttemptAt = DateTime.now().toUtc().add(
            _retryDelay(attempted.attemptCount),
          );
          await _store.scheduleRetry(attempted, nextAttemptAt, error.code);
          _scheduleRetry(nextAttemptAt);
        } else {
          await _store.markFailed(attempted, error.code);
        }
        return;
      } on FormatException {
        await _store.markFailed(attempted, 'malformed');
        return;
      } on StateError {
        final snapshot = await _reference(
          attempted.roomId,
          attempted.boardId,
        ).get();
        final data = snapshot.data();
        if (data != null) {
          try {
            final envelope = CollaborationBoardEnvelope.fromJson(
              Map<String, Object?>.from(data)..remove('updatedAt'),
            );
            await _store.markConflict(
              CollaborationBoardConflict(
                roomId: attempted.roomId,
                boardId: attempted.boardId,
                localBaseRevision: attempted.baseRevision,
                remoteRevision: envelope.revision,
                remoteEnvelope: envelope,
              ),
            );
          } on FormatException {
            await _store.markFailed(attempted, 'malformed-remote');
          }
        }
        return;
      }
    }
  }

  Future<int> _commit(CollaborationPendingBoardMutation mutation) {
    final reference = _reference(mutation.roomId, mutation.boardId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final current = snapshot.data();
      final revision = current?['revision'] as int? ?? 0;
      if (current?['schemaVersion'] ==
              CollaborationBoardEnvelope.schemaVersion &&
          current?['lastMutationId'] == mutation.mutationId) {
        return revision;
      }
      if (revision != mutation.baseRevision ||
          (!snapshot.exists && mutation.baseRevision != 0)) {
        throw StateError('Collaboration board revision conflict.');
      }
      final next = CollaborationBoardEnvelope(
        boardId: mutation.boardId,
        revision: revision + 1,
        payload: mutation.payload,
        createdByUid:
            current?['createdByUid'] as String? ?? mutation.updatedByUid,
        updatedByUid: mutation.updatedByUid,
        lastMutationId: mutation.mutationId,
      );
      transaction.set(reference, {
        ...next.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return next.revision;
    });
  }

  Future<void> _applyRemote(
    String roomId,
    CollaborationBoardEnvelope envelope,
  ) async {
    final pending = (await _store.pendingForRoom(
      roomId,
    )).where((mutation) => mutation.boardId == envelope.boardId).firstOrNull;
    if (pending != null) {
      if (pending.mutationId == envelope.lastMutationId) {
        await _store.acknowledgeIfCurrent(pending, envelope.revision);
        await _store.clearConflict(roomId, envelope.boardId);
      } else if (envelope.revision > pending.baseRevision) {
        await _store.markConflict(
          CollaborationBoardConflict(
            roomId: roomId,
            boardId: envelope.boardId,
            localBaseRevision: pending.baseRevision,
            remoteRevision: envelope.revision,
            remoteEnvelope: envelope,
          ),
        );
      }
      return;
    }
    await _repository.applyRemoteBoard(
      CanvasBoard.fromJson(envelope.payload),
      roomId: roomId,
      revision: envelope.revision,
    );
    await onRemoteApplied?.call();
  }

  DocumentReference<Map<String, dynamic>> _reference(
    String roomId,
    String boardId,
  ) => _firestore
      .collection('rooms')
      .doc(roomId)
      .collection('boards')
      .doc(boardId);

  void _scheduleRetry(DateTime nextAttemptAt) {
    final delay = nextAttemptAt.difference(DateTime.now().toUtc());
    _retryTimer?.cancel();
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, wake);
  }

  static Duration _retryDelay(int attemptCount) =>
      Duration(seconds: (1 << (attemptCount - 1).clamp(0, 8)).clamp(1, 300));
  static const _transientCodes = <String>{
    'aborted',
    'cancelled',
    'deadline-exceeded',
    'internal',
    'resource-exhausted',
    'unavailable',
    'unknown',
  };
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

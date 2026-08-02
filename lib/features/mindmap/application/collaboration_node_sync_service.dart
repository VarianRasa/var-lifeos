import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/collaboration_mindmap_repository.dart';
import '../data/sembast_collaboration_sync_store.dart';
import '../domain/collaboration_node_sync.dart';
import '../domain/mindmap_node.dart';

final class CollaborationNodeSyncService {
  CollaborationNodeSyncService({
    required FirebaseFirestore firestore,
    required SembastCollaborationSyncStore store,
    required CollaborationMindmapRepository repository,
  }) : _firestore = firestore,
       _store = store,
       _repository = repository;

  final FirebaseFirestore _firestore;
  final SembastCollaborationSyncStore _store;
  final CollaborationMindmapRepository _repository;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  String? _roomId;
  bool _writeStopped = false;
  Future<void>? _draining;
  Timer? _retryTimer;

  Future<List<CollaborationNodeConflict>> get conflicts async =>
      _roomId == null ? const [] : _store.conflictsForRoom(_roomId!);

  Future<List<CollaborationNodeConflict>> listConflicts(String roomId) =>
      _store.conflictsForRoom(roomId);

  Future<void> resolveKeepRemote(CollaborationNodeConflict conflict) async {
    final envelope = await _freshRemote(conflict);
    if (envelope.revision < conflict.remoteRevision) {
      throw StateError('Remote collaboration revision went backwards.');
    }
    final binding = await _store.getBindingByLocal(
      conflict.roomId,
      conflict.localNodeId,
    );
    if (binding == null) {
      throw StateError('Collaboration node binding is missing.');
    }
    final updated = CollaborationNodeBinding(
      roomId: binding.roomId,
      localNodeId: binding.localNodeId,
      remoteNodeId: binding.remoteNodeId,
      dayKey: binding.dayKey,
      revision: envelope.revision,
    );
    if (envelope.deleted) {
      await _repository.applyRemoteDelete(updated);
    } else {
      await _repository.applyRemoteUpsert(
        MindmapNode.fromJson(envelope.payload!),
        updated,
      );
    }
    await _store.discardPending(conflict.roomId, conflict.localNodeId);
    await _store.clearConflict(conflict.roomId, conflict.localNodeId);
  }

  Future<void> resolveKeepMine(CollaborationNodeConflict conflict) async {
    final envelope = await _freshRemote(conflict);
    await _store.rebasePending(
      conflict.roomId,
      conflict.localNodeId,
      envelope.revision,
    );
    await _store.clearConflict(conflict.roomId, conflict.localNodeId);
    await drain();
  }

  Future<CollaborationNodeEnvelope> _freshRemote(
    CollaborationNodeConflict conflict,
  ) async {
    if (conflict.remoteEnvelope == null) {
      throw StateError('Conflict has no resolvable remote snapshot.');
    }
    final snapshot = await _firestore
        .collection('rooms')
        .doc(conflict.roomId)
        .collection('nodes')
        .doc(conflict.remoteNodeId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw StateError('Remote collaboration node is missing.');
    }
    final envelope = CollaborationNodeEnvelope.fromJson(
      Map<String, Object?>.from(data)..remove('updatedAt'),
    );
    if (envelope.remoteNodeId != conflict.remoteNodeId ||
        envelope.dayKey != conflict.remoteEnvelope!.dayKey) {
      throw StateError('Remote collaboration node identity changed.');
    }
    return envelope;
  }

  Future<void> start(String roomId) async {
    await stop();
    _roomId = roomId;
    _writeStopped = false;
    _subscription = _firestore
        .collection('rooms')
        .doc(roomId)
        .collection('nodes')
        .snapshots()
        .listen((snapshot) async {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.removed) continue;
            final data = change.doc.data();
            if (data == null) continue;
            try {
              await _applyRemote(
                roomId,
                CollaborationNodeEnvelope.fromJson(
                  Map<String, Object?>.from(data)..remove('updatedAt'),
                ),
              );
            } on FormatException {
              continue;
            }
          }
        });
    await drain();
  }

  Future<void> stop({bool stopWrites = false}) async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _writeStopped = stopWrites;
    if (!stopWrites) _roomId = null;
  }

  Future<void> drain() {
    return _draining ??= _drain().whenComplete(() => _draining = null);
  }

  Future<void> _drain() async {
    final roomId = _roomId;
    if (roomId == null || _writeStopped) return;
    for (final mutation in await _store.duePending(roomId, DateTime.now())) {
      final attempted = await _store.markAttempt(mutation, DateTime.now());
      if (attempted == null) continue;
      try {
        final revision = await _commit(attempted);
        await _store.acknowledgeIfCurrent(attempted, revision);
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' ||
            error.code == 'unauthenticated') {
          await _store.markBlocked(attempted, error.code);
          return;
        }
        if (_isTransient(error.code)) {
          final delay = retryDelay(attempted.attemptCount);
          await _store.scheduleRetry(
            attempted,
            DateTime.now().toUtc().add(delay),
            error.code,
          );
          unawaited(_scheduleRetry());
        } else {
          await _store.markFailed(attempted, error.code);
        }
        return;
      } on FormatException {
        await _store.markFailed(attempted, 'malformed');
        return;
      } on StateError {
        final remote = await _firestore
            .collection('rooms')
            .doc(attempted.roomId)
            .collection('nodes')
            .doc(attempted.remoteNodeId)
            .get();
        final remoteData = remote.data();
        final remoteRevision = remoteData?['revision'];
        CollaborationNodeEnvelope? envelope;
        if (remoteRevision is int && remoteData != null) {
          try {
            envelope = CollaborationNodeEnvelope.fromJson(
              Map<String, Object?>.from(remoteData)..remove('updatedAt'),
            );
          } on FormatException {
            envelope = null;
          }
          await _store.markConflict(
            CollaborationNodeConflict(
              roomId: attempted.roomId,
              localNodeId: attempted.localNodeId,
              remoteNodeId: attempted.remoteNodeId,
              localBaseRevision: attempted.baseRevision,
              remoteRevision: remoteRevision,
              remoteEnvelope: envelope,
            ),
          );
        }
        return;
      }
    }
    unawaited(_scheduleRetry());
  }

  static Duration retryDelay(int attemptCount) =>
      Duration(seconds: (1 << (attemptCount - 1).clamp(0, 8)).clamp(1, 300));
  bool _isTransient(String code) => const {
    'aborted',
    'cancelled',
    'deadline-exceeded',
    'internal',
    'resource-exhausted',
    'unavailable',
    'unknown',
  }.contains(code);
  Future<void> retryNow() async {
    final roomId = _roomId;
    if (roomId == null) return;
    await _store.unblock(roomId);
    wake();
  }

  void wake() {
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(drain());
  }

  Future<void> setWritePermission(bool allowed, String reason) async {
    _writeStopped = !allowed;
    final roomId = _roomId;
    if (roomId == null) return;
    if (allowed) {
      await _store.unblock(roomId);
      wake();
    } else {
      for (final mutation in await _store.pendingForRoom(roomId)) {
        if (mutation.deliveryState == CollaborationDeliveryState.pending ||
            mutation.deliveryState == CollaborationDeliveryState.retryWaiting) {
          await _store.markBlocked(mutation, reason);
        }
      }
    }
  }

  Future<void> _scheduleRetry() async {
    final roomId = _roomId;
    if (roomId == null || _writeStopped) return;
    final next = (await _store.summary(roomId)).nextRetryAt;
    _retryTimer?.cancel();
    if (next != null) {
      _retryTimer = Timer(
        next.difference(DateTime.now().toUtc()).isNegative
            ? Duration.zero
            : next.difference(DateTime.now().toUtc()),
        wake,
      );
    }
  }

  Future<void> publish(MindmapNode node, String remoteNodeId) async {
    final roomId = _roomId;
    if (roomId == null) throw StateError('Collaboration sync is not started.');
    final pending = await _store.pendingForRoom(roomId);
    final mutation = pending
        .where((item) => item.localNodeId == node.id)
        .firstOrNull;
    if (mutation == null) {
      throw StateError('Node must be bound and queued before publish.');
    }
    await drain();
  }

  Future<int> _commit(CollaborationPendingMutation mutation) {
    final reference = _firestore
        .collection('rooms')
        .doc(mutation.roomId)
        .collection('nodes')
        .doc(mutation.remoteNodeId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final current = snapshot.data();
      final currentRevision = current?['revision'] as int? ?? 0;
      if (current?['schemaVersion'] == 2 &&
          current?['lastMutationId'] == mutation.mutationId) {
        return currentRevision;
      }
      if (currentRevision != mutation.baseRevision ||
          (!snapshot.exists && mutation.baseRevision != 0)) {
        throw StateError('Collaboration revision conflict.');
      }
      final createdByUid =
          current?['createdByUid'] as String? ?? mutation.updatedByUid;
      final revision = currentRevision + 1;
      final envelope = CollaborationNodeEnvelope(
        remoteNodeId: mutation.remoteNodeId,
        dayKey: mutation.dayKey,
        revision: revision,
        deleted: mutation.kind == CollaborationMutationKind.delete,
        payload: mutation.payload,
        createdByUid: createdByUid,
        updatedByUid: mutation.updatedByUid,
        lastMutationId: mutation.mutationId,
      );
      transaction.set(reference, {
        ...envelope.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return revision;
    });
  }

  Future<void> _applyRemote(
    String roomId,
    CollaborationNodeEnvelope envelope,
  ) async {
    if (await _store.isDetachedRemote(roomId, envelope.remoteNodeId)) return;
    final binding = await _store.getBindingByRemote(
      roomId,
      envelope.remoteNodeId,
    );
    if (binding != null && envelope.revision <= binding.revision) return;
    final pending = await _store.pendingForRoom(roomId);
    final localPending = pending
        .where((item) => item.remoteNodeId == envelope.remoteNodeId)
        .firstOrNull;
    if (localPending != null) {
      if (envelope.lastMutationId == localPending.mutationId) {
        await _store.acknowledgeIfCurrent(localPending, envelope.revision);
        await _store.clearConflict(roomId, localPending.localNodeId);
      } else if (envelope.revision > localPending.baseRevision) {
        await _store.markConflict(
          CollaborationNodeConflict(
            roomId: roomId,
            localNodeId: localPending.localNodeId,
            remoteNodeId: envelope.remoteNodeId,
            localBaseRevision: localPending.baseRevision,
            remoteRevision: envelope.revision,
            remoteEnvelope: envelope,
          ),
        );
      }
      return;
    }
    final resolved =
        binding ??
        CollaborationNodeBinding(
          roomId: roomId,
          localNodeId: envelope.remoteNodeId,
          remoteNodeId: envelope.remoteNodeId,
          dayKey: envelope.dayKey,
          revision: envelope.revision,
        );
    final updated = CollaborationNodeBinding(
      roomId: resolved.roomId,
      localNodeId: resolved.localNodeId,
      remoteNodeId: resolved.remoteNodeId,
      dayKey: resolved.dayKey,
      revision: envelope.revision,
    );
    if (envelope.deleted) {
      await _repository.applyRemoteDelete(updated);
    } else {
      await _repository.applyRemoteUpsert(
        MindmapNode.fromJson(envelope.payload!),
        updated,
      );
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

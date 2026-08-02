import 'dart:async';

import 'package:sembast/sembast.dart';

import '../domain/collaboration_node_sync.dart';

final class SembastCollaborationSyncStore {
  SembastCollaborationSyncStore({required FutureOr<Database> database})
    : _databaseSource = database;
  final FutureOr<Database> _databaseSource;
  final _bindings = stringMapStoreFactory.store('collaboration_bindings');
  final _pending = stringMapStoreFactory.store('collaboration_pending');
  final _conflicts = stringMapStoreFactory.store('collaboration_conflicts');
  final _detached = stringMapStoreFactory.store('collaboration_detached');
  final _changes = StreamController<void>.broadcast();
  Database? _database;
  Future<Database> get _db async =>
      _database ??= await Future<Database>.value(_databaseSource);
  Stream<void> get changes => _changes.stream;
  String _key(String roomId, String id) => '$roomId|$id';
  void _changed() => _changes.add(null);

  Future<List<CollaborationNodeBinding>> listBindings(String roomId) async =>
      List.unmodifiable(
        (await _bindings.find(
          await _db,
          finder: Finder(filter: Filter.equals('roomId', roomId)),
        )).map((record) => _binding(record.value)),
      );
  Future<CollaborationNodeBinding?> getBindingByLocal(
    String roomId,
    String localNodeId,
  ) async {
    final value = await _bindings
        .record(_key(roomId, localNodeId))
        .get(await _db);
    return value == null ? null : _binding(value);
  }

  Future<CollaborationNodeBinding?> getBindingByRemote(
    String roomId,
    String remoteNodeId,
  ) async {
    final records = await _bindings.find(
      await _db,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('roomId', roomId),
          Filter.equals('remoteNodeId', remoteNodeId),
        ]),
        limit: 1,
      ),
    );
    return records.isEmpty ? null : _binding(records.single.value);
  }

  Future<void> bind(CollaborationNodeBinding binding) async {
    final db = await _db;
    await db.transaction((transaction) async {
      final localValue = await _bindings
          .record(_key(binding.roomId, binding.localNodeId))
          .get(transaction);
      final remote = await _bindings.find(
        transaction,
        finder: Finder(
          filter: Filter.and([
            Filter.equals('roomId', binding.roomId),
            Filter.equals('remoteNodeId', binding.remoteNodeId),
          ]),
          limit: 1,
        ),
      );
      if ((localValue != null &&
              _binding(localValue).remoteNodeId != binding.remoteNodeId) ||
          (remote.isNotEmpty &&
              _binding(remote.single.value).localNodeId !=
                  binding.localNodeId)) {
        throw StateError('Collaboration node binding must be unique.');
      }
      await _bindings
          .record(_key(binding.roomId, binding.localNodeId))
          .put(transaction, _bindingJson(binding));
      await _detached
          .record(_key(binding.roomId, binding.remoteNodeId))
          .delete(transaction);
    });
    _changed();
  }

  Future<void> detach(CollaborationNodeBinding binding) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await _bindings
          .record(_key(binding.roomId, binding.localNodeId))
          .delete(transaction);
      await _pending
          .record(_key(binding.roomId, binding.localNodeId))
          .delete(transaction);
      await _conflicts
          .record(_key(binding.roomId, binding.localNodeId))
          .delete(transaction);
      await _detached.record(_key(binding.roomId, binding.remoteNodeId)).put(
        transaction,
        {'roomId': binding.roomId, 'remoteNodeId': binding.remoteNodeId},
      );
    });
    _changed();
  }

  Future<bool> isDetachedRemote(String roomId, String remoteNodeId) async =>
      await _detached.record(_key(roomId, remoteNodeId)).get(await _db) != null;

  Future<void> enqueue(CollaborationPendingMutation mutation) async {
    final record = _pending.record(_key(mutation.roomId, mutation.localNodeId));
    final existing = await record.get(await _db);
    final value = existing == null
        ? mutation
        : CollaborationPendingMutation(
            mutationId: mutation.mutationId,
            roomId: mutation.roomId,
            localNodeId: mutation.localNodeId,
            remoteNodeId: mutation.remoteNodeId,
            dayKey: mutation.dayKey,
            baseRevision: _mutation(existing).baseRevision,
            kind: mutation.kind,
            payload: mutation.payload,
            updatedByUid: mutation.updatedByUid,
            attemptCount: 0,
            createdAt: _mutation(existing).createdAt,
            updatedAt: mutation.updatedAt,
            nextAttemptAt: mutation.updatedAt,
            lastAttemptAt: null,
            lastErrorCode: null,
            deliveryState: CollaborationDeliveryState.pending,
          );
    await record.put(await _db, _mutationJson(value));
    _changed();
  }

  Future<List<CollaborationPendingMutation>> pendingForRoom(
    String roomId,
  ) async => List.unmodifiable(
    (await _pending.find(
      await _db,
      finder: Finder(filter: Filter.equals('roomId', roomId)),
    )).map((record) => _mutation(record.value)),
  );
  Future<List<CollaborationPendingMutation>> duePending(
    String roomId,
    DateTime now,
  ) async => List.unmodifiable(
    (await pendingForRoom(roomId)).where(
      (item) =>
          (item.deliveryState == CollaborationDeliveryState.pending ||
              item.deliveryState == CollaborationDeliveryState.retryWaiting) &&
          !item.nextAttemptAt.isAfter(now.toUtc()),
    ),
  );
  Future<CollaborationOutboxSummary> summary(String roomId) async {
    final items = await pendingForRoom(roomId);
    int count(CollaborationDeliveryState state) =>
        items.where((item) => item.deliveryState == state).length;
    final retries =
        items
            .where(
              (item) =>
                  item.deliveryState == CollaborationDeliveryState.retryWaiting,
            )
            .map((item) => item.nextAttemptAt)
            .toList()
          ..sort();
    return CollaborationOutboxSummary(
      pending: count(CollaborationDeliveryState.pending),
      retrying: count(CollaborationDeliveryState.retryWaiting),
      blocked: count(CollaborationDeliveryState.blocked),
      failed: count(CollaborationDeliveryState.failed),
      conflict: count(CollaborationDeliveryState.conflict),
      nextRetryAt: retries.isEmpty ? null : retries.first,
    );
  }

  Future<bool> _update(CollaborationPendingMutation mutation) async {
    var updated = false;
    final db = await _db;
    await db.transaction((transaction) async {
      final record = _pending.record(
        _key(mutation.roomId, mutation.localNodeId),
      );
      final value = await record.get(transaction);
      if (value == null || _mutation(value).mutationId != mutation.mutationId) {
        return;
      }
      await record.put(transaction, _mutationJson(mutation));
      updated = true;
    });
    if (updated) _changed();
    return updated;
  }

  Future<CollaborationPendingMutation?> markAttempt(
    CollaborationPendingMutation mutation,
    DateTime now,
  ) async {
    final attempted = mutation.copyWith(
      attemptCount: mutation.attemptCount + 1,
      lastAttemptAt: now,
      updatedAt: now,
    );
    return await _update(attempted) ? attempted : null;
  }

  Future<bool> scheduleRetry(
    CollaborationPendingMutation mutation,
    DateTime nextAttemptAt,
    String code,
  ) => _update(
    mutation.copyWith(
      nextAttemptAt: nextAttemptAt,
      updatedAt: DateTime.now().toUtc(),
      lastErrorCode: code,
      deliveryState: CollaborationDeliveryState.retryWaiting,
    ),
  );
  Future<bool> markBlocked(
    CollaborationPendingMutation mutation,
    String code,
  ) => _update(
    mutation.copyWith(
      updatedAt: DateTime.now().toUtc(),
      lastErrorCode: code,
      deliveryState: CollaborationDeliveryState.blocked,
    ),
  );
  Future<bool> markFailed(CollaborationPendingMutation mutation, String code) =>
      _update(
        mutation.copyWith(
          updatedAt: DateTime.now().toUtc(),
          lastErrorCode: code,
          deliveryState: CollaborationDeliveryState.failed,
        ),
      );
  Future<bool> markMutationConflict(CollaborationPendingMutation mutation) =>
      _update(
        mutation.copyWith(
          updatedAt: DateTime.now().toUtc(),
          deliveryState: CollaborationDeliveryState.conflict,
        ),
      );
  Future<void> unblock(String roomId, {DateTime? now}) async {
    for (final item in await pendingForRoom(roomId)) {
      if (item.deliveryState == CollaborationDeliveryState.blocked) {
        await _update(
          item.copyWith(
            nextAttemptAt: now ?? DateTime.now().toUtc(),
            updatedAt: now ?? DateTime.now().toUtc(),
            clearError: true,
            deliveryState: CollaborationDeliveryState.pending,
          ),
        );
      }
    }
  }

  Future<bool> acknowledgeIfCurrent(
    CollaborationPendingMutation committed,
    int revision,
  ) async {
    var removed = false;
    final db = await _db;
    await db.transaction((transaction) async {
      final key = _key(committed.roomId, committed.localNodeId);
      final value = await _pending.record(key).get(transaction);
      if (value != null) {
        final current = _mutation(value);
        if (current.mutationId == committed.mutationId) {
          await _pending.record(key).delete(transaction);
          removed = true;
        } else {
          await _pending
              .record(key)
              .put(
                transaction,
                _mutationJson(
                  current.copyWith(
                    baseRevision: revision > current.baseRevision
                        ? revision
                        : current.baseRevision,
                  ),
                ),
              );
        }
      }
      final bindingValue = await _bindings.record(key).get(transaction);
      if (bindingValue != null) {
        final binding = _binding(bindingValue);
        await _bindings
            .record(key)
            .put(
              transaction,
              _bindingJson(
                CollaborationNodeBinding(
                  roomId: binding.roomId,
                  localNodeId: binding.localNodeId,
                  remoteNodeId: binding.remoteNodeId,
                  dayKey: binding.dayKey,
                  revision: revision > binding.revision
                      ? revision
                      : binding.revision,
                ),
              ),
            );
      }
    });
    _changed();
    return removed;
  }

  Future<void> acknowledge(
    CollaborationPendingMutation mutation,
    int revision,
  ) async {
    await acknowledgeIfCurrent(mutation, revision);
  }

  Future<void> markConflict(CollaborationNodeConflict conflict) async {
    await _conflicts
        .record(_key(conflict.roomId, conflict.localNodeId))
        .put(await _db, conflict.toJson());
    final pending = (await pendingForRoom(
      conflict.roomId,
    )).where((item) => item.localNodeId == conflict.localNodeId).firstOrNull;
    if (pending != null) await markMutationConflict(pending);
    _changed();
  }

  Future<CollaborationNodeConflict?> getConflict(
    String roomId,
    String localNodeId,
  ) async {
    final value = await _conflicts
        .record(_key(roomId, localNodeId))
        .get(await _db);
    return value == null ? null : CollaborationNodeConflict.fromJson(value);
  }

  Future<void> clearConflict(String roomId, String localNodeId) async {
    await _conflicts.record(_key(roomId, localNodeId)).delete(await _db);
    _changed();
  }

  Future<void> discardPending(String roomId, String localNodeId) async {
    await _pending.record(_key(roomId, localNodeId)).delete(await _db);
    _changed();
  }

  Future<void> rebasePending(
    String roomId,
    String localNodeId,
    int baseRevision,
  ) async {
    final mutation = (await pendingForRoom(
      roomId,
    )).where((item) => item.localNodeId == localNodeId).firstOrNull;
    if (mutation == null) {
      throw StateError('Pending collaboration mutation is missing.');
    }
    await _update(
      mutation.copyWith(
        baseRevision: baseRevision,
        nextAttemptAt: DateTime.now().toUtc(),
        deliveryState: CollaborationDeliveryState.pending,
      ),
    );
  }

  Future<List<CollaborationNodeConflict>> conflictsForRoom(
    String roomId,
  ) async => List.unmodifiable(
    (await _conflicts.find(
      await _db,
      finder: Finder(filter: Filter.equals('roomId', roomId)),
    )).map((record) => CollaborationNodeConflict.fromJson(record.value)),
  );
  Future<bool> applyRemoteRevision(
    String roomId,
    String remoteNodeId,
    int revision,
  ) async {
    final binding = await getBindingByRemote(roomId, remoteNodeId);
    if (binding == null || revision <= binding.revision) return false;
    await bind(
      CollaborationNodeBinding(
        roomId: binding.roomId,
        localNodeId: binding.localNodeId,
        remoteNodeId: binding.remoteNodeId,
        dayKey: binding.dayKey,
        revision: revision,
      ),
    );
    return true;
  }
}

CollaborationNodeBinding _binding(Map<String, Object?> value) =>
    CollaborationNodeBinding(
      roomId: value['roomId']! as String,
      localNodeId: value['localNodeId']! as String,
      remoteNodeId: value['remoteNodeId']! as String,
      dayKey: value['dayKey']! as String,
      revision: value['revision']! as int,
    );
Map<String, Object?> _bindingJson(CollaborationNodeBinding value) => {
  'roomId': value.roomId,
  'localNodeId': value.localNodeId,
  'remoteNodeId': value.remoteNodeId,
  'dayKey': value.dayKey,
  'revision': value.revision,
};
CollaborationPendingMutation _mutation(Map<String, Object?> value) {
  final now = DateTime.now().toUtc();
  DateTime date(String key, DateTime fallback) =>
      DateTime.tryParse(value[key] as String? ?? '')?.toUtc() ?? fallback;
  return CollaborationPendingMutation(
    mutationId:
        value['mutationId'] as String? ??
        'legacy:${value['roomId']}:${value['localNodeId']}',
    roomId: value['roomId']! as String,
    localNodeId: value['localNodeId']! as String,
    remoteNodeId: value['remoteNodeId']! as String,
    dayKey: value['dayKey']! as String,
    baseRevision: value['baseRevision']! as int,
    kind: CollaborationMutationKind.values.byName(value['kind']! as String),
    payload: (value['payload'] as Map?)?.cast<String, Object?>(),
    updatedByUid: value['updatedByUid']! as String,
    attemptCount: value['attemptCount'] as int? ?? 0,
    createdAt: date('createdAt', now),
    updatedAt: date('updatedAt', now),
    nextAttemptAt: date('nextAttemptAt', now),
    lastAttemptAt: value['lastAttemptAt'] == null
        ? null
        : date('lastAttemptAt', now),
    lastErrorCode: value['lastErrorCode'] as String?,
    deliveryState: CollaborationDeliveryState.values.byName(
      value['deliveryState'] as String? ?? 'pending',
    ),
  );
}

Map<String, Object?> _mutationJson(CollaborationPendingMutation value) => {
  'mutationId': value.mutationId,
  'roomId': value.roomId,
  'localNodeId': value.localNodeId,
  'remoteNodeId': value.remoteNodeId,
  'dayKey': value.dayKey,
  'baseRevision': value.baseRevision,
  'kind': value.kind.name,
  'payload': value.payload,
  'updatedByUid': value.updatedByUid,
  'attemptCount': value.attemptCount,
  'createdAt': value.createdAt.toIso8601String(),
  'updatedAt': value.updatedAt.toIso8601String(),
  'nextAttemptAt': value.nextAttemptAt.toIso8601String(),
  'lastAttemptAt': value.lastAttemptAt?.toIso8601String(),
  'lastErrorCode': value.lastErrorCode,
  'deliveryState': value.deliveryState.name,
};

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

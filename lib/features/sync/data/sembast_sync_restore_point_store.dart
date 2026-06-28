/// Sembast-backed restore point store.
library;

import 'dart:async';

import 'package:sembast/sembast.dart';

import '../domain/sync_restore_point.dart';

final class SembastSyncRestorePointStore implements SyncRestorePointStore {
  SembastSyncRestorePointStore({required FutureOr<Database> database})
    : _databaseSource = database;

  static const String _storeName = 'sync_restore_points';

  final FutureOr<Database> _databaseSource;
  final StoreRef<String, Map<String, Object?>> _store = stringMapStoreFactory
      .store(_storeName);
  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;

    final opened = await Future<Database>.value(_databaseSource);
    _database = opened;
    return opened;
  }

  @override
  Future<void> add(SyncRestorePoint point) async {
    final db = await _db;
    await _store.record(point.id).put(db, point.toJson());
  }

  @override
  Future<void> clear() async {
    final db = await _db;
    await _store.delete(db);
  }

  @override
  Future<void> delete(String id) async {
    final db = await _db;
    await _store.record(id).delete(db);
  }

  @override
  Future<void> prune({required int keepLatest}) async {
    if (keepLatest < 0) {
      throw ArgumentError.value(keepLatest, 'keepLatest');
    }

    final db = await _db;
    final records = await _store.find(db);
    final points = [
      for (final record in records) SyncRestorePoint.fromJson(record.value),
    ]..sort(_compareNewestFirst);
    final retainedIds = points
        .take(keepLatest)
        .map((point) => point.id)
        .toSet();

    for (final point in points) {
      if (!retainedIds.contains(point.id)) {
        await _store.record(point.id).delete(db);
      }
    }
  }

  @override
  Future<SyncRestorePoint?> read(String id) async {
    final db = await _db;
    final record = await _store.record(id).get(db);
    if (record == null) return null;
    return SyncRestorePoint.fromJson(record);
  }

  @override
  Future<List<SyncRestorePoint>> recent({int limit = 5}) async {
    final db = await _db;
    final records = await _store.find(db);
    final points = [
      for (final record in records) SyncRestorePoint.fromJson(record.value),
    ]..sort(_compareNewestFirst);
    return List.unmodifiable(points.take(limit));
  }
}

int _compareNewestFirst(SyncRestorePoint a, SyncRestorePoint b) {
  final createdAt = b.createdAt.compareTo(a.createdAt);
  if (createdAt != 0) return createdAt;
  return b.id.compareTo(a.id);
}

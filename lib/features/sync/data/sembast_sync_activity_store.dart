/// Sembast-backed sync activity store.
library;

import 'dart:async';

import 'package:sembast/sembast.dart';

import '../domain/sync_activity.dart';

final class SembastSyncActivityStore implements SyncActivityStore {
  SembastSyncActivityStore({required FutureOr<Database> database})
    : _databaseSource = database;

  static const String _storeName = 'sync_activity';

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
  Future<void> add(SyncActivityEntry entry) async {
    final db = await _db;
    await _store.record(entry.id).put(db, entry.toJson());
  }

  @override
  Future<void> clear() async {
    final db = await _db;
    await _store.delete(db);
  }

  @override
  Future<List<SyncActivityEntry>> recent({int limit = 5}) async {
    final db = await _db;
    final records = await _store.find(db);
    final entries = [
      for (final record in records) SyncActivityEntry.fromJson(record.value),
    ]..sort(_compareNewestFirst);
    return List.unmodifiable(entries.take(limit));
  }
}

int _compareNewestFirst(SyncActivityEntry a, SyncActivityEntry b) {
  final occurredAt = b.occurredAt.compareTo(a.occurredAt);
  if (occurredAt != 0) return occurredAt;
  return b.id.compareTo(a.id);
}

/// Sembast-backed sync state store.
library;

import 'dart:async';

import 'package:sembast/sembast.dart';

import '../domain/sync_account.dart';
import '../domain/sync_state_store.dart';

final class SembastSyncStateStore implements SyncStateStore {
  SembastSyncStateStore({required FutureOr<Database> database})
    : _databaseSource = database;

  static const String _storeName = 'sync_snapshots';

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
  Future<void> clearSnapshot(SyncUser user) async {
    final db = await _db;
    await _store.record(user.id).delete(db);
  }

  @override
  Future<SyncSnapshot?> readSnapshot(SyncUser user) async {
    final db = await _db;
    final value = await _store.record(user.id).get(db);
    if (value == null) return null;
    return SyncSnapshot.fromJson(value);
  }

  @override
  Future<void> saveSnapshot(SyncUser user, SyncSnapshot snapshot) async {
    final db = await _db;
    await _store.record(user.id).put(db, snapshot.toJson());
  }
}

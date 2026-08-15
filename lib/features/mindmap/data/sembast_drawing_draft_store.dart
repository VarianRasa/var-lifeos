import 'dart:async';

import 'package:sembast/sembast.dart';

import '../domain/drawing_draft_checkpoint.dart';

final class SembastDrawingDraftStore {
  SembastDrawingDraftStore({required FutureOr<Database> database})
    : _databaseSource = database;

  final FutureOr<Database> _databaseSource;
  final StoreRef<String, Map<String, Object?>> _store = stringMapStoreFactory
      .store('drawing_draft_checkpoints');
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Database? _database;

  Future<Database> get _db async =>
      _database ??= await Future<Database>.value(_databaseSource);
  Stream<void> get changes => _changes.stream;

  Future<DrawingDraftCheckpoint?> get(String nodeId) async {
    final value = await _store.record(nodeId).get(await _db);
    return value == null ? null : DrawingDraftCheckpoint.fromJson(value);
  }

  Future<List<DrawingDraftCheckpoint>> list() async {
    final records = await _store.find(
      await _db,
      finder: Finder(sortOrders: <SortOrder>[SortOrder('updatedAt', false)]),
    );
    return List<DrawingDraftCheckpoint>.unmodifiable(
      records.map((record) => DrawingDraftCheckpoint.fromJson(record.value)),
    );
  }

  Future<bool> putIfNewer(DrawingDraftCheckpoint checkpoint) async {
    var written = false;
    final database = await _db;
    await database.transaction((transaction) async {
      final record = _store.record(checkpoint.nodeId);
      final value = await record.get(transaction);
      if (value != null &&
          DrawingDraftCheckpoint.fromJson(value).generation >=
              checkpoint.generation) {
        return;
      }
      await record.put(transaction, checkpoint.toJson());
      written = true;
    });
    if (written) _changes.add(null);
    return written;
  }

  Future<bool> deleteIfGeneration(String nodeId, int generation) async {
    var deleted = false;
    final database = await _db;
    await database.transaction((transaction) async {
      final record = _store.record(nodeId);
      final value = await record.get(transaction);
      if (value == null ||
          DrawingDraftCheckpoint.fromJson(value).generation != generation) {
        return;
      }
      await record.delete(transaction);
      deleted = true;
    });
    if (deleted) _changes.add(null);
    return deleted;
  }
}

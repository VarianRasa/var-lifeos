/// Sembast-backed attachment transfer progress metadata.
library;

import 'dart:async';

import 'package:sembast/sembast.dart';

import '../domain/attachment_sync_progress.dart';

final class SembastAttachmentSyncProgressStore
    implements AttachmentSyncProgressStore {
  SembastAttachmentSyncProgressStore({required FutureOr<Database> database})
    : _databaseSource = database;

  static const String _storeName = 'attachment_sync_progress_v1';
  final FutureOr<Database> _databaseSource;
  final StoreRef<String, Map<String, Object?>> _store = stringMapStoreFactory
      .store(_storeName);
  Database? _database;

  Future<Database> get _db async =>
      _database ??= await Future<Database>.value(_databaseSource);

  @override
  Future<List<AttachmentSyncProgress>> readAll() async {
    final db = await _db;
    return db.transaction((transaction) async {
      final records = await _store.find(transaction);
      final parsed = <String, AttachmentSyncProgress>{};
      final canonicalKeys = <String>{};
      for (final record in records) {
        try {
          final progress = AttachmentSyncProgress.fromJson(record.value);
          parsed[record.key] = progress;
          if (record.key == progress.key) canonicalKeys.add(progress.key);
        } on Object {
          await _store.record(record.key).delete(transaction);
        }
      }

      for (final entry in parsed.entries.toList(growable: false)) {
        final legacyKey = entry.key;
        final progress = entry.value;
        if (legacyKey == progress.key) continue;
        if (!canonicalKeys.contains(progress.key)) {
          await _store.record(progress.key).put(transaction, progress.toJson());
          canonicalKeys.add(progress.key);
          parsed[progress.key] = progress;
        }
        await _store.record(legacyKey).delete(transaction);
      }

      return List.unmodifiable([for (final key in canonicalKeys) parsed[key]!]);
    });
  }

  @override
  Future<void> remove(String key) async {
    await _store.record(key).delete(await _db);
  }

  @override
  Future<void> write(AttachmentSyncProgress progress) async {
    await _store.record(progress.key).put(await _db, progress.toJson());
  }
}

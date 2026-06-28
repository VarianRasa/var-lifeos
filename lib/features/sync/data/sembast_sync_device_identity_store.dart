/// Sembast-backed per-install device identity for multi-device sync metadata.
library;

import 'dart:async';

import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../domain/mindmap_backup_document.dart';
import '../domain/sync_device_identity_store.dart';

final class SembastSyncDeviceIdentityStore implements SyncDeviceIdentityStore {
  SembastSyncDeviceIdentityStore({
    required FutureOr<Database> database,
    String Function()? idGenerator,
    String defaultLabel = 'This device',
  }) : _databaseSource = database,
       _idGenerator = idGenerator ?? _defaultIdGenerator,
       _defaultLabel = defaultLabel;

  static const String _storeName = 'sync_device_identity';
  static const String _identityKey = 'identity';

  final FutureOr<Database> _databaseSource;
  final String Function() _idGenerator;
  final String _defaultLabel;
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
  Future<SyncDeviceIdentity> readOrCreateIdentity() async {
    final db = await _db;
    final existing = await _store.record(_identityKey).get(db);
    if (existing != null) {
      return SyncDeviceIdentity.fromJson(existing);
    }

    final identity = SyncDeviceIdentity(
      id: _normalizeId(_idGenerator()),
      label: _normalizeLabel(_defaultLabel),
    );
    await _save(identity);
    return identity;
  }

  @override
  Future<SyncDeviceIdentity> updateLabel(String label) async {
    final existing = await readOrCreateIdentity();
    final updated = SyncDeviceIdentity(
      id: existing.id,
      label: _normalizeLabel(label),
    );
    await _save(updated);
    return updated;
  }

  Future<void> _save(SyncDeviceIdentity identity) async {
    final db = await _db;
    await _store.record(_identityKey).put(db, {
      ...identity.toJson(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }
}

String _defaultIdGenerator() => 'device-${const Uuid().v4()}';

String _normalizeId(String id) {
  final trimmed = id.trim();
  return trimmed.isEmpty ? _defaultIdGenerator() : trimmed;
}

String _normalizeLabel(String label) {
  final trimmed = label.trim();
  return trimmed.isEmpty ? 'This device' : trimmed;
}

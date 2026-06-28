/// In-memory sync state store for tests and local development.
library;

import '../domain/sync_account.dart';
import '../domain/sync_state_store.dart';

final class InMemorySyncStateStore implements SyncStateStore {
  final Map<String, SyncSnapshot> _snapshotsByUserId = {};

  @override
  Future<void> clearSnapshot(SyncUser user) async {
    _snapshotsByUserId.remove(user.id);
  }

  @override
  Future<SyncSnapshot?> readSnapshot(SyncUser user) async {
    return _snapshotsByUserId[user.id];
  }

  @override
  Future<void> saveSnapshot(SyncUser user, SyncSnapshot snapshot) async {
    _snapshotsByUserId[user.id] = snapshot;
  }
}

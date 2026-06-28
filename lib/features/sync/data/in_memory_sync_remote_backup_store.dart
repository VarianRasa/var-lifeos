/// In-memory remote backup store used by tests and local development.
library;

import '../domain/mindmap_backup_document.dart';
import '../domain/sync_account.dart';

final class InMemorySyncRemoteBackupStore implements SyncRemoteBackupStore {
  final Map<String, MindmapBackupDocument> _documentsByUserId = {};

  @override
  Future<MindmapBackupDocument?> fetchLatestBackup(SyncUser user) async {
    return _documentsByUserId[user.id];
  }

  @override
  Future<void> uploadBackup(
    SyncUser user,
    MindmapBackupDocument document,
  ) async {
    _documentsByUserId[user.id] = document;
  }
}

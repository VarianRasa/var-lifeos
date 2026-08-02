/// In-memory attachment transfer progress store for tests.
library;

import '../domain/attachment_sync_progress.dart';

final class InMemoryAttachmentSyncProgressStore
    implements AttachmentSyncProgressStore {
  final Map<String, AttachmentSyncProgress> _entries = {};

  @override
  Future<List<AttachmentSyncProgress>> readAll() async =>
      List.unmodifiable(_entries.values);

  @override
  Future<void> remove(String key) async {
    _entries.remove(key);
  }

  @override
  Future<void> write(AttachmentSyncProgress progress) async {
    _entries[progress.key] = progress;
  }
}

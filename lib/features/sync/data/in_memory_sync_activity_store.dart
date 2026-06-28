/// In-memory sync activity store for tests and local development.
library;

import '../domain/sync_activity.dart';

final class InMemorySyncActivityStore implements SyncActivityStore {
  final List<SyncActivityEntry> _entries = [];

  @override
  Future<void> add(SyncActivityEntry entry) async {
    _entries.removeWhere((existing) => existing.id == entry.id);
    _entries.add(entry);
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }

  @override
  Future<List<SyncActivityEntry>> recent({int limit = 5}) async {
    final entries = [..._entries]..sort(_compareNewestFirst);
    return List.unmodifiable(entries.take(limit));
  }
}

int _compareNewestFirst(SyncActivityEntry a, SyncActivityEntry b) {
  final occurredAt = b.occurredAt.compareTo(a.occurredAt);
  if (occurredAt != 0) return occurredAt;
  return b.id.compareTo(a.id);
}

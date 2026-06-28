/// In-memory restore point store for tests and local development.
library;

import '../domain/sync_restore_point.dart';

final class InMemorySyncRestorePointStore implements SyncRestorePointStore {
  final List<SyncRestorePoint> _points = [];

  @override
  Future<void> add(SyncRestorePoint point) async {
    _points.removeWhere((existing) => existing.id == point.id);
    _points.add(point);
  }

  @override
  Future<void> clear() async {
    _points.clear();
  }

  @override
  Future<void> delete(String id) async {
    _points.removeWhere((point) => point.id == id);
  }

  @override
  Future<void> prune({required int keepLatest}) async {
    if (keepLatest < 0) {
      throw ArgumentError.value(keepLatest, 'keepLatest');
    }

    final retainedIds = (await recent(
      limit: keepLatest,
    )).map((point) => point.id).toSet();
    _points.removeWhere((point) => !retainedIds.contains(point.id));
  }

  @override
  Future<SyncRestorePoint?> read(String id) async {
    for (final point in _points) {
      if (point.id == id) return point;
    }
    return null;
  }

  @override
  Future<List<SyncRestorePoint>> recent({int limit = 5}) async {
    final points = [..._points]..sort(_compareNewestFirst);
    return List.unmodifiable(points.take(limit));
  }
}

int _compareNewestFirst(SyncRestorePoint a, SyncRestorePoint b) {
  final createdAt = b.createdAt.compareTo(a.createdAt);
  if (createdAt != 0) return createdAt;
  return b.id.compareTo(a.id);
}

/// Local sync state used to remember the last clean remote baseline.
library;

import 'mindmap_backup_document.dart';
import 'sync_account.dart';

final class SyncSnapshot {
  const SyncSnapshot({
    required this.userId,
    required this.syncedAt,
    required this.baseline,
  });

  factory SyncSnapshot.fromJson(Map<String, Object?> json) {
    final userId = json['userId'] as String? ?? '';
    if (userId.trim().isEmpty) {
      throw const FormatException('Sync snapshot user id is required.');
    }

    final syncedAtValue = json['syncedAt'];
    final syncedAt = syncedAtValue is String
        ? DateTime.tryParse(syncedAtValue)
        : null;
    if (syncedAt == null) {
      throw const FormatException('Sync snapshot syncedAt is invalid.');
    }

    final rawBaseline = json['baseline'];
    final baseline = rawBaseline is Map
        ? MindmapBackupDocument.fromJson(rawBaseline.cast<String, Object?>())
        : throw const FormatException('Sync snapshot baseline is invalid.');

    return SyncSnapshot(
      userId: userId.trim(),
      syncedAt: syncedAt,
      baseline: baseline,
    );
  }

  final String userId;
  final DateTime syncedAt;
  final MindmapBackupDocument baseline;

  Map<String, Object?> toJson() => {
    'userId': userId,
    'syncedAt': syncedAt.toIso8601String(),
    'baseline': baseline.toJson(),
  };
}

abstract interface class SyncStateStore {
  Future<SyncSnapshot?> readSnapshot(SyncUser user);

  Future<void> saveSnapshot(SyncUser user, SyncSnapshot snapshot);

  Future<void> clearSnapshot(SyncUser user);
}

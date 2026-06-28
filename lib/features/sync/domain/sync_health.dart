/// Derived sync health for compact status surfaces.
library;

import 'package:intl/intl.dart';

import 'sync_account.dart';
import 'sync_activity.dart';

enum SyncHealthLevel { signedOut, healthy, needsAttention, degraded }

final class SyncHealthSnapshot {
  const SyncHealthSnapshot({
    required this.level,
    required this.label,
    required this.detail,
  });

  factory SyncHealthSnapshot.evaluate({
    required SyncAuthState authState,
    required int pendingConflictCount,
    required List<SyncActivityEntry> activityLog,
    required DateTime? lastSyncedAt,
  }) {
    if (!authState.isSignedIn) {
      return const SyncHealthSnapshot(
        level: SyncHealthLevel.signedOut,
        label: 'Signed out',
        detail: 'Sign in to enable cloud sync.',
      );
    }

    if (pendingConflictCount > 0) {
      final conflicts = pendingConflictCount == 1
          ? '1 conflict'
          : '$pendingConflictCount conflicts';
      return SyncHealthSnapshot(
        level: SyncHealthLevel.needsAttention,
        label: 'Needs attention',
        detail: '$conflicts waiting for a decision.',
      );
    }

    final latestActivity = activityLog.isEmpty ? null : activityLog.first;
    if (latestActivity?.status == SyncActivityStatus.failed) {
      return SyncHealthSnapshot(
        level: SyncHealthLevel.degraded,
        label: 'Degraded',
        detail: latestActivity!.message.isEmpty
            ? 'Last sync action failed.'
            : latestActivity.message,
      );
    }

    final syncedAt = lastSyncedAt;
    if (syncedAt != null) {
      return SyncHealthSnapshot(
        level: SyncHealthLevel.healthy,
        label: 'Healthy',
        detail: 'Last sync: ${DateFormat('MMM d, y HH:mm').format(syncedAt)}',
      );
    }

    return const SyncHealthSnapshot(
      level: SyncHealthLevel.healthy,
      label: 'Healthy',
      detail: 'Ready to sync.',
    );
  }

  final SyncHealthLevel level;
  final String label;
  final String detail;
}

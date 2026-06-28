import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/sync/domain/sync_account.dart';
import 'package:var_app/features/sync/domain/sync_activity.dart';
import 'package:var_app/features/sync/domain/sync_health.dart';

void main() {
  test('evaluates signed out sync health', () {
    final health = SyncHealthSnapshot.evaluate(
      authState: const SyncAuthState.signedOut(),
      pendingConflictCount: 0,
      activityLog: const [],
      lastSyncedAt: null,
    );

    expect(health.level, SyncHealthLevel.signedOut);
    expect(health.label, 'Signed out');
    expect(health.detail, 'Sign in to enable cloud sync.');
  });

  test('evaluates conflicts before activity failures', () {
    final health = SyncHealthSnapshot.evaluate(
      authState: const SyncAuthState.signedIn(
        SyncUser(id: 'user-1', email: 'user@example.com', displayName: 'User'),
        accessToken: 'token',
      ),
      pendingConflictCount: 2,
      activityLog: [
        SyncActivityEntry(
          id: 'failed',
          action: SyncActivityAction.push,
          status: SyncActivityStatus.failed,
          message: 'Remote failed',
          occurredAt: DateTime(2026, 6, 19, 12),
        ),
      ],
      lastSyncedAt: DateTime(2026, 6, 19, 11),
    );

    expect(health.level, SyncHealthLevel.needsAttention);
    expect(health.label, 'Needs attention');
    expect(health.detail, '2 conflicts waiting for a decision.');
  });

  test('evaluates latest failed activity as degraded sync health', () {
    final health = SyncHealthSnapshot.evaluate(
      authState: const SyncAuthState.signedIn(
        SyncUser(id: 'user-1', email: 'user@example.com', displayName: 'User'),
        accessToken: 'token',
      ),
      pendingConflictCount: 0,
      activityLog: [
        SyncActivityEntry(
          id: 'failed',
          action: SyncActivityAction.pull,
          status: SyncActivityStatus.failed,
          message: 'Remote sync request was rejected.',
          occurredAt: DateTime(2026, 6, 19, 12),
        ),
      ],
      lastSyncedAt: null,
    );

    expect(health.level, SyncHealthLevel.degraded);
    expect(health.label, 'Degraded');
    expect(health.detail, 'Remote sync request was rejected.');
  });

  test('evaluates healthy signed in sync with last sync time', () {
    final health = SyncHealthSnapshot.evaluate(
      authState: const SyncAuthState.signedIn(
        SyncUser(id: 'user-1', email: 'user@example.com', displayName: 'User'),
        accessToken: 'token',
      ),
      pendingConflictCount: 0,
      activityLog: const [],
      lastSyncedAt: DateTime(2026, 6, 19, 12),
    );

    expect(health.level, SyncHealthLevel.healthy);
    expect(health.label, 'Healthy');
    expect(health.detail, 'Last sync: Jun 19, 2026 12:00');
  });
}

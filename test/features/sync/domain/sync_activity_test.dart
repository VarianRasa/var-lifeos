import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/sync/domain/sync_activity.dart';

void main() {
  test('roundtrips sync activity entries through json', () {
    final entry = SyncActivityEntry(
      id: 'activity-1',
      action: SyncActivityAction.syncNow,
      status: SyncActivityStatus.success,
      message: 'Sync complete',
      occurredAt: DateTime(2026, 6, 19, 12, 30),
      savedCount: 2,
      deletedCount: 1,
      conflictCount: 0,
      accountEmail: 'user@example.com',
    );

    final restored = SyncActivityEntry.fromJson(entry.toJson());

    expect(restored.id, 'activity-1');
    expect(restored.action, SyncActivityAction.syncNow);
    expect(restored.status, SyncActivityStatus.success);
    expect(restored.message, 'Sync complete');
    expect(restored.occurredAt, DateTime(2026, 6, 19, 12, 30));
    expect(restored.savedCount, 2);
    expect(restored.deletedCount, 1);
    expect(restored.conflictCount, 0);
    expect(restored.accountEmail, 'user@example.com');
    expect(restored.actionLabel, 'Sync now');
    expect(restored.statusLabel, 'Success');
  });
}

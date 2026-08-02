import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/settings/data/native_reminder_notification_adapter.dart';

void main() {
  test('stable notification IDs remain positive and deterministic', () {
    final first = stableReminderNotificationId('due-task-1-2026-07-11');
    final second = stableReminderNotificationId('due-task-1-2026-07-11');
    final other = stableReminderNotificationId('due-task-2-2026-07-11');

    expect(first, second);
    expect(first, isNonNegative);
    expect(other, isNot(first));
  });

  test('notification snapshot payload restores snooze metadata', () {
    final notification = reminderNotificationFromPayload(
      '{"id":"due-task-1-2026-07-11","title":"Due reminder",'
      '"body":"Ship it","day":"2026-07-11",'
      '"scheduledAt":"2026-07-11T09:00:00.000",'
      '"payload":{"kind":"dueNode","nodeId":"task-1",'
      '"snoozeMinutes":45}}',
    );

    expect(notification!.id, 'due-task-1-2026-07-11');
    expect(notification.payload['nodeId'], 'task-1');
    expect(notification.payload['snoozeMinutes'], 45);
    expect(reminderNotificationFromPayload('bad-json'), isNull);
  });
  test('past reminder dates move one minute ahead', () {
    final now = DateTime(2026, 7, 11, 10);

    expect(
      effectiveReminderDate(DateTime(2026, 7, 11, 9), now),
      DateTime(2026, 7, 11, 10, 1),
    );
    expect(
      effectiveReminderDate(DateTime(2026, 7, 11, 11), now),
      DateTime(2026, 7, 11, 11),
    );
  });
}

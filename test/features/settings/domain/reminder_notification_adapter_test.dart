import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_mini_app_data.dart';
import 'package:var_app/features/settings/domain/reminder_notification_adapter.dart';
import 'package:var_app/features/settings/domain/reminder_planner.dart';

void main() {
  test(
    'buildScheduledReminderNotifications maps due reminders to payloads',
    () {
      final today = DateTime(2026, 6, 29);
      final node = MindmapNode.create(
        id: 'task-1',
        type: NodeType.task,
        title: 'Pay invoice',
        day: today,
        now: today,
      ).copyWith(dueDate: today);
      final plan = buildReminderPlan(
        nodes: [node],
        routines: const [],
        options: ReminderPlannerOptions(
          today: today,
          lookaheadDays: 1,
          dueRemindersEnabled: true,
          routineRemindersEnabled: false,
        ),
      );

      final notifications = buildScheduledReminderNotifications(
        plan,
        policy: const ReminderSchedulePolicy(hour: 8, minute: 15),
      );

      expect(notifications.single.id, 'due-task-1-2026-06-29');
      expect(notifications.single.title, 'Due reminder');
      expect(notifications.single.scheduledAt, DateTime(2026, 6, 29, 8, 15));
      expect(notifications.single.payload['reminderTime'], '08:15');
      expect(notifications.single.payload['snoozeMinutes'], 30);
      expect(notifications.single.payload['nodeId'], 'task-1');
    },
  );

  test('habit notifications use per-node reminder time and payload', () {
    final now = DateTime(2026, 6, 29, 12);
    final base = MindmapNode.create(
      id: 'habit-1',
      type: NodeType.habit,
      title: 'Walk',
      day: now,
      now: now,
    );
    final habit = updateNodeMiniAppSection(base, 'habit', {
      'reminderEnabled': true,
      'reminderTime': '18:30',
    });
    final plan = buildReminderPlan(
      nodes: [habit],
      routines: const [],
      options: ReminderPlannerOptions(
        today: now,
        lookaheadDays: 0,
        dueRemindersEnabled: false,
        routineRemindersEnabled: false,
      ),
    );

    final notification = buildScheduledReminderNotifications(
      plan,
      policy: const ReminderSchedulePolicy(hour: 8, minute: 15),
    ).single;

    expect(notification.id, 'habit-habit-1-2026-06-29');
    expect(notification.title, 'Habit reminder');
    expect(notification.scheduledAt, DateTime(2026, 6, 29, 18, 30));
    expect(notification.payload['kind'], 'habit');
    expect(notification.payload['nodeId'], 'habit-1');
    expect(notification.payload['reminderTime'], '18:30');
  });

  test('scheduledReminderNotificationsFromJson decodes exported payloads', () {
    final decoded = scheduledReminderNotificationsFromJson([
      {
        'id': 'due-task-1-2026-06-29',
        'title': 'Due reminder',
        'body': 'Pay invoice',
        'day': '2026-06-29',
        'scheduledAt': '2026-06-29T08:15:00.000',
        'payload': {'kind': 'dueNode', 'nodeId': 'task-1'},
      },
    ]);

    expect(decoded.single.id, 'due-task-1-2026-06-29');
    expect(decoded.single.day, DateTime(2026, 6, 29));
    expect(decoded.single.scheduledAt, DateTime(2026, 6, 29, 8, 15));
    expect(decoded.single.payload['kind'], 'dueNode');
  });

  test('buildReminderSnoozePayload and dismiss payload encode actions', () {
    final notification = ScheduledReminderNotification(
      id: 'due-task-1-2026-06-29',
      title: 'Due reminder',
      body: 'Pay invoice',
      day: DateTime(2026, 6, 29),
      scheduledAt: DateTime(2026, 6, 29, 9),
      payload: const {'kind': 'dueNode', 'nodeId': 'task-1'},
    );

    final snooze = buildReminderSnoozePayload(
      notification,
      const Duration(minutes: 30),
    );
    final defaultSnooze = buildReminderSnoozePayload(notification, null);
    final dismiss = buildReminderDismissPayload(notification);

    expect(snooze['action'], 'snooze');
    expect(snooze['snoozedUntil'], '2026-06-29T09:30:00.000');
    expect(defaultSnooze['snoozedUntil'], '2026-06-29T09:30:00.000');
    expect(dismiss['action'], 'dismiss');
    expect(dismiss['notificationId'], notification.id);
  });

  test('InMemoryReminderNotificationAdapter syncs and cancels plan', () async {
    final adapter = InMemoryReminderNotificationAdapter();
    const plan = ReminderPlan(items: []);

    await adapter.sync(plan);
    expect(adapter.scheduled, isEmpty);

    await adapter.cancelAll();
    expect(adapter.scheduled, isEmpty);
  });
}

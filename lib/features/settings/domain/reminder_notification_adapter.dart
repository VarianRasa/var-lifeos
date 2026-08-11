/// Abstraction for scheduling reminder notifications.
library;

import '../../../core/utils/date_utils.dart';
import 'reminder_planner.dart';

final class ReminderSchedulePolicy {
  const ReminderSchedulePolicy({
    this.hour = 9,
    this.minute = 0,
    this.snoozeMinutes = 30,
  });

  final int hour;
  final int minute;
  final int snoozeMinutes;

  DateTime scheduledAt(DateTime day) {
    return DateTime(day.year, day.month, day.day, hour, minute);
  }
}

final class ScheduledReminderNotification {
  const ScheduledReminderNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.day,
    required this.scheduledAt,
    required this.payload,
  });

  final String id;
  final String title;
  final String body;
  final DateTime day;
  final DateTime scheduledAt;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'day': dayKey(day),
    'scheduledAt': scheduledAt.toIso8601String(),
    'payload': payload,
  };

  static ScheduledReminderNotification? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final id = value['id']?.toString() ?? '';
    final title = value['title']?.toString() ?? '';
    final body = value['body']?.toString() ?? '';
    final day = _dayFromString(value['day']?.toString());
    final scheduledAt = DateTime.tryParse(
      value['scheduledAt']?.toString() ?? '',
    );
    final payload = value['payload'] is Map<Object?, Object?>
        ? {
            for (final entry
                in (value['payload']! as Map<Object?, Object?>).entries)
              if (entry.key != null) entry.key.toString(): entry.value,
          }
        : <String, Object?>{};
    if (id.isEmpty || title.isEmpty || day == null) return null;
    return ScheduledReminderNotification(
      id: id,
      title: title,
      body: body,
      day: day,
      scheduledAt: scheduledAt ?? day,
      payload: payload,
    );
  }
}

List<ScheduledReminderNotification> scheduledReminderNotificationsFromJson(
  Object? value,
) {
  if (value is! List<Object?>) return const [];
  return value
      .map(ScheduledReminderNotification.fromJson)
      .nonNulls
      .toList(growable: false);
}

DateTime? _dayFromString(String? value) {
  if (value == null) return null;
  final parts = value.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day).dateOnly;
}

abstract interface class ReminderNotificationAdapter {
  Future<void> sync(
    ReminderPlan plan, {
    ReminderSchedulePolicy policy = const ReminderSchedulePolicy(),
  });

  Future<void> cancelAll();
}

final class InMemoryReminderNotificationAdapter
    implements ReminderNotificationAdapter {
  InMemoryReminderNotificationAdapter();

  final List<ScheduledReminderNotification> scheduled = [];

  @override
  Future<void> sync(
    ReminderPlan plan, {
    ReminderSchedulePolicy policy = const ReminderSchedulePolicy(),
  }) async {
    scheduled
      ..clear()
      ..addAll(buildScheduledReminderNotifications(plan, policy: policy));
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
  }
}

final class NoopReminderNotificationAdapter
    implements ReminderNotificationAdapter {
  const NoopReminderNotificationAdapter();

  @override
  Future<void> sync(
    ReminderPlan plan, {
    ReminderSchedulePolicy policy = const ReminderSchedulePolicy(),
  }) async {}

  @override
  Future<void> cancelAll() async {}
}

List<ScheduledReminderNotification> buildScheduledReminderNotifications(
  ReminderPlan plan, {
  ReminderSchedulePolicy policy = const ReminderSchedulePolicy(),
}) {
  return [
    for (final item in plan.items)
      ScheduledReminderNotification(
        id: _notificationIdFor(item),
        title: switch (item.kind) {
          ReminderPlanItemKind.routine => 'Routine ready',
          ReminderPlanItemKind.habit => 'Habit reminder',
          ReminderPlanItemKind.dueNode =>
            item.isOverdue ? 'Overdue task' : 'Due reminder',
        },
        body: item.title,
        day: item.day,
        scheduledAt: item.scheduledAt ?? policy.scheduledAt(item.day),
        payload: {
          ..._payloadFor(item),
          'reminderTime': item.scheduledAt == null
              ? _timeLabel(policy)
              : _dateTimeLabel(item.scheduledAt!),
          'snoozeMinutes': policy.snoozeMinutes,
        },
      ),
  ];
}

String _timeLabel(ReminderSchedulePolicy policy) =>
    _formatTime(policy.hour, policy.minute);

String _dateTimeLabel(DateTime value) => _formatTime(value.hour, value.minute);

String _formatTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

String _notificationIdFor(ReminderPlanItem item) {
  return switch (item.kind) {
    ReminderPlanItemKind.dueNode => 'due-${item.node!.id}-${dayKey(item.day)}',
    ReminderPlanItemKind.routine =>
      'routine-${item.routine!.id}-${dayKey(item.day)}',
    ReminderPlanItemKind.habit => 'habit-${item.node!.id}-${dayKey(item.day)}',
  };
}

Map<String, Object?> buildReminderSnoozePayload(
  ScheduledReminderNotification notification,
  Duration? duration,
) {
  final payloadMinutes = notification.payload['snoozeMinutes'];
  final fallbackMinutes = payloadMinutes is num ? payloadMinutes.round() : 30;
  final effectiveDuration = duration ?? Duration(minutes: fallbackMinutes);
  return {
    ...notification.payload,
    'action': 'snooze',
    'notificationId': notification.id,
    'snoozedUntil': notification.scheduledAt
        .add(effectiveDuration)
        .toIso8601String(),
  };
}

Map<String, Object?> buildReminderDismissPayload(
  ScheduledReminderNotification notification,
) {
  return {
    ...notification.payload,
    'action': 'dismiss',
    'notificationId': notification.id,
    'dismissedAt': DateTime.now().toIso8601String(),
  };
}

Map<String, Object?> _payloadFor(ReminderPlanItem item) {
  return switch (item.kind) {
    ReminderPlanItemKind.dueNode => {
      'kind': 'dueNode',
      'nodeId': item.node!.id,
      'day': dayKey(item.day),
      'overdue': item.isOverdue,
    },
    ReminderPlanItemKind.routine => {
      'kind': 'routine',
      'routineId': item.routine!.id,
      'day': dayKey(item.day),
    },
    ReminderPlanItemKind.habit => {
      'kind': 'habit',
      'nodeId': item.node!.id,
      'day': dayKey(item.day),
    },
  };
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/reminder_notification_adapter.dart';
import '../domain/reminder_planner.dart';

final class PersistedReminderNotificationAdapter
    implements ReminderNotificationAdapter {
  PersistedReminderNotificationAdapter({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const preferenceKey = 'scheduled_reminder_notifications';

  final SharedPreferencesAsync _preferences;

  Future<List<ScheduledReminderNotification>> load() async {
    final raw = await _preferences.getString(preferenceKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return scheduledReminderNotificationsFromJson(jsonDecode(raw));
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> sync(
    ReminderPlan plan, {
    ReminderSchedulePolicy policy = const ReminderSchedulePolicy(),
  }) async {
    final notifications = buildScheduledReminderNotifications(
      plan,
      policy: policy,
    );
    await _preferences.setString(
      preferenceKey,
      jsonEncode([
        for (final notification in notifications) notification.toJson(),
      ]),
    );
  }

  @override
  Future<void> cancelAll() => _preferences.remove(preferenceKey);
}

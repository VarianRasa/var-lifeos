import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_notification_adapter.dart';
import '../domain/reminder_planner.dart';

const reminderSnoozeActionId = 'var_reminder_snooze';
const reminderDismissActionId = 'var_reminder_dismiss';
const reminderDarwinCategoryId = 'var_reminder_actions';

final class NativeReminderNotificationAdapter
    implements ReminderNotificationAdapter {
  NativeReminderNotificationAdapter({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  String _timezoneIdentifier = 'local';
  final StreamController<String> _tapPayloadController =
      StreamController<String>.broadcast();

  Stream<String> get tapPayloads => _tapPayloadController.stream;

  bool get isSupported =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => true,
        TargetPlatform.fuchsia || TargetPlatform.linux => false,
      };

  Future<bool> initialize() async {
    if (!isSupported) return false;
    if (_initialized) return true;
    tz.initializeTimeZones();
    if (defaultTargetPlatform != TargetPlatform.windows) {
      final timeZone = await FlutterTimezone.getLocalTimezone();
      _timezoneIdentifier = timeZone.identifier;
      tz.setLocalLocation(tz.getLocation(timeZone.identifier));
    }
    _initialized =
        await _plugin.initialize(
          settings: InitializationSettings(
            android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
              notificationCategories: [_reminderDarwinCategory],
            ),
            macOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
              notificationCategories: [_reminderDarwinCategory],
            ),
            windows: const WindowsInitializationSettings(
              appName: 'Var',
              appUserModelId: 'Var.Productivity.App',
              guid: '459f42ad-37c8-4ca8-9f22-68945fe57092',
            ),
          ),
          onDidReceiveNotificationResponse: (response) {
            unawaited(_handleResponse(response));
          },
        ) ??
        false;
    return _initialized;
  }

  Future<String?> initialTapPayload() async {
    if (!await initialize()) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final response = details?.notificationResponse;
    if (response == null) return null;
    if (response.actionId == null || response.actionId!.isEmpty) {
      return response.payload;
    }
    await _handleResponse(response);
    return null;
  }

  String get timezoneIdentifier => _timezoneIdentifier;

  Future<Set<int>?> pendingNotificationIds() async {
    if (!await initialize()) return null;
    if (defaultTargetPlatform == TargetPlatform.windows) return null;
    final pending = await _plugin.pendingNotificationRequests();
    return {for (final request in pending) request.id};
  }

  Future<bool> requestPermission() async {
    if (!await initialize()) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false,
      TargetPlatform.iOS =>
        await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false,
      TargetPlatform.macOS =>
        await _plugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false,
      TargetPlatform.windows => true,
      TargetPlatform.fuchsia || TargetPlatform.linux => false,
    };
  }

  @override
  Future<void> sync(
    ReminderPlan plan, {
    ReminderSchedulePolicy policy = const ReminderSchedulePolicy(),
  }) async {
    if (!await requestPermission()) {
      throw StateError('Notification permission was not granted.');
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _plugin.cancelAll();
    } else {
      await _plugin.cancelAllPendingNotifications();
    }
    final now = DateTime.now();
    for (final notification in buildScheduledReminderNotifications(
      plan,
      policy: policy,
    )) {
      await _scheduleNotification(
        notification,
        effectiveReminderDate(notification.scheduledAt, now),
      );
    }
  }

  Future<void> _handleResponse(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    if (response.actionId == reminderDismissActionId) {
      await _plugin.cancel(id: response.id ?? 0);
      return;
    }
    if (response.actionId == reminderSnoozeActionId) {
      final notification = reminderNotificationFromPayload(payload);
      if (notification == null) return;
      final rawMinutes = notification.payload['snoozeMinutes'];
      final minutes = rawMinutes is num ? rawMinutes.round() : 30;
      await _scheduleNotification(
        notification,
        DateTime.now().add(Duration(minutes: minutes.clamp(5, 240))),
      );
      return;
    }
    _tapPayloadController.add(payload);
  }

  Future<void> _scheduleNotification(
    ScheduledReminderNotification notification,
    DateTime scheduledAt,
  ) {
    return _plugin.zonedSchedule(
      id: stableReminderNotificationId(notification.id),
      title: notification.title,
      body: notification.body,
      scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'var_reminders',
          'Var reminders',
          channelDescription: 'Task, routine, and due-date reminders',
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            AndroidNotificationAction(
              reminderSnoozeActionId,
              'Snooze',
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              reminderDismissActionId,
              'Dismiss',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: reminderDarwinCategoryId,
        ),
        macOS: DarwinNotificationDetails(
          categoryIdentifier: reminderDarwinCategoryId,
        ),
        windows: WindowsNotificationDetails(
          actions: [
            WindowsAction(content: 'Snooze', arguments: reminderSnoozeActionId),
            WindowsAction(
              content: 'Dismiss',
              arguments: reminderDismissActionId,
            ),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode(notification.toJson()),
    );
  }

  @override
  Future<void> cancelAll() async {
    if (await initialize()) {
      await _plugin.cancelAll();
    }
  }
}

final _reminderDarwinCategory = DarwinNotificationCategory(
  reminderDarwinCategoryId,
  actions: [
    DarwinNotificationAction.plain(
      reminderSnoozeActionId,
      'Snooze',
      options: {DarwinNotificationActionOption.foreground},
    ),
    DarwinNotificationAction.plain(
      reminderDismissActionId,
      'Dismiss',
      options: {DarwinNotificationActionOption.foreground},
    ),
  ],
);

DateTime effectiveReminderDate(DateTime scheduledAt, DateTime now) {
  if (scheduledAt.isAfter(now)) return scheduledAt;
  return now.add(const Duration(minutes: 1));
}

int stableReminderNotificationId(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

ScheduledReminderNotification? reminderNotificationFromPayload(String payload) {
  try {
    return ScheduledReminderNotification.fromJson(jsonDecode(payload));
  } on FormatException {
    return null;
  }
}

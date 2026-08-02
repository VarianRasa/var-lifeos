import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/recurring_routine.dart';
import '../data/native_reminder_notification_adapter.dart';
import '../data/persisted_reminder_notification_adapter.dart';
import '../domain/reminder_notification_adapter.dart';
import '../domain/reminder_planner.dart';
import 'reminder_notification_navigation.dart';

final reminderAutoSchedulerProvider = Provider<ReminderAutoScheduler>((ref) {
  final nativeAdapter = ref.watch(nativeReminderNotificationAdapterProvider);
  final scheduler = ReminderAutoScheduler(
    nativeSync: (plan, policy) => nativeAdapter.sync(plan, policy: policy),
    nativeState: () async => ReminderNativeScheduleState(
      pendingIds: await nativeAdapter.pendingNotificationIds(),
      timezoneIdentifier: nativeAdapter.timezoneIdentifier,
    ),
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

typedef ReminderNativeSync =
    Future<void> Function(ReminderPlan plan, ReminderSchedulePolicy policy);
typedef ReminderNativeStateLoader =
    Future<ReminderNativeScheduleState> Function();

final class ReminderNativeScheduleState {
  const ReminderNativeScheduleState({
    required this.pendingIds,
    required this.timezoneIdentifier,
  });

  final Set<int>? pendingIds;
  final String timezoneIdentifier;
}

final class ReminderAutoScheduler {
  ReminderAutoScheduler({
    SharedPreferencesAsync? preferences,
    ReminderNativeSync? nativeSync,
    ReminderNativeStateLoader? nativeState,
    Duration debounce = const Duration(milliseconds: 500),
  }) : _preferences = preferences ?? SharedPreferencesAsync(),
       _nativeSync = nativeSync ?? _unsupportedNativeSync,
       _nativeState = nativeState ?? _unsupportedNativeState,
       _debounce = debounce;

  static const enabledPreferenceKey = 'native_reminder_schedule_enabled';
  static const timezonePreferenceKey = 'native_reminder_schedule_timezone';

  final SharedPreferencesAsync _preferences;
  final ReminderNativeSync _nativeSync;
  final ReminderNativeStateLoader _nativeState;
  final Duration _debounce;
  Timer? _timer;
  bool _startupReconciled = false;

  Future<void> setEnabled(bool enabled) {
    return _preferences.setBool(enabledPreferenceKey, enabled);
  }

  void schedule(Iterable<MindmapNode> nodes) {
    _timer?.cancel();
    final snapshot = List<MindmapNode>.unmodifiable(nodes);
    _timer = Timer(_debounce, () => unawaited(_runScheduled(snapshot)));
  }

  Future<void> _runScheduled(Iterable<MindmapNode> nodes) async {
    try {
      await _syncIfEnabled(nodes);
    } on Object {
      // Background rescheduling retries on the next mindmap invalidation.
    }
  }

  Future<void> syncNowIfEnabled(Iterable<MindmapNode> nodes) {
    _timer?.cancel();
    return _syncIfEnabled(nodes);
  }

  Future<void> _syncIfEnabled(Iterable<MindmapNode> nodes) async {
    if (await _preferences.getBool(enabledPreferenceKey) != true) return;
    final lookahead = await _preferences.getInt('reminder_lookahead_days') ?? 7;
    final dueEnabled =
        await _preferences.getBool('due_reminders_enabled') ?? true;
    final routineEnabled =
        await _preferences.getBool('routine_reminders_enabled') ?? true;
    final hour = await _preferences.getInt('reminder_default_hour') ?? 9;
    final minute = await _preferences.getInt('reminder_default_minute') ?? 0;
    final snooze = await _preferences.getInt('reminder_snooze_minutes') ?? 30;
    final plan = buildReminderPlan(
      nodes: nodes,
      routines: defaultRecurringRoutines,
      options: ReminderPlannerOptions(
        today: DateTime.now(),
        lookaheadDays: lookahead.clamp(1, 30),
        dueRemindersEnabled: dueEnabled,
        routineRemindersEnabled: routineEnabled,
      ),
    );
    final policy = ReminderSchedulePolicy(
      hour: hour.clamp(0, 23),
      minute: minute.clamp(0, 59),
      snoozeMinutes: snooze.clamp(5, 240),
    );
    final notifications = buildScheduledReminderNotifications(
      plan,
      policy: policy,
    );
    if (!_startupReconciled) {
      _startupReconciled = true;
      final nativeState = await _nativeState();
      final savedTimezone = await _preferences.getString(timezonePreferenceKey);
      final persistedNotifications = await PersistedReminderNotificationAdapter(
        preferences: _preferences,
      ).load();
      if (!reminderScheduleNeedsReconciliation(
        notifications: notifications,
        persistedNotifications: persistedNotifications,
        nativeState: nativeState,
        savedTimezone: savedTimezone,
      )) {
        return;
      }
    }
    await PersistedReminderNotificationAdapter(
      preferences: _preferences,
    ).sync(plan, policy: policy);
    await _nativeSync(plan, policy);
    final nativeState = await _nativeState();
    await _preferences.setString(
      timezonePreferenceKey,
      nativeState.timezoneIdentifier,
    );
  }

  void dispose() {
    _timer?.cancel();
  }

  static Future<void> _unsupportedNativeSync(
    ReminderPlan plan,
    ReminderSchedulePolicy policy,
  ) {
    throw UnsupportedError('Native reminder sync was not configured.');
  }

  static Future<ReminderNativeScheduleState> _unsupportedNativeState() async {
    return const ReminderNativeScheduleState(
      pendingIds: null,
      timezoneIdentifier: 'unknown',
    );
  }
}

bool reminderScheduleNeedsReconciliation({
  required Iterable<ScheduledReminderNotification> notifications,
  required Iterable<ScheduledReminderNotification> persistedNotifications,
  required ReminderNativeScheduleState nativeState,
  required String? savedTimezone,
}) {
  if (!_sameNotificationSnapshots(notifications, persistedNotifications)) {
    return true;
  }
  if (nativeState.pendingIds == null) return true;
  if (savedTimezone != nativeState.timezoneIdentifier) return true;
  final expectedIds = {
    for (final notification in notifications)
      stableReminderNotificationId(notification.id),
  };
  return expectedIds.length != nativeState.pendingIds!.length ||
      !expectedIds.containsAll(nativeState.pendingIds!);
}

bool _sameNotificationSnapshots(
  Iterable<ScheduledReminderNotification> expected,
  Iterable<ScheduledReminderNotification> persisted,
) {
  final expectedJson = [
    for (final notification in expected) jsonEncode(notification.toJson()),
  ]..sort();
  final persistedJson = [
    for (final notification in persisted) jsonEncode(notification.toJson()),
  ]..sort();
  if (expectedJson.length != persistedJson.length) return false;
  for (var index = 0; index < expectedJson.length; index++) {
    if (expectedJson[index] != persistedJson[index]) return false;
  }
  return true;
}

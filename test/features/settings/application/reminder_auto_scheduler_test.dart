import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/settings/application/reminder_auto_scheduler.dart';
import 'package:var_app/features/settings/data/native_reminder_notification_adapter.dart';
import 'package:var_app/features/settings/data/persisted_reminder_notification_adapter.dart';
import 'package:var_app/features/settings/domain/reminder_notification_adapter.dart';
import 'package:var_app/features/settings/domain/reminder_planner.dart';

void main() {
  late SharedPreferencesAsync preferences;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
  });

  test('does not schedule before native reminders are enabled', () async {
    var calls = 0;
    final scheduler = ReminderAutoScheduler(
      preferences: preferences,
      nativeSync: (plan, policy) async => calls += 1,
    );

    await scheduler.syncNowIfEnabled(const []);

    expect(calls, 0);
  });

  test('skips startup rebuild when pending IDs and timezone match', () async {
    await preferences.setBool(ReminderAutoScheduler.enabledPreferenceKey, true);
    await preferences.setBool('routine_reminders_enabled', false);
    await preferences.setString(
      ReminderAutoScheduler.timezonePreferenceKey,
      'Asia/Jakarta',
    );
    final dueDate = DateTime.now().add(const Duration(days: 1));
    final node = MindmapNode.create(
      id: 'reconciled-task',
      type: NodeType.task,
      title: 'Already scheduled',
      day: DateTime.now(),
      dueDate: dueDate,
      now: DateTime.now(),
    );
    final plan = buildReminderPlan(
      nodes: [node],
      routines: const [],
      options: ReminderPlannerOptions(
        today: DateTime.now(),
        lookaheadDays: 7,
        dueRemindersEnabled: true,
        routineRemindersEnabled: false,
      ),
    );
    await PersistedReminderNotificationAdapter(
      preferences: preferences,
    ).sync(plan);
    final notificationId = stableReminderNotificationId(
      'due-reconciled-task-${dayKey(dueDate)}',
    );
    var syncCalls = 0;
    final scheduler = ReminderAutoScheduler(
      preferences: preferences,
      nativeSync: (plan, policy) async => syncCalls += 1,
      nativeState: () async => ReminderNativeScheduleState(
        pendingIds: {notificationId},
        timezoneIdentifier: 'Asia/Jakarta',
      ),
    );

    await scheduler.syncNowIfEnabled([node]);

    expect(syncCalls, 0);
  });

  test('rebuilds startup schedule when timezone changes', () async {
    await preferences.setBool(ReminderAutoScheduler.enabledPreferenceKey, true);
    await preferences.setBool('routine_reminders_enabled', false);
    await preferences.setString(
      ReminderAutoScheduler.timezonePreferenceKey,
      'UTC',
    );
    var syncCalls = 0;
    final scheduler = ReminderAutoScheduler(
      preferences: preferences,
      nativeSync: (plan, policy) async => syncCalls += 1,
      nativeState: () async => const ReminderNativeScheduleState(
        pendingIds: {},
        timezoneIdentifier: 'Asia/Jakarta',
      ),
    );

    await scheduler.syncNowIfEnabled(const []);

    expect(syncCalls, 1);
    expect(
      await preferences.getString(ReminderAutoScheduler.timezonePreferenceKey),
      'Asia/Jakarta',
    );
  });

  test('unknown pending state requires reconciliation', () {
    expect(
      reminderScheduleNeedsReconciliation(
        notifications: const [],
        persistedNotifications: const [],
        nativeState: const ReminderNativeScheduleState(
          pendingIds: null,
          timezoneIdentifier: 'local',
        ),
        savedTimezone: 'local',
      ),
      isTrue,
    );
  });

  test('reschedules changed due nodes with stored policy', () async {
    await preferences.setBool(ReminderAutoScheduler.enabledPreferenceKey, true);
    await preferences.setBool('routine_reminders_enabled', false);
    await preferences.setInt('reminder_default_hour', 8);
    await preferences.setInt('reminder_default_minute', 30);
    await preferences.setInt('reminder_snooze_minutes', 15);
    ReminderPlan? capturedPlan;
    ReminderSchedulePolicy? capturedPolicy;
    final scheduler = ReminderAutoScheduler(
      preferences: preferences,
      nativeSync: (plan, policy) async {
        capturedPlan = plan;
        capturedPolicy = policy;
      },
    );
    final dueDate = DateTime.now().add(const Duration(days: 1));
    final node = MindmapNode.create(
      id: 'auto-reminder-task',
      type: NodeType.task,
      title: 'Auto reschedule me',
      day: DateTime.now(),
      dueDate: dueDate,
      now: DateTime.now(),
    );

    await scheduler.syncNowIfEnabled([node]);

    expect(capturedPlan!.dueNodes.single.node!.id, node.id);
    expect(capturedPolicy!.hour, 8);
    expect(capturedPolicy!.minute, 30);
    expect(capturedPolicy!.snoozeMinutes, 15);
  });
}

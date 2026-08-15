import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/settings/data/persisted_reminder_notification_adapter.dart';
import 'package:var_app/features/settings/domain/reminder_notification_adapter.dart';
import 'package:var_app/features/settings/domain/reminder_planner.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('persists, restores, and cancels reminder schedule', () async {
    final today = DateTime(2026, 7, 11);
    final node = MindmapNode.create(
      id: 'settings-reminder-task',
      type: NodeType.task,
      title: 'Ship reminder backend',
      day: today,
      dueDate: today,
      now: today,
    );
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
    final preferences = SharedPreferencesAsync();
    final adapter = PersistedReminderNotificationAdapter(
      preferences: preferences,
    );

    await adapter.sync(
      plan,
      policy: const ReminderSchedulePolicy(
        hour: 8,
        minute: 45,
        snoozeMinutes: 15,
      ),
    );

    final restored = await PersistedReminderNotificationAdapter(
      preferences: preferences,
    ).load();
    expect(restored.single.id, 'due-settings-reminder-task-2026-07-11');
    expect(restored.single.scheduledAt, DateTime(2026, 7, 11, 8, 45));
    expect(restored.single.payload['snoozeMinutes'], 15);

    await adapter.cancelAll();
    expect(await adapter.load(), isEmpty);
  });
}

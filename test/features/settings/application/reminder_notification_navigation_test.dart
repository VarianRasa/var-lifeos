import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/settings/application/reminder_notification_navigation.dart';

void main() {
  test('due notification routes to day and highlighted node', () {
    final route = reminderRouteFromPayload(
      '{"kind":"dueNode","day":"2026-07-11","nodeId":"node 1"}',
    );

    expect(route, '/calendar/2026-07-11?highlight=node+1');
  });

  test('scheduled snapshot routes using nested node payload', () {
    final route = reminderRouteFromPayload(
      '{"id":"due-task-1-2026-07-11","title":"Due reminder",'
      '"body":"Ship it","day":"2026-07-11",'
      '"scheduledAt":"2026-07-11T09:00:00.000",'
      '"payload":{"kind":"dueNode","nodeId":"task-1"}}',
    );

    expect(route, '/calendar/2026-07-11?highlight=task-1');
  });
  test('routine notification routes to its day', () {
    final route = reminderRouteFromPayload(
      '{"kind":"routine","day":"2026-07-12","routineId":"morning"}',
    );

    expect(route, '/calendar/2026-07-12');
  });

  test('invalid payloads do not navigate', () {
    expect(reminderRouteFromPayload('not-json'), isNull);
    expect(reminderRouteFromPayload('{"nodeId":"missing-day"}'), isNull);
    expect(
      reminderRouteFromPayload('{"day":"2026-02-31","nodeId":"bad-day"}'),
      isNull,
    );
  });
}

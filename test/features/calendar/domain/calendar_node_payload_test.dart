import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/calendar/domain/calendar_node_payload.dart';

void main() {
  group('calendarNodePayloadFromData', () {
    test('null data returns null', () {
      expect(calendarNodePayloadFromData({}), isNull);
    });

    test('event kind returns event label', () {
      final payload = calendarNodePayloadFromData({
        'calendar_kind': 'event',
        'value': 'Team standup',
      });
      expect(payload, isNotNull);
      expect(payload!.kind, CalendarNodeKind.event);
      expect(payload.label, 'Event');
      expect(payload.subtitle, 'Event');
    });

    test('reminder kind', () {
      final payload = calendarNodePayloadFromData({
        'calendar_kind': 'reminder',
      });
      expect(payload, isNotNull);
      expect(payload!.kind, CalendarNodeKind.reminder);
      expect(payload.label, 'Reminder');
    });

    test('meeting kind', () {
      final payload = calendarNodePayloadFromData({
        'calendar_kind': 'meeting',
        'value': 'Design review',
        'unit': '30m',
      });
      expect(payload!.kind, CalendarNodeKind.meeting);
    });

    test('decision kind', () {
      final payload = calendarNodePayloadFromData({
        'calendar_kind': 'decision',
      });
      expect(payload!.kind, CalendarNodeKind.decision);
    });

    test('metric kind with value and unit', () {
      final payload = calendarNodePayloadFromData({
        'calendar_kind': 'metric',
        'metric': {'value': '7', 'unit': 'h'},
      });
      expect(payload!.kind, CalendarNodeKind.metric);
      expect(payload.subtitle, '7 h');
    });

    test('metric kind with value only', () {
      final payload = calendarNodePayloadFromData({
        'calendar_kind': 'metric',
        'metric': {'value': '75kg'},
      });
      expect(payload!.subtitle, '75kg');
    });

    test('unknown kind returns null', () {
      expect(
        calendarNodePayloadFromData({'calendar_kind': 'unknown_type'}),
        isNull,
      );
    });

    test('calendarKind camelCase alias works', () {
      final payload = calendarNodePayloadFromData({'calendarKind': 'event'});
      expect(payload, isNotNull);
      expect(payload!.kind, CalendarNodeKind.event);
    });
  });

  group('CalendarNodePayload toJson', () {
    test('event without value omits fields', () {
      const payload = CalendarNodePayload(kind: CalendarNodeKind.event);
      final json = payload.toJson();
      expect(json['calendar_kind'], 'event');
      expect(json.containsKey('value'), isFalse);
    });
  });
}

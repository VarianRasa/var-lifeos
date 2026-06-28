import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/domain/calendar_node_payload.dart';
import 'package:var_app/features/calendar/domain/time_block.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_data.dart';

void main() {
  test('calendarPayloadForNode reads flat calendar payload data', () {
    final node = MindmapNode.create(
      id: 'event-node',
      type: NodeType.task,
      title: 'Dentist',
      day: DateTime(2026, 6, 18),
      data: const {'calendar_kind': 'event', 'location': 'Clinic'},
      now: DateTime(2026, 6, 18),
    );

    final payload = calendarPayloadForNode(node);

    expect(payload?.kind, CalendarNodeKind.event);
    expect(payload?.location, 'Clinic');
  });

  test('timeBlock helpers add parse and remove schedule data', () {
    final scheduled = dataWithTimeBlock(const {
      'calendar_kind': 'event',
    }, const TimeBlock(startMinute: 9 * 60, endMinute: 10 * 60));
    final node = MindmapNode.create(
      id: 'scheduled-node',
      type: NodeType.task,
      title: 'Scheduled',
      day: DateTime(2026, 6, 18),
      data: scheduled,
      now: DateTime(2026, 6, 18),
    );

    expect(timeBlockForNode(node).block?.rangeLabel, '09:00 - 10:00');
    expect(dataWithoutTimeBlock(scheduled).containsKey('time_block'), isFalse);
  });

  test('dataWithCalendarSchedule merges payload and optional time block', () {
    final data = dataWithCalendarSchedule(
      data: const {'source': 'test'},
      payload: const CalendarNodePayload(
        kind: CalendarNodeKind.meeting,
        agenda: 'Launch',
      ),
      timeBlock: const TimeBlock(startMinute: 10 * 60, endMinute: 11 * 60),
    );

    expect(data['source'], 'test');
    expect(data['calendar_kind'], 'meeting');
    expect(data['agenda'], 'Launch');
    expect(data['time_block'], {'startTime': '10:00', 'endTime': '11:00'});
  });
}

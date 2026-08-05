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

  test('connectionMetadataFromData uses defaults and parses custom data', () {
    final defaultMeta = connectionMetadataFromData(const {});
    expect(defaultMeta.startNodeId, isNull);
    expect(defaultMeta.startPoint, isNull);
    expect(defaultMeta.endNodeId, isNull);
    expect(defaultMeta.endPoint, isNull);
    expect(defaultMeta.lineStyle, 'solid');
    expect(defaultMeta.arrowStyle, 'end');
    expect(defaultMeta.color, 'slate');
    expect(defaultMeta.label, isNull);

    final custom = connectionMetadataFromData(const {
      'connectionStartNodeId': 'node-1',
      'connectionStartDx': 10.0,
      'connectionStartDy': 20.0,
      'connectionEndNodeId': 'node-2',
      'connectionEndDx': 100.0,
      'connectionEndDy': 200.0,
      'connectionLineStyle': 'dashed',
      'connectionArrowStyle': 'both',
      'connectionColor': 'indigo',
      'connectionLabel': 'depends on',
    });

    expect(custom.startNodeId, 'node-1');
    expect(custom.startPoint, const Offset(10.0, 20.0));
    expect(custom.endNodeId, 'node-2');
    expect(custom.endPoint, const Offset(100.0, 200.0));
    expect(custom.lineStyle, 'dashed');
    expect(custom.arrowStyle, 'both');
    expect(custom.color, 'indigo');
    expect(custom.label, 'depends on');
  });

  test('dataWithConnectionMetadata updates data map', () {
    const meta = ConnectionMetadata(
      startNodeId: 'n1',
      startPoint: Offset(5, 15),
      endNodeId: 'n2',
      endPoint: Offset(50, 60),
      lineStyle: 'dotted',
      arrowStyle: 'none',
      color: 'emerald',
      label: 'relates to',
    );

    final data = dataWithConnectionMetadata(const {'existing': 'value'}, meta);

    expect(data['existing'], 'value');
    expect(data['connectionStartNodeId'], 'n1');
    expect(data['connectionStartDx'], 5.0);
    expect(data['connectionStartDy'], 15.0);
    expect(data['connectionEndNodeId'], 'n2');
    expect(data['connectionEndDx'], 50.0);
    expect(data['connectionEndDy'], 60.0);
    expect(data['connectionLineStyle'], 'dotted');
    expect(data['connectionArrowStyle'], 'none');
    expect(data['connectionColor'], 'emerald');
    expect(data['connectionLabel'], 'relates to');
  });

  test('groupMetadataFromData uses backward-compatible defaults', () {
    final metadata = groupMetadataFromData(const {'groupId': 'legacy-group'});

    expect(metadata.title, 'Group');
    expect(metadata.color, 'slate');
    expect(metadata.isCollapsed, isFalse);
    expect(metadata.layout, 'free');
  });

  test('dataWithGroupMetadata writes shared group fields', () {
    final data = dataWithGroupMetadata(
      const {'source': 'test'},
      const GroupMetadata(
        title: 'Sprint Backlog',
        color: '#6366F1',
        isCollapsed: true,
        layout: 'column',
      ),
    );

    expect(data['source'], 'test');
    expect(data['groupTitle'], 'Sprint Backlog');
    expect(data['groupColor'], '#6366F1');
    expect(data['groupCollapsed'], isTrue);
    expect(data['groupLayout'], 'column');
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
    expect(data['time_block'], containsPair('startTime', '10:00'));
    expect(data['time_block'], containsPair('endTime', '11:00'));
  });
}

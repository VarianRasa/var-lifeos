import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/ical_codec.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('ICalCodec exports and parses nodes correctly', () {
    final now = DateTime(2026, 7, 21, 10, 0);
    final nodes = [
      MindmapNode.create(
        id: 'node-1',
        title: 'Meeting with team',
        type: NodeType.task,
        day: now,
        body: 'Discuss Q3 goals',
      ),
    ];

    final icsString = ICalCodec.exportCalendar(nodes);
    expect(icsString, contains('BEGIN:VCALENDAR'));
    expect(icsString, contains('SUMMARY:Meeting with team'));
    expect(icsString, contains('DESCRIPTION:Discuss Q3 goals'));

    final importedNodes = ICalCodec.parseCalendar(icsString);
    expect(importedNodes.length, 1);
    expect(importedNodes.first.title, 'Meeting with team');
    expect(importedNodes.first.body, 'Discuss Q3 goals');
  });
}

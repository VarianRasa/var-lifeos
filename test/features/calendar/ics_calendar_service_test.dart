import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/calendar/domain/ics_calendar_service.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('IcsCalendarService exports and imports events correctly', () {
    final day = DateTime(2026, 8, 8).dateOnly;
    final node = MindmapNode.create(
      id: 'test_node_1',
      type: NodeType.event,
      title: 'Project Launch',
      body: 'Launch beta release',
      day: day,
    );

    final csString = IcsCalendarService.exportToIcs([node]);
    expect(csString, contains('SUMMARY:Project Launch'));
    expect(csString, contains('BEGIN:VCALENDAR'));

    final imported = IcsCalendarService.importFromIcs(csString);
    expect(imported.length, equals(1));
    expect(imported.first.title, equals('Project Launch'));
    expect(imported.first.body, equals('Launch beta release'));
    expect(imported.first.day, equals(day));
  });
}

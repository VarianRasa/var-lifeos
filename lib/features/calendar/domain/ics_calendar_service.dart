/// Pure Dart utility for iCalendar (.ics) export and import of events/plans.
library;

import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

final class IcsCalendarService {
  const IcsCalendarService._();

  static String exportToIcs(Iterable<MindmapNode> nodes) {
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//Var App//Life OS Calendar//EN');

    for (final node in nodes) {
      if (node.isArchived) continue;
      final dt = node.day;
      final dtStr =
          '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

      buffer
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:${node.id}@var.app')
        ..writeln('SUMMARY:${_escapeIcs(node.title)}')
        ..writeln('DESCRIPTION:${_escapeIcs(node.body)}')
        ..writeln('DTSTART;VALUE=DATE:$dtStr')
        ..writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  static List<({String title, String body, DateTime day})> importFromIcs(
    String csContent,
  ) {
    final events = <({String title, String body, DateTime day})>[];
    final lines = csContent.split(RegExp(r'\r?\n'));

    String title = '';
    String body = '';
    DateTime day = DateTime.now().dateOnly;
    bool inEvent = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed == 'BEGIN:VEVENT') {
        inEvent = true;
        title = '';
        body = '';
        day = DateTime.now().dateOnly;
      } else if (trimmed == 'END:VEVENT') {
        if (inEvent && title.isNotEmpty) {
          events.add((title: title, body: body, day: day));
        }
        inEvent = false;
      } else if (inEvent) {
        if (trimmed.startsWith('SUMMARY:')) {
          title = _unescapeIcs(trimmed.substring(8));
        } else if (trimmed.startsWith('DESCRIPTION:')) {
          body = _unescapeIcs(trimmed.substring(12));
        } else if (trimmed.startsWith('DTSTART')) {
          final parts = trimmed.split(':');
          if (parts.length > 1) {
            final dateStr = parts.last.trim();
            if (dateStr.length >= 8) {
              final y = int.tryParse(dateStr.substring(0, 4)) ?? 2026;
              final m = int.tryParse(dateStr.substring(4, 6)) ?? 1;
              final d = int.tryParse(dateStr.substring(6, 8)) ?? 1;
              day = DateTime(y, m, d).dateOnly;
            }
          }
        }
      }
    }
    return events;
  }

  static String _escapeIcs(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\n', '\\n');
  }

  static String _unescapeIcs(String text) {
    return text
        .replaceAll('\\n', '\n')
        .replaceAll('\\,', ',')
        .replaceAll('\\;', ';')
        .replaceAll('\\\\', '\\');
  }
}

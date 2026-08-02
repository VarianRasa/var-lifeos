library;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/canvas_position.dart';
import '../../mindmap/domain/mindmap_node.dart';

class ICalCodec {
  static String exportCalendar(Iterable<MindmapNode> nodes) {
    final buf = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//Var Productivity LifeOS//EN');

    for (final node in nodes) {
      if (node.isArchived) continue;
      final dt = _formatIcalDate(node.day);
      buf
        ..writeln('BEGIN:VEVENT')
        ..writeln('UID:${node.id}@var.app')
        ..writeln('DTSTAMP:$dt')
        ..writeln('DTSTART;VALUE=DATE:$dt')
        ..writeln(
          'SUMMARY:${_escape(node.title.isEmpty ? node.type.label : node.title)}',
        )
        ..writeln('DESCRIPTION:${_escape(node.body)}')
        ..writeln(
          'STATUS:${node.status == NodeStatus.done ? "COMPLETED" : "CONFIRMED"}',
        )
        ..writeln('END:VEVENT');
    }

    buf.writeln('END:VCALENDAR');
    return buf.toString();
  }

  static List<MindmapNode> parseCalendar(String icsContent) {
    final lines = icsContent.split(RegExp(r'\r?\n'));
    final result = <MindmapNode>[];

    String? currentSummary;
    String? currentDesc;
    DateTime? currentDay;
    String? currentUid;

    bool inEvent = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line == 'BEGIN:VEVENT') {
        inEvent = true;
        currentSummary = null;
        currentDesc = null;
        currentDay = null;
        currentUid = null;
      } else if (line == 'END:VEVENT') {
        if (inEvent && currentDay != null) {
          final now = DateTime.now();
          result.add(
            MindmapNode(
              id:
                  currentUid ??
                  'ical-${now.microsecondsSinceEpoch}-${result.length}',
              type: NodeType.task,
              title: currentSummary ?? 'Imported Event',
              body: currentDesc ?? '',
              day: currentDay,
              tags: const ['ical-import'],
              position: const CanvasPosition(0, 0),
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
        inEvent = false;
      } else if (inEvent) {
        if (line.startsWith('SUMMARY:')) {
          currentSummary = _unescape(line.substring(8));
        } else if (line.startsWith('DESCRIPTION:')) {
          currentDesc = _unescape(line.substring(12));
        } else if (line.startsWith('UID:')) {
          currentUid = line.substring(4).replaceAll('@var.app', '');
        } else if (line.contains('DTSTART')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            currentDay = _parseIcalDate(parts.last);
          }
        }
      }
    }

    return result;
  }

  static String _formatIcalDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  static DateTime _parseIcalDate(String str) {
    try {
      final clean = str.replaceAll(RegExp(r'[^0-9]'), '');
      if (clean.length >= 8) {
        final y = int.parse(clean.substring(0, 4));
        final m = int.parse(clean.substring(4, 6));
        final d = int.parse(clean.substring(6, 8));
        return DateTime(y, m, d);
      }
    } catch (_) {}
    return DateTime.now();
  }

  static String _escape(String s) {
    return s
        .replaceAll('\n', '\\n')
        .replaceAll(',', '\\,')
        .replaceAll(';', '\\;');
  }

  static String _unescape(String s) {
    return s
        .replaceAll('\\n', '\n')
        .replaceAll('\\,', ',')
        .replaceAll('\\;', ';');
  }
}

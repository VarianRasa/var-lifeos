/// Calendar day template selection helpers.
library;

import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import 'day_templates.dart';

bool isCalendarTemplateApplied({
  required List<MindmapNode> nodes,
  required String templateId,
  DateTime? day,
}) {
  final normalizedDay = day?.dateOnly;
  return nodes.any((node) {
    if (node.isArchived) {
      return false;
    }
    if (normalizedDay != null && !node.day.isSameDay(normalizedDay)) {
      return false;
    }
    return node.data['dayTemplateId'] == templateId &&
        node.tags.contains('template');
  });
}

Map<DateTime, bool> calendarTemplateDuplicateMap({
  required Iterable<DateTime> days,
  required Iterable<MindmapNode> nodes,
  required String templateId,
}) {
  final normalizedNodes = nodes.toList(growable: false);
  return {
    for (final day in days)
      day.dateOnly: isCalendarTemplateApplied(
        nodes: normalizedNodes,
        templateId: templateId,
        day: day,
      ),
  };
}

List<DayTemplate> suggestedCalendarTemplatesForDay(DateTime day) {
  final normalizedDay = day.dateOnly;
  final ids = <String>{};

  if (normalizedDay.weekday == DateTime.saturday ||
      normalizedDay.weekday == DateTime.sunday) {
    ids.add('weekend');
    ids.add('personal-reset');
  } else {
    ids.add('workday');
  }

  if (normalizedDay.weekday == DateTime.friday ||
      normalizedDay.weekday == DateTime.sunday) {
    ids.add('weekly-review');
  }

  return [
    for (final id in ids)
      if (dayTemplateById(id) != null) dayTemplateById(id)!,
  ];
}

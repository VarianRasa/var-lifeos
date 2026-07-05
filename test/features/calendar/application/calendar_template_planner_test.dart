import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/calendar_template_planner.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('suggestedCalendarTemplatesForDay prefers workday on weekdays', () {
    final templates = suggestedCalendarTemplatesForDay(DateTime(2026, 7, 2));

    expect(templates.map((template) => template.id), contains('workday'));
    expect(
      templates.map((template) => template.id),
      isNot(contains('weekend')),
    );
  });

  test('suggestedCalendarTemplatesForDay includes review on Friday', () {
    final templates = suggestedCalendarTemplatesForDay(DateTime(2026, 7, 3));

    expect(templates.map((template) => template.id), contains('workday'));
    expect(templates.map((template) => template.id), contains('weekly-review'));
  });

  test(
    'suggestedCalendarTemplatesForDay prefers reset templates on Sunday',
    () {
      final templates = suggestedCalendarTemplatesForDay(DateTime(2026, 7, 5));
      final ids = templates.map((template) => template.id).toList();

      expect(ids, contains('weekend'));
      expect(ids, contains('personal-reset'));
      expect(ids, contains('weekly-review'));
    },
  );

  test('calendarTemplateDuplicateMap detects duplicate per selected day', () {
    final thursday = DateTime(2026, 7, 2);
    final friday = DateTime(2026, 7, 3);
    final existing = MindmapNode.create(
      id: 'template-marker',
      type: NodeType.task,
      title: 'Pick top priority',
      day: friday,
      tags: const ['template'],
      data: const {'dayTemplateId': 'workday'},
    );

    final duplicates = calendarTemplateDuplicateMap(
      days: [thursday, friday],
      nodes: [existing],
      templateId: 'workday',
    );

    expect(duplicates[thursday], isFalse);
    expect(duplicates[friday], isTrue);
  });
}

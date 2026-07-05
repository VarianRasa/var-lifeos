import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/day_templates.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('dayTemplateById returns known template', () {
    final template = dayTemplateById('workday');

    expect(template, isNotNull);
    expect(template!.label, 'Workday');
    expect(template.drafts, isNotEmpty);
  });

  test('buildDayTemplateNodes creates deterministic template nodes', () {
    var id = 0;
    final day = DateTime(2026, 7, 2);
    final now = DateTime(2026, 7, 2, 8);
    final template = dayTemplateById('personal-reset')!;

    final nodes = buildDayTemplateNodes(
      template: template,
      day: day,
      now: now,
      idFactory: () => 'node-${id++}',
    );

    expect(nodes, hasLength(template.drafts.length));
    expect(nodes.first.id, 'node-0');
    expect(nodes.first.day, day);
    expect(nodes.first.tags, contains('template'));
    expect(nodes.first.data['dayTemplateId'], 'personal-reset');
  });

  test('buildDayTemplateNodes skips duplicate template marker', () {
    final day = DateTime(2026, 7, 2);
    final template = dayTemplateById('workday')!;
    final existing = MindmapNode.create(
      id: 'existing',
      type: NodeType.task,
      title: 'Existing template marker',
      day: day,
      tags: const ['template'],
      data: const {'dayTemplateId': 'workday'},
    );

    final nodes = buildDayTemplateNodes(
      template: template,
      day: day,
      now: day,
      idFactory: () => 'new',
      existingNodes: [existing],
    );

    expect(nodes, isEmpty);
  });
}

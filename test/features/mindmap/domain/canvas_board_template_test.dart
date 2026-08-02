import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_template.dart';

void main() {
  test('user template codec preserves source-linked metadata', () {
    final createdAt = DateTime.utc(2026, 8, 2, 10);
    final updatedAt = DateTime.utc(2026, 8, 2, 11);
    final template = CanvasBoardTemplate(
      id: 'template-1',
      name: '  Launch board  ',
      sourceBoardId: 'board-1',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    expect(template.name, 'Launch board');
    expect(CanvasBoardTemplate.fromJson(template.toJson()), template);
  });

  test('user template rejects empty identity, name, and source', () {
    final now = DateTime.utc(2026, 8, 2);

    expect(
      () => CanvasBoardTemplate(
        id: '',
        name: 'Template',
        sourceBoardId: 'board-1',
        createdAt: now,
        updatedAt: now,
      ),
      throwsFormatException,
    );
    expect(
      () => CanvasBoardTemplate(
        id: 'template-1',
        name: '   ',
        sourceBoardId: 'board-1',
        createdAt: now,
        updatedAt: now,
      ),
      throwsFormatException,
    );
    expect(
      () => CanvasBoardTemplate(
        id: 'template-1',
        name: 'Template',
        sourceBoardId: '   ',
        createdAt: now,
        updatedAt: now,
      ),
      throwsFormatException,
    );
  });

  test('defines exactly eight immutable built-in templates', () {
    expect(builtInCanvasBoardTemplates, hasLength(8));
    expect(
      builtInCanvasBoardTemplates.map((template) => template.name),
      <String>[
        'Project Plan',
        'Kanban',
        'Brainstorm',
        'Content Calendar',
        'Weekly Planner',
        'Research Board',
        'Moodboard',
        'Goal Tracker',
      ],
    );
    expect(
      builtInCanvasBoardTemplates.map((template) => template.template).toSet(),
      CanvasProjectTemplate.values.toSet(),
    );
    expect(
      () => builtInCanvasBoardTemplates.add(builtInCanvasBoardTemplates.first),
      throwsUnsupportedError,
    );
  });

  test('every built-in template contains immutable canvas objects', () {
    for (final definition in builtInCanvasBoardTemplates) {
      expect(definition.objects, isNotEmpty, reason: definition.name);
      expect(
        definition.objects.any(
          (object) => object.type == CanvasObjectType.boardReference,
        ),
        isFalse,
        reason: definition.name,
      );
      expect(
        () => definition.objects.add(definition.objects.first),
        throwsUnsupportedError,
      );
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/node_template.dart';

void main() {
  test('defaultNodeTemplates covers capture, planning, and Life OS needs', () {
    expect(
      defaultNodeTemplates.map((template) => template.id),
      containsAll([
        'daily-journal',
        'weekly-review',
        'workout-habit',
        'goal-tracker',
        'sprint-board',
        'research-note',
        'link-inbox',
      ]),
    );

    final dailyJournal = defaultNodeTemplates.firstWhere(
      (template) => template.id == 'daily-journal',
    );
    expect(dailyJournal.type, NodeType.journal);
    expect(dailyJournal.title, 'Daily journal');
    expect(
      dailyJournal.data['journal'],
      containsPair('prompt', 'What mattered today?'),
    );

    final sprintBoard = defaultNodeTemplates.firstWhere(
      (template) => template.id == 'sprint-board',
    );
    expect(sprintBoard.type, NodeType.kanban);
    expect(sprintBoard.data['kanban'], isA<Map<String, Object?>>());
  });
}

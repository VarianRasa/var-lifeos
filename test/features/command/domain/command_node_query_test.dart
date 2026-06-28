import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/command/domain/command_node_query.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('parses free text and metadata filters from command query', () {
    final today = DateTime(2026, 6, 18);

    final query = commandNodeQueryFromText(
      'checklist type:task status:doing !high project:Launch_App area:Work #release due:today',
      today: today,
    );

    expect(query.searchText, 'checklist');
    expect(query.type, NodeType.task);
    expect(query.status, NodeStatus.doing);
    expect(query.priority, NodePriority.high);
    expect(query.project, 'Launch App');
    expect(query.area, 'Work');
    expect(query.tags, ['release']);
    expect(query.dueDate, today);
  });

  test('ignores unknown modifiers as searchable text', () {
    final today = DateTime(2026, 6, 18);

    final query = commandNodeQueryFromText('release owner:maya', today: today);

    expect(query.searchText, 'release owner:maya');
    expect(query.hasFilters, isFalse);
  });

  test('parses relation filters from command query', () {
    final today = DateTime(2026, 6, 18);

    final query = commandNodeQueryFromText(
      'retro rel:launch-task|launch-goal link:daily-note',
      today: today,
    );

    expect(query.searchText, 'retro');
    expect(query.relatedNodeIds, ['launch-task', 'launch-goal', 'daily-note']);
    expect(query.hasFilters, isTrue);
  });
}

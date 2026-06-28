import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/command/domain/command_palette_entry.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('builds quick-create jump-date and node entries in display order', () {
    final today = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'existing-node',
      type: NodeType.note,
      title: 'Existing node',
      day: today,
      now: today,
    );

    final entries = commandPaletteEntriesFromQuery(
      query: 'today',
      today: today,
      defaultDay: today,
      filteredNodes: [node],
    );

    expect(entries.map((entry) => entry.kind), [
      CommandPaletteEntryKind.jumpDate,
      CommandPaletteEntryKind.node,
    ]);
    expect(entries.first.dateCommand?.date, today);
    expect(entries.last.node, node);
  });

  test('builds natural quick-create entries', () {
    final today = DateTime(2026, 6, 18);

    final entries = commandPaletteEntriesFromQuery(
      query: 'meeting launch tomorrow 10:00 #work',
      today: today,
      defaultDay: today,
      filteredNodes: const [],
    );

    expect(entries, hasLength(1));
    final command = entries.single.quickCreateCommand!;
    expect(entries.single.kind, CommandPaletteEntryKind.quickCreate);
    expect(command.title, 'launch');
    expect(command.data['calendar_kind'], 'meeting');
  });
}

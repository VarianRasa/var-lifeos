/// Domain entries rendered by the global command palette.
library;

import '../../mindmap/domain/mindmap_node.dart';
import 'command_date_parser.dart';
import 'quick_create_command_parser.dart';

enum CommandPaletteEntryKind { quickCreate, jumpDate, node }

final class CommandPaletteEntry {
  const CommandPaletteEntry._({
    required this.kind,
    this.quickCreateCommand,
    this.dateCommand,
    this.node,
  });

  const CommandPaletteEntry.quickCreate(QuickCreateCommand command)
    : this._(
        kind: CommandPaletteEntryKind.quickCreate,
        quickCreateCommand: command,
      );

  const CommandPaletteEntry.jumpDate(CommandDateResult command)
    : this._(kind: CommandPaletteEntryKind.jumpDate, dateCommand: command);

  const CommandPaletteEntry.node(MindmapNode node)
    : this._(kind: CommandPaletteEntryKind.node, node: node);

  final CommandPaletteEntryKind kind;
  final QuickCreateCommand? quickCreateCommand;
  final CommandDateResult? dateCommand;
  final MindmapNode? node;

  String get key {
    return switch (kind) {
      CommandPaletteEntryKind.quickCreate =>
        'quick-create-${quickCreateCommand!.label}',
      CommandPaletteEntryKind.jumpDate =>
        'jump-date-${dateCommand!.date.toIso8601String()}',
      CommandPaletteEntryKind.node => 'node-${node!.id}',
    };
  }
}

List<CommandPaletteEntry> commandPaletteEntriesFromQuery({
  required String query,
  required DateTime today,
  required DateTime defaultDay,
  required List<MindmapNode> filteredNodes,
}) {
  final entries = <CommandPaletteEntry>[];
  final quickCreateCommand = quickCreateCommandFromQuery(
    query,
    today: today,
    defaultDay: defaultDay,
  );
  if (quickCreateCommand != null) {
    entries.add(CommandPaletteEntry.quickCreate(quickCreateCommand));
  }

  final dateCommand = dateCommandFromQuery(query, today: today);
  if (dateCommand != null) {
    entries.add(CommandPaletteEntry.jumpDate(dateCommand));
  }

  entries.addAll([
    for (final node in filteredNodes) CommandPaletteEntry.node(node),
  ]);
  return List.unmodifiable(entries);
}

/// Domain entries rendered by the global command palette.
library;

import '../../mindmap/domain/mindmap_node.dart';
import 'command_date_parser.dart';
import 'quick_create_command_parser.dart';

enum CommandPaletteEntryKind { quickCreate, jumpDate, node, collab }

final class CommandPaletteEntry {
  const CommandPaletteEntry._({
    required this.kind,
    this.quickCreateCommand,
    this.dateCommand,
    this.node,
    this.collabLink,
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

  const CommandPaletteEntry.collab(String link)
    : this._(kind: CommandPaletteEntryKind.collab, collabLink: link);

  final CommandPaletteEntryKind kind;
  final QuickCreateCommand? quickCreateCommand;
  final CommandDateResult? dateCommand;
  final MindmapNode? node;
  final String? collabLink;

  String get key {
    return switch (kind) {
      CommandPaletteEntryKind.quickCreate =>
        'quick-create-${quickCreateCommand!.label}',
      CommandPaletteEntryKind.jumpDate =>
        'jump-date-${dateCommand!.date.toIso8601String()}',
      CommandPaletteEntryKind.node => 'node-${node!.id}',
      CommandPaletteEntryKind.collab => 'collab-${collabLink.hashCode}',
    };
  }
}

List<CommandPaletteEntry> commandPaletteEntriesFromQuery({
  required String query,
  required DateTime today,
  required DateTime defaultDay,
  required List<MindmapNode> filteredNodes,
  List<String> roomHistory = const [],
}) {
  final entries = <CommandPaletteEntry>[];
  final trimmed = query.trim();

  // Add room history suggestions if query matches collab terms
  if (trimmed.isEmpty ||
      'collab'.contains(trimmed.toLowerCase()) ||
      'join'.contains(trimmed.toLowerCase()) ||
      'room'.contains(trimmed.toLowerCase())) {
    for (final code in roomHistory) {
      entries.add(CommandPaletteEntry.collab('var-collab://var.app/room/$code'));
    }
  }

  if (trimmed.startsWith('var-collab://') ||
      trimmed.startsWith('/join ') ||
      trimmed.startsWith('join ')) {
    final rawLink = trimmed.startsWith('/join ')
        ? trimmed.substring(6).trim()
        : trimmed.startsWith('join ')
            ? trimmed.substring(5).trim()
            : trimmed;
    if (rawLink.isNotEmpty) {
      final link = rawLink.startsWith('var-collab://')
          ? rawLink
          : 'var-collab://var.app/room/$rawLink';
      entries.add(CommandPaletteEntry.collab(link));
    }
  }

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

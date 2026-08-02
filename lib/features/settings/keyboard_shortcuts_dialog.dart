/// Keyboard shortcut reference dialog — shows all available key bindings
/// grouped by context, triggered via `Ctrl+/` or `?`.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_design_tokens.dart';

class ShortcutGroup {
  const ShortcutGroup(this.label, this.items);
  final String label;
  final List<ShortcutItem> items;
}

class ShortcutItem {
  const ShortcutItem(this.keys, this.description);
  final List<String> keys;
  final String description;
}

const List<ShortcutGroup> _shortcutGroups = [
  ShortcutGroup('Global', [
    ShortcutItem(['Ctrl/⌘', 'K'], 'Open command palette'),
    ShortcutItem(['Ctrl/⌘', 'T'], 'Jump to today'),
    ShortcutItem(['Ctrl/⌘', '/'], 'Show this shortcut reference'),
    ShortcutItem(['?'], 'Show this shortcut reference'),
  ]),
  ShortcutGroup('Calendar / Agenda', [
    ShortcutItem(['←', '→'], 'Navigate months'),
    ShortcutItem(['Enter'], 'Open selected day'),
    ShortcutItem(['1'], 'Agenda filter: all'),
    ShortcutItem(['2'], 'Agenda filter: tasks'),
    ShortcutItem(['3'], 'Agenda filter: events'),
    ShortcutItem(['4'], 'Agenda filter: habits'),
    ShortcutItem(['5'], 'Agenda filter: routines'),
    ShortcutItem(['6'], 'Agenda filter: done'),
  ]),
  ShortcutGroup('Command grammar', [
    ShortcutItem(['complete A'], 'Complete first matching node'),
    ShortcutItem(['link A to B'], 'Create relation'),
    ShortcutItem(['unlink A from B'], 'Remove relation'),
    ShortcutItem(['tag A with x'], 'Add tag'),
    ShortcutItem(['remove tag A with x'], 'Remove tag'),
    ShortcutItem(['pin A / unpin A'], 'Pin or unpin node'),
    ShortcutItem(['archive A / unarchive A'], 'Archive or restore node'),
    ShortcutItem(['status A doing'], 'Set status'),
    ShortcutItem(['clear status A'], 'Reset status to open'),
    ShortcutItem(['priority A high'], 'Set priority'),
    ShortcutItem(['clear priority A'], 'Reset priority'),
    ShortcutItem(['type A note'], 'Convert node type'),
    ShortcutItem(['due A tomorrow'], 'Set due date'),
    ShortcutItem(['undue A'], 'Clear due date'),
    ShortcutItem(['remove project A'], 'Clear project/area/tags aliases'),
    ShortcutItem(['rename A to B'], 'Rename node'),
    ShortcutItem(['append A with text'], 'Append body text'),
    ShortcutItem(['replace body A with text'], 'Replace body text'),
  ]),
  ShortcutGroup('Day Mindmap', [
    ShortcutItem(['Ctrl/⌘', 'N'], 'Create new task node'),
    ShortcutItem(['Ctrl/⌘', 'Z'], 'Undo last action'),
    ShortcutItem(['Ctrl/⌘', 'Shift', 'Z'], 'Redo last undo'),
    ShortcutItem(['Esc'], 'Deselect node / clear focus'),
    ShortcutItem(['Drag'], 'Move nodes on canvas'),
    ShortcutItem(['Shift', 'Drag'], 'Lasso multi-select'),
    ShortcutItem(['Ctrl/⌘', 'Click'], 'Toggle multi-select'),
    ShortcutItem([
      'Batch toolbar',
    ], 'Status, priority, tag, project, area, due, archive'),
    ShortcutItem([
      'More batch edits',
    ], 'Align/distribute selected nodes on canvas'),
    ShortcutItem(['Connect'], 'Create labeled relations'),
  ]),
  ShortcutGroup('Node Editor', [
    ShortcutItem(['Ctrl/⌘', 'S'], 'Save current node'),
    ShortcutItem(['Delete'], 'Delete selected node'),
    ShortcutItem(['Smart actions'], 'Complete, reschedule, pin, link, extract'),
  ]),
  ShortcutGroup('Automation', [
    ShortcutItem(['Smart plan'], 'Apply routines and carry over work'),
    ShortcutItem(['Insights'], 'Open Automation Center and presets'),
  ]),
  ShortcutGroup('Graph', [
    ShortcutItem(['Ctrl/⌘', 'F'], 'Search nodes in graph'),
    ShortcutItem(['Save graph filter'], 'Persist current graph filters'),
    ShortcutItem(['Edit edge'], 'Rename relation label from graph links'),
  ]),
  ShortcutGroup('Settings', [
    ShortcutItem([
      'Templates',
    ], 'Edit fields, reorder, duplicate, import/export'),
    ShortcutItem(['Saved views'], 'CRUD, duplicate, import/export'),
    ShortcutItem(['Graph filters'], 'Rename, duplicate, delete, import/export'),
    ShortcutItem([
      'Reminders',
    ], 'Time, snooze, preview, sync, copy/import payloads'),
  ]),
];

Future<void> showKeyboardShortcutsDialog(BuildContext context) async {
  return showDialog(
    context: context,
    builder: (context) => const _KeyboardShortcutsDialog(),
  );
}

class _KeyboardShortcutsDialog extends StatefulWidget {
  const _KeyboardShortcutsDialog();

  @override
  State<_KeyboardShortcutsDialog> createState() =>
      _KeyboardShortcutsDialogState();
}

class _KeyboardShortcutsDialogState extends State<_KeyboardShortcutsDialog> {
  final Set<String> _expandedGroups = {'Global'};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.keyboard_outlined,
            size: 24,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text('Keyboard Shortcuts', style: theme.textTheme.titleMedium),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final group in _shortcutGroups) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (_expandedGroups.contains(group.label)) {
                              _expandedGroups.remove(group.label);
                            } else {
                              _expandedGroups.add(group.label);
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                group.label,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Icon(
                                _expandedGroups.contains(group.label)
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_expandedGroups.contains(group.label)) ...[
                        const SizedBox(height: 4),
                        for (final item in group.items) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.description,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (
                                      var i = 0;
                                      i < item.keys.length;
                                      i++
                                    ) ...[
                                      if (i > 0) ...[
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          child: Text(
                                            '+',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                      ],
                                      DecoratedBox(
                                        decoration: ShapeDecoration(
                                          color: theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppDesignTokens.of(
                                                context,
                                              ).radiusInner,
                                            ),
                                            side: BorderSide(
                                              color: theme
                                                  .colorScheme
                                                  .outlineVariant,
                                            ),
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            item.keys[i],
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  fontFamily: 'monospace',
                                                  fontWeight: FontWeight.bold,
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (item != group.items.last)
                            Divider(
                              height: 1,
                              color: theme.dividerColor.withValues(alpha: 0.4),
                            ),
                        ],
                      ],
                    ],
                  ),
                ),
                if (group != _shortcutGroups.last) const SizedBox(height: 4),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}

/// Keyboard shortcut reference dialog — shows all available key bindings
/// grouped by context, triggered via `Ctrl+/` or `?`.
library;

import 'package:flutter/material.dart';

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
    ShortcutItem(['Ctrl', 'K'], 'Open command palette'),
    ShortcutItem(['Ctrl', '/'], 'Show this shortcut reference'),
    ShortcutItem(['?'], 'Show this shortcut reference'),
  ]),
  ShortcutGroup('Calendar', [
    ShortcutItem(['←', '→'], 'Navigate months'),
    ShortcutItem(['Ctrl', 'T'], 'Jump to today'),
    ShortcutItem(['Enter'], 'Open selected day'),
  ]),
  ShortcutGroup('Mindmap', [
    ShortcutItem(['Ctrl', 'N'], 'Create new task node'),
    ShortcutItem(['Ctrl', 'Z'], 'Undo last action'),
    ShortcutItem(['Ctrl', 'Shift', 'Z'], 'Redo last undo'),
    ShortcutItem(['Esc'], 'Deselect node / close panels'),
    ShortcutItem(['Ctrl', 'Click'], 'Multi-select nodes'),
    ShortcutItem(['Shift', 'Click'], 'Range-select nodes'),
  ]),
  ShortcutGroup('Node Editor', [
    ShortcutItem(['Ctrl', 'S'], 'Save current node'),
    ShortcutItem(['Delete'], 'Delete selected node'),
  ]),
  ShortcutGroup('Graph', [
    ShortcutItem(['Ctrl', 'F'], 'Search nodes in graph'),
  ]),
];

Future<void> showKeyboardShortcutsDialog(BuildContext context) async {
  return showDialog(
    context: context,
    builder: (context) => const _KeyboardShortcutsDialog(),
  );
}

class _KeyboardShortcutsDialog extends StatelessWidget {
  const _KeyboardShortcutsDialog();

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
                      Text(
                        group.label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color:
                                              theme.colorScheme.outlineVariant,
                                        ),
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

import 'package:flutter/material.dart';
import 'package:var_app/core/constants/app_constants.dart';

/// Quick drag-and-drop tool palette inspired by Milanote.
/// Allows fast insertion and drag creation of Note, Board/Column, Link, Task, and Image cards.
class MilanoteElementPalette extends StatelessWidget {
  const MilanoteElementPalette({required this.onSelectType, super.key});

  final ValueChanged<NodeType> onSelectType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final tools = <(NodeType, IconData, String)>[
      (NodeType.note, Icons.sticky_note_2_outlined, 'Card'),
      (NodeType.canvas, Icons.brush_outlined, 'Sketch'),
      (NodeType.image, Icons.auto_awesome_mosaic_outlined, 'Gendo AI'),
      (NodeType.image, Icons.image_outlined, 'Media'),
      (NodeType.task, Icons.check_circle_outline, 'Task'),
      (NodeType.link, Icons.link_outlined, 'Link'),
      (NodeType.kanban, Icons.view_column_outlined, 'Board'),
    ];

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tool in tools)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Tooltip(
                  message: 'Drag or click to add ${tool.$3}',
                  child: Draggable<NodeType>(
                    data: tool.$1,
                    feedback: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tool.$2,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              tool.$3,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.4,
                      child: _PaletteItemButton(
                        tool: tool,
                        onTap: () => onSelectType(tool.$1),
                      ),
                    ),
                    child: _PaletteItemButton(
                      tool: tool,
                      onTap: () => onSelectType(tool.$1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaletteItemButton extends StatelessWidget {
  const _PaletteItemButton({required this.tool, required this.onTap});

  final (NodeType, IconData, String) tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tool.$2, size: 20, color: theme.colorScheme.primary),
            const SizedBox(height: 2),
            Text(
              tool.$3,
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../domain/connection_style.dart';

class ConnectionStyleBar extends StatelessWidget {
  final ConnectionStyle style;
  final ValueChanged<ConnectionStyle> onStyleChanged;
  final VoidCallback onDelete;

  const ConnectionStyleBar({
    super.key,
    required this.style,
    required this.onStyleChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
        ],
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Line type menu
          PopupMenuButton<ConnectionLineType>(
            icon: Icon(switch (style.lineType) {
              ConnectionLineType.bezier => Icons.gesture,
              ConnectionLineType.straight => Icons.show_chart,
              ConnectionLineType.orthogonal => Icons.alt_route,
            }, size: 18),
            tooltip: 'Line Style',
            onSelected: (type) =>
                onStyleChanged(style.copyWith(lineType: type)),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: ConnectionLineType.bezier,
                child: Text('Curved (Bézier)'),
              ),
              const PopupMenuItem(
                value: ConnectionLineType.straight,
                child: Text('Straight'),
              ),
              const PopupMenuItem(
                value: ConnectionLineType.orthogonal,
                child: Text('Orthogonal (90°)'),
              ),
            ],
          ),
          const SizedBox(width: 4),

          // Pattern menu
          PopupMenuButton<ConnectionLinePattern>(
            icon: Icon(
              style.linePattern == ConnectionLinePattern.solid
                  ? Icons.line_weight
                  : Icons.more_horiz,
              size: 18,
            ),
            tooltip: 'Stroke Pattern',
            onSelected: (pattern) =>
                onStyleChanged(style.copyWith(linePattern: pattern)),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: ConnectionLinePattern.solid,
                child: Text('Solid'),
              ),
              const PopupMenuItem(
                value: ConnectionLinePattern.dashed,
                child: Text('Dashed'),
              ),
              const PopupMenuItem(
                value: ConnectionLinePattern.dotted,
                child: Text('Dotted'),
              ),
            ],
          ),
          const SizedBox(width: 4),

          // Arrowhead toggle
          IconButton(
            icon: Icon(switch (style.arrowhead) {
              ConnectionArrowhead.target => Icons.east,
              ConnectionArrowhead.both => Icons.sync_alt,
              ConnectionArrowhead.none => Icons.horizontal_rule,
            }, size: 18),
            tooltip: 'Arrowhead',
            onPressed: () {
              final next = switch (style.arrowhead) {
                ConnectionArrowhead.target => ConnectionArrowhead.both,
                ConnectionArrowhead.both => ConnectionArrowhead.none,
                ConnectionArrowhead.none => ConnectionArrowhead.target,
              };
              onStyleChanged(style.copyWith(arrowhead: next));
            },
          ),
          const SizedBox(width: 4),

          // Delete
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Delete Connection',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class CanvasToolPopover extends StatelessWidget {
  const CanvasToolPopover({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('canvas-tool-popover'),
    elevation: 10,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Semantics(
                  label: 'Close tool settings',
                  button: true,
                  child: IconButton(
                    key: const ValueKey('canvas-tool-popover-close'),
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    ),
  );
}

class CanvasColorChoices extends StatelessWidget {
  const CanvasColorChoices({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  static const colors = <String, Color>{
    '#4F7CFF': Color(0xFF4F7CFF),
    '#FFC247': Color(0xFFFFC247),
    '#4CAF50': Color(0xFF4CAF50),
    '#F05B78': Color(0xFFF05B78),
    '#FFFFFF': Color(0xFFFFFFFF),
    '#202124': Color(0xFF202124),
  };

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final entry in colors.entries)
        Semantics(
          button: true,
          selected: selected == entry.key,
          label: 'Color ${entry.key}',
          child: InkWell(
            key: ValueKey('canvas-color-${entry.key}'),
            borderRadius: BorderRadius.circular(999),
            onTap: () => onSelected(entry.key),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: entry.value,
                border: Border.all(
                  color: selected == entry.key
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: selected == entry.key ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

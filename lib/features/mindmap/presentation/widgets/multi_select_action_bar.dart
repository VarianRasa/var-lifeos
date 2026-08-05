import 'package:flutter/material.dart';

class MultiSelectActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback? onGroupIntoFrame;
  final VoidCallback? onChangeColor;
  final VoidCallback? onDeleteSelected;
  final VoidCallback? onClearSelection;

  const MultiSelectActionBar({
    super.key,
    required this.selectedCount,
    this.onGroupIntoFrame,
    this.onChangeColor,
    this.onDeleteSelected,
    this.onClearSelection,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedCount < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(30),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '$selectedCount selected',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.crop_free, size: 20),
              tooltip: 'Group into Frame',
              onPressed: onGroupIntoFrame,
            ),
            IconButton(
              icon: const Icon(Icons.palette_outlined, size: 20),
              tooltip: 'Change Color',
              onPressed: onChangeColor,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Delete Selected',
              onPressed: onDeleteSelected,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Clear Selection',
              onPressed: onClearSelection,
            ),
          ],
        ),
      ),
    );
  }
}

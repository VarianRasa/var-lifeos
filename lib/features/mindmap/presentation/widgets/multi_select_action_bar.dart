import 'package:flutter/material.dart';

import '../../../../core/theme/app_design_tokens.dart';

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
    final tokens = AppDesignTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 480;
        return DecoratedBox(
          key: const ValueKey('multi-select-action-bar'),
          decoration: ShapeDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            shadows: tokens.shadowMedium,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusContainer),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Flexible(
                  child: Semantics(
                    liveRegion: true,
                    label: '$selectedCount items selected',
                    excludeSemantics: true,
                    child: Text(
                      '$selectedCount selected',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (compact)
                  MenuAnchor(
                    menuChildren: [
                      MenuItemButton(
                        onPressed: onGroupIntoFrame,
                        leadingIcon: const Icon(Icons.crop_free),
                        child: const Text('Group into frame'),
                      ),
                      MenuItemButton(
                        onPressed: onChangeColor,
                        leadingIcon: const Icon(Icons.palette_outlined),
                        child: const Text('Change color'),
                      ),
                      MenuItemButton(
                        onPressed: onDeleteSelected,
                        leadingIcon: const Icon(Icons.delete_outline),
                        child: const Text('Delete selected'),
                      ),
                      MenuItemButton(
                        onPressed: onClearSelection,
                        leadingIcon: const Icon(Icons.close),
                        child: const Text('Clear selection'),
                      ),
                    ],
                    builder: (context, controller, child) => IconButton(
                      constraints: BoxConstraints(
                        minWidth: tokens.minimumTarget,
                        minHeight: tokens.minimumTarget,
                      ),
                      tooltip: 'Selection actions',
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                      icon: const Icon(Icons.more_vert),
                    ),
                  )
                else ...[
                  IconButton(
                    tooltip: 'Group into frame',
                    onPressed: onGroupIntoFrame,
                    icon: const Icon(Icons.crop_free, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Change color',
                    onPressed: onChangeColor,
                    icon: const Icon(Icons.palette_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Delete selected',
                    onPressed: onDeleteSelected,
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Clear selection',
                    onPressed: onClearSelection,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

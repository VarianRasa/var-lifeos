import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_design_tokens.dart';

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
  Widget build(BuildContext context) {
    final tokens = AppDesignTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        key: const ValueKey('canvas-tool-popover'),
        constraints: BoxConstraints(
          minWidth: math.min(240, constraints.maxWidth),
          maxWidth: math.min(320, constraints.maxWidth),
        ),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colorScheme.surfaceContainerHigh,
            shadows: tokens.shadowMedium,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusContainer),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
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
                      child: SizedBox.square(
                        key: const ValueKey('canvas-tool-popover-close'),
                        dimension: tokens.minimumTarget,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
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
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final tokens = AppDesignTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in colors.entries)
          Semantics(
            button: true,
            selected: selected == entry.key,
            label: selected == entry.key
                ? 'Color ${entry.key}, selected'
                : 'Color ${entry.key}',
            child: SizedBox.square(
              key: ValueKey('canvas-color-${entry.key}'),
              dimension: tokens.minimumTarget,
              child: InkResponse(
                customBorder: const CircleBorder(),
                onTap: () => onSelected(entry.key),
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: entry.value,
                      border: Border.all(
                        color: selected == entry.key
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                        width: selected == entry.key ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

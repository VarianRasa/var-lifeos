import 'package:flutter/material.dart';

class FrameContainerWidget extends StatelessWidget {
  final String title;
  final double width;
  final double height;
  final Color? color;
  final VoidCallback? onResize;

  const FrameContainerWidget({
    super.key,
    required this.title,
    this.width = 400,
    this.height = 300,
    this.color,
    this.onResize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = color ?? theme.colorScheme.outline.withValues(alpha: 0.4);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: (color ?? theme.colorScheme.surfaceContainerLowest).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: 2,
          style: BorderStyle.solid,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 8,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                title.isEmpty ? 'Frame Container' : title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          if (onResize != null)
            Positioned(
              bottom: 4,
              right: 4,
              child: GestureDetector(
                onTap: onResize,
                child: Icon(
                  Icons.open_in_full,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

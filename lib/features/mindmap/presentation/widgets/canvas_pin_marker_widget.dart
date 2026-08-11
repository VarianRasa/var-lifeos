import 'package:flutter/material.dart';
import 'package:var_app/features/mindmap/domain/canvas_pin_comment.dart';

class CanvasPinMarkerWidget extends StatelessWidget {
  final CanvasPinComment pin;
  final VoidCallback? onTap;

  const CanvasPinMarkerWidget({super.key, required this.pin, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pinColor = pin.isResolved
        ? theme.colorScheme.outline
        : theme.colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: pinColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              pin.isResolved ? Icons.check : Icons.comment,
              size: 16,
              color: theme.colorScheme.onPrimary,
            ),
            if (pin.replies.isNotEmpty)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${pin.replies.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
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

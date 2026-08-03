import 'package:flutter/material.dart';

typedef OnFilesDroppedCallback =
    void Function(List<String> filePaths, Offset screenOffset);

class CanvasDropzoneOverlay extends StatefulWidget {
  final Widget child;
  final OnFilesDroppedCallback onFilesDropped;

  const CanvasDropzoneOverlay({
    super.key,
    required this.child,
    required this.onFilesDropped,
  });

  @override
  State<CanvasDropzoneOverlay> createState() => _CanvasDropzoneOverlayState();
}

class _CanvasDropzoneOverlayState extends State<CanvasDropzoneOverlay> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        widget.child,
        DragTarget<List<String>>(
          onWillAcceptWithDetails: (details) {
            setState(() => _isDragging = true);
            return true;
          },
          onLeave: (_) {
            setState(() => _isDragging = false);
          },
          onAcceptWithDetails: (details) {
            setState(() => _isDragging = false);
            widget.onFilesDropped(details.data, details.offset);
          },
          builder: (context, candidateData, rejectedData) {
            if (!_isDragging) return const SizedBox.shrink();

            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Drop files to add to Canvas',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

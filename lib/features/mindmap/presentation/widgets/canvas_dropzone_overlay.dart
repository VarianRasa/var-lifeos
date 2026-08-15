import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

typedef OnFilesDroppedCallback =
    void Function(List<XFile> files, Offset screenOffset);

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

    return DropTarget(
      onDragEntered: (details) {
        setState(() => _isDragging = true);
      },
      onDragExited: (details) {
        setState(() => _isDragging = false);
      },
      onDragDone: (details) {
        setState(() => _isDragging = false);
        if (details.files.isNotEmpty) {
          final xFiles = details.files.map((file) {
            final raw = file.name.isNotEmpty ? file.name : file.path;
            final fileName = raw.split(RegExp(r'[/\\]')).last;
            return XFile(file.path, name: fileName);
          }).toList();
          widget.onFilesDropped(xFiles, details.localPosition);
        }
      },
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (_isDragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2.5,
                    ),
                  ),
                  child: Center(
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: theme.colorScheme.surfaceContainerHigh,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_upload_outlined,
                              size: 48,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Drop files to add to Canvas',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class CanvasPresentationFrame {
  final String id;
  final String title;
  final String contentSummary;

  const CanvasPresentationFrame({
    required this.id,
    required this.title,
    this.contentSummary = '',
  });
}

class CanvasPresentationModeDialog extends StatefulWidget {
  final List<CanvasPresentationFrame> frames;

  const CanvasPresentationModeDialog({super.key, required this.frames});

  @override
  State<CanvasPresentationModeDialog> createState() =>
      _CanvasPresentationModeDialogState();
}

class _CanvasPresentationModeDialogState
    extends State<CanvasPresentationModeDialog> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frames = widget.frames;
    final currentFrame = frames.isNotEmpty ? frames[_currentIndex] : null;

    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Presentation Mode (${_currentIndex + 1}/${frames.length})',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        body: Center(
          child: currentFrame == null
              ? const Text(
                  'No frames found on canvas to present.',
                  style: TextStyle(color: Colors.white70),
                )
              : Container(
                  width: 640,
                  height: 400,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentFrame.title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Text(
                          currentFrame.contentSummary.isEmpty
                              ? 'Slide Content Details...'
                              : currentFrame.contentSummary,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          color: Colors.black45,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: _currentIndex > 0
                    ? () => setState(() => _currentIndex--)
                    : null,
              ),
              Text(
                currentFrame?.title ?? '',
                style: const TextStyle(color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                onPressed: _currentIndex < frames.length - 1
                    ? () => setState(() => _currentIndex++)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

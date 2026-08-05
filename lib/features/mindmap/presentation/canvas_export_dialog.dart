import 'package:flutter/material.dart';

enum CanvasExportFormat { pdf, png }

class CanvasExportDialog extends StatefulWidget {
  final String title;
  final VoidCallback? onExportPdf;
  final VoidCallback? onExportPng;

  const CanvasExportDialog({
    super.key,
    required this.title,
    this.onExportPdf,
    this.onExportPng,
  });

  @override
  State<CanvasExportDialog> createState() => _CanvasExportDialogState();
}

class _CanvasExportDialogState extends State<CanvasExportDialog> {
  CanvasExportFormat _selectedFormat = CanvasExportFormat.pdf;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Export Canvas: ${widget.title}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select export format for your board canvas:'),
          const SizedBox(height: 16),
          RadioGroup<CanvasExportFormat>(
            groupValue: _selectedFormat,
            onChanged: (value) {
              if (value != null) setState(() => _selectedFormat = value);
            },
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<CanvasExportFormat>(
                  title: Text('PDF Document (.pdf)'),
                  subtitle: Text('Structured printable PDF with frame grouping'),
                  value: CanvasExportFormat.pdf,
                ),
                RadioListTile<CanvasExportFormat>(
                  title: Text('PNG High-Res Image (.png)'),
                  subtitle: Text('Full canvas visual snapshot image'),
                  value: CanvasExportFormat.png,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            if (_selectedFormat == CanvasExportFormat.pdf) {
              widget.onExportPdf?.call();
            } else {
              widget.onExportPng?.call();
            }
          },
          icon: const Icon(Icons.download),
          label: const Text('Export'),
        ),
      ],
    );
  }
}

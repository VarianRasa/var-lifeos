import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:var_app/features/capture/application/capture_providers.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/duplicate_detector.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

class QuickCaptureDialog extends ConsumerStatefulWidget {
  final CapturePayload? initialPayload;

  const QuickCaptureDialog({super.key, this.initialPayload});

  @override
  ConsumerState<QuickCaptureDialog> createState() => _QuickCaptureDialogState();
}

class _QuickCaptureDialogState extends ConsumerState<QuickCaptureDialog> {
  final _textController = TextEditingController();
  final _urlController = TextEditingController();
  CaptureDestination? _selectedDestination;
  bool _isSaving = false;
  bool _checkingDuplicates = false;
  DuplicateMatchResult _duplicateMatch = DuplicateMatchResult.none;
  MindmapNode? _matchedNode;
  final List<CaptureFileAttachment> _attachments = [];

  @override
  void initState() {
    super.initState();
    final payload = widget.initialPayload;
    if (payload != null) {
      if (payload.text != null) {
        _textController.text = payload.text!;
      }
      if (payload.urls.isNotEmpty) {
        _urlController.text = payload.urls.first;
      }
      if (payload.attachments.isNotEmpty) {
        _attachments.addAll(payload.attachments);
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    setState(() {});
    _checkDuplicates();
  }

  Future<void> _checkDuplicates() async {
    final text = _textController.text.trim();
    final url = _urlController.text.trim();

    if (text.isEmpty && url.isEmpty) {
      if (mounted) {
        setState(() {
          _duplicateMatch = DuplicateMatchResult.none;
          _matchedNode = null;
          _checkingDuplicates = false;
        });
      }
      return;
    }

    setState(() => _checkingDuplicates = true);

    try {
      final payload = CapturePayload(
        text: text.isEmpty ? null : text,
        urls: url.isEmpty ? const [] : [url],
      );

      final repository = ref.read(mindmapRepositoryProvider);
      final existingNodes = await repository.listNodes();
      final match = DuplicateDetector.check(payload, existingNodes);

      MindmapNode? foundNode;
      if (match.hasDuplicate && match.existingNodeId != null) {
        foundNode = await repository.getNode(match.existingNodeId!);
      }

      if (mounted) {
        setState(() {
          _duplicateMatch = match;
          _matchedNode = foundNode;
          _checkingDuplicates = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _checkingDuplicates = false);
      }
    }
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (!mounted || result == null) return;
      final attachments = [
        for (final file in result.files)
          if (file.bytes != null)
            CaptureFileAttachment(
              fileName: file.name,
              mimeType: _mimeTypeFor(file.name),
              bytes: file.bytes!,
              localPath: file.path,
            ),
      ];
      setState(() => _attachments.addAll(attachments));
    } catch (_) {}
  }

  String _mimeTypeFor(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'txt' => 'text/plain',
      'md' => 'text/markdown',
      'csv' => 'text/csv',
      'json' => 'application/json',
      'pdf' => 'application/pdf',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _handleSave({bool forceCopy = false}) async {
    if (_selectedDestination == null ||
        (_duplicateMatch.hasDuplicate && !forceCopy)) {
      return;
    }
    setState(() => _isSaving = true);

    try {
      final text = _textController.text.trim();
      final url = _urlController.text.trim();

      final payload = CapturePayload(
        text: text.isEmpty ? null : text,
        urls: url.isEmpty ? const [] : [url],
        attachments: List.unmodifiable(_attachments),
      );

      final service = await ref.read(captureServiceProvider.future);
      final createdNode = await service.saveCapture(
        payload: payload,
        destination: _selectedDestination!,
      );

      if (mounted) {
        Navigator.of(context).pop(createdNode);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _textController.text.trim();
    final url = _urlController.text.trim();
    final hasContent =
        text.isNotEmpty || url.isNotEmpty || _attachments.isNotEmpty;
    final canSave =
        _selectedDestination != null &&
        hasContent &&
        !_duplicateMatch.hasDuplicate;
    final asyncDestinations = ref.watch(availableCaptureDestinationsProvider);

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Quick Capture',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('quick_capture_text_field'),
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Note / Content',
                  hintText: 'Enter text, thought, or note...',
                ),
                maxLines: 3,
                onChanged: (_) => _onInputChanged(),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('quick_capture_url_field'),
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL (optional)',
                  hintText: 'https://example.com',
                ),
                onChanged: (_) => _onInputChanged(),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('quick_capture_add_attachments_button'),
                onPressed: _isSaving ? null : _pickAttachments,
                icon: const Icon(Icons.attach_file),
                label: const Text('Add images or files'),
              ),
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (var index = 0; index < _attachments.length; index++)
                  ListTile(
                    key: Key('quick_capture_attachment_$index'),
                    leading: Icon(
                      _attachments[index].mimeType.startsWith('image/')
                          ? Icons.image_outlined
                          : Icons.insert_drive_file_outlined,
                    ),
                    title: Text(_attachments[index].fileName),
                    subtitle: Text(_attachments[index].mimeType),
                    trailing: IconButton(
                      tooltip: 'Remove attachment',
                      onPressed: () =>
                          setState(() => _attachments.removeAt(index)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              asyncDestinations.when(
                data: (destinations) {
                  return DropdownButtonFormField<CaptureDestination>(
                    key: const Key('quick_capture_destination_dropdown'),
                    initialValue: _selectedDestination,
                    hint: const Text('Select Destination Board *'),
                    items: destinations.map((dest) {
                      return DropdownMenuItem<CaptureDestination>(
                        value: dest,
                        child: Text('${dest.boardTitle} (${dest.workspaceId})'),
                      );
                    }).toList(),
                    onChanged: (dest) =>
                        setState(() => _selectedDestination = dest),
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (err, _) => Text(
                  'Failed loading boards: $err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              if (_checkingDuplicates) ...[
                const SizedBox(height: 12),
                const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Checking for duplicate content...'),
                  ],
                ),
              ],
              if (_duplicateMatch.hasDuplicate) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Duplicate content detected',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _matchedNode != null
                            ? 'Matches existing item "${_matchedNode!.title}".'
                            : 'Existing item match found.',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (_matchedNode != null)
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop(_matchedNode);
                              },
                              child: const Text('Open Existing'),
                            ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed:
                                _selectedDestination != null &&
                                    hasContent &&
                                    !_isSaving
                                ? () => _handleSave(forceCopy: true)
                                : null,
                            child: const Text('Create Copy'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                key: const Key('quick_capture_save_button'),
                onPressed: canSave && !_isSaving ? () => _handleSave() : null,
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Capture'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

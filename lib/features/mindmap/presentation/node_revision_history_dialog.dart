import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/mindmap_mutation_controller.dart';
import '../application/mindmap_providers.dart';
import '../domain/mindmap_node_revision.dart';

final class NodeRevisionHistoryDialog extends ConsumerStatefulWidget {
  const NodeRevisionHistoryDialog({
    required this.nodeId,
    this.canRestore = true,
    this.restoreDisabledReason,
    super.key,
  });

  final String nodeId;
  final bool canRestore;
  final String? restoreDisabledReason;

  @override
  ConsumerState<NodeRevisionHistoryDialog> createState() =>
      _NodeRevisionHistoryDialogState();
}

final class _NodeRevisionHistoryDialogState
    extends ConsumerState<NodeRevisionHistoryDialog> {
  String? _restoringId;
  Object? _error;

  Future<void> _restore(MindmapNodeRevision revision) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore revision?'),
        content: const Text('Current node state will remain in history'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _restoringId = revision.id;
      _error = null;
    });
    try {
      await ref
          .read(mindmapMutationControllerProvider)
          .restoreRevision(revision.id);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _restoringId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final revisions = ref.watch(nodeRevisionsProvider(widget.nodeId));
    return AlertDialog(
      title: const Text('Version history'),
      content: SizedBox(
        width: 520,
        child: revisions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('Could not load history: $error'),
          data: (items) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) Text('Restore failed: $_error'),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final revision = items[index];
                    return ListTile(
                      title: Text(revision.snapshot.title),
                      subtitle: Text(
                        '${revision.kind.name} · ${revision.recordedAt.toLocal()}',
                      ),
                      trailing: _restoringId == revision.id
                          ? const CircularProgressIndicator()
                          : Tooltip(
                              message: widget.canRestore
                                  ? ''
                                  : widget.restoreDisabledReason ??
                                        'Restore unavailable.',
                              child: TextButton(
                                onPressed:
                                    widget.canRestore && _restoringId == null
                                    ? () => _restore(revision)
                                    : null,
                                child: const Text('Restore'),
                              ),
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _restoringId == null ? () => Navigator.pop(context) : null,
          child: const Text('Close'),
        ),
      ],
    );
  }
}

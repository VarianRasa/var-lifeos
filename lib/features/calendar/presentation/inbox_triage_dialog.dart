library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/node_visuals.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/application/mindmap_mutation_controller.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../application/node_inbox.dart';

Future<void> showInboxTriageDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const InboxTriageDialog(),
  );
}

class InboxTriageDialog extends ConsumerStatefulWidget {
  const InboxTriageDialog({super.key});

  @override
  ConsumerState<InboxTriageDialog> createState() => _InboxTriageDialogState();
}

class _InboxTriageDialogState extends ConsumerState<InboxTriageDialog> {
  DateTime _targetDay = DateTime.now().dateOnly;

  @override
  Widget build(BuildContext context) {
    final nodesAsync = ref.watch(allMindmapNodesProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.inbox_outlined),
          const SizedBox(width: 8),
          const Expanded(child: Text('Inbox Triage')),
          TextButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(
              _targetDay.isToday
                  ? 'Today'
                  : '${_targetDay.month}/${_targetDay.day}',
            ),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _targetDay,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (picked != null) {
                setState(() => _targetDay = picked.dateOnly);
              }
            },
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: nodesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (allNodes) {
            final inboxNodes = allNodes.where(isInboxNode).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

            if (inboxNodes.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.done_all,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text('Inbox is empty! Zero inbox achieved.'),
                  ],
                ),
              );
            }

            return ListView.separated(
              itemCount: inboxNodes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final node = inboxNodes[index];
                return ListTile(
                  leading: Icon(
                    NodeVisuals.icon(node.type),
                    size: 20,
                    color: NodeVisuals.color(context, node.type),
                  ),
                  title: Text(node.title.isEmpty ? 'Untitled' : node.title),
                  subtitle: Text(
                    'Created ${_formatDate(node.createdAt)} • ${node.type.label}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip:
                            'Schedule to ${_targetDay.isToday ? "Today" : "Target"}',
                        icon: const Icon(Icons.arrow_forward_outlined),
                        onPressed: () async {
                          final updated = assignInboxNodeToDay(
                            node,
                            _targetDay,
                          );
                          await ref
                              .read(mindmapMutationControllerProvider)
                              .saveNode(updated);
                        },
                      ),
                      IconButton(
                        tooltip: 'Someday',
                        icon: const Icon(Icons.snooze_outlined),
                        onPressed: () async {
                          await ref
                              .read(mindmapMutationControllerProvider)
                              .saveNode(deferInboxNode(node));
                        },
                      ),
                      IconButton(
                        tooltip: 'Archive',
                        icon: const Icon(Icons.archive_outlined),
                        onPressed: () async {
                          final updated = node.copyWith(
                            isArchived: true,
                            updatedAt: DateTime.now(),
                          );
                          await ref
                              .read(mindmapMutationControllerProvider)
                              .saveNode(updated);
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}';
  }
}

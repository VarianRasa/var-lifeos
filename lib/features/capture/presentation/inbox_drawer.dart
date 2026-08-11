/// Floating/Drawer Inbox Tray for quick access to un-scheduled or inbox nodes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/node_visuals.dart';
import '../../../shared/widgets/error_message.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../../mindmap/domain/mindmap_node.dart';

class InboxDrawer extends ConsumerWidget {
  const InboxDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nodesAsync = ref.watch(allMindmapNodesProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  Icon(Icons.inbox_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Inbox Tray',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: nodesAsync.when(
                data: (List<MindmapNode> nodes) {
                  final inboxNodes = nodes
                      .where(
                        (MindmapNode n) =>
                            !n.isArchived &&
                            (n.status == NodeStatus.inbox ||
                                n.tags.contains('inbox')),
                      )
                      .toList();

                  if (inboxNodes.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 48,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Inbox is clear!',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Captured ideas without a date appear here.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: inboxNodes.length,
                    itemBuilder: (context, index) {
                      final node = inboxNodes[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            NodeVisuals.icon(node.type),
                            color: NodeVisuals.color(context, node.type),
                          ),
                          title: Text(
                            node.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            node.type.label,
                            style: theme.textTheme.labelSmall,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            tooltip: 'Move to Day Canvas',
                            onPressed: () {
                              Navigator.of(context).pop();
                              goToDay(
                                context,
                                node.day,
                                highlightNodeId: node.id,
                              );
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => ErrorMessage(
                  message: 'Failed to load inbox items',
                  onRetry: () => ref.invalidate(allMindmapNodesProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

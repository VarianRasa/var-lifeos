import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/node_visuals.dart';
import '../../application/mindmap_providers.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_knowledge_index.dart';
import '../../domain/spaced_repetition.dart';

class NodeBacklinksPanel extends ConsumerWidget {
  const NodeBacklinksPanel({super.key, required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesAsync = ref.watch(allMindmapNodesProvider);
    final theme = Theme.of(context);

    return nodesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (nodes) {
        final index = NodeKnowledgeIndex(nodes);
        final links = index.linksFor(node.id);

        if (links.backlinks.isEmpty && links.incomingMentions.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          key: const ValueKey('node-backlinks-panel'),
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.link_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Backlinks & Knowledge Connections',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isFlashcardNode(node)) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.teal.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.psychology,
                              size: 12,
                              color: Colors.teal,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'SM-2 Due: ${getFlashcardState(node).intervalDays}d',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.teal,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (links.backlinks.isNotEmpty) ...[
                  Text(
                    'Linked Backlinks (${links.backlinks.length})',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final backlink in links.backlinks) ...[
                    _BacklinkTile(backlink: backlink),
                    const SizedBox(height: 4),
                  ],
                ],
                if (links.incomingMentions.isNotEmpty) ...[
                  if (links.backlinks.isNotEmpty) const Divider(height: 12),
                  Text(
                    'Unlinked Mentions (${links.incomingMentions.length})',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final mention in links.incomingMentions) ...[
                    _UnlinkedMentionTile(
                      targetNode: node,
                      mentioningNode: mention,
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BacklinkTile extends StatelessWidget {
  const _BacklinkTile({required this.backlink});

  final NodeBacklink backlink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = backlink.node;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            NodeVisuals.icon(node.type),
            size: 14,
            color: NodeVisuals.color(context, node.type),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              node.title,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              backlink.reasonLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlinkedMentionTile extends ConsumerWidget {
  const _UnlinkedMentionTile({
    required this.targetNode,
    required this.mentioningNode,
  });

  final MindmapNode targetNode;
  final MindmapNode mentioningNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            NodeVisuals.icon(mentioningNode.type),
            size: 14,
            color: NodeVisuals.color(context, mentioningNode.type),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              mentioningNode.title,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () async {
              final newBody = bodyWithLinkedTitle(
                mentioningNode.body,
                targetNode.title,
              );
              final updated = mentioningNode.copyWith(
                body: newBody,
                relatedNodeIds: [
                  ...mentioningNode.relatedNodeIds,
                  if (!mentioningNode.relatedNodeIds.contains(targetNode.id))
                    targetNode.id,
                ],
                updatedAt: DateTime.now(),
              );
              final repository = ref.read(mindmapRepositoryProvider);
              await repository.saveNode(updated);
              invalidateMindmapState(ref, day: mentioningNode.day);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_link,
                    size: 12,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'Linkify',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

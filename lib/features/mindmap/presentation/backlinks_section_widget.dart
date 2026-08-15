/// Bi-directional linking widget for node inspection / detail view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/node_visuals.dart';
import '../application/mindmap_providers.dart';

class BacklinksSectionWidget extends ConsumerWidget {
  const BacklinksSectionWidget({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final relationsAsync = ref.watch(nodeRelationsProvider(nodeId));

    return relationsAsync.when(
      data: (relations) {
        final backlinks = relations.backlinks;
        final outgoing = relations.relatedNodes;

        if (backlinks.isEmpty && outgoing.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Bi-directional Links',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              if (backlinks.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Linked From (${backlinks.length}):',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final backlink in backlinks)
                      ActionChip(
                        avatar: Icon(
                          NodeVisuals.icon(backlink.type),
                          size: 14,
                          color: NodeVisuals.color(context, backlink.type),
                        ),
                        label: Text(
                          '[[${backlink.title}]]',
                          style: const TextStyle(fontSize: 12),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => goToDay(
                          context,
                          backlink.day,
                          highlightNodeId: backlink.id,
                        ),
                      ),
                  ],
                ),
              ],
              if (outgoing.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Links To (${outgoing.length}):',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final out in outgoing)
                      ActionChip(
                        avatar: Icon(
                          NodeVisuals.icon(out.type),
                          size: 14,
                          color: NodeVisuals.color(context, out.type),
                        ),
                        label: Text(
                          out.title,
                          style: const TextStyle(fontSize: 12),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            goToDay(context, out.day, highlightNodeId: out.id),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }
}

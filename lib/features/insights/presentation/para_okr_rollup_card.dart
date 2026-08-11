import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/node_visuals.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../../mindmap/domain/para_okr_rollup.dart';

class ParaOkrRollupCard extends ConsumerWidget {
  const ParaOkrRollupCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rollupAsync = ref.watch(paraOkrRollupProvider);
    final theme = Theme.of(context);

    return Card(
      key: const ValueKey('para-okr-rollup-card'),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'PARA & OKR Progress Rollup',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            rollupAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, stack) => Text(
                'Failed to load hierarchy: $err',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              data: (summary) {
                if (summary.goals.isEmpty && summary.unlinkedProjects.isEmpty) {
                  return Text(
                    'No goals or projects defined yet for top-down rollup.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final goal in summary.goals) ...[
                      _RollupNodeItem(rollup: goal, depth: 0),
                      const SizedBox(height: 8),
                    ],
                    if (summary.unlinkedProjects.isNotEmpty) ...[
                      const Divider(height: 16),
                      Text(
                        'Standalone Projects',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final proj in summary.unlinkedProjects) ...[
                        _RollupNodeItem(rollup: proj, depth: 1),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RollupNodeItem extends StatelessWidget {
  const _RollupNodeItem({required this.rollup, required this.depth});

  final ParaOkrNodeRollup rollup;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = (rollup.rollupProgress * 100).round();

    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                NodeVisuals.icon(rollup.type),
                size: 16,
                color: NodeVisuals.color(context, rollup.type),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rollup.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: depth == 0
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$percent%',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: rollup.rollupProgress,
            minHeight: depth == 0 ? 6 : 4,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: NodeVisuals.color(context, rollup.type),
          ),
          if (rollup.children.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final child in rollup.children) ...[
              _RollupNodeItem(rollup: child, depth: depth + 1),
              const SizedBox(height: 4),
            ],
          ],
        ],
      ),
    );
  }
}

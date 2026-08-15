import 'package:flutter/material.dart';

import '../../../core/theme/node_visuals.dart';
import '../../mindmap/domain/eisenhower_matrix.dart';
import '../../mindmap/domain/mindmap_node.dart';

class EisenhowerMatrixCard extends StatelessWidget {
  const EisenhowerMatrixCard({
    super.key,
    required this.nodes,
    required this.today,
    required this.onNodeSelected,
  });

  final List<MindmapNode> nodes;
  final DateTime today;
  final ValueChanged<MindmapNode> onNodeSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = EisenhowerMatrixSummary.fromNodes(nodes, today);

    return Card(
      key: const ValueKey('eisenhower-matrix-card'),
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
                  Icons.grid_view_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Eisenhower Priority Matrix',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 600;
                final q1Widget = _QuadrantBox(
                  title: EisenhowerQuadrant.doFirst.title,
                  badge: EisenhowerQuadrant.doFirst.badge,
                  color: theme.colorScheme.error,
                  items: summary.q1DoFirst,
                  onNodeSelected: onNodeSelected,
                );
                final q2Widget = _QuadrantBox(
                  title: EisenhowerQuadrant.schedule.title,
                  badge: EisenhowerQuadrant.schedule.badge,
                  color: theme.colorScheme.primary,
                  items: summary.q2Schedule,
                  onNodeSelected: onNodeSelected,
                );
                final q3Widget = _QuadrantBox(
                  title: EisenhowerQuadrant.delegate.title,
                  badge: EisenhowerQuadrant.delegate.badge,
                  color: theme.colorScheme.tertiary,
                  items: summary.q3Delegate,
                  onNodeSelected: onNodeSelected,
                );
                final q4Widget = _QuadrantBox(
                  title: EisenhowerQuadrant.dontDo.title,
                  badge: EisenhowerQuadrant.dontDo.badge,
                  color: theme.colorScheme.outline,
                  items: summary.q4DontDo,
                  onNodeSelected: onNodeSelected,
                );

                if (isWide) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: q1Widget),
                          const SizedBox(width: 10),
                          Expanded(child: q2Widget),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: q3Widget),
                          const SizedBox(width: 10),
                          Expanded(child: q4Widget),
                        ],
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    q1Widget,
                    const SizedBox(height: 10),
                    q2Widget,
                    const SizedBox(height: 10),
                    q3Widget,
                    const SizedBox(height: 10),
                    q4Widget,
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

class _QuadrantBox extends StatelessWidget {
  const _QuadrantBox({
    required this.title,
    required this.badge,
    required this.color,
    required this.items,
    required this.onNodeSelected,
  });

  final String title;
  final String badge;
  final Color color;
  final List<EisenhowerNodeScore> items;
  final ValueChanged<MindmapNode> onNodeSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${items.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              'No items',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Column(
              children: items.take(4).map((scored) {
                final node = scored.node;
                return InkWell(
                  onTap: () => onNodeSelected(node),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          NodeVisuals.icon(node.type),
                          size: 14,
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            node.title,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${scored.score.round()}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

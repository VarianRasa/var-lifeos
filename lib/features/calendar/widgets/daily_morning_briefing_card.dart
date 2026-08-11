import 'package:flutter/material.dart';

import '../../../core/theme/node_visuals.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../application/energy_task_scheduler.dart';

class DailyMorningBriefingCard extends StatelessWidget {
  const DailyMorningBriefingCard({
    super.key,
    required this.dayNodes,
    required this.onNodeSelected,
  });

  final List<MindmapNode> dayNodes;
  final ValueChanged<MindmapNode> onNodeSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final briefing = generateDailyMorningBriefing(dayNodes: dayNodes);

    if (dayNodes.isEmpty) return const SizedBox.shrink();

    return Card(
      key: const ValueKey('daily-morning-briefing-card'),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wb_sunny_outlined,
                  size: 18,
                  color: Colors.amber.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'Daily Morning Energy Briefing',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              briefing.briefingHeadline,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (briefing.peakFocusTasks.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '⚡ Morning Peak Focus (${briefing.peakFocusTasks.length})',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final item in briefing.peakFocusTasks.take(3))
                    ActionChip(
                      avatar: Icon(
                        NodeVisuals.icon(item.node.type),
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      label: Text(item.node.title),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onNodeSelected(item.node),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

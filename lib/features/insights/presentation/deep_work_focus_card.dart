import 'package:flutter/material.dart';

import '../../mindmap/domain/mindmap_node.dart';
import '../application/focus_insights.dart';

class DeepWorkFocusCard extends StatelessWidget {
  const DeepWorkFocusCard({
    super.key,
    required this.nodes,
    required this.today,
  });

  final List<MindmapNode> nodes;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focusSummary = buildFocusInsightSummary(
      start: today.subtract(const Duration(days: 30)),
      end: today,
      nodes: nodes,
    );

    final totalMinutes = focusSummary.totalMinutes;
    final bestMinutes = focusSummary.bestFocusMinutes;
    final openTasks = focusSummary.plannedOpenTasks;
    final hoursLabel = (totalMinutes / 60.0).toStringAsFixed(1);

    return Card(
      key: const ValueKey('deep-work-focus-card'),
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
                  Icons.timer_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Deep Work & Focus Analytics',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Stat Cards Grid
            Row(
              children: [
                Expanded(
                  child: _StatBox(
                    icon: Icons.access_time_filled,
                    color: theme.colorScheme.primary,
                    value: '${hoursLabel}h',
                    label: '30D Focus Time',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatBox(
                    icon: Icons.star_rounded,
                    color: theme.colorScheme.tertiary,
                    value: '${bestMinutes}m',
                    label: 'Best Day Record',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatBox(
                    icon: Icons.task_alt_rounded,
                    color: Colors.orange,
                    value: '$openTasks',
                    label: 'Open Planned Tasks',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

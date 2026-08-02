import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/theme/node_visuals.dart';
import '../domain/executive_dashboard_summary.dart';

class ExecutiveDashboardPanel extends StatelessWidget {
  const ExecutiveDashboardPanel({
    super.key,
    required this.summary,
    required this.onAreaTap,
    required this.onStartWeeklyReview,
  });

  final ExecutiveDashboardSummary summary;
  final ValueChanged<LifeOsArea> onAreaTap;
  final VoidCallback onStartWeeklyReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Executive Health Header Banner
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusContainer),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: summary.healthIndexScore / 100.0,
                        strokeWidth: 8,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        color: summary.healthIndexScore >= 70
                            ? semantic.success
                            : (summary.healthIndexScore >= 40
                                  ? semantic.warning
                                  : semantic.danger),
                      ),
                    ),
                    Text(
                      '${summary.healthIndexScore}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Life OS Executive Health Index',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${summary.totalActiveGoals} Active Goals • ${summary.totalHabits} Habits • ${summary.totalOverdueTasks} Overdue',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: onStartWeeklyReview,
                  icon: const Icon(Icons.rate_review_outlined, size: 16),
                  label: const Text('Weekly Review'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 4 Domain Quad-Cards Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;
            final cards = LifeOsArea.values.map((area) {
              final metrics = summary.areaMetrics[area]!;
              final iconData = switch (area) {
                LifeOsArea.work => Icons.work_outline,
                LifeOsArea.health => Icons.favorite_outline,
                LifeOsArea.growth => Icons.menu_book_outlined,
                LifeOsArea.personal => Icons.person_outline,
              };
              final color = switch (area) {
                LifeOsArea.work => NodeVisuals.color(context, NodeType.task),
                LifeOsArea.health => NodeVisuals.color(context, NodeType.habit),
                LifeOsArea.growth => NodeVisuals.color(context, NodeType.goal),
                LifeOsArea.personal => NodeVisuals.color(
                  context,
                  NodeType.journal,
                ),
              };

              return InkWell(
                onTap: () => onAreaTap(area),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(iconData, size: 18, color: color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              area.label,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '${metrics.totalNodes} items',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _MetricStatTile(
                            label: 'Tasks Done',
                            value:
                                '${metrics.completedTasks}/${metrics.totalTasks}',
                          ),
                          _MetricStatTile(
                            label: 'Goal Progress',
                            value:
                                '${(metrics.averageGoalProgress * 100).round()}%',
                          ),
                          _MetricStatTile(
                            label: 'Habits',
                            value: '${metrics.activeHabits}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: metrics.taskCompletionRate,
                          minHeight: 4,
                          color: color,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList();

            if (isWide) {
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
                children: cards,
              );
            } else {
              return Column(
                children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: 8),
                  ],
                ],
              );
            }
          },
        ),
      ],
    );
  }
}

class _MetricStatTile extends StatelessWidget {
  const _MetricStatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 10,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

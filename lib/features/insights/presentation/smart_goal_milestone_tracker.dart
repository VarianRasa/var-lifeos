/// Smart Goal & Milestone Tracker widget for auditing goals and advancing milestones.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/theme/node_visuals.dart';
import '../../mindmap/application/mindmap_mutation_controller.dart';
import '../../mindmap/domain/goal_progress.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../application/goal_insights.dart' as goals;

class SmartGoalMilestoneTracker extends ConsumerWidget {
  const SmartGoalMilestoneTracker({
    required this.nodes,
    required this.today,
    super.key,
  });

  final List<MindmapNode> nodes;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final goalColor = NodeVisuals.color(context, NodeType.goal);
    final summary = goals.buildGoalInsightSummary(today: today, nodes: nodes);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: semantic.card,
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
        border: Border.all(color: semantic.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.flag_rounded,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Audit Target & Milestone OS',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: semantic.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(summary.averageProgress * 100).toInt()}% Progres Rata-rata',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: semantic.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MetricCard(
                label: 'Total Target',
                value: '${summary.goalCount}',
                icon: Icons.track_changes,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              _MetricCard(
                label: 'Aktif / Berjalan',
                value: '${summary.inProgressCount}',
                icon: Icons.directions_run,
                color: semantic.info,
              ),
              const SizedBox(width: 8),
              _MetricCard(
                label: 'Selesai',
                value: '${summary.completedCount}',
                icon: Icons.check_circle_outline,
                color: semantic.success,
              ),
              const SizedBox(width: 8),
              _MetricCard(
                label: 'Stalled (Macet)',
                value: '${summary.stalledGoals.length}',
                icon: Icons.warning_amber_rounded,
                color: semantic.warning,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Daftar Milestone Berikutnya:',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (summary.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Belum ada target yang dibuat.',
                style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: summary.items.length > 5 ? 5 : summary.items.length,
              separatorBuilder: (_, _) => const Divider(height: 12),
              itemBuilder: (context, index) {
                final item = summary.items[index];
                final nextMilestone = item.nextMilestone;
                final isDone = item.progress >= 1.0;

                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.node.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    decoration: isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              Text(
                                '${(item.progress * 100).toInt()}%',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: item.progress,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDone
                                  ? semantic.success
                                  : (item.isStalled
                                        ? semantic.warning
                                        : goalColor),
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (nextMilestone != null)
                            Text(
                              'Milestone berikut: $nextMilestone',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          else if (isDone)
                            Text(
                              'Semua milestone tercapai!',
                              style: TextStyle(
                                fontSize: 11,
                                color: semantic.success,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!isDone && nextMilestone != null)
                      IconButton(
                        icon: const Icon(
                          Icons.check_box_outline_blank,
                          size: 20,
                        ),
                        tooltip: 'Selesaikan Milestone',
                        onPressed: () async {
                          final updated = advanceGoalMilestone(item.node);
                          await ref
                              .read(mindmapMutationControllerProvider)
                              .saveNode(updated);
                        },
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

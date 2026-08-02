import 'package:flutter/material.dart';

import '../../../core/theme/app_design_tokens.dart';
import '../application/today_cockpit.dart';

class TodayCockpitPanel extends StatelessWidget {
  const TodayCockpitPanel({
    required this.summary,
    required this.onTriageInbox,
    required this.onOpenDay,
    required this.onOpenNode,
    super.key,
  });

  final TodayCockpitSummary summary;
  final VoidCallback onTriageInbox;
  final VoidCallback onOpenDay;
  final ValueChanged<String> onOpenNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppDesignTokens.of(context);
    final schedule = summary.nextSchedule;
    final habitLabel = summary.habitDueCount == 0
        ? 'No habits due'
        : '${summary.habitCompletedCount}/${summary.habitDueCount} habits';

    return DecoratedBox(
      key: const ValueKey('today-cockpit-panel'),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dashboard_customize_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Today cockpit',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('today-cockpit-open-day'),
                  onPressed: onOpenDay,
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: const Text('Plan / Focus'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  key: const ValueKey('today-cockpit-inbox'),
                  avatar: const Icon(Icons.inbox_outlined, size: 16),
                  label: Text('${summary.inboxNodes.length} inbox'),
                  onPressed: onTriageInbox,
                ),
                ActionChip(
                  key: const ValueKey('today-cockpit-schedule'),
                  avatar: const Icon(Icons.schedule_outlined, size: 16),
                  label: Text(
                    schedule == null
                        ? '${summary.unscheduledActionCount} unscheduled'
                        : '${schedule.block.startLabel} ${schedule.node.title}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: onOpenDay,
                ),
                ActionChip(
                  key: const ValueKey('today-cockpit-habits'),
                  avatar: const Icon(Icons.repeat_rounded, size: 16),
                  label: Text(habitLabel),
                  onPressed: onOpenDay,
                ),
                ActionChip(
                  key: const ValueKey('today-cockpit-review'),
                  avatar: Icon(
                    summary.hasDailyReview
                        ? Icons.fact_check_outlined
                        : Icons.rate_review_outlined,
                    size: 16,
                  ),
                  label: Text(
                    summary.hasDailyReview ? 'Review ready' : 'Start review',
                  ),
                  onPressed: summary.dailyReview == null
                      ? onOpenDay
                      : () => onOpenNode(summary.dailyReview!.id),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Top 3 · ${summary.missionNodes.length}/3 selected',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            if (summary.missionNodes.isEmpty)
              Semantics(
                button: true,
                label: 'Choose up to 3 missions in full day',
                child: InkWell(
                  key: const ValueKey('today-cockpit-empty-missions'),
                  onTap: onOpenDay,
                  borderRadius: BorderRadius.circular(tokens.radiusElement),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_task_outlined,
                          size: 17,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Choose up to 3 missions in full day',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              for (final node in summary.missionNodes)
                Semantics(
                  button: true,
                  label: 'Open mission ${node.title}',
                  child: InkWell(
                    key: ValueKey('today-cockpit-mission-${node.id}'),
                    onTap: () => onOpenNode(node.id),
                    borderRadius: BorderRadius.circular(tokens.radiusElement),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
                        children: [
                          Icon(
                            Icons.adjust_rounded,
                            size: 15,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              node.title.trim().isEmpty
                                  ? 'Untitled mission'
                                  : node.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

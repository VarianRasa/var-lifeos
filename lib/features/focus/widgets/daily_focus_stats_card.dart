import 'package:flutter/material.dart';

import '../../../core/theme/app_design_tokens.dart';

class DailyFocusStatsCard extends StatelessWidget {
  const DailyFocusStatsCard({
    required this.completedSessions,
    required this.totalFocusMinutes,
    super.key,
  });

  final int completedSessions;
  final int totalFocusMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppDesignTokens.of(context);
    final hours = totalFocusMinutes ~/ 60;
    final mins = totalFocusMinutes % 60;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$completedSessions',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Sesi Selesai',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 40,
              color: theme.colorScheme.outlineVariant,
            ),
            Expanded(
              child: Column(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hours > 0 ? '${hours}j ${mins}m' : '${mins}m',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Total Fokus',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

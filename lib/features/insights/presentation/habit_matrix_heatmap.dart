import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/habit_completion.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../application/habit_insights.dart';

class HabitMatrixHeatmap extends StatefulWidget {
  const HabitMatrixHeatmap({
    required this.habitNodes,
    this.initialWeeks = 16,
    super.key,
  });

  final List<MindmapNode> habitNodes;
  final int initialWeeks;

  @override
  State<HabitMatrixHeatmap> createState() => _HabitMatrixHeatmapState();
}

class _HabitMatrixHeatmapState extends State<HabitMatrixHeatmap> {
  late int _weeks;

  @override
  void initState() {
    super.initState();
    _weeks = widget.initialWeeks;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final today = DateTime.now().dateOnly;

    // Start date calculation aligned to Monday
    final startDay = today.subtract(Duration(days: (_weeks * 7) - 1));
    final completionMap = <String, int>{};
    for (final node in widget.habitNodes) {
      for (final key in habitCompletionKeys(node)) {
        completionMap[key] = (completionMap[key] ?? 0) + 1;
      }
    }

    // Aggregate strength score computation
    final habitStreaks = widget.habitNodes
        .map((node) => calculateHabitStrength(node, today))
        .toList();
    final avgStrengthScore = habitStreaks.isEmpty
        ? 0.0
        : (habitStreaks.reduce((a, b) => a + b) / habitStreaks.length);

    final strengthLabel = avgStrengthScore >= 80
        ? 'Mastered'
        : (avgStrengthScore >= 50
              ? 'Building'
              : (avgStrengthScore >= 20 ? 'Fragile' : 'Dormant'));

    final strengthColor = avgStrengthScore >= 80
        ? semantic.success
        : (avgStrengthScore >= 50
              ? semantic.info
              : (avgStrengthScore >= 20 ? semantic.warning : semantic.danger));

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Control Bar: Title, Strength Badge & 16/52-week ChoiceChips
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Matriks Kebiasaan ($_weeks Minggu)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: strengthColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(
                          tokens.radiusElement,
                        ),
                        border: Border.all(
                          color: strengthColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        'Score ${avgStrengthScore.toStringAsFixed(1)} • $strengthLabel',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: strengthColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
                final range = SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(
                      value: 16,
                      label: Text('16M', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment<int>(
                      value: 52,
                      label: Text('1 thn', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  selected: {_weeks},
                  onSelectionChanged: (newSelection) {
                    setState(() => _weeks = newSelection.first);
                  },
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                );
                if (constraints.maxWidth < 360) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 8), range],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    range,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

            // Legend Header
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Kurang',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                ),
                const SizedBox(width: 4),
                _LegendBox(color: theme.colorScheme.surfaceContainerHighest),
                const SizedBox(width: 2),
                _LegendBox(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 2),
                _LegendBox(
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 2),
                _LegendBox(color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Banyak',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Semantics(
              container: true,
              image: true,
              label: 'Habit matrix heatmap',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 280),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Weekday Header Column
                      const Padding(
                        padding: EdgeInsets.only(right: 6, top: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _WeekdayLabel('S'),
                            _WeekdayLabel('S'),
                            _WeekdayLabel('R'),
                            _WeekdayLabel('K'),
                            _WeekdayLabel('J'),
                            _WeekdayLabel('S'),
                            _WeekdayLabel('M'),
                          ],
                        ),
                      ),

                      // Grid Cells
                      Row(
                        children: List.generate(_weeks, (weekIdx) {
                          return Column(
                            children: List.generate(7, (dayIdx) {
                              final dayOffset = (weekIdx * 7) + dayIdx;
                              final date = startDay.addDays(dayOffset);
                              final key = dayKey(date);
                              final count = completionMap[key] ?? 0;

                              Color cellColor =
                                  theme.colorScheme.surfaceContainerHighest;
                              if (count == 1) {
                                cellColor = theme.colorScheme.primary
                                    .withValues(alpha: 0.3);
                              } else if (count == 2) {
                                cellColor = theme.colorScheme.primary
                                    .withValues(alpha: 0.6);
                              } else if (count >= 3) {
                                cellColor = theme.colorScheme.primary;
                              }

                              return Tooltip(
                                message:
                                    '${dayKey(date)}: $count habit selesai',
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: cellColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            }),
                          );
                        }),
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

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LegendBox extends StatelessWidget {
  const _LegendBox({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

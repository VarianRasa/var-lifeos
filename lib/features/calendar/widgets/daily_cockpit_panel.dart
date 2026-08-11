import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../life_os/application/user_gamification_providers.dart';
import '../../mindmap/application/mindmap_mutation_controller.dart';
import '../../mindmap/application/spaced_repetition_providers.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/presentation/flashcard_review_dialog.dart';
import '../application/energy_task_scheduler.dart';
import 'daily_morning_briefing_card.dart';

class DailyCockpitPanel extends ConsumerWidget {
  const DailyCockpitPanel({
    required this.day,
    required this.nodes,
    required this.onRescheduleRequested,
    this.inboxCount = 0,
    this.somedayCount = 0,
    this.onInboxPressed,
    this.onSomedayPressed,
    this.onNodeSelected,
    super.key,
  });

  final DateTime day;
  final List<MindmapNode> nodes;
  final void Function(List<MindmapNode> overloadedNodes) onRescheduleRequested;
  final int inboxCount;
  final int somedayCount;
  final VoidCallback? onInboxPressed;
  final VoidCallback? onSomedayPressed;
  final ValueChanged<MindmapNode>? onNodeSelected;

  Future<void> _handleAutoTimeBlock(BuildContext context, WidgetRef ref) async {
    final assignments = autoTimeBlockDay(dayNodes: nodes);
    if (assignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No unallocated tasks to time-block.')),
      );
      return;
    }

    final mutationCtrl = ref.read(mindmapMutationControllerProvider);
    for (final entry in assignments.entries) {
      final node = nodes.firstWhere((n) => n.id == entry.key);
      final updatedNode = node.copyWith(
        data: {...node.data, 'timeBlock': entry.value.toJson()},
      );
      await mutationCtrl.saveNode(updatedNode);
    }

    await ref.read(userGamificationProvider.notifier).addXp(20);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Auto time-blocked ${assignments.length} tasks! (+20 XP)',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final openTasks = nodes
        .where((n) => n.type == NodeType.task && !n.isDone)
        .toList();
    final isOverloaded = openTasks.length >= 6;
    final dueCards = ref.watch(dueFlashcardsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _handleAutoTimeBlock(context, ref),
                  icon: const Icon(Icons.bolt, size: 16, color: Colors.amber),
                  label: const Text(
                    'Auto Time-Block',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (dueCards.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        FlashcardReviewDialog.show(context, dueCards),
                    icon: const Icon(Icons.psychology, size: 16),
                    label: Text(
                      'Review Deck (${dueCards.length})',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onNodeSelected != null && nodes.isNotEmpty)
          DailyMorningBriefingCard(
            dayNodes: nodes,
            onNodeSelected: onNodeSelected!,
          ),
        if (isOverloaded) ...[
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.error,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Overloaded: ${openTasks.length} task terbuka.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => onRescheduleRequested(openTasks),
                      child: const Text(
                        'Seimbangkan',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

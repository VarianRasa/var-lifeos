import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../mindmap/application/spaced_repetition_providers.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/presentation/flashcard_review_dialog.dart';
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
        if (dueCards.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => FlashcardReviewDialog.show(context, dueCards),
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

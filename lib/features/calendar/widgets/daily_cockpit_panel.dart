import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';

class DailyCockpitPanel extends StatelessWidget {
  const DailyCockpitPanel({
    required this.day,
    required this.nodes,
    required this.onRescheduleRequested,
    this.inboxCount = 0,
    this.somedayCount = 0,
    this.onInboxPressed,
    this.onSomedayPressed,
    super.key,
  });

  final DateTime day;
  final List<MindmapNode> nodes;
  final void Function(List<MindmapNode> overloadedNodes) onRescheduleRequested;
  final int inboxCount;
  final int somedayCount;
  final VoidCallback? onInboxPressed;
  final VoidCallback? onSomedayPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openTasks = nodes
        .where((n) => n.type == NodeType.task && !n.isDone)
        .toList();
    final isOverloaded = openTasks.length >= 6;

    final journalNode = nodes.firstWhere(
      (n) => n.type == NodeType.journal,
      orElse: () => MindmapNode(
        id: '',
        type: NodeType.journal,
        title: '',
        day: day,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    final journalData =
        journalNode.data['journal'] as Map<String, Object?>? ?? const {};
    final mood = journalData['mood'] as num?;
    final energy = journalData['energy'] as num?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.wb_sunny_outlined,
                      color: theme.colorScheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text('Sunny, 28°C', style: theme.textTheme.bodySmall),
                  ],
                ),
                Row(
                  children: [
                    if (inboxCount > 0) ...[
                      ActionChip(
                        avatar: const Icon(Icons.inbox_outlined, size: 14),
                        label: Text(
                          'Inbox $inboxCount',
                          style: theme.textTheme.labelSmall,
                        ),
                        onPressed: onInboxPressed,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (somedayCount > 0) ...[
                      ActionChip(
                        avatar: const Icon(Icons.next_plan_outlined, size: 14),
                        label: Text(
                          'Someday $somedayCount',
                          style: theme.textTheme.labelSmall,
                        ),
                        onPressed: onSomedayPressed,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Icon(
                      Icons.favorite_border,
                      color: theme.colorScheme.error,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      mood != null
                          ? 'Mood: ${mood.toInt()}/5'
                          : (energy != null
                                ? 'Energy: ${energy.toInt()}/5'
                                : 'Mood: -'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: (mood != null || energy != null)
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (isOverloaded) ...[
              const SizedBox(height: 6),
              Container(
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
            ],
          ],
        ),
      ),
    );
  }
}

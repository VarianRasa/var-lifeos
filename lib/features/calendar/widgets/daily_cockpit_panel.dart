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

    if (!isOverloaded) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
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

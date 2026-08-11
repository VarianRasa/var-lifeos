/// Guided Multi-step Weekly Review Wizard for Life OS.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/error_message.dart';
import '../../mindmap/application/mindmap_providers.dart';

class WeeklyReviewDialog extends ConsumerStatefulWidget {
  const WeeklyReviewDialog({super.key});

  @override
  ConsumerState<WeeklyReviewDialog> createState() => _WeeklyReviewDialogState();
}

class _WeeklyReviewDialogState extends ConsumerState<WeeklyReviewDialog> {
  int _currentStep = 0;
  final TextEditingController _reflectionController = TextEditingController();

  @override
  void dispose() {
    _reflectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodesAsync = ref.watch(allMindmapNodesProvider);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: nodesAsync.when(
            data: (nodes) {
              final activeNodes = nodes.where((n) => !n.isArchived).toList();
              final doneTasks = activeNodes
                  .where((n) => n.type == NodeType.task && n.isDone)
                  .length;
              final habitCount = activeNodes
                  .where((n) => n.type == NodeType.habit)
                  .length;
              final goalCount = activeNodes
                  .where((n) => n.type == NodeType.goal)
                  .length;

              return Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.rate_review_rounded,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Weekly Review Wizard',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: IndexedStack(
                      index: _currentStep,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Step 1: Weekly Progress',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _StatCard(
                                  icon: Icons.check_circle_outline,
                                  label: 'Tasks Done',
                                  value: '$doneTasks',
                                ),
                                _StatCard(
                                  icon: Icons.repeat,
                                  label: 'Habits',
                                  value: '$habitCount',
                                ),
                                _StatCard(
                                  icon: Icons.flag_outlined,
                                  label: 'Active Goals',
                                  value: '$goalCount',
                                ),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Step 2: Inbox & Stale Items',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Review items in your Inbox Tray and reorganize open tasks.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Step 3: Weekly Reflection',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'What went well this week? What can be improved next week?',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: TextField(
                                controller: _reflectionController,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Write your reflection notes here...',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentStep > 0)
                        OutlinedButton(
                          onPressed: () => setState(() => _currentStep--),
                          child: const Text('Back'),
                        )
                      else
                        const SizedBox.shrink(),
                      ElevatedButton(
                        onPressed: () {
                          if (_currentStep < 2) {
                            setState(() => _currentStep++);
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                        child: Text(
                          _currentStep == 2 ? 'Complete Review' : 'Next Step',
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => ErrorMessage(
              message: 'Failed to initialize review',
              onRetry: () => ref.invalidate(allMindmapNodesProvider),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

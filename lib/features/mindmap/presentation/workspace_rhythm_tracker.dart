/// Interactive Workspace Context Switcher & Daily Energy/Workload Rhythm Tracker.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../domain/mindmap_node.dart';
import '../domain/workspace_context.dart';

final activeWorkspaceContextFilterProvider = StateProvider<WorkspaceContext?>(
  (ref) => null,
);

class WorkspaceRhythmTracker extends ConsumerWidget {
  const WorkspaceRhythmTracker({
    required this.workspaceContexts,
    required this.nodes,
    super.key,
  });

  final List<WorkspaceContext> workspaceContexts;
  final List<MindmapNode> nodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final activeContext = ref.watch(activeWorkspaceContextFilterProvider);

    // Compute energy/workload breakdown (Pagi: 6-12, Siang: 12-18, Malam: 18-24)
    var morningTaskCount = 0;
    var afternoonTaskCount = 0;
    var eveningTaskCount = 0;

    final targetNodes = activeContext != null ? activeContext.nodes : nodes;

    for (final node in targetNodes) {
      if (node.isArchived) continue;
      final hour = node.createdAt.hour;
      if (hour >= 6 && hour < 12) {
        morningTaskCount++;
      } else if (hour >= 12 && hour < 18) {
        afternoonTaskCount++;
      } else {
        eveningTaskCount++;
      }
    }

    final totalCount = morningTaskCount + afternoonTaskCount + eveningTaskCount;
    final maxCount = [
      morningTaskCount,
      afternoonTaskCount,
      eveningTaskCount,
    ].reduce((a, b) => a > b ? a : b);

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
                Icons.insights_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Ritme Energi & Ruang Kerja',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (activeContext != null)
                TextButton.icon(
                  icon: const Icon(Icons.clear, size: 14),
                  label: const Text(
                    'Reset Konteks',
                    style: TextStyle(fontSize: 12),
                  ),
                  onPressed: () {
                    ref
                            .read(activeWorkspaceContextFilterProvider.notifier)
                            .state =
                        null;
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Pilih Ruang Kerja:',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Semua Konteks'),
                  selected: activeContext == null,
                  onSelected: (selected) {
                    if (selected) {
                      ref
                              .read(
                                activeWorkspaceContextFilterProvider.notifier,
                              )
                              .state =
                          null;
                    }
                  },
                ),
                const SizedBox(width: 8),
                ...workspaceContexts.map((ctx) {
                  final isSelected =
                      activeContext?.name == ctx.name &&
                      activeContext?.type == ctx.type;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(
                        ctx.type == WorkspaceContextType.project
                            ? Icons.folder_outlined
                            : Icons.workspaces_outline,
                        size: 14,
                      ),
                      label: Text('${ctx.name} (${ctx.activeNodeCount})'),
                      selected: isSelected,
                      onSelected: (selected) {
                        ref
                            .read(activeWorkspaceContextFilterProvider.notifier)
                            .state = selected
                            ? ctx
                            : null;
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Distribusi Beban Kerja Harian:',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _RhythmSlotBar(
                slotLabel: 'Pagi (06-12)',
                count: morningTaskCount,
                maxCount: maxCount,
                color: semantic.info,
              ),
              const SizedBox(width: 12),
              _RhythmSlotBar(
                slotLabel: 'Siang (12-18)',
                count: afternoonTaskCount,
                maxCount: maxCount,
                color: semantic.warning,
              ),
              const SizedBox(width: 12),
              _RhythmSlotBar(
                slotLabel: 'Malam (18-24)',
                count: eveningTaskCount,
                maxCount: maxCount,
                color: semantic.accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Total $totalCount node aktif terdistribusi pada ruang kerja ini.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RhythmSlotBar extends StatelessWidget {
  const _RhythmSlotBar({
    required this.slotLabel,
    required this.count,
    required this.maxCount,
    required this.color,
  });

  final String slotLabel;
  final int count;
  final int maxCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final factor = maxCount > 0 ? (count / maxCount).clamp(0.1, 1.0) : 0.1;

    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: color.withValues(alpha: 0.15),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: factor,
                widthFactor: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: color,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            slotLabel,
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

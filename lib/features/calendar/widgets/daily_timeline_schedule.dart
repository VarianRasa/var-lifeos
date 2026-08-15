import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/theme/node_visuals.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/application/mindmap_mutation_controller.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../../mindmap/domain/canvas_position.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/mindmap_node_data.dart';
import '../domain/calendar_node_payload.dart';
import '../domain/time_block.dart';

class DailyTimelineSchedule extends ConsumerStatefulWidget {
  const DailyTimelineSchedule({
    required this.day,
    required this.nodes,
    required this.onNodeSelected,
    required this.onTaskDoneChanged,
    super.key,
  });

  final DateTime day;
  final List<MindmapNode> nodes;
  final ValueChanged<MindmapNode> onNodeSelected;
  final void Function(MindmapNode, bool) onTaskDoneChanged;

  @override
  ConsumerState<DailyTimelineSchedule> createState() =>
      _DailyTimelineScheduleState();
}

class _DailyTimelineScheduleState extends ConsumerState<DailyTimelineSchedule> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final today = ref.read(currentDateProvider);
        final initialMinute = widget.day.isSameDay(today)
            ? (DateTime.now().hour * 60 + DateTime.now().minute)
            : 420;
        final scrollTarget = (initialMinute / 60.0) * _hourHeight - 120;
        _scrollController.jumpTo(scrollTarget.clamp(0.0, 24 * _hourHeight));
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showScheduleDialog(BuildContext context, int hour, int minute) {
    final theme = Theme.of(context);
    final unscheduledNodes = widget.nodes.where((node) {
      return timeBlockForNode(node).isUnscheduled;
    }).toList();

    int selectedDurationMinutes = 60;
    const selectedNodeType = NodeType.task;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Schedule Slot: ${formatTimeOfDay(hour * 60 + minute)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preset Durasi Time Block:',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [15, 30, 60, 90, 120].map((dur) {
                          final isSelected = selectedDurationMinutes == dur;
                          final label = dur >= 60
                              ? '${dur / 60} Jam'
                              : '$dur Menit';
                          return ChoiceChip(
                            label: Text(label),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) {
                                setDialogState(
                                  () => selectedDurationMinutes = dur,
                                );
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Pilih Node Unscheduled / Buat Baru:',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (unscheduledNodes.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Tidak ada node unscheduled. Pilih durasi dan klik "Buat Task Baru" di bawah.',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: unscheduledNodes.length,
                            itemBuilder: (ctx, index) {
                              final node = unscheduledNodes[index];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  NodeVisuals.icon(node.type),
                                  color: NodeVisuals.color(context, node.type),
                                ),
                                title: Text(
                                  node.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(_nodeSubtitle(node)),
                                onTap: () async {
                                  final startMinute = hour * 60 + minute;
                                  final endMinute =
                                      (startMinute + selectedDurationMinutes)
                                          .clamp(1, 1440);
                                  final updated = await ref
                                      .read(mindmapMutationControllerProvider)
                                      .scheduleNode(
                                        node,
                                        TimeBlock(
                                          startMinute: startMinute,
                                          endMinute: endMinute,
                                        ),
                                      );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  widget.onNodeSelected(updated);
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final startMinute = hour * 60 + minute;
                    final endMinute = (startMinute + selectedDurationMinutes)
                        .clamp(1, 1440);
                    final now = DateTime.now();
                    final newTask = MindmapNode(
                      id: const Uuid().v4(),
                      type: selectedNodeType,
                      title: 'Scheduled Task',
                      day: widget.day.dateOnly,
                      createdAt: now,
                      updatedAt: now,
                      position: const CanvasPosition(200, 200),
                      data: dataWithTimeBlock(
                        const {},
                        TimeBlock(
                          startMinute: startMinute,
                          endMinute: endMinute,
                        ),
                      ),
                    );

                    final saved = await ref
                        .read(mindmapMutationControllerProvider)
                        .saveNode(newTask);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      widget.onNodeSelected(saved);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: Text('Buat Slot (${selectedDurationMinutes}m)'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _autoResolveConflicts(
    List<_TimelineEntry> scheduledEntries,
  ) async {
    final dayBlocks = [
      for (final entry in scheduledEntries)
        DayTimeBlock(
          id: entry.node.id,
          block: entry.block,
          isHighPriority:
              entry.node.priority == NodePriority.high ||
              entry.node.priority == NodePriority.urgent,
          isDone: entry.node.isDone || entry.node.status == NodeStatus.done,
        ),
    ];

    final resolved = autoResolveConflicts(dayBlocks);
    if (resolved.isEmpty) return;

    final controller = ref.read(mindmapMutationControllerProvider);
    for (final entry in scheduledEntries) {
      if (resolved.containsKey(entry.node.id)) {
        await controller.scheduleNode(entry.node, resolved[entry.node.id]!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppDesignTokens.of(context);
    final parsedNodes = _ParsedTimelineNodes.fromNodes(widget.nodes);
    final scheduledEntries = _layoutOverlaps(parsedNodes.scheduled);
    final conflicts = detectTimeBlockConflicts([
      for (final entry in parsedNodes.scheduled)
        DayTimeBlock(
          id: entry.node.id,
          block: entry.block,
          isHighPriority:
              entry.node.priority == NodePriority.high ||
              entry.node.priority == NodePriority.urgent,
          isDone: entry.node.isDone || entry.node.status == NodeStatus.done,
        ),
    ]);
    final conflictingNodeIds = {
      for (final conflict in conflicts) ...conflict.nodeIds,
    };
    final today = ref.watch(currentDateProvider);
    final showNowMarker = widget.day.isSameDay(today);
    final now = DateTime.now();
    final nowMinute = now.hour * 60 + now.minute;

    final totalScheduledMinutes = scheduledEntries.fold<int>(
      0,
      (sum, entry) => sum + entry.block.durationMinutes,
    );
    final totalHoursLabel = (totalScheduledMinutes / 60.0).toStringAsFixed(1);
    final workloadCapacityPercent = ((totalScheduledMinutes / 480.0) * 100)
        .clamp(0, 100)
        .toInt();

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dynamic Workload & Capacity Bar Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh.withValues(
                  alpha: 0.6,
                ),
                borderRadius: BorderRadius.circular(tokens.radiusContainer),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Daily Workload: ${totalHoursLabel}h scheduled',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (totalScheduledMinutes / 480.0).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        color: workloadCapacityPercent > 100
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$workloadCapacityPercent% of 8h',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (parsedNodes.invalid.isNotEmpty)
            _NodeLane(
              key: const ValueKey('timeline-invalid-lane'),
              icon: Icons.warning_amber_outlined,
              title: 'Invalid schedule',
              nodes: parsedNodes.invalid,
              onNodeSelected: widget.onNodeSelected,
            ),
          if (parsedNodes.unscheduled.isNotEmpty)
            _NodeLane(
              key: const ValueKey('timeline-unscheduled-lane'),
              icon: Icons.inbox_outlined,
              title: 'Unscheduled',
              nodes: parsedNodes.unscheduled,
              onNodeSelected: widget.onNodeSelected,
              onScheduleNext: _scheduleNextAvailable,
            ),
          if (conflicts.isNotEmpty)
            _ConflictLane(
              key: const ValueKey('timeline-conflict-lane'),
              conflicts: conflicts,
              nodesById: {for (final node in widget.nodes) node.id: node},
              onAutoResolve: () => _autoResolveConflicts(scheduledEntries),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: _timelineWidth,
                height: 24 * _hourHeight,
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    end: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
                child: Stack(
                  children: [
                    for (int i = 0; i < 24; i++)
                      Positioned(
                        top: i * _hourHeight,
                        left: 0,
                        right: 8,
                        child: Text(
                          '${i.toString().padLeft(2, '0')}:00',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 6.0;

                    return SizedBox(
                      height: 24 * _hourHeight,
                      child: Stack(
                        children: [
                          for (int i = 0; i < 24; i++)
                            Positioned(
                              top: i * _hourHeight + 8.0,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 1,
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                          Positioned.fill(
                            child: DragTarget<MindmapNode>(
                              onAcceptWithDetails: (details) {
                                final box =
                                    context.findRenderObject() as RenderBox?;
                                if (box == null) return;
                                final localOffset = box.globalToLocal(
                                  details.offset,
                                );
                                final slot = _slotFromDy(localOffset.dy);
                                if (slot == null) return;
                                _scheduleAt(
                                  details.data,
                                  slot.startMinute,
                                  slot.endMinute,
                                );
                              },
                              builder: (context, candidateData, rejectedData) {
                                return GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTapUp: (details) {
                                    final slot = _slotFromDy(
                                      details.localPosition.dy,
                                    );
                                    if (slot == null) return;
                                    _showScheduleDialog(
                                      context,
                                      slot.startMinute ~/ 60,
                                      slot.startMinute % 60,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          if (showNowMarker)
                            Positioned(
                              key: const ValueKey('timeline-now-marker'),
                              top: (nowMinute / 60.0) * _hourHeight + 8.0,
                              left: 0,
                              right: 0,
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.error,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 2,
                                      color: theme.colorScheme.error.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (final entry in scheduledEntries)
                            (() {
                              final laneUnit =
                                  constraints.maxWidth / entry.columnCount;
                              final leftItem =
                                  12.0 + entry.column * laneUnit + gap;
                              final rightItem =
                                  (entry.columnCount - 1 - entry.column) *
                                      laneUnit +
                                  gap;
                              return Positioned(
                                key: ValueKey(
                                  'timeline-entry-${entry.node.id}',
                                ),
                                top:
                                    (entry.block.startMinute / 60.0) *
                                        _hourHeight +
                                    8.0,
                                height:
                                    ((entry.block.durationMinutes / 60.0) *
                                            _hourHeight)
                                        .clamp(28.0, 24 * _hourHeight),
                                left: leftItem,
                                right: rightItem,
                                child: _TimelineNodeCard(
                                  entry: entry,
                                  hasConflict: conflictingNodeIds.contains(
                                    entry.node.id,
                                  ),
                                  onNodeSelected: widget.onNodeSelected,
                                  onTaskDoneChanged: widget.onTaskDoneChanged,
                                  onUnschedule: () => _unschedule(entry.node),
                                  onExtend: () =>
                                      _extend(entry.node, entry.block),
                                ),
                              );
                            }()),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _unschedule(MindmapNode node) async {
    await ref.read(mindmapMutationControllerProvider).unscheduleNode(node);
  }

  Future<void> _scheduleAt(
    MindmapNode node,
    int startMinute,
    int endMinute,
  ) async {
    final updated = await ref
        .read(mindmapMutationControllerProvider)
        .scheduleNode(
          node,
          TimeBlock(startMinute: startMinute, endMinute: endMinute),
        );
    widget.onNodeSelected(updated);
  }

  Future<void> _extend(MindmapNode node, TimeBlock block) async {
    final nextEnd = (block.endMinute + 15).clamp(block.startMinute + 1, 1440);
    await ref
        .read(mindmapMutationControllerProvider)
        .scheduleNode(
          node,
          TimeBlock(startMinute: block.startMinute, endMinute: nextEnd),
        );
  }

  Future<void> _scheduleNextAvailable(MindmapNode node) async {
    final parsedNodes = _ParsedTimelineNodes.fromNodes(widget.nodes);
    final startMinute = _nextAvailableStart(parsedNodes.scheduled);
    final block = TimeBlock(
      startMinute: startMinute,
      endMinute: (startMinute + 60).clamp(startMinute + 1, 1440),
    );
    final updated = await ref
        .read(mindmapMutationControllerProvider)
        .scheduleNode(node, block);
    widget.onNodeSelected(updated);
  }
}

class _TimelineNodeCard extends StatelessWidget {
  const _TimelineNodeCard({
    required this.entry,
    required this.hasConflict,
    required this.onNodeSelected,
    required this.onTaskDoneChanged,
    required this.onUnschedule,
    required this.onExtend,
  });

  final _TimelineEntry entry;
  final bool hasConflict;
  final ValueChanged<MindmapNode> onNodeSelected;
  final void Function(MindmapNode, bool) onTaskDoneChanged;
  final VoidCallback onUnschedule;
  final VoidCallback onExtend;

  @override
  Widget build(BuildContext context) {
    final node = entry.node;
    final block = entry.block;
    final theme = Theme.of(context);
    final tokens = AppDesignTokens.of(context);
    final color = NodeVisuals.color(context, node.type);
    final isDone = node.isDone || node.status == NodeStatus.done;
    final borderColor = hasConflict ? theme.colorScheme.error : color;
    final stateLabel = isDone
        ? 'Done'
        : hasConflict
        ? 'Conflict'
        : 'Scheduled';
    final stateColor = isDone
        ? theme.colorScheme.tertiary
        : hasConflict
        ? theme.colorScheme.error
        : color;
    final height = (block.durationMinutes / 60.0) * _hourHeight;

    return Semantics(
      button: true,
      label: '${node.title}, ${block.rangeLabel}, $stateLabel',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusElement),
        child: InkWell(
          onTap: () => onNodeSelected(node),
          child: Container(
            constraints: BoxConstraints(minHeight: tokens.minimumTarget),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDone
                  ? theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.35,
                    )
                  : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(tokens.radiusElement),
              border: Border.all(
                color: borderColor.withValues(alpha: hasConflict ? 0.9 : 0.6),
                width: hasConflict ? 2 : 1.5,
              ),
            ),
            child: Row(
              children: [
                if (node.type == NodeType.task || node.type == NodeType.habit)
                  Transform.scale(
                    scale: 0.8,
                    child: Checkbox(
                      value: node.isDone,
                      activeColor: color,
                      onChanged: (val) {
                        if (val != null) onTaskDoneChanged(node, val);
                      },
                    ),
                  ),
                Icon(NodeVisuals.icon(node.type), size: 16, color: color),
                if (hasConflict) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.report_problem_outlined,
                    key: ValueKey('timeline-conflict-icon-${node.id}'),
                    size: 15,
                    color: theme.colorScheme.error,
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        node.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: height < 40 ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (height >= 40)
                        Text(
                          '${block.rangeLabel} • ${_nodeSubtitle(node)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (height >= 52)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: stateColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: stateColor.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              child: Text(
                                stateLabel,
                                key: ValueKey(
                                  'timeline-state-${node.id}-$stateLabel',
                                ),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: stateColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Schedule actions',
                  icon: const Icon(Icons.more_vert, size: 16),
                  onSelected: (value) {
                    switch (value) {
                      case 'extend':
                        onExtend();
                      case 'clear':
                        onUnschedule();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'extend', child: Text('Extend 15m')),
                    PopupMenuItem(
                      value: 'clear',
                      child: Text('Clear schedule'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeLane extends StatelessWidget {
  const _NodeLane({
    super.key,
    required this.icon,
    required this.title,
    required this.nodes,
    required this.onNodeSelected,
    this.onScheduleNext,
  });

  final IconData icon;
  final String title;
  final List<MindmapNode> nodes;
  final ValueChanged<MindmapNode> onNodeSelected;
  final ValueChanged<MindmapNode>? onScheduleNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '$title (${nodes.length})',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final node in nodes)
                    Draggable<MindmapNode>(
                      data: node,
                      feedback: Material(
                        color: Colors.transparent,
                        child: Chip(
                          avatar: Icon(NodeVisuals.icon(node.type), size: 16),
                          label: Text(node.title),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.45,
                        child: _ScheduleNodeChip(
                          node: node,
                          onNodeSelected: onNodeSelected,
                          onScheduleNext: onScheduleNext,
                        ),
                      ),
                      child: _ScheduleNodeChip(
                        node: node,
                        onNodeSelected: onNodeSelected,
                        onScheduleNext: onScheduleNext,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleNodeChip extends StatelessWidget {
  const _ScheduleNodeChip({
    required this.node,
    required this.onNodeSelected,
    required this.onScheduleNext,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onNodeSelected;
  final ValueChanged<MindmapNode>? onScheduleNext;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(
        NodeVisuals.icon(node.type),
        size: 16,
        color: NodeVisuals.color(context, node.type),
      ),
      label: Text(node.title),
      onPressed: () => onNodeSelected(node),
      onDeleted: onScheduleNext == null ? null : () => onScheduleNext!(node),
      deleteIcon: const Icon(Icons.schedule_send_outlined),
      deleteButtonTooltipMessage: 'Schedule next available',
    );
  }
}

class _ConflictLane extends StatelessWidget {
  const _ConflictLane({
    super.key,
    required this.conflicts,
    required this.nodesById,
    required this.onAutoResolve,
  });

  final List<TimeBlockConflict> conflicts;
  final Map<String, MindmapNode> nodesById;
  final VoidCallback onAutoResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.report_problem_outlined, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Schedule conflicts (${conflicts.length})',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: theme.colorScheme.onError,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onAutoResolve,
                    icon: const Icon(Icons.auto_fix_high, size: 14),
                    label: const Text(
                      'Auto-Shift Conflicts',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final conflict in conflicts.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${_conflictLabel(conflict)} · ${conflict.rangeLabel} · ${_conflictNodeTitles(conflict, nodesById)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ParsedTimelineNodes {
  const _ParsedTimelineNodes({
    required this.scheduled,
    required this.unscheduled,
    required this.invalid,
  });

  factory _ParsedTimelineNodes.fromNodes(List<MindmapNode> nodes) {
    final scheduled = <_TimelineEntry>[];
    final unscheduled = <MindmapNode>[];
    final invalid = <MindmapNode>[];

    for (final node in nodes) {
      final parsed = timeBlockForNode(node);
      if (parsed.isValid) {
        scheduled.add(_TimelineEntry(node: node, block: parsed.block!));
      } else if (parsed.isInvalid) {
        invalid.add(node);
      } else {
        unscheduled.add(node);
      }
    }

    scheduled.sort((a, b) {
      final byStart = a.block.startMinute.compareTo(b.block.startMinute);
      if (byStart != 0) return byStart;
      return a.node.title.compareTo(b.node.title);
    });
    return _ParsedTimelineNodes(
      scheduled: scheduled,
      unscheduled: unscheduled,
      invalid: invalid,
    );
  }

  final List<_TimelineEntry> scheduled;
  final List<MindmapNode> unscheduled;
  final List<MindmapNode> invalid;
}

final class _TimelineEntry {
  const _TimelineEntry({
    required this.node,
    required this.block,
    this.column = 0,
    this.columnCount = 1,
  });

  final MindmapNode node;
  final TimeBlock block;
  final int column;
  final int columnCount;

  _TimelineEntry copyWith({int? column, int? columnCount}) {
    return _TimelineEntry(
      node: node,
      block: block,
      column: column ?? this.column,
      columnCount: columnCount ?? this.columnCount,
    );
  }
}

List<_TimelineEntry> _layoutOverlaps(List<_TimelineEntry> entries) {
  final laidOut = <_TimelineEntry>[];
  var index = 0;
  while (index < entries.length) {
    final group = <_TimelineEntry>[entries[index]];
    var groupEnd = entries[index].block.endMinute;
    var cursor = index + 1;
    while (cursor < entries.length &&
        entries[cursor].block.startMinute < groupEnd) {
      group.add(entries[cursor]);
      if (entries[cursor].block.endMinute > groupEnd) {
        groupEnd = entries[cursor].block.endMinute;
      }
      cursor++;
    }

    final columnEnds = <int>[];
    final assigned = <_TimelineEntry>[];
    for (final entry in group) {
      var column = columnEnds.indexWhere(
        (end) => end <= entry.block.startMinute,
      );
      if (column == -1) {
        column = columnEnds.length;
        columnEnds.add(entry.block.endMinute);
      } else {
        columnEnds[column] = entry.block.endMinute;
      }
      assigned.add(entry.copyWith(column: column));
    }

    final columnCount = columnEnds.length.clamp(1, group.length);
    laidOut.addAll([
      for (final entry in assigned) entry.copyWith(columnCount: columnCount),
    ]);
    index = cursor;
  }
  return laidOut;
}

final class _TimelineSlot {
  const _TimelineSlot({required this.startMinute, required this.endMinute});

  final int startMinute;
  final int endMinute;
}

_TimelineSlot? _slotFromDy(double dy) {
  final adjusted = dy - 8.0;
  if (adjusted < 0) return null;
  final hour = adjusted ~/ _hourHeight;
  if (hour < 0 || hour >= 24) return null;
  final subHourY = adjusted % _hourHeight;
  final minute = subHourY >= (_hourHeight / 2) ? 30 : 0;
  final startMinute = (hour * 60) + minute;
  return _TimelineSlot(
    startMinute: startMinute,
    endMinute: (startMinute + 60).clamp(startMinute + 1, 1440),
  );
}

int _nextAvailableStart(List<_TimelineEntry> scheduled) {
  const dayStart = 8 * 60;
  const dayEnd = 18 * 60;
  const duration = 60;
  final sorted = [...scheduled]
    ..sort((a, b) => a.block.startMinute.compareTo(b.block.startMinute));

  for (var start = dayStart; start + duration <= dayEnd; start += 30) {
    final end = start + duration;
    final hasOverlap = sorted.any(
      (entry) => start < entry.block.endMinute && end > entry.block.startMinute,
    );
    if (!hasOverlap) return start;
  }

  return dayStart;
}

String _conflictLabel(TimeBlockConflict conflict) {
  switch (conflict.type) {
    case TimeBlockConflictType.overlap:
      return 'Overlap';
    case TimeBlockConflictType.highPriorityOverload:
      return 'High-priority overload';
  }
}

String _conflictNodeTitles(
  TimeBlockConflict conflict,
  Map<String, MindmapNode> nodesById,
) {
  return conflict.nodeIds
      .map((id) => nodesById[id]?.title.trim() ?? id)
      .join(' / ');
}

String _nodeSubtitle(MindmapNode node) {
  final payload = calendarNodePayloadFromData(node.data);
  if (payload != null) return payload.subtitle;
  return node.type.label;
}

const _hourHeight = 60.0;
const _timelineWidth = 60.0;

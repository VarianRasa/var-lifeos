import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/application/mindmap_mutation_controller.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../../mindmap/domain/canvas_position.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/mindmap_node_data.dart';
import '../../mindmap/presentation/mindmap_canvas.dart'; // for nodeIcon, nodeColor
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

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            'Schedule Slot: ${formatTimeOfDay(hour * 60 + minute)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 340,
            child: unscheduledNodes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 36,
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No unscheduled nodes for today.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create one in the palette on the left or save a new scheduled task directly.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: unscheduledNodes.length,
                    itemBuilder: (ctx, index) {
                      final node = unscheduledNodes[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          nodeIcon(node.type),
                          color: nodeColor(node.type),
                        ),
                        title: Text(
                          node.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(_nodeSubtitle(node)),
                        onTap: () async {
                          final updated = await ref
                              .read(mindmapMutationControllerProvider)
                              .scheduleNode(
                                node,
                                TimeBlock(
                                  startMinute: hour * 60 + minute,
                                  endMinute:
                                      ((hour + 1).clamp(0, 24) * 60) + minute,
                                ),
                              );
                          if (ctx.mounted) Navigator.pop(ctx);
                          widget.onNodeSelected(updated);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            if (unscheduledNodes.isEmpty)
              FilledButton.icon(
                onPressed: () async {
                  final startMinute = hour * 60 + minute;
                  final endMinute = (startMinute + 60).clamp(1, 1440);
                  final now = DateTime.now();
                  final newTask = MindmapNode(
                    id: const Uuid().v4(),
                    type: NodeType.task,
                    title: 'Scheduled Task',
                    day: widget.day.dateOnly,
                    createdAt: now,
                    updatedAt: now,
                    position: const CanvasPosition(200, 200),
                    data: dataWithTimeBlock(
                      const {},
                      TimeBlock(startMinute: startMinute, endMinute: endMinute),
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
                label: const Text('Create Task'),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsedNodes = _ParsedTimelineNodes.fromNodes(widget.nodes);
    final scheduledEntries = _layoutOverlaps(parsedNodes.scheduled);
    final today = ref.watch(currentDateProvider);
    final showNowMarker = widget.day.isSameDay(today);
    final now = DateTime.now();
    final nowMinute = now.hour * 60 + now.minute;

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: _timelineWidth,
                height: 24 * _hourHeight,
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
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
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTapUp: (details) {
                                final localOffset = details.localPosition;
                                final hour =
                                    (localOffset.dy - 8.0) ~/ _hourHeight;
                                if (hour >= 0 && hour < 24) {
                                  final subHourY =
                                      (localOffset.dy - 8.0) % _hourHeight;
                                  final minute = subHourY >= (_hourHeight / 2)
                                      ? 30
                                      : 0;
                                  _showScheduleDialog(context, hour, minute);
                                }
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
                                  onNodeSelected: widget.onNodeSelected,
                                  onTaskDoneChanged: widget.onTaskDoneChanged,
                                  onUnschedule: () => _unschedule(entry.node),
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
}

class _TimelineNodeCard extends StatelessWidget {
  const _TimelineNodeCard({
    required this.entry,
    required this.onNodeSelected,
    required this.onTaskDoneChanged,
    required this.onUnschedule,
  });

  final _TimelineEntry entry;
  final ValueChanged<MindmapNode> onNodeSelected;
  final void Function(MindmapNode, bool) onTaskDoneChanged;
  final VoidCallback onUnschedule;

  @override
  Widget build(BuildContext context) {
    final node = entry.node;
    final block = entry.block;
    final theme = Theme.of(context);
    final color = nodeColor(node.type);
    final height = (block.durationMinutes / 60.0) * _hourHeight;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => onNodeSelected(node),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
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
              Icon(nodeIcon(node.type), size: 16, color: color),
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
                        decoration: node.isDone
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
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.8,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                visualDensity: VisualDensity.compact,
                tooltip: 'Unschedule',
                onPressed: onUnschedule,
              ),
            ],
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
  });

  final IconData icon;
  final String title;
  final List<MindmapNode> nodes;
  final ValueChanged<MindmapNode> onNodeSelected;

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
                    ActionChip(
                      avatar: Icon(
                        nodeIcon(node.type),
                        size: 16,
                        color: nodeColor(node.type),
                      ),
                      label: Text(node.title),
                      onPressed: () => onNodeSelected(node),
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

String _nodeSubtitle(MindmapNode node) {
  final payload = calendarNodePayloadFromData(node.data);
  if (payload != null) return payload.subtitle;
  return node.type.label;
}

const _hourHeight = 60.0;
const _timelineWidth = 60.0;

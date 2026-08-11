import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../calendar/application/focus_session.dart';
import '../../../focus/application/focus_audio_player_service.dart';
import '../../application/focus_timer_provider.dart';
import '../../data/canvas_export_stub.dart'
    if (dart.library.io) '../../data/canvas_export_io.dart'
    if (dart.library.html) '../../data/canvas_export_web.dart';
import '../../domain/hybrid_timer.dart';
import '../../domain/kanban_board.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_mini_app_data.dart';
import '../../domain/node_type_payloads.dart';
import '../../domain/project_plan.dart';
import 'node_mini_app_common.dart';

Widget? buildProductivityMiniApp({
  required MindmapNode node,
  required ValueChanged<MindmapNode> onChanged,
  required Widget editor,
}) => switch (node.type) {
  NodeType.task => TaskMiniApp(
    node: node,
    onChanged: onChanged,
    editor: editor,
  ),
  NodeType.kanban => KanbanMiniApp(
    node: node,
    onChanged: onChanged,
    editor: editor,
  ),
  NodeType.plan => PlanMiniApp(
    node: node,
    onChanged: onChanged,
    editor: editor,
  ),
  NodeType.timer => TimerMiniApp(
    node: node,
    onChanged: onChanged,
    editor: editor,
  ),
  _ => null,
};

class TaskMiniApp extends ConsumerWidget {
  const TaskMiniApp({
    required this.node,
    required this.onChanged,
    required this.editor,
    super.key,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onChanged;
  final Widget editor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = nodeMiniAppSection(node, 'task');
    final important = section['important'] == true;
    final urgent = section['urgent'] == true;
    final actualMinutes = totalFocusMinutes(node);
    final estimate = switch (node.effort) {
      NodeEffort.fiveMinutes => 5,
      NodeEffort.fifteenMinutes => 15,
      NodeEffort.thirtyMinutes => 30,
      NodeEffort.oneHourPlus => 60,
      NodeEffort.unspecified => 0,
    };
    final quadrant = switch ((urgent, important)) {
      (true, true) => ('Do now', Icons.flash_on, Colors.red),
      (false, true) => ('Schedule', Icons.calendar_month, Colors.blue),
      (true, false) => ('Delegate', Icons.group, Colors.orange),
      _ => ('Eliminate', Icons.delete_sweep, Colors.grey),
    };
    final focus = ref.watch(focusTimerProvider);
    final focusNotifier = ref.read(focusTimerProvider.notifier);
    final ownsFocusTimer = focus.selectedNodeId == node.id;

    return _MiniAppScroll(
      children: [
        MiniAppSection(
          title: 'Task command center',
          subtitle: 'Prioritize, estimate, and track focused work.',
          icon: Icons.task_alt,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Urgent'),
                    avatar: const Icon(Icons.schedule, size: 18),
                    selected: urgent,
                    onSelected: (selected) => onChanged(
                      updateNodeMiniAppSection(node, 'task', <String, Object?>{
                        'urgent': selected,
                      }),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Important'),
                    avatar: const Icon(Icons.star_outline, size: 18),
                    selected: important,
                    onSelected: (selected) => onChanged(
                      updateNodeMiniAppSection(node, 'task', <String, Object?>{
                        'important': selected,
                      }),
                    ),
                  ),
                  Chip(
                    avatar: Icon(quadrant.$2, color: quadrant.$3),
                    label: Text('Matrix: ${quadrant.$1}'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _TaskEisenhowerMatrix(urgent: urgent, important: important),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MiniAppStat(
                    label: 'Subtasks',
                    value:
                        '${node.completedChecklistCount}/${node.checklist.length}',
                    icon: Icons.checklist,
                  ),
                  MiniAppStat(
                    label: 'Focused',
                    value: '$actualMinutes min',
                    icon: Icons.timer_outlined,
                  ),
                  MiniAppStat(
                    label: 'Estimate',
                    value: estimate == 0 ? 'Unset' : '$estimate min',
                    icon: Icons.hourglass_bottom,
                  ),
                  MiniAppStat(
                    label: 'Blockers',
                    value: '${node.blockedByNodeIds.length}',
                    icon: Icons.account_tree_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              MiniAppProgressMeter(
                label: 'Task completion',
                value: node.checklist.isEmpty
                    ? node.progress
                    : node.checklistProgress,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('task-focus-timer-toggle'),
                    onPressed: () {
                      if (!ownsFocusTimer) {
                        focusNotifier.selectNode(node.id, node.title);
                        if (!focus.isRunning) focusNotifier.start();
                      } else if (focus.isRunning) {
                        focusNotifier.pause();
                      } else {
                        focusNotifier.start();
                      }
                    },
                    icon: Icon(
                      ownsFocusTimer && focus.isRunning
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    label: Text(
                      ownsFocusTimer && focus.isRunning
                          ? 'Pause focus'
                          : 'Focus on task',
                    ),
                  ),
                  if (ownsFocusTimer)
                    Semantics(
                      label:
                          'Task focus timer ${focus.remainingSeconds ~/ 60} minutes ${focus.remainingSeconds % 60} seconds',
                      child: Chip(
                        avatar: const Icon(Icons.timer_outlined, size: 18),
                        label: Text(
                          '${(focus.remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(focus.remainingSeconds % 60).toString().padLeft(2, '0')}',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        editor,
      ],
    );
  }
}

class _TaskEisenhowerMatrix extends StatelessWidget {
  const _TaskEisenhowerMatrix({required this.urgent, required this.important});

  final bool urgent;
  final bool important;

  @override
  Widget build(BuildContext context) {
    final selected = switch ((urgent, important)) {
      (true, true) => 0,
      (false, true) => 1,
      (true, false) => 2,
      _ => 3,
    };
    const quadrants = <(String, String, IconData)>[
      ('Do now', 'Urgent · Important', Icons.flash_on),
      ('Schedule', 'Not urgent · Important', Icons.calendar_month),
      ('Delegate', 'Urgent · Not important', Icons.group_outlined),
      ('Eliminate', 'Not urgent · Not important', Icons.delete_sweep_outlined),
    ];
    return Semantics(
      container: true,
      label: 'Eisenhower matrix, selected ${quadrants[selected].$1}',
      child: GridView.count(
        key: const ValueKey('task-eisenhower-matrix'),
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (var index = 0; index < quadrants.length; index++)
            Semantics(
              label:
                  '${quadrants[index].$1}, ${quadrants[index].$2}, ${index == selected ? 'selected' : 'not selected'}',
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: index == selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: index == selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: index == selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(quadrants[index].$3, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            quadrants[index].$1,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            quadrants[index].$2,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class KanbanMiniApp extends StatefulWidget {
  const KanbanMiniApp({
    required this.node,
    required this.onChanged,
    required this.editor,
    super.key,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onChanged;
  final Widget editor;

  @override
  State<KanbanMiniApp> createState() => _KanbanMiniAppState();
}

class _KanbanMiniAppState extends State<KanbanMiniApp> {
  final GlobalKey _exportKey = GlobalKey();
  String _query = '';
  String _priority = 'all';
  String _swimlane = 'none';
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final payload = KanbanPayload.fromNode(widget.node);
    final section = nodeMiniAppSection(widget.node, 'kanban');
    final savedSwimlane = section['swimlane'] as String? ?? 'none';
    if (_swimlane == 'none' && savedSwimlane != 'none') {
      _swimlane = savedSwimlane;
    }
    final limitedColumns = payload.columns
        .where((column) => column.wipLimit != null)
        .toList();
    final overLimitColumns = limitedColumns
        .where(
          (column) =>
              payload.board.cardsFor(column.id).length > column.wipLimit!,
        )
        .toList();
    final filtered = payload.cards.where((card) {
      final queryMatch =
          _query.trim().isEmpty ||
          card.title.toLowerCase().contains(_query.trim().toLowerCase()) ||
          card.labels.any(
            (label) =>
                label.toLowerCase().contains(_query.trim().toLowerCase()),
          );
      return queryMatch &&
          (_priority == 'all' || card.priority.name == _priority);
    }).toList();

    return _MiniAppScroll(
      maxWidth: 1200,
      children: [
        RepaintBoundary(
          key: _exportKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiniAppSection(
                title: 'Board controls',
                subtitle: 'Search cards, enforce WIP, and export board data.',
                icon: Icons.view_kanban_outlined,
                child: Column(
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 280,
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search cards or labels',
                            ),
                            onChanged: (value) =>
                                setState(() => _query = value),
                          ),
                        ),
                        DropdownButton<String>(
                          value: _priority,
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('All priorities'),
                            ),
                            DropdownMenuItem(value: 'low', child: Text('Low')),
                            DropdownMenuItem(
                              value: 'medium',
                              child: Text('Medium'),
                            ),
                            DropdownMenuItem(
                              value: 'high',
                              child: Text('High'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _priority = value ?? 'all'),
                        ),
                        DropdownButton<String>(
                          value: _swimlane,
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'none',
                              child: Text('No swimlanes'),
                            ),
                            DropdownMenuItem(
                              value: 'priority',
                              child: Text('Swimlane: priority'),
                            ),
                            DropdownMenuItem(
                              value: 'label',
                              child: Text('Swimlane: label'),
                            ),
                            DropdownMenuItem(
                              value: 'due',
                              child: Text('Swimlane: due date'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _swimlane = value);
                            widget.onChanged(
                              updateNodeMiniAppSection(
                                widget.node,
                                'kanban',
                                <String, Object?>{'swimlane': value},
                              ),
                            );
                          },
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _copyBoard(
                            context,
                            'JSON',
                            const JsonEncoder.withIndent(
                              '  ',
                            ).convert(<String, Object?>{
                              'title': widget.node.title,
                              'kanban': payload.board.toJson(),
                            }),
                          ),
                          icon: const Icon(Icons.data_object),
                          label: const Text('Copy JSON'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('kanban-copy-csv'),
                          onPressed: () => _copyBoard(
                            context,
                            'CSV',
                            kanbanBoardCsv(payload),
                          ),
                          icon: const Icon(Icons.table_view_outlined),
                          label: const Text('Copy CSV'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('kanban-export-png'),
                          onPressed: _exporting
                              ? null
                              : () => _exportPng(context),
                          icon: _exporting
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.image_outlined),
                          label: const Text('Export PNG'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (limitedColumns.isEmpty)
                      const MiniAppEmptyState(
                        icon: Icons.speed,
                        message:
                            'Set per-column WIP limits in board column menus.',
                      )
                    else
                      Column(
                        children: [
                          for (final column in limitedColumns) ...[
                            MiniAppProgressMeter(
                              label: '${column.title} WIP',
                              value:
                                  payload.board.cardsFor(column.id).length /
                                  column.wipLimit!,
                              detail:
                                  '${payload.board.cardsFor(column.id).length}/${column.wipLimit}',
                              color: overLimitColumns.contains(column)
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${filtered.length} matching cards'),
                    ),
                    if (_query.isNotEmpty ||
                        _priority != 'all' ||
                        _swimlane != 'none')
                      _KanbanSwimlanes(cards: filtered, mode: _swimlane),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              widget.editor,
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _exportPng(BuildContext context) async {
    setState(() => _exporting = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _exportKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('Board preview is unavailable.');
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Board image could not be encoded.');
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final path = await saveCanvasPng(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        'var-kanban-$timestamp.png',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Board PNG saved to $path')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Board PNG export failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _copyBoard(
    BuildContext context,
    String format,
    String value,
  ) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Board $format copied')));
    }
  }
}

String kanbanBoardCsv(KanbanPayload payload) {
  String cell(Object? value) =>
      '"${(value ?? '').toString().replaceAll('"', '""')}"';
  final rows = <String>[
    ['title', 'column', 'priority', 'dueDate', 'labels'].map(cell).join(','),
    for (final card in payload.cards)
      [
        card.title,
        payload.columns
            .where((column) => column.id == card.columnId)
            .firstOrNull
            ?.title,
        card.priority.name,
        card.dueDate?.toIso8601String(),
        card.labels.join('|'),
      ].map(cell).join(','),
  ];
  return rows.join('\n');
}

class _KanbanSwimlanes extends StatelessWidget {
  const _KanbanSwimlanes({required this.cards, required this.mode});

  final List<KanbanCard> cards;
  final String mode;

  @override
  Widget build(BuildContext context) {
    if (mode == 'none') {
      return Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final card in cards) Chip(label: Text(card.title))],
        ),
      );
    }
    final lanes = <String, List<KanbanCard>>{};
    for (final card in cards) {
      final keys = switch (mode) {
        'priority' => <String>[card.priority.label],
        'label' => card.labels.isEmpty ? <String>['Unlabeled'] : card.labels,
        'due' => <String>[
          card.dueDate == null
              ? 'No due date'
              : card.dueDate!.toIso8601String().split('T').first,
        ],
        _ => <String>['All cards'],
      };
      for (final key in keys) {
        (lanes[key] ??= <KanbanCard>[]).add(card);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in lanes.entries) ...[
          const SizedBox(height: 10),
          Text(entry.key, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final card in entry.value) Chip(label: Text(card.title)),
            ],
          ),
        ],
      ],
    );
  }
}

class PlanMiniApp extends StatelessWidget {
  const PlanMiniApp({
    required this.node,
    required this.onChanged,
    required this.editor,
    super.key,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onChanged;
  final Widget editor;

  @override
  Widget build(BuildContext context) {
    final project = PlanPayload.fromNode(node).project;
    final tasks = project.tasks;
    final done = tasks
        .where((task) => task.status == ProjectTaskStatus.done)
        .length;
    final estimate = tasks.fold<int>(
      0,
      (total, task) => total + (task.estimatedMinutes ?? 0),
    );
    final actual = tasks.fold<int>(
      0,
      (total, task) => total + (task.actualMinutes ?? 0),
    );
    final remaining = tasks.length - done;
    final velocity = actual == 0 ? 0 : done / actual;
    final forecastMinutes = velocity == 0 ? 0 : (remaining / velocity).round();

    return _MiniAppScroll(
      maxWidth: 1200,
      children: [
        MiniAppSection(
          title: 'Project timeline',
          subtitle: 'Phase progress and effort forecast from plan tasks.',
          icon: Icons.timeline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MiniAppStat(
                    label: 'Tasks done',
                    value: '$done/${tasks.length}',
                    icon: Icons.task_alt,
                  ),
                  MiniAppStat(
                    label: 'Estimate',
                    value: '$estimate min',
                    icon: Icons.hourglass_top,
                  ),
                  MiniAppStat(
                    label: 'Actual',
                    value: '$actual min',
                    icon: Icons.timer_outlined,
                  ),
                  MiniAppStat(
                    label: 'Forecast left',
                    value: forecastMinutes == 0
                        ? 'Need data'
                        : '$forecastMinutes min',
                    icon: Icons.insights_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (project.phases.isEmpty)
                const MiniAppEmptyState(
                  icon: Icons.timeline,
                  message: 'Add phases and tasks to build timeline.',
                )
              else ...[
                _ProjectGantt(project: project),
                const SizedBox(height: 16),
                for (final phase in project.phases) ...[
                  _PlanPhaseTimeline(phase: phase),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        editor,
      ],
    );
  }
}

class TimerMiniApp extends StatefulWidget {
  const TimerMiniApp({
    required this.node,
    required this.onChanged,
    required this.editor,
    super.key,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onChanged;
  final Widget editor;

  @override
  State<TimerMiniApp> createState() => _TimerMiniAppState();
}

class _TimerMiniAppState extends State<TimerMiniApp> {
  late final Ticker _ticker;
  bool _showAmbientAudio = false;
  bool _isZenFullscreen = false;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(() {
      if (mounted && TimerPayload.fromNode(widget.node).timer.isRunning) {
        setState(() {});
      }
    });
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant TimerMiniApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final running = TimerPayload.fromNode(widget.node).timer.isRunning;
    if (running && !_ticker.isActive) {
      _ticker.start();
    } else if (!running && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _update(HybridTimerState timer) {
    final payload = TimerPayload(timer: timer);
    widget.onChanged(
      widget.node.copyWith(
        data: payload.toData(widget.node.data),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _showZenFullscreen() async {
    setState(() => _isZenFullscreen = true);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) =>
            _TimerZenFullscreen(node: widget.node, onChanged: widget.onChanged),
      ),
    );
    if (mounted) setState(() => _isZenFullscreen = false);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timer = TimerPayload.fromNode(widget.node).timer;
    final seconds = timer.isBounded
        ? timer.remainingSecondsAt(now) ?? 0
        : timer.elapsedSecondsAt(now);
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    final totalFocus = timer.history
        .where((record) => record.segment == FocusSegment.focus)
        .fold<int>(0, (total, record) => total + record.actualSeconds);

    return _MiniAppScroll(
      children: [
        MiniAppSection(
          title: 'Zen focus',
          subtitle: 'Persistent hybrid timer with cycles and session history.',
          icon: Icons.self_improvement,
          child: Column(
            children: [
              Semantics(
                label: 'Timer $minutes minutes $remainder seconds',
                child: Text(
                  '$minutes:$remainder',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              MiniAppProgressMeter(
                label: timer.mode == TimerMode.focus
                    ? '${timer.segment.name} cycle'
                    : timer.mode.name,
                value: timer.progressAt(now),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: timer.isRunning
                        ? () => _update(timer.pause(now))
                        : () => _update(timer.start(now)),
                    icon: Icon(
                      timer.isRunning ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(timer.isRunning ? 'Pause' : 'Start'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _update(timer.reset()),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _update(
                      timer.complete(now, recordId: const Uuid().v4()),
                    ),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Complete'),
                  ),
                  ChoiceChip(
                    label: const Text('Focus'),
                    selected: timer.mode == TimerMode.focus,
                    onSelected: (_) =>
                        _update(timer.reset().copyWith(mode: TimerMode.focus)),
                  ),
                  ChoiceChip(
                    label: const Text('Countdown'),
                    selected: timer.mode == TimerMode.countdown,
                    onSelected: (_) => _update(
                      timer.reset().copyWith(mode: TimerMode.countdown),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Stopwatch'),
                    selected: timer.mode == TimerMode.stopwatch,
                    onSelected: (_) => _update(
                      timer.reset().copyWith(mode: TimerMode.stopwatch),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('timer-zen-fullscreen'),
                    onPressed: _isZenFullscreen ? null : _showZenFullscreen,
                    icon: const Icon(Icons.fullscreen),
                    label: const Text('Fullscreen Zen'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('timer-ambient-audio-toggle'),
                    onPressed: () =>
                        setState(() => _showAmbientAudio = !_showAmbientAudio),
                    icon: Icon(
                      _showAmbientAudio ? Icons.music_off : Icons.music_note,
                    ),
                    label: Text(
                      _showAmbientAudio ? 'Hide ambient' : 'Ambient audio',
                    ),
                  ),
                ],
              ),
              if (_showAmbientAudio) ...[
                const SizedBox(height: 16),
                const _TimerAmbientAudioControls(),
              ],
              const SizedBox(height: 16),
              _TimerFocusBuckets(history: timer.history, now: now),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MiniAppStat(
                    label: 'Sessions',
                    value: '${timer.history.length}',
                    icon: Icons.repeat,
                  ),
                  MiniAppStat(
                    label: 'Focus time',
                    value: '${totalFocus ~/ 60} min',
                    icon: Icons.center_focus_strong,
                  ),
                  MiniAppStat(
                    label: 'Distractions',
                    value:
                        '${timer.history.fold<int>(0, (sum, item) => sum + item.distractions.length)}',
                    icon: Icons.notifications_off_outlined,
                  ),
                  MiniAppStat(
                    label: 'Cycle',
                    value: '${timer.completedCycles}/${timer.cycleTarget}',
                    icon: Icons.loop,
                  ),
                ],
              ),
              if (timer.history.isNotEmpty) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recent sessions',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final record in timer.history.take(5))
                  ListTile(
                    leading: Icon(
                      record.completed
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                    ),
                    title: Text(
                      record.label.isEmpty ? record.mode.name : record.label,
                    ),
                    subtitle: Text(
                      '${record.actualSeconds ~/ 60} min · ${record.completedAt.toLocal()}',
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        widget.editor,
      ],
    );
  }
}

Map<DateTime, int> timerFocusSecondsByLocalDay(
  Iterable<TimerSessionRecord> history,
) {
  final totals = <DateTime, int>{};
  for (final record in history) {
    if (record.segment != FocusSegment.focus) continue;
    final completedAt = record.completedAt.toLocal();
    final day = DateTime(completedAt.year, completedAt.month, completedAt.day);
    totals[day] = (totals[day] ?? 0) + record.actualSeconds;
  }
  return totals;
}

class _TimerFocusBuckets extends StatelessWidget {
  const _TimerFocusBuckets({required this.history, required this.now});

  final List<TimerSessionRecord> history;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final dayStart = today.subtract(const Duration(days: 6));
    final weekStart = today.subtract(const Duration(days: 27));
    final daily = <DateTime, int>{
      for (var offset = 0; offset < 7; offset++)
        dayStart.add(Duration(days: offset)): 0,
    };
    final weekly = <DateTime, int>{
      for (var offset = 0; offset < 4; offset++)
        weekStart.add(Duration(days: offset * 7)): 0,
    };
    for (final entry in timerFocusSecondsByLocalDay(history).entries) {
      final day = entry.key;
      if (!day.isBefore(dayStart) && !day.isAfter(today)) {
        daily[day] = (daily[day] ?? 0) + entry.value;
      }
      final weekIndex = day.difference(weekStart).inDays ~/ 7;
      if (weekIndex >= 0 && weekIndex < 4) {
        final bucket = weekStart.add(Duration(days: weekIndex * 7));
        weekly[bucket] = (weekly[bucket] ?? 0) + entry.value;
      }
    }
    return Column(
      key: const ValueKey('timer-focus-buckets'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Focus history', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _FocusBucketRow(
          label: 'Daily',
          values: daily.entries
              .map(
                (entry) =>
                    (DateFormat('E').format(entry.key), entry.value ~/ 60),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        _FocusBucketRow(
          label: 'Weekly',
          values: weekly.entries
              .map(
                (entry) =>
                    (DateFormat('d MMM').format(entry.key), entry.value ~/ 60),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _FocusBucketRow extends StatelessWidget {
  const _FocusBucketRow({required this.label, required this.values});

  final String label;
  final List<(String, int)> values;

  @override
  Widget build(BuildContext context) {
    final max = values.fold<int>(0, (value, item) => math.max(value, item.$2));
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label:
          '$label focus minutes, ${values.map((item) => '${item.$1} ${item.$2}').join(', ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final value in values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${value.$2}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 3),
                        Tooltip(
                          message: '${value.$1}: ${value.$2} focus minutes',
                          child: Container(
                            height: max == 0 ? 4 : 8 + (48 * value.$2 / max),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          value.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimerZenFullscreen extends StatefulWidget {
  const _TimerZenFullscreen({required this.node, required this.onChanged});

  final MindmapNode node;
  final ValueChanged<MindmapNode> onChanged;

  @override
  State<_TimerZenFullscreen> createState() => _TimerZenFullscreenState();
}

class _TimerZenFullscreenState extends State<_TimerZenFullscreen> {
  late final Ticker _ticker;
  late MindmapNode _node = widget.node;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(() {
      if (mounted && TimerPayload.fromNode(_node).timer.isRunning) {
        setState(() {});
      }
    });
    _syncTicker();
  }

  void _syncTicker() {
    final running = TimerPayload.fromNode(_node).timer.isRunning;
    if (running && !_ticker.isActive) {
      _ticker.start();
    } else if (!running && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _update(HybridTimerState timer) {
    final updated = _node.copyWith(
      data: TimerPayload(timer: timer).toData(_node.data),
      updatedAt: DateTime.now(),
    );
    setState(() => _node = updated);
    _syncTicker();
    widget.onChanged(updated);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timer = TimerPayload.fromNode(_node).timer;
    final seconds = timer.isBounded
        ? timer.remainingSecondsAt(now) ?? 0
        : timer.elapsedSecondsAt(now);
    final display =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Scaffold(
      key: const ValueKey('timer-zen-fullscreen-page'),
      appBar: AppBar(
        title: Text(_node.title.isEmpty ? 'Zen focus' : _node.title),
        leading: IconButton(
          tooltip: 'Close Zen view',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.self_improvement, size: 72),
              const SizedBox(height: 20),
              Semantics(
                label: 'Zen timer $display',
                child: Text(
                  display,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontSize: 72,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 480,
                child: MiniAppProgressMeter(
                  label: timer.mode == TimerMode.focus
                      ? '${timer.segment.name} cycle'
                      : timer.mode.name,
                  value: timer.progressAt(now),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: timer.isRunning
                        ? () => _update(timer.pause(now))
                        : () => _update(timer.start(now)),
                    icon: Icon(
                      timer.isRunning ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(timer.isRunning ? 'Pause' : 'Start'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _update(timer.reset()),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _update(
                      timer.complete(now, recordId: const Uuid().v4()),
                    ),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Complete'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _TimerAmbientAudioControls(),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimerAmbientAudioControls extends ConsumerWidget {
  const _TimerAmbientAudioControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(focusAudioPlayerServiceProvider);
    final notifier = ref.read(focusAudioPlayerServiceProvider.notifier);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            value: state.currentTrack?.id,
            hint: const Text('Choose ambient track'),
            items: [
              for (final track in state.tracks)
                DropdownMenuItem(value: track.id, child: Text(track.title)),
            ],
            onChanged: (trackId) {
              if (trackId == null) return;
              final track = state.tracks
                  .where((item) => item.id == trackId)
                  .firstOrNull;
              if (track != null) unawaited(notifier.selectTrack(track));
            },
          ),
          FilledButton.tonalIcon(
            onPressed: state.isLoadingStream
                ? null
                : () => unawaited(notifier.togglePlayPause()),
            icon: state.isLoadingStream
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
            label: Text(state.isPlaying ? 'Pause ambient' : 'Play ambient'),
          ),
          IconButton(
            tooltip: state.isMuted
                ? 'Unmute ambient audio'
                : 'Mute ambient audio',
            onPressed: () => unawaited(notifier.toggleMute()),
            icon: Icon(state.isMuted ? Icons.volume_off : Icons.volume_up),
          ),
          SizedBox(
            width: 160,
            child: Slider(
              value: state.isMuted ? 0 : state.volume,
              onChanged: (value) => unawaited(notifier.setVolume(value)),
            ),
          ),
          if (state.error != null)
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}

class _ProjectGantt extends StatelessWidget {
  const _ProjectGantt({required this.project});

  final ProjectPlan project;

  @override
  Widget build(BuildContext context) {
    final tasks = project.tasks.where((task) {
      return task.startDate != null || task.deadline != null;
    }).toList();
    if (tasks.isEmpty &&
        project.startDate == null &&
        project.targetDate == null) {
      return const MiniAppEmptyState(
        icon: Icons.date_range_outlined,
        message: 'Set project or task dates to build Gantt chart.',
      );
    }

    final starts = <DateTime>[
      if (project.startDate != null) _day(project.startDate!),
      for (final task in tasks)
        if (task.startDate != null) _day(task.startDate!),
      for (final task in tasks)
        if (task.startDate == null && task.deadline != null)
          _day(task.deadline!),
    ];
    final ends = <DateTime>[
      if (project.targetDate != null) _day(project.targetDate!),
      for (final phase in project.phases)
        if (phase.targetDate != null) _day(phase.targetDate!),
      for (final milestone in project.milestones)
        if (milestone.deadline != null) _day(milestone.deadline!),
      for (final task in tasks)
        if (task.deadline != null) _day(task.deadline!),
      for (final task in tasks)
        if (task.deadline == null && task.startDate != null)
          _day(task.startDate!),
    ];
    if (starts.isEmpty) starts.addAll(ends);
    if (ends.isEmpty) ends.addAll(starts);
    starts.sort();
    ends.sort();
    var rangeStart = starts.first;
    var rangeEnd = ends.last;
    if (rangeEnd.isBefore(rangeStart)) {
      (rangeStart, rangeEnd) = (rangeEnd, rangeStart);
    }
    final days = rangeEnd.difference(rangeStart).inDays + 1;
    final colors = Theme.of(context).colorScheme;

    return Container(
      key: const ValueKey('plan-gantt-chart'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gantt chart', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 150,
                child: Text(DateFormat('d MMM yyyy').format(rangeStart)),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat('d MMM').format(rangeStart)),
                    if (days > 2) Text('$days days'),
                    Text(DateFormat('d MMM').format(rangeEnd)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final phase in project.phases) ...[
            _GanttSummaryRow(
              key: ValueKey('plan-gantt-phase-${phase.id}'),
              icon: Icons.account_tree_outlined,
              label: phase.title,
              progress: phase.progress,
              end: phase.targetDate,
            ),
            const SizedBox(height: 6),
            for (final milestone in phase.milestones) ...[
              _GanttSummaryRow(
                key: ValueKey('plan-gantt-milestone-${milestone.id}'),
                icon: Icons.flag_outlined,
                label: milestone.title,
                progress: milestone.progress,
                end: milestone.deadline,
                indent: true,
              ),
              const SizedBox(height: 6),
            ],
          ],
          if (tasks.isEmpty)
            Text(
              'Add task dates for task-level timeline bars.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final task in tasks) ...[
              _GanttTaskRow(
                task: task,
                rangeStart: rangeStart,
                rangeDays: days,
                fallbackStart: project.startDate,
                fallbackEnd: project.targetDate,
              ),
              const SizedBox(height: 6),
            ],
        ],
      ),
    );
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class _GanttSummaryRow extends StatelessWidget {
  const _GanttSummaryRow({
    required this.icon,
    required this.label,
    required this.progress,
    required this.end,
    this.indent = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final double progress;
  final DateTime? end;
  final bool indent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: indent ? 20 : 0),
    child: Row(
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        SizedBox(
          width: indent ? 124 : 144,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          end == null ? 'No date' : DateFormat('d MMM').format(end!.toLocal()),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    ),
  );
}

class _GanttTaskRow extends StatelessWidget {
  const _GanttTaskRow({
    required this.task,
    required this.rangeStart,
    required this.rangeDays,
    required this.fallbackStart,
    required this.fallbackEnd,
  });

  final ProjectTask task;
  final DateTime rangeStart;
  final int rangeDays;
  final DateTime? fallbackStart;
  final DateTime? fallbackEnd;

  @override
  Widget build(BuildContext context) {
    var start = _day(
      task.startDate ?? task.deadline ?? fallbackStart ?? rangeStart,
    );
    var end = _day(task.deadline ?? task.startDate ?? fallbackEnd ?? start);
    if (end.isBefore(start)) (start, end) = (end, start);
    final offset = start.difference(rangeStart).inDays.clamp(0, rangeDays - 1);
    final endOffset = end.difference(rangeStart).inDays.clamp(0, rangeDays - 1);
    final span = endOffset - offset + 1;
    final colors = Theme.of(context).colorScheme;
    final rangeLabel =
        '${DateFormat('d MMM yyyy').format(start)} to ${DateFormat('d MMM yyyy').format(end)}';
    return Semantics(
      label: '${task.title}, $rangeLabel',
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 24,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final unit = constraints.maxWidth / rangeDays;
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Positioned(
                        left: offset * unit,
                        top: 4,
                        width: (span * unit).clamp(4.0, constraints.maxWidth),
                        height: 16,
                        child: Tooltip(
                          message: '${task.title}\n$rangeLabel',
                          child: DecoratedBox(
                            key: ValueKey('plan-gantt-task-${task.id}'),
                            decoration: BoxDecoration(
                              color: task.status == ProjectTaskStatus.done
                                  ? colors.tertiary
                                  : colors.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class _PlanPhaseTimeline extends StatelessWidget {
  const _PlanPhaseTimeline({required this.phase});

  final ProjectPhase phase;

  @override
  Widget build(BuildContext context) {
    final tasks = phase.milestones
        .expand((milestone) => milestone.tasks)
        .toList();
    final done = tasks
        .where((task) => task.status == ProjectTaskStatus.done)
        .length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(phase.title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          MiniAppProgressMeter(
            label: '${phase.milestones.length} milestones',
            value: tasks.isEmpty ? 0 : done / tasks.length,
            detail: '$done/${tasks.length} tasks',
          ),
        ],
      ),
    );
  }
}

class _MiniAppScroll extends StatelessWidget {
  const _MiniAppScroll({required this.children, this.maxWidth = 900});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}

class Ticker {
  Ticker(this.callback);

  final VoidCallback callback;
  bool get isActive => _timer?.isActive ?? false;
  Timer? _timer;

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => callback());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

/// Day detail page — opens the mindmap for a given date.
///
/// Renders the day's mindmap canvas, side panels, timeline, and node mutation
/// flows through the repository/provider boundary.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/error_message.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/application/recurring_routine_application.dart';
import '../mindmap/domain/canvas_position.dart';
import '../mindmap/domain/goal_progress.dart';
import '../mindmap/domain/habit_completion.dart';
import '../mindmap/domain/kanban_board.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/plan_progress.dart';
import '../mindmap/domain/recurring_routine.dart';
import '../mindmap/domain/task_checklist_progress.dart';
import '../mindmap/domain/workspace_context.dart';
import '../mindmap/presentation/mindmap_canvas.dart';
import '../mindmap/presentation/node_editor_panel.dart';
import '../workspace/data/workspace_title_repository.dart';
import 'widgets/daily_timeline_schedule.dart';

class DayPage extends ConsumerStatefulWidget {
  const DayPage({required this.date, this.highlightNodeId, super.key});

  final DateTime date;
  final String? highlightNodeId;

  @override
  ConsumerState<DayPage> createState() => _DayPageState();
}

class _DayPageState extends ConsumerState<DayPage> {
  final _canvasKey = GlobalKey<MindmapCanvasState>();
  String? _selectedNodeId;
  bool _isLeftPanelOpen = true;
  bool _isRightPanelOpen = true;
  double _leftPanelWidth = 240.0;
  double _rightPanelWidth = 360.0;
  bool _isDraggingLeft = false;
  bool _showTimeline = false;

  // Undo / Redo stacks for node mutations (max 50 entries).
  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];
  static const int _maxUndo = 50;

  @override
  void initState() {
    super.initState();
    _selectedNodeId = widget.highlightNodeId;
  }

  @override
  void didUpdateWidget(covariant DayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightNodeId != oldWidget.highlightNodeId &&
        widget.highlightNodeId != null) {
      _selectedNodeId = widget.highlightNodeId;
    }
  }

  void _pushUndo(_UndoEntry entry) {
    _undoStack.add(entry);
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  Future<void> _undo() async {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    _redoStack.add(entry);
    try {
      final repository = ref.read(mindmapRepositoryProvider);
      switch (entry.kind) {
        case _UndoKind.save:
          // Revert to the node before the save.
          if (entry.before != null) {
            await repository.saveNode(entry.before!);
          }
        case _UndoKind.delete:
          // Re-create the deleted node.
          if (entry.before != null) {
            await repository.saveNode(entry.before!);
          }
        case _UndoKind.create:
          // Remove the created node.
          await repository.deleteNode(entry.nodeId);
      }
      final day = widget.date.dateOnly;
      invalidateMindmapState(ref, day: day);
      if (context.mounted) _showSnackBar('Undo');
    } catch (e) {
      if (context.mounted) _showSnackBar('Undo failed: $e');
    }
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    _undoStack.add(entry);
    try {
      final repository = ref.read(mindmapRepositoryProvider);
      switch (entry.kind) {
        case _UndoKind.save:
          if (entry.after != null) {
            await repository.saveNode(entry.after!);
          }
        case _UndoKind.delete:
          await repository.deleteNode(entry.nodeId);
        case _UndoKind.create:
          if (entry.after != null) {
            await repository.saveNode(entry.after!);
          }
      }
      final day = widget.date.dateOnly;
      invalidateMindmapState(ref, day: day);
      if (context.mounted) _showSnackBar('Redo');
    } catch (e) {
      if (context.mounted) _showSnackBar('Redo failed: $e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _focusOrCreateNode(NodeType type) {
    final currentNodes =
        ref.read(nodesForDayProvider(widget.date.dateOnly)).valueOrNull ??
        const <MindmapNode>[];
    _createNodeOfType(
      context,
      ref,
      widget.date.dateOnly,
      currentNodes,
      type,
      null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalizedDate = widget.date.dateOnly;
    final nodes = ref.watch(nodesForDayProvider(normalizedDate));
    final allNodes = ref.watch(allMindmapNodesProvider);

    MindmapNode? selectedNode;
    if (_selectedNodeId != null) {
      final all = allNodes.valueOrNull ?? const <MindmapNode>[];
      selectedNode = all.where((n) => n.id == _selectedNodeId).firstOrNull;
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          _focusOrCreateNode(NodeType.task);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectedNodeId != null) {
            setState(() {
              _selectedNodeId = null;
            });
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          _undo();
        },
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): () {
          _redo();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          floatingActionButton: LayoutBuilder(
            builder: (context, constraints) {
              // Only show FAB on mobile (viewport narrower than 840px)
              if (constraints.maxWidth >= 840) return const SizedBox.shrink();
              return FloatingActionButton.small(
                key: const ValueKey('day-fab'),
                tooltip: 'Quick create',
                onPressed: () {
                  _showQuickCreateSheet(context);
                },
                child: const Icon(Icons.add),
              );
            },
          ),
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go(AppRoute.calendar.path),
            ),
            title: Consumer(
              builder: (context, ref, child) {
                final titleMap = ref.watch(workspaceTitleProvider);
                final titleKey =
                    '${WorkspaceContextType.daily.name}_${dayKey(normalizedDate)}';
                final customTitle = titleMap[titleKey];
                final displayTitle =
                    (customTitle != null && customTitle.isNotEmpty)
                    ? customTitle
                    : '${dayKey(normalizedDate)} mindmap';

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final showBreadcrumb = constraints.maxWidth >= 360;
                    return Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        if (showBreadcrumb) ...[
                          TextButton(
                            onPressed: () => context.go(AppRoute.calendar.path),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text(
                              'Calendar',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              final controller = TextEditingController(
                                text: customTitle ?? '',
                              );
                              final result = await showDialog<String>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Set Workspace Title'),
                                  content: TextField(
                                    controller: controller,
                                    decoration: const InputDecoration(
                                      hintText: 'Enter custom title',
                                      border: OutlineInputBorder(),
                                    ),
                                    autofocus: true,
                                    onSubmitted: (val) =>
                                        Navigator.pop(context, val),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(
                                        context,
                                        controller.text,
                                      ),
                                      child: const Text('Save'),
                                    ),
                                  ],
                                ),
                              );

                              if (result != null) {
                                await ref
                                    .read(workspaceTitleProvider.notifier)
                                    .setTitle(
                                      WorkspaceContextType.daily,
                                      dayKey(normalizedDate),
                                      result,
                                    );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                                vertical: 4.0,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.edit, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          body: nodes.when(
            data: (value) {
              final canvasNodes = _canvasNodesFor(
                activeNodes: value,
                allNodes: allNodes.valueOrNull ?? const <MindmapNode>[],
                day: normalizedDate,
                highlightedNodeId: widget.highlightNodeId,
              );

              final counts = <NodeType, int>{};
              for (final node in value) {
                counts[node.type] = (counts[node.type] ?? 0) + 1;
              }

              return Row(
                children: [
                  AnimatedContainer(
                    duration: _isDraggingLeft
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    width: _isLeftPanelOpen ? _leftPanelWidth : 64,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      color: Theme.of(context).colorScheme.surface,
                    ),
                    child: Column(
                      children: [
                        if (_isLeftPanelOpen) ...[
                          Container(
                            height: 56,
                            padding: const EdgeInsets.only(left: 16, right: 8),
                            child: Stack(
                              children: [
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Node Palette',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    icon: const Icon(Icons.chevron_left),
                                    tooltip: 'Collapse',
                                    onPressed: () {
                                      setState(() {
                                        _isLeftPanelOpen = false;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              children: NodeType.values
                                  .map((type) => _buildPaletteItem(type))
                                  .toList(),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _applyRoutines(context, ref, normalizedDate),
                              icon: const Icon(
                                Icons.auto_awesome_motion_outlined,
                              ),
                              label: const Text('Routines'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            tooltip: 'Expand Palette',
                            onPressed: () {
                              setState(() {
                                _isLeftPanelOpen = true;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: ListView(
                              children: NodeType.values.map((type) {
                                final count = counts[type] ?? 0;
                                return _buildMiniPaletteItem(type, count);
                              }).toList(),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Apply Routines',
                            icon: const Icon(
                              Icons.auto_awesome_motion_outlined,
                            ),
                            onPressed: () =>
                                _applyRoutines(context, ref, normalizedDate),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                  if (_isLeftPanelOpen)
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (_) =>
                            setState(() => _isDraggingLeft = true),
                        onPanEnd: (_) =>
                            setState(() => _isDraggingLeft = false),
                        onPanCancel: () =>
                            setState(() => _isDraggingLeft = false),
                        onPanUpdate: (details) {
                          setState(() {
                            _leftPanelWidth =
                                (_leftPanelWidth + details.delta.dx).clamp(
                                  200.0,
                                  MediaQuery.of(context).size.width * 0.4,
                                );
                          });
                        },
                        child: Container(
                          width: 8,
                          decoration: BoxDecoration(
                            color: _isDraggingLeft
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant
                                      .withValues(alpha: 0.4),
                            border: Border(
                              left: BorderSide(
                                color: _isDraggingLeft
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 2,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: SegmentedButton<bool>(
                            style: SegmentedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              selectedBackgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              selectedForegroundColor: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                            segments: const [
                              ButtonSegment<bool>(
                                value: false,
                                label: Text('Visual Canvas'),
                                icon: Icon(Icons.hub_outlined, size: 16),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                label: Text('Timeline Schedule'),
                                icon: Icon(
                                  Icons.calendar_view_day_outlined,
                                  size: 16,
                                ),
                              ),
                            ],
                            selected: {_showTimeline},
                            onSelectionChanged: (newSelection) {
                              setState(() {
                                _showTimeline = newSelection.first;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          child: _showTimeline
                              ? DailyTimelineSchedule(
                                  day: normalizedDate,
                                  nodes: value,
                                  onNodeSelected: (node) {
                                    setState(() {
                                      _selectedNodeId = node.id;
                                      _isRightPanelOpen = true;
                                    });
                                  },
                                  onTaskDoneChanged: (node, isDone) async {
                                    final repository = ref.read(
                                      mindmapRepositoryProvider,
                                    );
                                    final updatedNode = node.copyWith(
                                      isDone: isDone,
                                      status: isDone
                                          ? NodeStatus.done
                                          : NodeStatus.open,
                                      progress: isDone ? 1 : node.progress,
                                      updatedAt: DateTime.now(),
                                    );
                                    _pushUndo(
                                      _UndoEntry(
                                        kind: _UndoKind.save,
                                        nodeId: node.id,
                                        before: node,
                                        after: updatedNode,
                                      ),
                                    );
                                    try {
                                      await repository.saveNode(updatedNode);
                                      invalidateMindmapState(
                                        ref,
                                        day: normalizedDate,
                                      );
                                      if (context.mounted) {
                                        _showSnackBar(
                                          isDone
                                              ? 'Task completed'
                                              : 'Task reopened',
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        _showSnackBar(
                                          'Failed to update task: $e',
                                        );
                                      }
                                    }
                                  },
                                )
                              : Stack(
                                  children: [
                                    Positioned.fill(
                                      child: MindmapCanvas(
                                        key: _canvasKey,
                                        nodes: canvasNodes,
                                        highlightedNodeId:
                                            widget.highlightNodeId,
                                        onNodeDropped: (type, offset) {
                                          _createNodeOfType(
                                            context,
                                            ref,
                                            normalizedDate,
                                            canvasNodes,
                                            type,
                                            offset,
                                          );
                                        },
                                        onNodeSelected: (node) {
                                          setState(() {
                                            _selectedNodeId = node.id;
                                            _isRightPanelOpen = true;
                                          });
                                        },
                                        onTaskDoneChanged:
                                            (node, isDone) async {
                                              final repository = ref.read(
                                                mindmapRepositoryProvider,
                                              );
                                              final updatedNode = node.copyWith(
                                                isDone: isDone,
                                                status: isDone
                                                    ? NodeStatus.done
                                                    : NodeStatus.open,
                                                progress: isDone
                                                    ? 1
                                                    : node.progress,
                                                updatedAt: DateTime.now(),
                                              );
                                              _pushUndo(
                                                _UndoEntry(
                                                  kind: _UndoKind.save,
                                                  nodeId: node.id,
                                                  before: node,
                                                  after: updatedNode,
                                                ),
                                              );
                                              try {
                                                await repository.saveNode(
                                                  updatedNode,
                                                );
                                                invalidateMindmapState(
                                                  ref,
                                                  day: normalizedDate,
                                                );
                                                if (context.mounted) {
                                                  _showSnackBar(
                                                    isDone
                                                        ? 'Task completed'
                                                        : 'Task reopened',
                                                  );
                                                }
                                              } catch (e) {
                                                if (context.mounted) {
                                                  _showSnackBar(
                                                    'Failed to update task: $e',
                                                  );
                                                }
                                              }
                                            },
                                        onTaskChecklistItemCompleted: (node) async {
                                          final repository = ref.read(
                                            mindmapRepositoryProvider,
                                          );
                                          final updatedNode =
                                              completeNextChecklistItem(
                                                node,
                                                now: DateTime.now(),
                                              );
                                          if (updatedNode == node) return;

                                          _pushUndo(
                                            _UndoEntry(
                                              kind: _UndoKind.save,
                                              nodeId: node.id,
                                              before: node,
                                              after: updatedNode,
                                            ),
                                          );
                                          try {
                                            await repository.saveNode(
                                              updatedNode,
                                            );
                                            invalidateMindmapState(
                                              ref,
                                              day: normalizedDate,
                                            );
                                            if (context.mounted) {
                                              _showSnackBar(
                                                'Checklist item completed',
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              _showSnackBar(
                                                'Failed to update checklist: $e',
                                              );
                                            }
                                          }
                                        },
                                        onKanbanCardAdvanced:
                                            (node, cardId) async {
                                              final board =
                                                  KanbanBoard.fromNodeData(
                                                    node.data,
                                                  );
                                              final updatedBoard = board
                                                  .moveCardToNextColumn(cardId);
                                              final repository = ref.read(
                                                mindmapRepositoryProvider,
                                              );
                                              final updatedNode = node.copyWith(
                                                data: {
                                                  ...node.data,
                                                  'kanban': updatedBoard
                                                      .toJson(),
                                                },
                                                updatedAt: DateTime.now(),
                                              );
                                              _pushUndo(
                                                _UndoEntry(
                                                  kind: _UndoKind.save,
                                                  nodeId: node.id,
                                                  before: node,
                                                  after: updatedNode,
                                                ),
                                              );
                                              try {
                                                await repository.saveNode(
                                                  updatedNode,
                                                );
                                                invalidateMindmapState(
                                                  ref,
                                                  day: normalizedDate,
                                                );
                                                if (context.mounted) {
                                                  _showSnackBar('Card moved');
                                                }
                                              } catch (e) {
                                                if (context.mounted) {
                                                  _showSnackBar(
                                                    'Failed to move card: $e',
                                                  );
                                                }
                                              }
                                            },
                                        onHabitCompleted: (node) async {
                                          final repository = ref.read(
                                            mindmapRepositoryProvider,
                                          );
                                          final updatedNode =
                                              logHabitCompletion(
                                                node,
                                                normalizedDate,
                                                now: DateTime.now(),
                                              );
                                          if (updatedNode == node) return;

                                          _pushUndo(
                                            _UndoEntry(
                                              kind: _UndoKind.save,
                                              nodeId: node.id,
                                              before: node,
                                              after: updatedNode,
                                            ),
                                          );
                                          try {
                                            await repository.saveNode(
                                              updatedNode,
                                            );
                                            invalidateMindmapState(
                                              ref,
                                              day: normalizedDate,
                                            );
                                            if (context.mounted) {
                                              _showSnackBar('Habit logged');
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              _showSnackBar(
                                                'Failed to log habit: $e',
                                              );
                                            }
                                          }
                                        },
                                        onGoalMilestoneAdvanced: (node) async {
                                          final repository = ref.read(
                                            mindmapRepositoryProvider,
                                          );
                                          final updatedNode =
                                              advanceGoalMilestone(
                                                node,
                                                now: DateTime.now(),
                                              );
                                          if (updatedNode == node) return;

                                          _pushUndo(
                                            _UndoEntry(
                                              kind: _UndoKind.save,
                                              nodeId: node.id,
                                              before: node,
                                              after: updatedNode,
                                            ),
                                          );
                                          try {
                                            await repository.saveNode(
                                              updatedNode,
                                            );
                                            invalidateMindmapState(
                                              ref,
                                              day: normalizedDate,
                                            );
                                            if (context.mounted) {
                                              _showSnackBar(
                                                'Milestone advanced',
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              _showSnackBar(
                                                'Failed to advance milestone: $e',
                                              );
                                            }
                                          }
                                        },
                                        onPlanStepAdvanced: (node) async {
                                          final repository = ref.read(
                                            mindmapRepositoryProvider,
                                          );
                                          final updatedNode = advancePlanStep(
                                            node,
                                            now: DateTime.now(),
                                          );
                                          if (updatedNode == node) return;

                                          _pushUndo(
                                            _UndoEntry(
                                              kind: _UndoKind.save,
                                              nodeId: node.id,
                                              before: node,
                                              after: updatedNode,
                                            ),
                                          );
                                          try {
                                            await repository.saveNode(
                                              updatedNode,
                                            );
                                            invalidateMindmapState(
                                              ref,
                                              day: normalizedDate,
                                            );
                                            if (context.mounted) {
                                              _showSnackBar('Step advanced');
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              _showSnackBar(
                                                'Failed to advance step: $e',
                                              );
                                            }
                                          }
                                        },
                                        onNodeMoved: (node, position) async {
                                          final repository = ref.read(
                                            mindmapRepositoryProvider,
                                          );
                                          final updatedNode = node.copyWith(
                                            position: position,
                                            updatedAt: DateTime.now(),
                                          );
                                          _pushUndo(
                                            _UndoEntry(
                                              kind: _UndoKind.save,
                                              nodeId: node.id,
                                              before: node,
                                              after: updatedNode,
                                            ),
                                          );
                                          try {
                                            await repository.saveNode(
                                              updatedNode,
                                            );
                                            invalidateMindmapState(
                                              ref,
                                              day: normalizedDate,
                                            );
                                          } catch (e) {
                                            if (context.mounted) {
                                              _showSnackBar(
                                                'Failed to save position: $e',
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                    if (canvasNodes.isEmpty)
                                      Center(
                                        child: _EmptyMindmapQuickStart(
                                          onCreateTask: () => _createNodeOfType(
                                            context,
                                            ref,
                                            normalizedDate,
                                            canvasNodes,
                                            NodeType.task,
                                            null,
                                          ),
                                          onCreateNote: () => _createNodeOfType(
                                            context,
                                            ref,
                                            normalizedDate,
                                            canvasNodes,
                                            NodeType.note,
                                            null,
                                          ),
                                          onCreateKanban: () => _createNodeOfType(
                                            context,
                                            ref,
                                            normalizedDate,
                                            canvasNodes,
                                            NodeType.kanban,
                                            null,
                                          ),
                                        ),
                                      ),
                                    if (widget.highlightNodeId != null)
                                      Positioned(
                                        left: 16,
                                        right: 16,
                                        bottom: 16,
                                        child: _NodeRelationsDock(
                                          nodeId: widget.highlightNodeId!,
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                  if (selectedNode != null) ...[
                    if (!_isRightPanelOpen)
                      Container(
                        width: 56,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          color: Theme.of(context).colorScheme.surface,
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 16),
                            IconButton(
                              icon: const Icon(Icons.chevron_left),
                              tooltip: 'Expand Editor',
                              onPressed: () {
                                setState(() {
                                  _isRightPanelOpen = true;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            Tooltip(
                              message: selectedNode.title.trim().isEmpty
                                  ? 'Untitled ${selectedNode.type.name}'
                                  : selectedNode.title.trim(),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: nodeColor(
                                    selectedNode.type,
                                  ).withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  nodeIcon(selectedNode.type),
                                  color: nodeColor(selectedNode.type),
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onPanStart: (_) =>
                              setState(() => _isDraggingLeft = true),
                          onPanEnd: (_) =>
                              setState(() => _isDraggingLeft = false),
                          onPanCancel: () =>
                              setState(() => _isDraggingLeft = false),
                          onPanUpdate: (details) {
                            setState(() {
                              _rightPanelWidth =
                                  (_rightPanelWidth - details.delta.dx).clamp(
                                    280.0,
                                    MediaQuery.of(context).size.width * 0.5,
                                  );
                            });
                          },
                          child: Container(
                            width: 8,
                            decoration: BoxDecoration(
                              color: _isDraggingLeft
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outlineVariant
                                        .withValues(alpha: 0.4),
                              border: Border(
                                left: BorderSide(
                                  color: _isDraggingLeft
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 2,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: _rightPanelWidth,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        child: NodeEditorPanel(
                          node: selectedNode,
                          onCollapse: () {
                            setState(() {
                              _isRightPanelOpen = false;
                            });
                          },
                          onSave: (updatedNode) async {
                            final repository = ref.read(
                              mindmapRepositoryProvider,
                            );
                            final allNodeList =
                                allNodes.valueOrNull ?? const [];
                            final wasNewNode = !allNodeList.any(
                              (n) => n.id == updatedNode.id,
                            );
                            if (!wasNewNode && selectedNode != null) {
                              _pushUndo(
                                _UndoEntry(
                                  kind: _UndoKind.save,
                                  nodeId: updatedNode.id,
                                  before: selectedNode,
                                  after: updatedNode,
                                ),
                              );
                            } else if (wasNewNode) {
                              _pushUndo(
                                _UndoEntry(
                                  kind: _UndoKind.create,
                                  nodeId: updatedNode.id,
                                  after: updatedNode,
                                ),
                              );
                            }
                            try {
                              await repository.saveNode(updatedNode);
                              invalidateMindmapState(ref, day: normalizedDate);
                              if (context.mounted) {
                                _showSnackBar(
                                  wasNewNode ? 'Node created' : 'Node saved',
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                _showSnackBar('Failed to save: $e');
                              }
                            }
                          },
                          onClose: () {
                            setState(() {
                              _selectedNodeId = null;
                            });
                          },
                          onDelete: () async {
                            final repository = ref.read(
                              mindmapRepositoryProvider,
                            );
                            final deleteNode = selectedNode;
                            if (deleteNode == null) return;
                            _pushUndo(
                              _UndoEntry(
                                kind: _UndoKind.delete,
                                nodeId: deleteNode.id,
                                before: deleteNode,
                              ),
                            );
                            try {
                              await repository.deleteNode(deleteNode.id);
                              invalidateMindmapState(ref, day: normalizedDate);
                              setState(() {
                                _selectedNodeId = null;
                              });
                              if (context.mounted) {
                                _showSnackBar('Node deleted');
                              }
                            } catch (e) {
                              if (context.mounted) {
                                _showSnackBar('Failed to delete: $e');
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ErrorMessage(
              message: 'Unable to load ${dayKey(normalizedDate)}',
              onRetry: () =>
                  ref.invalidate(nodesForDayProvider(normalizedDate)),
            ),
          ),
        ),
      ),
    );
  }

  void _showQuickCreateSheet(BuildContext context) {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final nameController = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final theme = Theme.of(ctx);
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Quick Create', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Pick a type. Leave title empty to use a default name.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Node title...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.edit_outlined),
                    ),
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        Navigator.pop(
                          ctx,
                          '${NodeType.task.name}:${value.trim()}',
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('Type', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.maxWidth >= 520
                          ? 5
                          : 3;
                      return GridView.count(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1.25,
                        children: NodeType.values.map((type) {
                          final color = nodeColor(type);
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.pop(
                              ctx,
                              '${type.name}:${nameController.text.trim()}',
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(nodeIcon(type), color: color, size: 22),
                                  const SizedBox(height: 4),
                                  Text(
                                    type.label,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    ).then((result) {
      if (result is String && result.contains(':')) {
        final colonIndex = result.indexOf(':');
        final typeName = result.substring(0, colonIndex);
        final title = result.substring(colonIndex + 1).trim();
        final type = NodeType.values.firstWhere(
          (t) => t.name == typeName,
          orElse: () => NodeType.task,
        );
        final day = widget.date.dateOnly;
        final currentNodes =
            ref.read(nodesForDayProvider(day)).valueOrNull ?? const [];
        if (context.mounted) {
          _createNodeOfType(
            context,
            ref,
            day,
            currentNodes,
            type,
            null,
            title: title,
          );
        }
      }
    });
  }

  Widget _buildPaletteItem(NodeType type) {
    final color = nodeColor(type);
    final icon = nodeIcon(type);

    final child = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 6)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('palette-item-${type.name}'),
              onTap: () {
                final day = widget.date.dateOnly;
                final currentNodes =
                    ref.read(nodesForDayProvider(day)).valueOrNull ?? [];
                _createNodeOfType(context, ref, day, currentNodes, type, null);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // When constrained too narrow (e.g. during drag animation),
                    // show only the icon to avoid overflow.
                    if (constraints.maxWidth < 80) {
                      return Icon(icon, color: color, size: 22);
                    }
                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, color: color, size: 22),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            type.label,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.drag_indicator,
                          size: 18,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Draggable<NodeType>(
      data: type,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: SizedBox(width: 240, child: child)),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }

  Widget _buildMiniPaletteItem(NodeType type, int count) {
    final color = nodeColor(type);
    final icon = nodeIcon(type);

    Widget miniIconWidget = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Icon(icon, color: color, size: 20),
    );

    if (count > 0) {
      miniIconWidget = Badge(
        label: Text('$count'),
        backgroundColor: color,
        child: miniIconWidget,
      );
    }

    return Draggable<NodeType>(
      data: type,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 24),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            final day = widget.date.dateOnly;
            final currentNodes =
                ref.read(nodesForDayProvider(day)).valueOrNull ?? [];
            _createNodeOfType(context, ref, day, currentNodes, type, null);
          },
          child: miniIconWidget,
        ),
      ),
    );
  }

  Future<void> _applyRoutines(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
  ) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final plan = await previewRecurringRoutines(
      repository: repository,
      day: day,
      now: DateTime.now(),
    );
    if (!context.mounted) return;

    final shouldApply = await showDialog<bool>(
      context: context,
      builder: (context) => _RoutinePreviewDialog(plan: plan),
    );
    if (shouldApply != true || !context.mounted) return;

    await applyRecurringRoutines(
      repository: repository,
      day: day,
      now: DateTime.now(),
    );
    invalidateMindmapState(ref, day: day);
    if (context.mounted) _showSnackBar('Routines applied');
  }

  Future<void> _createNodeOfType(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    List<MindmapNode> currentNodes,
    NodeType type,
    Offset? position, {
    String? title,
  }) async {
    final now = DateTime.now();

    // Default values
    final nodeTitle = title == null || title.trim().isEmpty
        ? 'New ${type.label}'
        : title.trim();

    // If no position is provided (clicked from palette), use the viewport center
    final CanvasPosition pos;
    if (position != null) {
      pos = CanvasPosition(position.dx, position.dy);
    } else {
      final center = _canvasKey.currentState?.viewportCenter;
      if (center != null) {
        // Offset slightly if there are many nodes to prevent perfect overlap
        final offsetNodes = currentNodes.length * 10.0;
        pos = CanvasPosition(center.dx + offsetNodes, center.dy + offsetNodes);
      } else {
        pos = _nextNodePosition(currentNodes.length);
      }
    }

    final String bodyTemplate = switch (type) {
      NodeType.task => '- [ ] ',
      NodeType.kanban => 'Add description or context for this kanban board...',
      NodeType.plan => '## Objectives\n- \n\n## Action Items\n- [ ] ',
      NodeType.note => 'Write your notes here...',
      NodeType.journal => '## Daily Entry\n\nHow was your day?',
      NodeType.habit => 'Track your habit progress here.',
      NodeType.goal => '## Target\n\n## Motivation\n',
      NodeType.link => 'https://',
      NodeType.empty => '',
    };

    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: type,
      title: nodeTitle,
      body: bodyTemplate,
      day: day,
      position: pos,
      now: now,
    );

    final repository = ref.read(mindmapRepositoryProvider);
    _pushUndo(_UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node));
    try {
      await repository.saveNode(node);
      invalidateMindmapState(ref, day: day);

      if (context.mounted) {
        // Auto-select the newly created node so the user can immediately edit it
        setState(() {
          _selectedNodeId = node.id;
        });
        _showSnackBar('${type.label} created');
      }

      // Automatically pan the mindmap to focus on the newly created node
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _canvasKey.currentState?.focusOnPosition(pos);
      });
    } catch (e) {
      if (context.mounted) _showSnackBar('Failed to create node: $e');
    }
  }
}

List<MindmapNode> _canvasNodesFor({
  required List<MindmapNode> activeNodes,
  required List<MindmapNode> allNodes,
  required DateTime day,
  required String? highlightedNodeId,
}) {
  if (highlightedNodeId == null ||
      activeNodes.any((node) => node.id == highlightedNodeId)) {
    return activeNodes;
  }

  for (final node in allNodes) {
    if (node.id == highlightedNodeId &&
        node.isArchived &&
        node.day.isSameDay(day)) {
      return List.unmodifiable([...activeNodes, node]);
    }
  }

  return activeNodes;
}

class _RoutinePreviewDialog extends StatelessWidget {
  const _RoutinePreviewDialog({required this.plan});

  final RecurringRoutinePlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Routine preview'),
      content: SizedBox(
        width: 430,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _RoutinePreviewChip(
                      icon: Icons.add_task_outlined,
                      label: 'Ready to create ${plan.readyCount}',
                    ),
                    _RoutinePreviewChip(
                      icon: Icons.history_toggle_off_outlined,
                      label: 'Existing ${plan.skippedCount}',
                    ),
                    _RoutinePreviewChip(
                      icon: Icons.event_busy_outlined,
                      label: 'Not due ${plan.notDueCount}',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (var index = 0; index < plan.items.length; index++) ...[
                  if (index > 0) const Divider(height: 16),
                  _RoutinePreviewRow(item: plan.items[index]),
                ],
                if (plan.items.isEmpty)
                  Text(
                    'No routines configured',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('routine-preview-cancel-button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('routine-preview-apply-button'),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.auto_awesome_motion_outlined),
          label: Text(plan.readyCount == 0 ? 'Close' : 'Apply due routines'),
        ),
      ],
    );
  }
}

class _RoutinePreviewChip extends StatelessWidget {
  const _RoutinePreviewChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 7),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _RoutinePreviewRow extends StatelessWidget {
  const _RoutinePreviewRow({required this.item});

  final RecurringRoutinePlanItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _routineStatusColor(theme, item.status);

    return Row(
      children: [
        Icon(_routineStatusIcon(item.status), size: 20, color: statusColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.routine.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                _routineRuleLabel(item.routine.rule),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          item.statusLabel,
          style: theme.textTheme.labelMedium?.copyWith(color: statusColor),
        ),
      ],
    );
  }
}

class _NodeRelationsDock extends ConsumerWidget {
  const _NodeRelationsDock({required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relations = ref.watch(nodeRelationsProvider(nodeId));

    return relations.when(
      data: (value) {
        if (value.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Material(
          key: const ValueKey('node-relations-dock'),
          elevation: 14,
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text('Node links', style: theme.textTheme.titleSmall),
                  ],
                ),
                if (value.relatedNodes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _RelationsSection(
                    label: 'Related',
                    keyPrefix: 'relation-related',
                    nodes: value.relatedNodes,
                  ),
                ],
                if (value.backlinks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _RelationsSection(
                    label: 'Backlinks',
                    keyPrefix: 'relation-backlink',
                    nodes: value.backlinks,
                  ),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _EmptyMindmapQuickStart extends StatelessWidget {
  const _EmptyMindmapQuickStart({
    required this.onCreateTask,
    required this.onCreateNote,
    required this.onCreateKanban,
  });

  final VoidCallback onCreateTask;
  final VoidCallback onCreateNote;
  final VoidCallback onCreateKanban;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('day-mindmap-empty-quick-start'),
        width: 360,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hub_outlined,
              size: 36,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              'Start today\'s mindmap',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Drop a node from the palette, or start with one of these.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('day-mindmap-empty-add-task'),
                  onPressed: onCreateTask,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Task'),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('day-mindmap-empty-add-note'),
                  onPressed: onCreateNote,
                  icon: const Icon(Icons.notes_outlined),
                  label: const Text('Note'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('day-mindmap-empty-add-kanban'),
                  onPressed: onCreateKanban,
                  icon: const Icon(Icons.view_kanban_outlined),
                  label: const Text('Kanban'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RelationsSection extends StatelessWidget {
  const _RelationsSection({
    required this.label,
    required this.keyPrefix,
    required this.nodes,
  });

  final String label;
  final String keyPrefix;
  final List<MindmapNode> nodes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final node in nodes)
              ActionChip(
                key: ValueKey('$keyPrefix-${node.id}'),
                avatar: Icon(_relationIcon(node.type), size: 16),
                label: Text(node.title),
                onPressed: () =>
                    goToDay(context, node.day, highlightNodeId: node.id),
              ),
          ],
        ),
      ],
    );
  }
}

CanvasPosition _nextNodePosition(int existingCount) {
  final offset = existingCount * 42.0;
  return CanvasPosition(offset - 84, offset - 24);
}

IconData _relationIcon(NodeType type) => switch (type) {
  NodeType.task => Icons.check_circle_outline,
  NodeType.kanban => Icons.view_kanban_outlined,
  NodeType.plan => Icons.route_outlined,
  NodeType.note => Icons.notes_outlined,
  NodeType.journal => Icons.book_outlined,
  NodeType.habit => Icons.repeat_outlined,
  NodeType.goal => Icons.flag_outlined,
  NodeType.link => Icons.link_outlined,
  NodeType.empty => Icons.crop_square_outlined,
};

IconData _routineStatusIcon(RecurringRoutinePlanItemStatus status) {
  return switch (status) {
    RecurringRoutinePlanItemStatus.ready => Icons.add_task_outlined,
    RecurringRoutinePlanItemStatus.skippedExisting =>
      Icons.check_circle_outline,
    RecurringRoutinePlanItemStatus.skippedToday => Icons.block_outlined,
    RecurringRoutinePlanItemStatus.snoozedToday => Icons.snooze_outlined,
    RecurringRoutinePlanItemStatus.notDue => Icons.event_busy_outlined,
  };
}

Color _routineStatusColor(
  ThemeData theme,
  RecurringRoutinePlanItemStatus status,
) {
  return switch (status) {
    RecurringRoutinePlanItemStatus.ready => theme.colorScheme.primary,
    RecurringRoutinePlanItemStatus.skippedExisting =>
      theme.colorScheme.tertiary,
    RecurringRoutinePlanItemStatus.skippedToday => theme.colorScheme.outline,
    RecurringRoutinePlanItemStatus.snoozedToday => theme.colorScheme.outline,
    RecurringRoutinePlanItemStatus.notDue => theme.colorScheme.outline,
  };
}

String _routineRuleLabel(RecurringRule rule) {
  return switch (rule.frequency) {
    RecurringFrequency.daily => 'Every day',
    RecurringFrequency.weekly => 'Weekly on ${_weekdayName(rule.weekday)}',
    RecurringFrequency.monthly => 'Monthly on day ${rule.dayOfMonth}',
  };
}

String _weekdayName(int? weekday) {
  return switch (weekday) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => 'schedule',
  };
}

/// Kinds of mutations tracked by the undo/redo system.
enum _UndoKind { save, delete, create }

/// A single entry in the undo/redo stack.
///
/// Keeps snapshots of the node [before] and [after] the mutation so we can
/// reverse or re-apply the operation.
final class _UndoEntry {
  const _UndoEntry({
    required this.kind,
    required this.nodeId,
    this.before,
    this.after,
  });

  final _UndoKind kind;
  final String nodeId;
  final MindmapNode? before;
  final MindmapNode? after;
}

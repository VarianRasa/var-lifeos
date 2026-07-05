/// Day detail page — opens the mindmap for a given date.
///
/// Renders the day's mindmap canvas, side panels, timeline, and node mutation
/// flows through the repository/provider boundary.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/doodle_border.dart';
import '../../shared/widgets/error_message.dart';
import '../command/domain/quick_create_command_parser.dart';
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
import 'application/carry_over_planner.dart';
import 'application/daily_planning_engine.dart';
import 'application/daily_review_builder.dart';
import 'application/day_markdown_export.dart';
import 'application/day_mini_insights.dart';
import 'application/day_templates.dart';
import 'application/focus_session.dart';
import 'application/node_inbox.dart';
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
  final TextEditingController _quickCaptureController = TextEditingController();
  bool _isMissionMode = false;
  DateTime? _focusStartedAt;
  String? _focusNodeId;
  int? _focusTargetMinutes;
  bool _focusTargetNotified = false;
  Timer? _focusTicker;
  bool _isDayTabsCollapsed = false;
  bool _isBlankBoardHidden = false;
  bool _isCanvasAddNodeMenuOpen = false;
  bool _isCanvasAddNodeFabHovered = false;
  bool _isSelectedNodeToolsCollapsed = false;
  bool _isRightPanelOpen = true;
  double _rightPanelWidth = 360.0;
  bool _isDraggingRight = false;
  _DayViewMode _viewMode = _DayViewMode.canvas;
  _DayContextFilter _contextFilter = _DayContextFilter.all;
  String? _workspaceContextKey;
  _TableQuickView _tableQuickView = _TableQuickView.all;
  _TableSortMode _tableSortMode = _TableSortMode.updatedDesc;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  static const String _viewModePreferenceKey = 'day_view_mode';
  static const String _contextFilterPreferenceKey = 'day_context_filter';
  static const String _workspaceContextPreferenceKey = 'day_workspace_context';
  static const String _tableQuickViewPreferenceKey = 'day_table_quick_view';
  static const String _tableSortModePreferenceKey = 'day_table_sort_mode';

  // Undo / Redo stacks for node mutations (max 50 entries).
  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];
  static const int _maxUndo = 50;

  @override
  void initState() {
    super.initState();
    _selectedNodeId = widget.highlightNodeId;
    _loadViewPreferences();
  }

  @override
  void dispose() {
    _focusTicker?.cancel();
    _quickCaptureController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightNodeId != oldWidget.highlightNodeId &&
        widget.highlightNodeId != null) {
      _selectedNodeId = widget.highlightNodeId;
    }
  }

  Future<void> _loadViewPreferences() async {
    final storedViewMode = await _preferences.getString(_viewModePreferenceKey);
    final storedContextFilter = await _preferences.getString(
      _contextFilterPreferenceKey,
    );
    final storedWorkspaceContext = await _preferences.getString(
      _workspaceContextPreferenceKey,
    );
    final storedTableView = await _preferences.getString(
      _tableQuickViewPreferenceKey,
    );
    final storedTableSortMode = await _preferences.getString(
      _tableSortModePreferenceKey,
    );
    if (!mounted) return;

    setState(() {
      _viewMode = _dayViewModeFromName(storedViewMode) ?? _viewMode;
      _contextFilter =
          _dayContextFilterFromName(storedContextFilter) ?? _contextFilter;
      _workspaceContextKey = storedWorkspaceContext?.isEmpty == true
          ? null
          : storedWorkspaceContext;
      _tableQuickView =
          _tableQuickViewFromName(storedTableView) ?? _tableQuickView;
      _tableSortMode =
          _tableSortModeFromName(storedTableSortMode) ?? _tableSortMode;
    });
  }

  Future<void> _setViewMode(_DayViewMode value) async {
    setState(() => _viewMode = value);
    await _preferences.setString(_viewModePreferenceKey, value.name);
  }

  Future<void> _setContextFilter(_DayContextFilter value) async {
    setState(() {
      _contextFilter = value;
      _workspaceContextKey = null;
    });
    await _preferences.setString(_contextFilterPreferenceKey, value.name);
    await _preferences.remove(_workspaceContextPreferenceKey);
  }

  Future<void> _setWorkspaceContextFilter(WorkspaceContext context) async {
    final key = _workspaceContextFilterKey(context);
    setState(() {
      _contextFilter = _DayContextFilter.all;
      _workspaceContextKey = key;
    });
    await _preferences.setString(
      _contextFilterPreferenceKey,
      _contextFilter.name,
    );
    await _preferences.setString(_workspaceContextPreferenceKey, key);
  }

  bool _matchesActiveContext(MindmapNode node) {
    final workspaceKey = _workspaceContextKey;
    if (workspaceKey == null) return _contextFilter.matches(node);
    final projectKey = _workspaceContextFilterKeyFor(
      WorkspaceContextType.project,
      node.project,
    );
    final areaKey = _workspaceContextFilterKeyFor(
      WorkspaceContextType.area,
      node.area,
    );
    return workspaceKey == projectKey || workspaceKey == areaKey;
  }

  Future<void> _setTableQuickView(_TableQuickView value) async {
    setState(() => _tableQuickView = value);
    await _preferences.setString(_tableQuickViewPreferenceKey, value.name);
  }

  Future<void> _setTableSortMode(_TableSortMode value) async {
    setState(() => _tableSortMode = value);
    await _preferences.setString(_tableSortModePreferenceKey, value.name);
  }

  List<_DailyPlanningSuggestion> _dailyPlanningSuggestions({
    required DateTime day,
    required List<MindmapNode> nodes,
    required List<MindmapNode> dayNodes,
    required int readyRoutineCount,
  }) {
    final models = buildDailyPlanningSuggestions(
      DailyPlanningContext(
        day: day,
        allNodes: nodes,
        dayNodes: dayNodes,
        readyRoutineCount: readyRoutineCount,
      ),
    );
    return [
      for (final model in models)
        _mapDailyPlanningSuggestion(model, day, nodes, dayNodes),
    ];
  }

  _DailyPlanningSuggestion _mapDailyPlanningSuggestion(
    DailyPlanningSuggestionModel model,
    DateTime day,
    List<MindmapNode> nodes,
    List<MindmapNode> dayNodes,
  ) {
    return switch (model.type) {
      DailyPlanningActionType.applyRoutines => _DailyPlanningSuggestion(
        icon: Icons.auto_awesome_motion_outlined,
        label: model.label,
        onPressed: () => unawaited(_applyReadyRoutines(day)),
      ),
      DailyPlanningActionType.carryOver => _DailyPlanningSuggestion(
        icon: Icons.event_repeat,
        label: model.label,
        onPressed: () => unawaited(
          _showCarryOverSheet(
            day,
            buildCarryOverCandidates(nodes: nodes, selectedDay: day),
          ),
        ),
      ),
      DailyPlanningActionType.reviewOverdue => _DailyPlanningSuggestion(
        icon: Icons.warning_amber_rounded,
        label: model.label,
        onPressed: () => unawaited(
          _carryOverOverdueTasks(day, _nodesByIds(nodes, model.payload)),
        ),
      ),
      DailyPlanningActionType.rescheduleLowPriority => _DailyPlanningSuggestion(
        icon: Icons.low_priority_rounded,
        label: model.label,
        onPressed: () => unawaited(
          _showCarryOverSheet(
            day,
            buildCarryOverCandidates(nodes: nodes, selectedDay: day)
                .where((candidate) => model.payload.contains(candidate.node.id))
                .toList(),
            title: model.label,
          ),
        ),
      ),
      DailyPlanningActionType.createGoalNextAction => _DailyPlanningSuggestion(
        icon: Icons.add_task_outlined,
        label: model.label,
        onPressed: () {
          final node = _nodeById(nodes, model.nodeId);
          if (node != null) unawaited(_createGoalNextAction(day, node));
        },
      ),
      DailyPlanningActionType.applyTemplate => _DailyPlanningSuggestion(
        icon: Icons.dashboard_customize_outlined,
        label: model.label,
        onPressed: () => unawaited(_showDayTemplateSheet(day, dayNodes)),
      ),
      DailyPlanningActionType.startDailyReview => _DailyPlanningSuggestion(
        icon: Icons.rate_review_outlined,
        label: model.label,
        onPressed: () => unawaited(_openOrCreateDailyReview(day, dayNodes)),
      ),
      DailyPlanningActionType.createTomorrowTopTasks =>
        _DailyPlanningSuggestion(
          icon: Icons.playlist_add_check_rounded,
          label: model.label,
          onPressed: () {
            final review = _nodeById(dayNodes, model.nodeId);
            if (review != null) {
              unawaited(_createTomorrowTopTasks(day, review, model.payload));
            }
          },
        ),
    };
  }

  MindmapNode? _nodeById(List<MindmapNode> nodes, String? id) {
    if (id == null) return null;
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  List<MindmapNode> _nodesByIds(List<MindmapNode> nodes, List<String> ids) {
    final idSet = ids.toSet();
    return nodes.where((node) => idSet.contains(node.id)).toList();
  }

  Future<void> _applyReadyRoutines(DateTime day) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final plan = await previewRecurringRoutines(
      repository: repository,
      day: day,
      now: now,
    );
    if (plan.readyCount == 0) {
      if (mounted) _showSnackBar('No routines ready');
      return;
    }

    final created = await applyRecurringRoutines(
      repository: repository,
      day: day,
      now: now,
    );
    invalidateMindmapState(ref, day: day);
    if (mounted) {
      final count = created.length;
      _showSnackBar(
        count == 1 ? '1 routine applied' : '$count routines applied',
      );
    }
  }

  Future<void> _carryOverOverdueTasks(
    DateTime day,
    List<MindmapNode> tasks,
  ) async {
    final repository = ref.read(mindmapRepositoryProvider);
    for (final task in tasks) {
      final updated = task.copyWith(dueDate: day, updatedAt: DateTime.now());
      await repository.saveNode(updated);
      _pushUndo(
        _UndoEntry(
          kind: _UndoKind.save,
          nodeId: task.id,
          before: task,
          after: updated,
        ),
      );
    }
    invalidateMindmapState(ref, day: day);
    if (mounted) _showSnackBar('Overdue tasks carried over');
  }

  Future<void> _showCarryOverSheet(
    DateTime day,
    List<CarryOverCandidate> candidates, {
    String title = 'Carry-over assistant',
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_repeat),
                    title: Text(title),
                    subtitle: Text('${candidates.length} unfinished items'),
                  );
                }
                final candidate = candidates[index - 1];
                final node = candidate.node;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    nodeIcon(node.type),
                    color: nodeColor(node.type),
                  ),
                  title: Text(
                    node.title.isEmpty ? node.type.label : node.title,
                  ),
                  subtitle: Text(
                    '${candidate.reason.label} · ${dayKey(node.day)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Move to day',
                        icon: const Icon(Icons.drive_file_move_outline),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _applyCarryOverAction(
                            day,
                            node,
                            CarryOverAction.moveToDay,
                          );
                        },
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Duplicate to day',
                        icon: const Icon(Icons.copy_outlined),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _applyCarryOverAction(
                            day,
                            node,
                            CarryOverAction.duplicateToDay,
                          );
                        },
                      ),
                      PopupMenuButton<CarryOverAction>(
                        tooltip: 'More actions',
                        onSelected: (action) async {
                          Navigator.of(context).pop();
                          await _applyCarryOverAction(day, node, action);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: CarryOverAction.reschedule,
                            child: Text('Reschedule'),
                          ),
                          const PopupMenuItem(
                            value: CarryOverAction.markDone,
                            child: Text('Mark done'),
                          ),
                          const PopupMenuItem(
                            value: CarryOverAction.archive,
                            child: Text('Archive'),
                          ),
                          if (node.checklist.isNotEmpty)
                            const PopupMenuItem(
                              value: CarryOverAction.splitChecklist,
                              child: Text('Split checklist'),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemCount: candidates.length + 1,
            ),
          ),
        );
      },
    );
  }

  Future<void> _applyCarryOverAction(
    DateTime day,
    MindmapNode node,
    CarryOverAction action,
  ) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    switch (action) {
      case CarryOverAction.moveToDay:
        final updated = node.copyWith(day: day, dueDate: day, updatedAt: now);
        await repository.saveNode(updated);
        _pushUndo(
          _UndoEntry(
            kind: _UndoKind.save,
            nodeId: node.id,
            before: node,
            after: updated,
          ),
        );
        invalidateMindmapState(ref, day: day, extraDay: node.day);
        if (mounted) _showSnackBar('Moved to ${dayKey(day)}');
      case CarryOverAction.reschedule:
        final pickedDay = await showDatePicker(
          context: context,
          initialDate: day,
          firstDate: DateTime(day.year - 1),
          lastDate: DateTime(day.year + 3),
        );
        if (pickedDay == null) return;
        final updated = node.copyWith(
          day: pickedDay,
          dueDate: pickedDay,
          updatedAt: now,
        );
        await repository.saveNode(updated);
        _pushUndo(
          _UndoEntry(
            kind: _UndoKind.save,
            nodeId: node.id,
            before: node,
            after: updated,
          ),
        );
        invalidateMindmapState(ref, day: day, extraDay: node.day);
        invalidateMindmapState(ref, day: pickedDay);
        if (mounted) _showSnackBar('Rescheduled to ${dayKey(pickedDay)}');
      case CarryOverAction.duplicateToDay:
        final duplicate = node.copyWith(
          id: const Uuid().v4(),
          day: day,
          dueDate: day,
          createdAt: now,
          updatedAt: now,
        );
        await repository.saveNode(duplicate);
        _pushUndo(
          _UndoEntry(
            kind: _UndoKind.create,
            nodeId: duplicate.id,
            after: duplicate,
          ),
        );
        invalidateMindmapState(ref, day: day);
        if (mounted) _showSnackBar('Duplicated to ${dayKey(day)}');
      case CarryOverAction.markDone:
        final updated = node.copyWith(
          isDone: true,
          status: NodeStatus.done,
          progress: 1,
          updatedAt: now,
        );
        await repository.saveNode(updated);
        _pushUndo(
          _UndoEntry(
            kind: _UndoKind.save,
            nodeId: node.id,
            before: node,
            after: updated,
          ),
        );
        invalidateMindmapState(ref, day: day, extraDay: node.day);
        if (mounted) _showSnackBar('Marked done');
      case CarryOverAction.archive:
        final updated = node.copyWith(isArchived: true, updatedAt: now);
        await repository.saveNode(updated);
        _pushUndo(
          _UndoEntry(
            kind: _UndoKind.save,
            nodeId: node.id,
            before: node,
            after: updated,
          ),
        );
        invalidateMindmapState(ref, day: day, extraDay: node.day);
        if (mounted) _showSnackBar('Archived');
      case CarryOverAction.splitChecklist:
        final openItems = node.checklist.where((item) => !item.isDone).toList();
        if (openItems.isEmpty) {
          if (mounted) _showSnackBar('No open checklist items');
          return;
        }
        final createdNodes = <MindmapNode>[];
        for (var i = 0; i < openItems.length; i += 1) {
          final item = openItems[i];
          final child = MindmapNode.create(
            id: const Uuid().v4(),
            type: NodeType.task,
            title: item.title,
            day: day,
            position: CanvasPosition(
              node.position.dx + 260,
              node.position.dy + (i * 90),
            ),
            priority: node.priority,
            project: node.project,
            area: node.area,
            tags: node.tags,
            dueDate: day,
            relatedNodeIds: [node.id],
            data: {
              'relations': [
                {'targetId': node.id, 'label': 'split from'},
              ],
            },
            now: now,
          );
          await repository.saveNode(child);
          createdNodes.add(child);
          _pushUndo(
            _UndoEntry(kind: _UndoKind.create, nodeId: child.id, after: child),
          );
        }
        final updated = node.copyWith(
          day: day,
          dueDate: day,
          relatedNodeIds: {
            ...node.relatedNodeIds,
            for (final child in createdNodes) child.id,
          }.toList(),
          updatedAt: now,
        );
        await repository.saveNode(updated);
        _pushUndo(
          _UndoEntry(
            kind: _UndoKind.save,
            nodeId: node.id,
            before: node,
            after: updated,
          ),
        );
        invalidateMindmapState(ref, day: day, extraDay: node.day);
        if (mounted) _showSnackBar('Checklist split into tasks');
    }
  }

  Future<void> _createGoalNextAction(DateTime day, MindmapNode goal) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final node = MindmapNode(
      id: 'daily-goal-action-${now.microsecondsSinceEpoch}',
      type: NodeType.task,
      title: 'Next action: ${goal.title}',
      day: day,
      createdAt: now,
      updatedAt: now,
      body: 'Move goal forward: [[${goal.title}]]',
      position: CanvasPosition(goal.position.dx + 260, goal.position.dy + 80),
      priority: NodePriority.high,
      project: goal.project,
      area: goal.area,
      tags: const ['next-action'],
      relatedNodeIds: [goal.id],
      dueDate: day,
      data: {
        'relations': [
          {'targetId': goal.id, 'label': 'moves goal'},
        ],
      },
    );
    await repository.saveNode(node);
    _pushUndo(_UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node));
    invalidateMindmapState(ref, day: day, extraDay: goal.day);
    if (mounted) _showSnackBar('Next action created');
  }

  Future<void> _showDayTemplateSheet(
    DateTime day,
    List<MindmapNode> dayNodes,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: dayTemplates.length + 1,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.dashboard_customize_outlined),
                  title: const Text('Apply day template'),
                  subtitle: Text('One-click setup for ${dayKey(day)}'),
                );
              }
              final sortedTemplates = [
                ...dayTemplates.where(
                  (template) => template.id == 'personal-reset',
                ),
                ...dayTemplates.where(
                  (template) => template.id != 'personal-reset',
                ),
              ];
              final template = sortedTemplates[index - 1];
              final applied = hasAppliedDayTemplate(dayNodes, template.id);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: !applied,
                leading: Icon(
                  applied ? Icons.check_circle_outline : Icons.auto_awesome,
                  color: applied
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.primary,
                ),
                title: Text(template.label),
                subtitle: Text(
                  applied
                      ? 'Already applied'
                      : '${template.description} · ${template.drafts.length} nodes',
                ),
                onTap: applied
                    ? null
                    : () async {
                        Navigator.of(context).pop();
                        await _applyDayTemplate(day, template);
                      },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _applyDayTemplate(DateTime day, DayTemplate template) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final existingNodes =
        ref.read(nodesForDayProvider(day)).valueOrNull ?? const <MindmapNode>[];
    final nodes = buildDayTemplateNodes(
      template: template,
      day: day,
      now: DateTime.now(),
      idFactory: () => const Uuid().v4(),
      existingNodes: existingNodes,
    );
    if (nodes.isEmpty) {
      if (mounted) _showSnackBar('${template.label} already applied');
      return;
    }

    for (final node in nodes) {
      await repository.saveNode(node);
      _pushUndo(
        _UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node),
      );
    }
    invalidateMindmapState(ref, day: day);
    if (mounted) _showSnackBar('${template.label} applied');
  }

  Future<void> _createTomorrowTopTasks(
    DateTime day,
    MindmapNode review,
    List<String> titles,
  ) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final tomorrow = day.add(const Duration(days: 1)).dateOnly;
    final now = DateTime.now();
    final existingTomorrowNodes = await repository.listNodes(day: tomorrow);
    final existingTitles = existingTomorrowNodes
        .where((node) => node.tags.contains('tomorrow-top-3'))
        .map((node) => node.title.trim().toLowerCase())
        .toSet();
    var createdCount = 0;

    for (var i = 0; i < titles.length; i += 1) {
      final title = titles[i].trim();
      if (title.isEmpty || existingTitles.contains(title.toLowerCase())) {
        continue;
      }
      final node = MindmapNode.create(
        id: const Uuid().v4(),
        type: NodeType.task,
        title: title,
        day: tomorrow,
        position: CanvasPosition(120 + (i * 220), -120),
        priority: i == 0 ? NodePriority.high : NodePriority.medium,
        dueDate: tomorrow,
        tags: const ['daily-review', 'tomorrow-top-3'],
        relatedNodeIds: [review.id],
        data: {
          'relations': [
            {'targetId': review.id, 'label': 'from review'},
          ],
        },
        now: now.add(Duration(seconds: i)),
      );
      await repository.saveNode(node);
      existingTitles.add(title.toLowerCase());
      _pushUndo(
        _UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node),
      );
      createdCount += 1;
    }

    invalidateMindmapState(ref, day: day, extraDay: tomorrow);
    if (mounted) {
      if (createdCount == 0) {
        _showSnackBar('Tomorrow top 3 already created');
      } else {
        _showSnackBar(
          createdCount == 1
              ? 'Tomorrow task created'
              : '$createdCount tomorrow tasks created',
        );
      }
    }
  }

  Future<void> _openOrCreateDailyReview(
    DateTime day,
    List<MindmapNode> dayNodes,
  ) async {
    final existingReview = dayNodes.cast<MindmapNode?>().firstWhere(
      (node) =>
          node != null &&
          node.type == NodeType.journal &&
          (node.tags.contains('daily-review') ||
              node.title == dailyReviewTitle(day)),
      orElse: () => null,
    );
    if (existingReview != null) {
      setState(() {
        _selectedNodeId = existingReview.id;
        _isRightPanelOpen = true;
      });
      _showSnackBar('Daily review opened');
      return;
    }

    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final journalNodes = dayNodes
        .where((node) => node.type == NodeType.journal && !node.isArchived)
        .length;
    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: NodeType.journal,
      title: dailyReviewTitle(day),
      day: day,
      body: buildDailyReviewBody(day, dayNodes),
      position: CanvasPosition(0, -220 - (journalNodes * 120)),
      tags: const ['daily-review'],
      data: const {
        'journal': {'prompt': 'Daily review', 'isDailyReview': true},
      },
      now: now,
    );
    await repository.saveNode(node);
    _pushUndo(_UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node));
    invalidateMindmapState(ref, day: day);
    setState(() {
      _selectedNodeId = node.id;
      _isRightPanelOpen = true;
    });
    if (mounted) _showSnackBar('Daily review created');
  }

  void _pushUndo(_UndoEntry entry) {
    setState(() {
      _undoStack.add(entry);
      if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
      _redoStack.clear();
    });
  }

  Future<void> _undo() async {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    _redoStack.add(entry);
    setState(() {});
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
      if (context.mounted) _showUndoRedoSnackBar('Undo');
    } catch (e) {
      if (context.mounted) _showSnackBar('Undo failed: $e');
    }
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    _undoStack.add(entry);
    setState(() {});
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
      if (context.mounted) _showUndoRedoSnackBar('Redo');
    } catch (e) {
      if (context.mounted) _showSnackBar('Redo failed: $e');
    }
  }

  void _showSnackBar(String message) {
    _showCompactSnackBar(
      icon: Icons.check_circle_outline_rounded,
      message: message,
      duration: const Duration(milliseconds: 1600),
    );
  }

  Future<void> _copyDayMarkdown(DateTime day, List<MindmapNode> nodes) async {
    final markdown = buildDayMarkdownExport(day: day, nodes: nodes);
    await Clipboard.setData(ClipboardData(text: markdown));
    if (mounted) _showSnackBar('Day markdown copied');
  }

  void _showActivityLog() {
    setState(() {
      _selectedNodeId = null;
      _isRightPanelOpen = false;
    });
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ActivityLogSheet(
        undoEntries: _undoStack.reversed.toList(),
        redoEntries: _redoStack.reversed.toList(),
        onUndo: _undoStack.isEmpty
            ? null
            : () {
                Navigator.of(context).pop();
                unawaited(_undo());
              },
        onRedo: _redoStack.isEmpty
            ? null
            : () {
                Navigator.of(context).pop();
                unawaited(_redo());
              },
      ),
    );
  }

  void _showUndoRedoSnackBar(String action) {
    final undoCount = _undoStack.length;
    final redoCount = _redoStack.length;
    final canUndo = undoCount > 0;
    final canRedo = redoCount > 0;
    final showRedo = action == 'Undo' && canRedo;
    final showUndo = action == 'Redo' && canUndo;

    _showCompactSnackBar(
      icon: Icons.history_rounded,
      message: '$action • $undoCount undo / $redoCount redo',
      duration: const Duration(milliseconds: 2200),
      actionLabel: showRedo
          ? 'Redo'
          : showUndo
          ? 'Undo'
          : null,
      onActionPressed: showRedo
          ? _redo
          : showUndo
          ? _undo
          : null,
    );
  }

  void _showCompactSnackBar({
    required IconData icon,
    required String message,
    required Duration duration,
    String? actionLabel,
    VoidCallback? onActionPressed,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final snackWidth = screenWidth < 420 ? screenWidth - 32 : 388.0;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: snackWidth,
        duration: duration,
        dismissDirection: DismissDirection.horizontal,
        elevation: 14,
        backgroundColor: colorScheme.surfaceContainerHighest,
        shape: DoodleShapeBorder(
          side: BorderSide(color: colorScheme.outlineVariant),
          radius: 18,
          wobble: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 17, color: colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (actionLabel != null && onActionPressed != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  onActionPressed();
                },
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
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
    final workspaceContexts = ref.watch(workspaceContextsProvider);
    final activeWorkspaceContext = _workspaceContextForKey(
      workspaceContexts.valueOrNull,
      _workspaceContextKey,
    );
    final automationSuggestions = ref.watch(automationSuggestionsProvider);

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
              return _DayQuickCreateFab(
                onMore: () => _showQuickCreateSheet(context),
                onSelectType: (NodeType type) {
                  final currentNodes =
                      ref
                          .read(nodesForDayProvider(widget.date.dateOnly))
                          .valueOrNull ??
                      const <MindmapNode>[];
                  _createNodeOfType(
                    context,
                    ref,
                    widget.date.dateOnly,
                    currentNodes,
                    type,
                    null,
                  );
                },
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
                          child: _InlineWorkspaceTitle(
                            customTitle: customTitle,
                            displayTitle: displayTitle,
                            onTitleChanged: (String title) => ref
                                .read(workspaceTitleProvider.notifier)
                                .setTitle(
                                  WorkspaceContextType.daily,
                                  dayKey(normalizedDate),
                                  title,
                                ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: _DayTopTabStrip(
                selectedDay: normalizedDate,
                isCollapsed: _isDayTabsCollapsed,
                onDaySelected: (day) => goToDay(context, day),
                onCollapsedChanged: (value) {
                  setState(() => _isDayTabsCollapsed = value);
                },
              ),
            ),
            actions: [
              Builder(
                builder: (context) {
                  final actionWidth = MediaQuery.sizeOf(context).width * 0.62;
                  final showViewToggle =
                      MediaQuery.sizeOf(context).width >= 900;
                  return SizedBox(
                    width: actionWidth,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showViewToggle) ...[
                            _DayViewModeToggle(
                              mode: _viewMode,
                              onChanged: (value) {
                                _setViewMode(value);
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                          _DayContextSwitcher(
                            filter: _contextFilter,
                            workspaceContext: activeWorkspaceContext,
                            workspaceContexts: workspaceContexts.valueOrNull,
                            onChanged: _setContextFilter,
                            onWorkspaceChanged: _setWorkspaceContextFilter,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Copy day markdown',
                            onPressed: () => unawaited(
                              _copyDayMarkdown(
                                normalizedDate,
                                allNodes.valueOrNull ?? const <MindmapNode>[],
                              ),
                            ),
                            icon: const Icon(Icons.ios_share_outlined),
                          ),
                          const SizedBox(width: 8),
                          _UndoRedoIndicator(
                            undoCount: _undoStack.length,
                            redoCount: _redoStack.length,
                            onUndo: _undoStack.isEmpty ? null : _undo,
                            onRedo: _redoStack.isEmpty ? null : _redo,
                            onHistory: _showActivityLog,
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: nodes.when(
            data: (value) {
              final canvasNodes = _canvasNodesFor(
                activeNodes: value,
                allNodes: allNodes.valueOrNull ?? const <MindmapNode>[],
                day: normalizedDate,
                highlightedNodeId: widget.highlightNodeId,
              );

              final allNodeList = allNodes.valueOrNull ?? const <MindmapNode>[];
              final readyRoutineCount =
                  normalizedDate == DateTime.now().dateOnly
                  ? automationSuggestions.valueOrNull?.readyCount ?? 0
                  : 0;
              final planningSuggestions = _dailyPlanningSuggestions(
                day: normalizedDate,
                nodes: allNodeList,
                dayNodes: value,
                readyRoutineCount: readyRoutineCount,
              );
              final missionStats = _buildDailyMissionStats(
                value,
                normalizedDate,
                readyRoutineCount: readyRoutineCount,
              );

              final miniInsights = buildDayMiniInsights(
                nodes: allNodeList,
                selectedDay: normalizedDate,
              );
              final inboxNodes = inboxNodesForDay(allNodeList, normalizedDate);
              final filteredDayNodes = value
                  .where(_matchesActiveContext)
                  .toList();
              final filteredCanvasNodes = canvasNodes
                  .where(
                    (node) =>
                        node.id == widget.highlightNodeId ||
                        _matchesActiveContext(node),
                  )
                  .toList();
              final missionNodes = filteredDayNodes
                  .where(isTodayMission)
                  .toList();
              final visibleCanvasNodes =
                  _isMissionMode && missionNodes.isNotEmpty
                  ? filteredCanvasNodes.where(isTodayMission).toList()
                  : filteredCanvasNodes;

              return Column(
                children: [
                  _DayToolsBar(
                    stats: missionStats,
                    planningSuggestions: planningSuggestions,
                    miniInsights: miniInsights,
                    selectedDay: normalizedDate,
                    isMissionMode: _isMissionMode,
                    isFocusRunning: _focusStartedAt != null,
                    focusElapsed: _focusElapsed,
                    focusRemaining: _focusRemaining,
                    inboxCount: inboxNodes.length,
                    onShowStatus: () => _showDayStatusSheet(missionStats),
                    onShowPlan: () => _showDayPlanSheet(planningSuggestions),
                    onShowPulse: () => _showDayPulseSheet(
                      insights: miniInsights,
                      selectedDay: normalizedDate,
                    ),
                    onToggleMissionMode: missionNodes.isEmpty
                        ? null
                        : () =>
                              setState(() => _isMissionMode = !_isMissionMode),
                    onStopFocus: _focusStartedAt == null || missionNodes.isEmpty
                        ? null
                        : () => _stopFocusSession(
                            missionNodes.firstWhere(
                              (node) => node.id == _focusNodeId,
                              orElse: () => missionNodes.first,
                            ),
                          ),
                    onInboxPressed: inboxNodes.isEmpty
                        ? null
                        : () => _showInboxSheet(
                            context,
                            inboxNodes,
                            normalizedDate,
                          ),
                    onQuickCapture: _showQuickCaptureSheet,
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: _viewMode == _DayViewMode.timeline
                                    ? DailyTimelineSchedule(
                                        day: normalizedDate,
                                        nodes: filteredDayNodes,
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
                                      )
                                    : _viewMode == _DayViewMode.board
                                    ? _DayNodeBoardView(
                                        nodes: filteredDayNodes,
                                        selectedNodeId: _selectedNodeId,
                                        onNodeSelected: (node) {
                                          setState(() {
                                            _selectedNodeId = node.id;
                                            _isRightPanelOpen = true;
                                          });
                                        },
                                        onNodeUpdated: (updatedNode) async {
                                          final currentNode = value.firstWhere(
                                            (node) => node.id == updatedNode.id,
                                            orElse: () => updatedNode,
                                          );
                                          final repository = ref.read(
                                            mindmapRepositoryProvider,
                                          );
                                          _pushUndo(
                                            _UndoEntry(
                                              kind: _UndoKind.save,
                                              nodeId: updatedNode.id,
                                              before: currentNode,
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
                                              _showSnackBar('Board updated');
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              _showSnackBar(
                                                'Failed to update board: $e',
                                              );
                                            }
                                          }
                                        },
                                      )
                                    : _viewMode == _DayViewMode.table
                                    ? _DayNodeTableView(
                                        nodes: filteredDayNodes,
                                        selectedNodeId: _selectedNodeId,
                                        view: _tableQuickView,
                                        sortMode: _tableSortMode,
                                        onViewChanged: _setTableQuickView,
                                        onSortModeChanged: _setTableSortMode,
                                        onNodeSelected: (node) {
                                          setState(() {
                                            _selectedNodeId = node.id;
                                            _isRightPanelOpen = true;
                                          });
                                        },
                                        onNodeUpdated: (updatedNode) async {
                                          final currentNode = value.firstWhere(
                                            (node) => node.id == updatedNode.id,
                                            orElse: () => updatedNode,
                                          );
                                          final repository = ref.read(
                                            mindmapRepositoryProvider,
                                          );
                                          _pushUndo(
                                            _UndoEntry(
                                              kind: _UndoKind.save,
                                              nodeId: updatedNode.id,
                                              before: currentNode,
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
                                              _showSnackBar('Table updated');
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              _showSnackBar(
                                                'Failed to update table: $e',
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
                                              nodes: visibleCanvasNodes,
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
                                              onClearNodes: () =>
                                                  _clearMindmapNodes(
                                                    context,
                                                    ref,
                                                    normalizedDate,
                                                    canvasNodes,
                                                  ),
                                              onCanvasContextMenu:
                                                  (
                                                    globalPosition,
                                                    canvasPosition,
                                                  ) {
                                                    _showCanvasAddNodeMenu(
                                                      context,
                                                      ref,
                                                      normalizedDate,
                                                      canvasNodes,
                                                      globalPosition,
                                                      canvasPosition,
                                                    );
                                                  },
                                              onConnectedNodeCreate:
                                                  (
                                                    source,
                                                    type,
                                                    canvasPosition,
                                                  ) {
                                                    return _createNodeOfType(
                                                      context,
                                                      ref,
                                                      normalizedDate,
                                                      canvasNodes,
                                                      type,
                                                      canvasPosition,
                                                      title:
                                                          '${source.title} · ${type.label}',
                                                    );
                                                  },
                                              onNodeSelected: (node) {
                                                if (node.isDone &&
                                                    filteredDayNodes.length ==
                                                        1) {
                                                  unawaited(
                                                    _createSelectedNodeFollowUp(
                                                      node,
                                                    ),
                                                  );
                                                  return;
                                                }
                                                setState(() {
                                                  _selectedNodeId = node.id;
                                                  _isRightPanelOpen = true;
                                                });
                                              },
                                              onNodeConnected: (source, target) async {
                                                final repository = ref.read(
                                                  mindmapRepositoryProvider,
                                                );
                                                final relatedNodeIds = {
                                                  ...source.relatedNodeIds,
                                                  target.id,
                                                }.toList();
                                                final updatedNode = source
                                                    .copyWith(
                                                      relatedNodeIds:
                                                          relatedNodeIds,
                                                      data: {
                                                        ...source.data,
                                                        'relations':
                                                            _relationDataForIds(
                                                              source,
                                                              relatedNodeIds,
                                                            ),
                                                      },
                                                      updatedAt: DateTime.now(),
                                                    );
                                                _pushUndo(
                                                  _UndoEntry(
                                                    kind: _UndoKind.save,
                                                    nodeId: source.id,
                                                    before: source,
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
                                                      'Connected ${source.title} → ${target.title}',
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    _showSnackBar(
                                                      'Failed to connect nodes: $e',
                                                    );
                                                  }
                                                }
                                              },
                                              onNodeDisconnected: (source, target) async {
                                                final repository = ref.read(
                                                  mindmapRepositoryProvider,
                                                );
                                                MindmapNode nodeToUpdate;
                                                List<String> relatedNodeIds;
                                                if (source.relatedNodeIds
                                                    .contains(target.id)) {
                                                  nodeToUpdate = source;
                                                  relatedNodeIds = source
                                                      .relatedNodeIds
                                                      .where(
                                                        (id) => id != target.id,
                                                      )
                                                      .toList();
                                                } else if (target.relatedNodeIds
                                                    .contains(source.id)) {
                                                  nodeToUpdate = target;
                                                  relatedNodeIds = target
                                                      .relatedNodeIds
                                                      .where(
                                                        (id) => id != source.id,
                                                      )
                                                      .toList();
                                                } else {
                                                  return;
                                                }
                                                final updatedNode = nodeToUpdate
                                                    .copyWith(
                                                      relatedNodeIds:
                                                          relatedNodeIds,
                                                      data: {
                                                        ...nodeToUpdate.data,
                                                        'relations':
                                                            _relationDataForIds(
                                                              nodeToUpdate,
                                                              relatedNodeIds,
                                                            ),
                                                      },
                                                      updatedAt: DateTime.now(),
                                                    );
                                                _pushUndo(
                                                  _UndoEntry(
                                                    kind: _UndoKind.save,
                                                    nodeId: nodeToUpdate.id,
                                                    before: nodeToUpdate,
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
                                                      'Disconnected ${source.title} ↮ ${target.title}',
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    _showSnackBar(
                                                      'Failed to disconnect nodes: $e',
                                                    );
                                                  }
                                                }
                                              },
                                              onNodeUpdated: (updatedNode) async {
                                                final repository = ref.read(
                                                  mindmapRepositoryProvider,
                                                );
                                                MindmapNode? previousNode;
                                                for (final node
                                                    in canvasNodes) {
                                                  if (node.id ==
                                                      updatedNode.id) {
                                                    previousNode = node;
                                                    break;
                                                  }
                                                }
                                                if (previousNode != null) {
                                                  _pushUndo(
                                                    _UndoEntry(
                                                      kind: _UndoKind.save,
                                                      nodeId: updatedNode.id,
                                                      before: previousNode,
                                                      after: updatedNode,
                                                    ),
                                                  );
                                                }
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
                                                      'Node updated',
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    _showSnackBar(
                                                      'Failed to update node: $e',
                                                    );
                                                  }
                                                }
                                              },
                                              onTaskDoneChanged:
                                                  (node, isDone) async {
                                                    final repository = ref.read(
                                                      mindmapRepositoryProvider,
                                                    );
                                                    final updatedNode = node
                                                        .copyWith(
                                                          isDone: isDone,
                                                          status: isDone
                                                              ? NodeStatus.done
                                                              : NodeStatus.open,
                                                          progress: isDone
                                                              ? 1
                                                              : node.progress,
                                                          updatedAt:
                                                              DateTime.now(),
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
                                                        .moveCardToNextColumn(
                                                          cardId,
                                                        );
                                                    final repository = ref.read(
                                                      mindmapRepositoryProvider,
                                                    );
                                                    final updatedNode = node
                                                        .copyWith(
                                                          data: {
                                                            ...node.data,
                                                            'kanban':
                                                                updatedBoard
                                                                    .toJson(),
                                                          },
                                                          updatedAt:
                                                              DateTime.now(),
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
                                                          'Card moved',
                                                        );
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
                                                    _showSnackBar(
                                                      'Habit logged',
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    _showSnackBar(
                                                      'Failed to log habit: $e',
                                                    );
                                                  }
                                                }
                                              },
                                              onGoalMilestoneAdvanced:
                                                  (node) async {
                                                    final repository = ref.read(
                                                      mindmapRepositoryProvider,
                                                    );
                                                    final updatedNode =
                                                        advanceGoalMilestone(
                                                          node,
                                                          now: DateTime.now(),
                                                        );
                                                    if (updatedNode == node) {
                                                      return;
                                                    }

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
                                                final updatedNode =
                                                    advancePlanStep(
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
                                                      'Step advanced',
                                                    );
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
                                                final updatedNode = node
                                                    .copyWith(
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
                                          Positioned(
                                            left: 16,
                                            top: 16,
                                            child: MouseRegion(
                                              onEnter: (_) {
                                                setState(
                                                  () =>
                                                      _isCanvasAddNodeFabHovered =
                                                          true,
                                                );
                                                Future<void>.delayed(
                                                  const Duration(
                                                    milliseconds: 90,
                                                  ),
                                                  () {
                                                    if (!mounted ||
                                                        !_isCanvasAddNodeFabHovered) {
                                                      return;
                                                    }
                                                    unawaited(
                                                      _showCanvasAddNodeMenuFromFab(
                                                        ref,
                                                        normalizedDate,
                                                        value,
                                                      ),
                                                    );
                                                  },
                                                );
                                              },
                                              onExit: (_) => setState(
                                                () =>
                                                    _isCanvasAddNodeFabHovered =
                                                        false,
                                              ),
                                              child: AnimatedScale(
                                                key: const ValueKey(
                                                  'canvas-add-node-fab-hover-scale',
                                                ),
                                                scale:
                                                    _isCanvasAddNodeFabHovered
                                                    ? 1.16
                                                    : 1,
                                                duration: const Duration(
                                                  milliseconds: 160,
                                                ),
                                                curve: Curves.easeOutBack,
                                                child: AnimatedRotation(
                                                  turns:
                                                      _isCanvasAddNodeFabHovered
                                                      ? 0.125
                                                      : 0,
                                                  duration: const Duration(
                                                    milliseconds: 180,
                                                  ),
                                                  curve: Curves.easeOutBack,
                                                  child: AnimatedContainer(
                                                    duration: const Duration(
                                                      milliseconds: 160,
                                                    ),
                                                    curve: Curves.easeOutCubic,
                                                    padding: EdgeInsets.all(
                                                      _isCanvasAddNodeFabHovered
                                                          ? 4
                                                          : 0,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          _isCanvasAddNodeFabHovered
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                                .withValues(
                                                                  alpha: 0.16,
                                                                )
                                                          : Colors.transparent,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: FloatingActionButton.small(
                                                      tooltip: 'Add node',
                                                      heroTag:
                                                          'day-canvas-add-node',
                                                      onPressed: () => unawaited(
                                                        _showCanvasAddNodeMenuFromFab(
                                                          ref,
                                                          normalizedDate,
                                                          value,
                                                        ),
                                                      ),
                                                      child: const Icon(
                                                        Icons.add,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (value.isEmpty &&
                                              !_isBlankBoardHidden)
                                            Center(
                                              child: _DayEmptyStateCockpit(
                                                onDismiss: () => setState(
                                                  () => _isBlankBoardHidden =
                                                      true,
                                                ),
                                                onPlanDay: () => unawaited(
                                                  _showDayTemplateSheet(
                                                    normalizedDate,
                                                    value,
                                                  ),
                                                ),
                                                onImportLeftovers: () => unawaited(
                                                  _showCarryOverSheet(
                                                    normalizedDate,
                                                    buildCarryOverCandidates(
                                                      nodes: allNodeList,
                                                      selectedDay:
                                                          normalizedDate,
                                                    ),
                                                    title:
                                                        'Import yesterday leftovers',
                                                  ),
                                                ),
                                                onStartJournal: () => unawaited(
                                                  _openOrCreateDailyReview(
                                                    normalizedDate,
                                                    value,
                                                  ),
                                                ),
                                                onApplyRoutine: () => unawaited(
                                                  _applyRoutines(
                                                    context,
                                                    ref,
                                                    normalizedDate,
                                                  ),
                                                ),
                                                onUseTemplate: () => unawaited(
                                                  _showDayTemplateSheet(
                                                    normalizedDate,
                                                    value,
                                                  ),
                                                ),
                                                onQuickCapture:
                                                    _showQuickCaptureSheet,
                                              ),
                                            ),

                                          if (widget.highlightNodeId != null)
                                            Positioned(
                                              left: 20,
                                              bottom: 20,
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
                        if (selectedNode case final activeSelectedNode?) ...[
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
                                    message:
                                        activeSelectedNode.title.trim().isEmpty
                                        ? 'Untitled ${activeSelectedNode.type.name}'
                                        : activeSelectedNode.title.trim(),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: nodeColor(
                                          activeSelectedNode.type,
                                        ).withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        nodeIcon(activeSelectedNode.type),
                                        color: nodeColor(
                                          activeSelectedNode.type,
                                        ),
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
                              child: Tooltip(
                                message: 'Drag to resize editor panel',
                                waitDuration: const Duration(milliseconds: 500),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onPanStart: (_) =>
                                      setState(() => _isDraggingRight = true),
                                  onPanEnd: (_) =>
                                      setState(() => _isDraggingRight = false),
                                  onPanCancel: () =>
                                      setState(() => _isDraggingRight = false),
                                  onPanUpdate: (details) {
                                    setState(() {
                                      _rightPanelWidth =
                                          (_rightPanelWidth - details.delta.dx)
                                              .clamp(
                                                280.0,
                                                MediaQuery.of(
                                                      context,
                                                    ).size.width *
                                                    0.5,
                                              );
                                    });
                                  },
                                  child: Container(
                                    width: 10,
                                    decoration: BoxDecoration(
                                      color: _isDraggingRight
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(context)
                                                .colorScheme
                                                .outlineVariant
                                                .withValues(alpha: 0.35),
                                      border: Border(
                                        left: BorderSide(
                                          color: _isDraggingRight
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
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
                                          borderRadius: BorderRadius.circular(
                                            1,
                                          ),
                                        ),
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
                              child: Column(
                                children: [
                                  if (!activeSelectedNode.isArchived)
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxHeight: 160,
                                      ),
                                      child: SingleChildScrollView(
                                        child: _SelectedNodeMissionActions(
                                          node: activeSelectedNode,
                                          actions: _selectedNodeActions(
                                            activeSelectedNode,
                                          ),
                                          isMission: isTodayMission(
                                            activeSelectedNode,
                                          ),
                                          isFocusRunning:
                                              _focusNodeId ==
                                                  activeSelectedNode.id &&
                                              _focusStartedAt != null,
                                          isCollapsed:
                                              _isSelectedNodeToolsCollapsed,
                                          focusElapsed: _focusElapsed,
                                          focusRemaining: _focusRemaining,
                                          onToggleCollapsed: () => setState(
                                            () => _isSelectedNodeToolsCollapsed =
                                                !_isSelectedNodeToolsCollapsed,
                                          ),
                                          onToggleMission: () =>
                                              _toggleTodayMission(
                                                activeSelectedNode,
                                              ),
                                          onStartFocus: () =>
                                              _startFocusSession(
                                                activeSelectedNode,
                                              ),
                                          onStartPomodoro: (minutes) =>
                                              _startFocusSession(
                                                activeSelectedNode,
                                                targetMinutes: minutes,
                                              ),
                                          onStartCustomFocus: () =>
                                              _showCustomFocusDialog(
                                                activeSelectedNode,
                                              ),
                                          onStopFocus: () => _stopFocusSession(
                                            activeSelectedNode,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: NodeEditorPanel(
                                      node: activeSelectedNode,
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
                                        if (!wasNewNode) {
                                          _pushUndo(
                                            _UndoEntry(
                                              kind: _UndoKind.save,
                                              nodeId: updatedNode.id,
                                              before: activeSelectedNode,
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
                                          await repository.saveNode(
                                            updatedNode,
                                          );
                                          invalidateMindmapState(
                                            ref,
                                            day: normalizedDate,
                                          );
                                          if (context.mounted) {
                                            _showSnackBar(
                                              wasNewNode
                                                  ? 'Node created'
                                                  : 'Node saved',
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
                                      onOpenNode: (node) {
                                        setState(() {
                                          _selectedNodeId = node.id;
                                          _isRightPanelOpen = true;
                                        });
                                      },
                                      onDelete: () async {
                                        final repository = ref.read(
                                          mindmapRepositoryProvider,
                                        );
                                        final deleteNode = activeSelectedNode;
                                        _pushUndo(
                                          _UndoEntry(
                                            kind: _UndoKind.delete,
                                            nodeId: deleteNode.id,
                                            before: deleteNode,
                                          ),
                                        );
                                        try {
                                          await repository.deleteNode(
                                            deleteNode.id,
                                          );
                                          invalidateMindmapState(
                                            ref,
                                            day: normalizedDate,
                                          );
                                          setState(() {
                                            _selectedNodeId = null;
                                          });
                                          if (context.mounted) {
                                            _showSnackBar('Node deleted');
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            _showSnackBar(
                                              'Failed to delete: $e',
                                            );
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
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

  void _showDayStatusSheet(_DailyMissionStats stats) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: _DailyMissionDashboard(stats: stats),
          ),
        );
      },
    );
  }

  void _showDayPlanSheet(List<_DailyPlanningSuggestion> suggestions) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: suggestions.isEmpty
                ? ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('Plan'),
                    subtitle: Text(
                      'No suggestions now.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : _DailyPlanningSuggestionsBar(suggestions: suggestions),
          ),
        );
      },
    );
  }

  void _showDayPulseSheet({
    required List<DayMiniInsight> insights,
    required DateTime selectedDay,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: _DayMiniInsightsStrip(
              insights: insights,
              selectedDay: selectedDay,
              onDaySelected: (day) {
                Navigator.of(sheetContext).pop();
                goToDay(context, day);
              },
            ),
          ),
        );
      },
    );
  }

  void _showQuickCaptureSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        void submit() {
          final query = _quickCaptureController.text.trim();
          if (query.isEmpty) return;
          Navigator.of(sheetContext).pop();
          unawaited(_submitQuickCapture(query));
        }

        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              left: 16,
              right: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Quick capture',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Type fast command. Example: task bayar listrik p1 #home.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('day-quick-capture-field'),
                    controller: _quickCaptureController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'task bayar listrik p1 #home',
                      border: DoodleInputBorder(),
                      prefixIcon: Icon(Icons.keyboard_command_key_rounded),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _QuickCaptureHint(
                        text: 'event meeting 14:00-15:00 @work',
                        controller: _quickCaptureController,
                      ),
                      _QuickCaptureHint(
                        text: 'habit workout daily',
                        controller: _quickCaptureController,
                      ),
                      _QuickCaptureHint(
                        text: 'note idea aplikasi baru #product',
                        controller: _quickCaptureController,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: submit,
                    icon: const Icon(Icons.bolt_outlined),
                    label: const Text('Capture'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitQuickCapture(String query) async {
    await _createNodeFromQuickCapture(query);
    _quickCaptureController.clear();
  }

  void _showQuickCreateSheet(BuildContext context) {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final nameController = TextEditingController();
        final bodyController = TextEditingController();
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Quick Create', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Capture fast. Try: task bayar listrik p1 #home or event meeting 14:00-15:00 @work.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Node title...',
                        border: DoodleInputBorder(),
                        prefixIcon: Icon(Icons.edit_outlined),
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty) {
                          Navigator.pop(ctx, 'command:${value.trim()}');
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
                              customBorder: const DoodleShapeBorder(
                                radius: 12,
                                wobble: 1.5,
                              ),
                              onTap: () => Navigator.pop(
                                ctx,
                                '${type.name}:${nameController.text.trim()}|${bodyController.text.trim()}',
                              ),
                              child: Container(
                                decoration: ShapeDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  shape: DoodleShapeBorder(
                                    side: BorderSide(
                                      color: color.withValues(alpha: 0.3),
                                    ),
                                    radius: 12,
                                    wobble: 1.5,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      nodeIcon(type),
                                      color: color,
                                      size: 22,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      type.label,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
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
                    const SizedBox(height: 8),
                    TextField(
                      controller: bodyController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Optional inbox notes, context, links...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.inbox_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((result) {
      if (result is String && result.startsWith('command:')) {
        final query = result.substring('command:'.length).trim();
        _createNodeFromQuickCapture(query);
      } else if (result is String && result.contains(':')) {
        final colonIndex = result.indexOf(':');
        final typeName = result.substring(0, colonIndex);
        final payload = result.substring(colonIndex + 1);
        final separatorIndex = payload.indexOf('|');
        final title = separatorIndex == -1
            ? payload.trim()
            : payload.substring(0, separatorIndex).trim();
        final body = separatorIndex == -1
            ? null
            : payload.substring(separatorIndex + 1).trim();
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
            body: body,
          );
        }
      }
    });
  }

  Future<void> _createNodeFromQuickCapture(String query) async {
    final day = widget.date.dateOnly;
    final command = quickCreateCommandFromQuery(
      query,
      today: DateTime.now().dateOnly,
      defaultDay: day,
    );
    final now = DateTime.now();
    final nodeDay = command?.day ?? day;
    final currentNodes =
        ref.read(nodesForDayProvider(nodeDay)).valueOrNull ??
        const <MindmapNode>[];
    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: command?.type ?? NodeType.note,
      title: command?.title ?? query,
      day: nodeDay,
      body: command?.body ?? '',
      position: _nextNodePosition(currentNodes.length),
      status: command?.status ?? NodeStatus.open,
      priority: command?.priority ?? NodePriority.none,
      project: command?.project ?? '',
      area: command?.area ?? '',
      tags: command?.tags ?? const [],
      dueDate: command?.dueDate,
      progress: command?.progress ?? 0,
      isPinned: command?.isPinned ?? false,
      isArchived: command?.isArchived ?? false,
      checklist: [
        for (final title in command?.checklistTitles ?? const <String>[])
          TaskChecklistItem(id: const Uuid().v4(), title: title),
      ],
      relatedNodeIds: command?.relatedNodeIds ?? const [],
      data: command?.data ?? const {},
      now: now,
    );
    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(node);
    _pushUndo(_UndoEntry(kind: _UndoKind.create, nodeId: node.id, after: node));
    invalidateMindmapState(ref, day: nodeDay, extraDay: day);
    if (mounted) {
      if (nodeDay != day) {
        context.go('/calendar/${dayKey(nodeDay)}?highlight=${node.id}');
        _showSnackBar(
          'Captured ${node.type.label.toLowerCase()} for ${dayKey(nodeDay)}',
        );
        return;
      }
      setState(() {
        _selectedNodeId = node.id;
        _isRightPanelOpen = true;
      });
      _showSnackBar('Captured ${node.type.label.toLowerCase()}');
    }
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

  Future<void> _showCanvasAddNodeMenuFromFab(
    WidgetRef ref,
    DateTime day,
    List<MindmapNode> currentNodes,
  ) async {
    if (_isCanvasAddNodeMenuOpen) return;
    _isCanvasAddNodeMenuOpen = true;
    try {
      await _showCanvasAddNodeMenu(
        context,
        ref,
        day,
        currentNodes,
        const Offset(72, 160),
        const Offset(96, 96),
      );
    } finally {
      _isCanvasAddNodeMenuOpen = false;
    }
  }

  Future<void> _showCanvasAddNodeMenu(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    List<MindmapNode> currentNodes,
    Offset globalPosition,
    Offset canvasPosition,
  ) async {
    const panelWidth = 368.0;
    const panelHeight = 374.0;
    const margin = 12.0;
    final screenSize = MediaQuery.sizeOf(context);
    final left = globalPosition.dx.clamp(
      margin,
      (screenSize.width - panelWidth - margin).clamp(margin, screenSize.width),
    );
    final top = globalPosition.dy.clamp(
      margin,
      (screenSize.height - panelHeight - margin).clamp(
        margin,
        screenSize.height,
      ),
    );

    final selectedType = await showGeneralDialog<NodeType>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              left: left.toDouble(),
              top: top.toDouble(),
              child: _CanvasAddNodeContextPanel(
                types: const [
                  ..._canvasPrimaryAddTypes,
                  ..._canvasMoreAddTypes,
                ],
                onSelect: (NodeType type) => Navigator.of(context).pop(type),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            alignment: Alignment.topLeft,
            child: child,
          ),
        );
      },
    );
    if (selectedType == null || !context.mounted) return;
    await _createNodeOfType(
      context,
      ref,
      day,
      currentNodes,
      selectedType,
      canvasPosition,
    );
  }

  static const List<NodeType> _canvasPrimaryAddTypes = [
    NodeType.task,
    NodeType.note,
    NodeType.event,
    NodeType.idea,
    NodeType.question,
    NodeType.bookmark,
  ];

  static const List<NodeType> _canvasMoreAddTypes = [
    NodeType.decision,
    NodeType.resource,
    NodeType.plan,
    NodeType.habit,
    NodeType.goal,
    NodeType.contact,
    NodeType.metric,
    NodeType.expense,
    NodeType.routine,
    NodeType.kanban,
  ];

  Future<void> _clearMindmapNodes(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    List<MindmapNode> nodes,
  ) async {
    if (nodes.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear mindmap nodes?'),
        content: Text(
          'This will delete ${nodes.length} node${nodes.length == 1 ? '' : 's'} from this day. You can undo them one by one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clear nodes'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repository = ref.read(mindmapRepositoryProvider);
    for (final node in nodes) {
      _pushUndo(
        _UndoEntry(kind: _UndoKind.delete, nodeId: node.id, before: node),
      );
      await repository.deleteNode(node.id);
    }
    invalidateMindmapState(ref, day: day);
    if (!context.mounted) return;
    setState(() => _selectedNodeId = null);
    _showSnackBar('Cleared ${nodes.length} nodes');
  }

  Future<MindmapNode?> _createNodeOfType(
    BuildContext context,
    WidgetRef ref,
    DateTime day,
    List<MindmapNode> currentNodes,
    NodeType type,
    Offset? position, {
    String? title,
    String? body,
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
      NodeType.event => '## Agenda\n- \n\n## Notes\n',
      NodeType.decision => '## Decision\n\n## Options\n- \n\n## Rationale\n',
      NodeType.resource => '## Resource\n\nURL or reference:\n',
      NodeType.idea => '## Spark\n\n## Why it matters\n\n## Next experiment\n',
      NodeType.question =>
        '## Question\n\n## Context\n\n## Possible answers\n- ',
      NodeType.contact => '## Contact\n\nName:\nRole:\nEmail:\nNotes:\n',
      NodeType.metric => '## Metric\n\nValue:\nUnit:\nTrend:\n',
      NodeType.expense => '## Expense\n\nAmount:\nCategory:\nNotes:\n',
      NodeType.bookmark => '## Bookmark\n\nURL:\nWhy saved:\n',
      NodeType.routine => '## Routine\n\nTrigger:\nSteps:\n- ',
      NodeType.empty => '',
    };

    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: type,
      title: nodeTitle,
      body: body == null || body.trim().isEmpty ? bodyTemplate : body.trim(),
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
      return node;
    } catch (e) {
      if (context.mounted) _showSnackBar('Failed to create node: $e');
      return null;
    }
  }

  Duration get _focusElapsed {
    final startedAt = _focusStartedAt;
    if (startedAt == null) return Duration.zero;
    return DateTime.now().difference(startedAt);
  }

  Duration? get _focusRemaining {
    final targetMinutes = _focusTargetMinutes;
    if (targetMinutes == null || _focusStartedAt == null) return null;
    final remaining = Duration(minutes: targetMinutes) - _focusElapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _showInboxSheet(
    BuildContext context,
    List<MindmapNode> inboxNodes,
    DateTime day,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: inboxNodes.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: const Text('Inbox'),
                  subtitle: Text('${inboxNodes.length} loose captures'),
                );
              }
              final node = inboxNodes[index - 1];
              return ListTile(
                leading: Icon(nodeIcon(node.type)),
                title: Text(
                  node.title.trim().isEmpty ? 'Untitled' : node.title,
                ),
                subtitle: Text(node.type.label),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      tooltip: 'Assign today',
                      icon: const Icon(Icons.today_outlined),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _assignInboxNode(node, day);
                      },
                    ),
                    IconButton(
                      tooltip: 'Assign tomorrow',
                      icon: const Icon(Icons.event_available_outlined),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _assignInboxNode(
                          node,
                          day.add(const Duration(days: 1)),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'Archive',
                      icon: const Icon(Icons.archive_outlined),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _archiveInboxNode(node, day);
                      },
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() {
                    _selectedNodeId = node.id;
                    _isRightPanelOpen = true;
                  });
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _assignInboxNode(MindmapNode node, DateTime day) async {
    final updated = assignInboxNodeToDay(node, day);
    final repository = ref.read(mindmapRepositoryProvider);
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.save,
        nodeId: node.id,
        before: node,
        after: updated,
      ),
    );
    await repository.saveNode(updated);
    invalidateMindmapState(ref, day: node.day, extraDay: updated.day);
    if (mounted) _showSnackBar('Inbox item assigned');
  }

  Future<void> _archiveInboxNode(MindmapNode node, DateTime day) async {
    final updated = node.copyWith(isArchived: true, updatedAt: DateTime.now());
    final repository = ref.read(mindmapRepositoryProvider);
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.save,
        nodeId: node.id,
        before: node,
        after: updated,
      ),
    );
    await repository.saveNode(updated);
    invalidateMindmapState(ref, day: node.day, extraDay: day);
    if (mounted) _showSnackBar('Inbox item archived');
  }

  List<_SelectedNodeAction> _selectedNodeActions(MindmapNode node) {
    return [
      if (!node.isDone)
        _SelectedNodeAction(
          icon: Icons.check_circle_outline,
          label: 'Mark done',
          onPressed: () => unawaited(_markSelectedNodeDone(node)),
        ),
      if (node.type != NodeType.task)
        _SelectedNodeAction(
          icon: Icons.check_box_outlined,
          label: 'Convert to task',
          onPressed: () => unawaited(_convertSelectedNodeToTask(node)),
        ),
      _SelectedNodeAction(
        icon: Icons.event_available_outlined,
        label: 'Schedule',
        onPressed: () => unawaited(_scheduleSelectedNode(node)),
      ),
      if (node.checklist.isEmpty)
        _SelectedNodeAction(
          icon: Icons.playlist_add_check_outlined,
          label: 'Split checklist',
          onPressed: () => unawaited(_splitSelectedNodeIntoChecklist(node)),
        ),
      _SelectedNodeAction(
        icon: Icons.add_task_outlined,
        label: 'Follow-up',
        onPressed: () => unawaited(_createSelectedNodeFollowUp(node)),
      ),
      _SelectedNodeAction(
        icon: Icons.hub_outlined,
        label: 'Link related',
        onPressed: () => unawaited(_showNodeLinkPicker(node)),
      ),
      _SelectedNodeAction(
        icon: Icons.next_plan_outlined,
        label: 'Tomorrow',
        onPressed: () => unawaited(_moveSelectedNodeToTomorrow(node)),
      ),
      _SelectedNodeAction(
        icon: Icons.rate_review_outlined,
        label: 'Review note',
        onPressed: () => unawaited(_createSelectedNodeReviewNote(node)),
      ),
    ];
  }

  Future<void> _saveSelectedNodeAction(
    MindmapNode before,
    MindmapNode after,
    String message, {
    DateTime? extraDay,
  }) async {
    final repository = ref.read(mindmapRepositoryProvider);
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.save,
        nodeId: before.id,
        before: before,
        after: after,
      ),
    );
    await repository.saveNode(after);
    invalidateMindmapState(
      ref,
      day: before.day,
      extraDay: extraDay ?? after.day,
    );
    if (mounted) _showSnackBar(message);
  }

  Future<void> _convertSelectedNodeToTask(MindmapNode node) async {
    await _saveSelectedNodeAction(
      node,
      node.copyWith(type: NodeType.task, updatedAt: DateTime.now()),
      'Converted to task',
    );
  }

  Future<void> _scheduleSelectedNode(MindmapNode node) async {
    final pickedDay = await showDatePicker(
      context: context,
      initialDate: node.day,
      firstDate: DateTime(node.day.year - 1),
      lastDate: DateTime(node.day.year + 3),
    );
    if (pickedDay == null) return;
    await _saveSelectedNodeAction(
      node,
      node.copyWith(
        day: pickedDay.dateOnly,
        dueDate: pickedDay.dateOnly,
        updatedAt: DateTime.now(),
      ),
      'Scheduled to ${dayKey(pickedDay)}',
      extraDay: pickedDay.dateOnly,
    );
  }

  Future<void> _splitSelectedNodeIntoChecklist(MindmapNode node) async {
    final lines = node.body
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^[-*]\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        .take(8)
        .toList();
    final titles = lines.isEmpty ? [node.title] : lines;
    await _saveSelectedNodeAction(
      node,
      node.copyWith(
        checklist: [
          for (final title in titles)
            TaskChecklistItem(id: const Uuid().v4(), title: title),
        ],
        updatedAt: DateTime.now(),
      ),
      'Checklist created',
    );
  }

  Future<void> _createSelectedNodeFollowUp(MindmapNode node) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final followUp = MindmapNode.create(
      id: const Uuid().v4(),
      type: NodeType.task,
      title: 'Follow-up: ${node.title}',
      day: node.day,
      position: CanvasPosition(node.position.dx + 260, node.position.dy + 80),
      priority: node.priority,
      project: node.project,
      area: node.area,
      tags: node.tags,
      relatedNodeIds: [node.id],
      dueDate: node.dueDate,
      now: now,
    );
    _pushUndo(
      _UndoEntry(kind: _UndoKind.create, nodeId: followUp.id, after: followUp),
    );
    await repository.saveNode(followUp);
    invalidateMindmapState(ref, day: node.day);
    if (mounted) _showSnackBar('Follow-up created');
  }

  Future<void> _moveSelectedNodeToTomorrow(MindmapNode node) async {
    final tomorrow = node.day.add(const Duration(days: 1)).dateOnly;
    await _saveSelectedNodeAction(
      node,
      node.copyWith(
        day: tomorrow,
        dueDate: tomorrow,
        updatedAt: DateTime.now(),
      ),
      'Moved to tomorrow',
      extraDay: tomorrow,
    );
  }

  Future<void> _markSelectedNodeDone(MindmapNode node) async {
    await _saveSelectedNodeAction(
      node,
      node.copyWith(
        isDone: true,
        status: NodeStatus.done,
        progress: 1,
        updatedAt: DateTime.now(),
      ),
      'Marked done',
    );
  }

  Future<void> _createSelectedNodeReviewNote(MindmapNode node) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final review = MindmapNode.create(
      id: const Uuid().v4(),
      type: NodeType.journal,
      title: 'Review: ${node.title}',
      day: node.day,
      body: '## Review\n\n- What happened?\n- What changed?\n- Next action?\n',
      position: CanvasPosition(node.position.dx + 260, node.position.dy + 160),
      tags: const ['review'],
      relatedNodeIds: [node.id],
      now: now,
    );
    _pushUndo(
      _UndoEntry(kind: _UndoKind.create, nodeId: review.id, after: review),
    );
    await repository.saveNode(review);
    invalidateMindmapState(ref, day: node.day);
    if (mounted) _showSnackBar('Review note created');
  }

  Future<void> _showNodeLinkPicker(MindmapNode node) async {
    final nodes = (ref.read(nodesForDayProvider(node.day)).valueOrNull ?? [])
        .where((candidate) => candidate.id != node.id && !candidate.isArchived)
        .toList();
    if (nodes.isEmpty) {
      _showSnackBar('No nodes to link');
      return;
    }
    final picked = await showModalBottomSheet<MindmapNode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              leading: Icon(Icons.hub_outlined),
              title: Text('Link related node'),
            ),
            for (final candidate in nodes.take(12))
              ListTile(
                leading: Icon(nodeIcon(candidate.type)),
                title: Text(candidate.title),
                subtitle: Text(candidate.type.label),
                onTap: () => Navigator.of(context).pop(candidate),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final related = {...node.relatedNodeIds, picked.id}.toList();
    await _saveSelectedNodeAction(
      node,
      node.copyWith(relatedNodeIds: related, updatedAt: DateTime.now()),
      'Linked related node',
    );
  }

  Future<void> _showCustomFocusDialog(MindmapNode node) async {
    final controller = TextEditingController(text: '30');
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Custom focus'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Minutes',
              hintText: '30',
            ),
            onSubmitted: (_) {
              final value = int.tryParse(controller.text.trim());
              Navigator.of(context).pop(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                Navigator.of(context).pop(value);
              },
              child: const Text('Start'),
            ),
          ],
        );
      },
    );
    _disposeTextControllerAfterRouteFrame(controller);
    if (minutes == null || minutes <= 0) return;
    _startFocusSession(node, targetMinutes: minutes);
  }

  void _startFocusSession(MindmapNode node, {int? targetMinutes}) {
    _focusTicker?.cancel();
    setState(() {
      _focusStartedAt = DateTime.now();
      _focusNodeId = node.id;
      _focusTargetMinutes = targetMinutes;
      _focusTargetNotified = false;
    });
    _focusTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _focusRemaining;
      if (remaining == Duration.zero && !_focusTargetNotified) {
        _focusTargetNotified = true;
        _showSnackBar('Focus block complete');
      }
      setState(() {});
    });
  }

  Future<void> _toggleTodayMission(MindmapNode node) async {
    final willAdd = !isTodayMission(node);
    if (willAdd) {
      final dayNodes = ref.read(nodesForDayProvider(node.day)).valueOrNull;
      if (dayNodes != null && !canAddTodayMission(dayNodes, node)) {
        if (mounted) _showSnackBar('Mission limit reached (3 nodes)');
        return;
      }
    }
    final repository = ref.read(mindmapRepositoryProvider);
    final updated = markTodayMission(node, isMission: willAdd);
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.save,
        nodeId: node.id,
        before: node,
        after: updated,
      ),
    );
    await repository.saveNode(updated);
    invalidateMindmapState(ref, day: node.day);
    if (mounted) {
      _showSnackBar(
        isTodayMission(updated) ? 'Added to mission' : 'Removed from mission',
      );
    }
  }

  Future<void> _stopFocusSession(MindmapNode node) async {
    final startedAt = _focusStartedAt;
    if (startedAt == null) return;
    final endedAt = DateTime.now();
    final updated = addFocusSession(
      node,
      startedAt: startedAt,
      endedAt: endedAt,
    );
    _focusTicker?.cancel();
    setState(() {
      _focusStartedAt = null;
      _focusNodeId = null;
      _focusTargetMinutes = null;
      _focusTargetNotified = false;
    });
    if (updated == node) return;
    final repository = ref.read(mindmapRepositoryProvider);
    _pushUndo(
      _UndoEntry(
        kind: _UndoKind.save,
        nodeId: node.id,
        before: node,
        after: updated,
      ),
    );
    await repository.saveNode(updated);
    invalidateMindmapState(ref, day: node.day);
    if (mounted) _showSnackBar('Focus session saved');
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

class _InlineWorkspaceTitle extends StatefulWidget {
  const _InlineWorkspaceTitle({
    required this.customTitle,
    required this.displayTitle,
    required this.onTitleChanged,
  });

  final String? customTitle;
  final String displayTitle;
  final Future<void> Function(String title) onTitleChanged;

  @override
  State<_InlineWorkspaceTitle> createState() => _InlineWorkspaceTitleState();
}

class _InlineWorkspaceTitleState extends State<_InlineWorkspaceTitle> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isHovered = false;
  bool _isEditing = false;
  bool _isSaving = false;
  String _lastSubmitted = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.customTitle ?? '');
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
    _lastSubmitted = widget.customTitle ?? '';
  }

  @override
  void didUpdateWidget(covariant _InlineWorkspaceTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextTitle = widget.customTitle ?? '';
    if (!_isEditing && _controller.text != nextTitle) {
      _controller.text = nextTitle;
      _lastSubmitted = nextTitle;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus && _isEditing) {
      _submit();
    }
  }

  void _startEditing() {
    setState(() => _isEditing = true);
    _controller.text = widget.customTitle ?? widget.displayTitle;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _focusNode.requestFocus();
  }

  Future<void> _submit() async {
    final nextTitle = _controller.text.trim();
    if (_isSaving || nextTitle == _lastSubmitted) {
      setState(() => _isEditing = false);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await widget.onTitleChanged(nextTitle);
      _lastSubmitted = nextTitle;
      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _cancelEditing() {
    _controller.text = widget.customTitle ?? '';
    setState(() => _isEditing = false);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _isEditing || _isHovered;
    final borderColor = active
        ? theme.colorScheme.primary.withValues(alpha: 0.54)
        : Colors.transparent;
    final bgColor = active
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 34),
        padding: EdgeInsets.only(
          left: _isEditing ? 8 : 10,
          right: _isEditing ? 6 : 8,
        ),
        decoration: ShapeDecoration(
          color: bgColor,
          shape: DoodleShapeBorder(
            side: BorderSide(color: borderColor),
            radius: 12,
            wobble: 1.5,
          ),
        ),
        child: _isEditing
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: TextField(
                        key: const ValueKey('day-inline-title-field'),
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 1,
                        textInputAction: TextInputAction.done,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Rename day',
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                  ),
                  if (_isSaving) ...[
                    const SizedBox(width: 8),
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: 'Save title',
                      visualDensity: VisualDensity.compact,
                      onPressed: _submit,
                      icon: const Icon(Icons.check_rounded, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Cancel',
                      visualDensity: VisualDensity.compact,
                      onPressed: _cancelEditing,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ],
              )
            : InkWell(
                key: const ValueKey('day-inline-title-display'),
                borderRadius: BorderRadius.circular(12),
                onTap: _startEditing,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: active ? 1 : 0,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.edit_rounded,
                            size: 15,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _CanvasAddNodeContextPanel extends StatefulWidget {
  const _CanvasAddNodeContextPanel({
    required this.types,
    required this.onSelect,
  });

  final List<NodeType> types;
  final ValueChanged<NodeType> onSelect;

  @override
  State<_CanvasAddNodeContextPanel> createState() =>
      _CanvasAddNodeContextPanelState();
}

class _CanvasAddNodeContextPanelState
    extends State<_CanvasAddNodeContextPanel> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final types = _query.isEmpty
        ? widget.types
        : widget.types
              .where((type) {
                final label = type.label.toLowerCase();
                return label.contains(_query) || type.name.contains(_query);
              })
              .toList(growable: false);
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('canvas-add-node-context-panel'),
        width: 368,
        padding: const EdgeInsets.all(10),
        decoration: ShapeDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.98),
          shape: DoodleShapeBorder(
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
            radius: 18,
            wobble: 2.2,
          ),
          shadows: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Create node',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Right click',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.64,
                      ),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                minLines: 1,
                maxLines: 1,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search type...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          visualDensity: VisualDensity.compact,
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                  border: DoodleInputBorder(
                    borderSide: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                    radius: 14,
                    wobble: 1.6,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                ),
              ),
            ),
            if (types.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No node type found',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 44,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: types.length,
                itemBuilder: (context, index) {
                  final type = types[index];
                  return _CanvasAddNodeTypeTile(
                    type: type,
                    onPressed: () => widget.onSelect(type),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CanvasAddNodeTypeTile extends StatefulWidget {
  const _CanvasAddNodeTypeTile({required this.type, required this.onPressed});

  final NodeType type;
  final VoidCallback onPressed;

  @override
  State<_CanvasAddNodeTypeTile> createState() => _CanvasAddNodeTypeTileState();
}

class _CanvasAddNodeTypeTileState extends State<_CanvasAddNodeTypeTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = nodeColor(widget.type);
    final surfaceColor = theme.colorScheme.surfaceContainerHighest;
    final bgColor = Color.alphaBlend(
      color.withValues(alpha: _isHovered ? 0.18 : 0.08),
      surfaceColor.withValues(alpha: _isHovered ? 0.72 : 0.46),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        offset: _isHovered ? const Offset(0.025, -0.015) : Offset.zero,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          scale: _isHovered ? 1.035 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            decoration: ShapeDecoration(
              color: bgColor,
              shape: DoodleShapeBorder(
                side: BorderSide(
                  color: color.withValues(alpha: _isHovered ? 0.62 : 0.24),
                ),
                radius: _isHovered ? 15 : 13,
                wobble: 1.7,
              ),
              shadows: _isHovered
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.24),
                        blurRadius: 18,
                        spreadRadius: 1,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: InkWell(
              onTap: widget.onPressed,
              customBorder: DoodleShapeBorder(
                radius: _isHovered ? 15 : 13,
                wobble: 1.7,
              ),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return color.withValues(alpha: 0.18);
                }
                if (states.contains(WidgetState.hovered)) {
                  return color.withValues(alpha: 0.08);
                }
                return null;
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      width: _isHovered ? 30 : 26,
                      height: _isHovered ? 30 : 26,
                      decoration: BoxDecoration(
                        color: color.withValues(
                          alpha: _isHovered ? 0.26 : 0.16,
                        ),
                        borderRadius: BorderRadius.circular(
                          _isHovered ? 11 : 9,
                        ),
                      ),
                      child: Icon(
                        nodeIcon(widget.type),
                        size: _isHovered ? 16 : 15,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOutCubic,
                        style:
                            theme.textTheme.labelMedium?.copyWith(
                              color: _isHovered
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: _isHovered
                                  ? FontWeight.w900
                                  : FontWeight.w800,
                            ) ??
                            TextStyle(
                              color: _isHovered
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: _isHovered
                                  ? FontWeight.w900
                                  : FontWeight.w800,
                            ),
                        child: Text(
                          widget.type.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: _isHovered ? 1 : 0,
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
      decoration: ShapeDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: DoodleShapeBorder(
          side: BorderSide(color: theme.dividerColor),
          radius: 8,
          wobble: 1.2,
        ),
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

class _NodeRelationsDock extends ConsumerStatefulWidget {
  const _NodeRelationsDock({required this.nodeId});

  final String nodeId;

  @override
  ConsumerState<_NodeRelationsDock> createState() => _NodeRelationsDockState();
}

class _NodeRelationsDockState extends ConsumerState<_NodeRelationsDock> {
  bool _closed = false;

  @override
  void didUpdateWidget(covariant _NodeRelationsDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) _closed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();
    final relations = ref.watch(nodeRelationsProvider(widget.nodeId));

    return relations.when(
      data: (value) {
        if (value.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Material(
            key: const ValueKey('node-relations-dock'),
            elevation: 14,
            color: theme.colorScheme.surfaceContainerHigh.withValues(
              alpha: 0.96,
            ),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(14),
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
                      Expanded(
                        child: Text(
                          'Node links',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close links panel',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _closed = true),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
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
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
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

class _DayTopTabStrip extends StatelessWidget {
  const _DayTopTabStrip({
    required this.selectedDay,
    required this.isCollapsed,
    required this.onDaySelected,
    required this.onCollapsedChanged,
  });

  final DateTime selectedDay;
  final bool isCollapsed;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<bool> onCollapsedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now().dateOnly;
    final days = List<DateTime>.generate(
      7,
      (index) => selectedDay.add(Duration(days: index - 3)).dateOnly,
    );

    if (isCollapsed) {
      return Container(
        height: 56,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        alignment: Alignment.centerLeft,
        child: InkWell(
          customBorder: const DoodleShapeBorder(radius: 999, wobble: 1.5),
          onTap: () => onCollapsedChanged(false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: ShapeDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.62,
              ),
              shape: DoodleShapeBorder(
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.44,
                  ),
                ),
                radius: 999,
                wobble: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_view_week_rounded, size: 16),
                const SizedBox(width: 8),
                Text(
                  dayKey(selectedDay),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.26),
          ),
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.36),
          ),
        ),
      ),
      child: Row(
        children: [
          _DayNavButton(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: 'Hide day tabs',
            onPressed: () => onCollapsedChanged(true),
          ),
          const SizedBox(width: 6),
          _DayNavButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Previous day',
            onPressed: () =>
                onDaySelected(selectedDay.subtract(const Duration(days: 1))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                for (final day in days) ...[
                  Expanded(
                    child: _DayTabPill(
                      day: day,
                      isSelected: day == selectedDay.dateOnly,
                      isToday: day == today,
                      onTap: () => onDaySelected(day),
                    ),
                  ),
                  if (day != days.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _DayNavButton(
            icon: Icons.today_rounded,
            tooltip: 'Today',
            onPressed: () => onDaySelected(today),
          ),
          const SizedBox(width: 6),
          _DayNavButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next day',
            onPressed: () =>
                onDaySelected(selectedDay.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }
}

class _DayTabPill extends StatelessWidget {
  const _DayTabPill({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekday = switch (day.weekday) {
      DateTime.monday => 'Mon',
      DateTime.tuesday => 'Tue',
      DateTime.wednesday => 'Wed',
      DateTime.thursday => 'Thu',
      DateTime.friday => 'Fri',
      DateTime.saturday => 'Sat',
      DateTime.sunday => 'Sun',
      _ => '',
    };
    final bg = isSelected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.46);
    final fg = isSelected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Tooltip(
      message: dayKey(day),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const DoodleShapeBorder(radius: 999, wobble: 1.5),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: ShapeDecoration(
              color: bg,
              shape: DoodleShapeBorder(
                side: BorderSide(
                  color: isToday
                      ? theme.colorScheme.tertiary.withValues(alpha: 0.75)
                      : isSelected
                      ? theme.colorScheme.primary.withValues(alpha: 0.65)
                      : theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.36,
                        ),
                ),
                radius: 999,
                wobble: 1.5,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 72;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!compact) ...[
                      Flexible(
                        child: Text(
                          weekday,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      '${day.day}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DayNavButton extends StatelessWidget {
  const _DayNavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.62,
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _DayToolsBar extends StatelessWidget {
  const _DayToolsBar({
    required this.stats,
    required this.planningSuggestions,
    required this.miniInsights,
    required this.selectedDay,
    required this.isMissionMode,
    required this.isFocusRunning,
    required this.focusElapsed,
    required this.focusRemaining,
    required this.inboxCount,
    required this.onShowStatus,
    required this.onShowPlan,
    required this.onShowPulse,
    required this.onToggleMissionMode,
    required this.onStopFocus,
    required this.onInboxPressed,
    required this.onQuickCapture,
  });

  final _DailyMissionStats stats;
  final List<_DailyPlanningSuggestion> planningSuggestions;
  final List<DayMiniInsight> miniInsights;
  final DateTime selectedDay;
  final bool isMissionMode;
  final bool isFocusRunning;
  final Duration focusElapsed;
  final Duration? focusRemaining;
  final int inboxCount;
  final VoidCallback onShowStatus;
  final VoidCallback onShowPlan;
  final VoidCallback onShowPulse;
  final VoidCallback? onToggleMissionMode;
  final VoidCallback? onStopFocus;
  final VoidCallback? onInboxPressed;
  final VoidCallback onQuickCapture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focusLabel = focusRemaining == null
        ? _formatFocusDuration(focusElapsed)
        : '${_formatFocusDuration(focusRemaining!)} left';
    final pulseScore = miniInsights
        .where((insight) => insight.day.isSameDay(selectedDay))
        .firstOrNull
        ?.score;
    return Container(
      height: 56,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: ShapeDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.78),
        shape: DoodleShapeBorder(
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.52),
          ),
          radius: 18,
          wobble: 1.8,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            _DayToolActionChip(
              icon: Icons.draw_outlined,
              label: 'Board ${stats.completionPercent}%',
              tooltip: 'Board status',
              onPressed: onShowStatus,
            ),
            const SizedBox(width: 8),
            _DayToolActionChip(
              icon: Icons.analytics_outlined,
              label: pulseScore == null ? 'Pulse' : 'Pulse $pulseScore',
              tooltip: '7-day pulse',
              onPressed: onShowPulse,
            ),
            const SizedBox(width: 8),
            _DayToolActionChip(
              icon: isMissionMode
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              label: isMissionMode ? 'Show all' : 'Focus only',
              tooltip: 'Show only focused nodes',
              onPressed: onToggleMissionMode,
              accent: theme.colorScheme.tertiary,
            ),
            if (isFocusRunning) ...[
              const SizedBox(width: 8),
              _DayToolActionChip(
                icon: Icons.timer_outlined,
                label: focusLabel,
                tooltip: 'Focus timer',
                onPressed: onStopFocus,
                accent: theme.colorScheme.tertiary,
              ),
            ],
            if (inboxCount > 0) ...[
              const SizedBox(width: 8),
              _DayToolActionChip(
                icon: Icons.inbox_outlined,
                label: 'Inbox $inboxCount',
                onPressed: onInboxPressed,
                accent: theme.colorScheme.secondary,
              ),
            ],
            const SizedBox(width: 8),
            _DayToolActionChip(
              icon: Icons.auto_awesome_outlined,
              label: 'Plan',
              tooltip: planningSuggestions.isEmpty
                  ? 'No plan suggestions'
                  : '${planningSuggestions.length} plan suggestions',
              onPressed: onShowPlan,
              accent: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            _DayToolActionChip(
              icon: Icons.bolt_outlined,
              label: 'Capture',
              tooltip: 'Quick capture',
              onPressed: onQuickCapture,
              accent: theme.colorScheme.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _DayToolActionChip extends StatelessWidget {
  const _DayToolActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;
    return Tooltip(
      message: tooltip ?? label,
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
        backgroundColor: color.withValues(
          alpha: onPressed == null ? 0.05 : 0.12,
        ),
        side: BorderSide(color: color.withValues(alpha: 0.34)),
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      ),
    );
  }
}

String _formatFocusDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours <= 0) return '$minutes:$seconds';
  return '$hours:$minutes:$seconds';
}

final class _SelectedNodeAction {
  const _SelectedNodeAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

class _SelectedNodeMissionActions extends StatelessWidget {
  const _SelectedNodeMissionActions({
    required this.node,
    required this.actions,
    required this.isMission,
    required this.isFocusRunning,
    required this.isCollapsed,
    required this.focusElapsed,
    required this.focusRemaining,
    required this.onToggleCollapsed,
    required this.onToggleMission,
    required this.onStartFocus,
    required this.onStartPomodoro,
    required this.onStartCustomFocus,
    required this.onStopFocus,
  });

  final MindmapNode? node;
  final List<_SelectedNodeAction> actions;
  final bool isMission;
  final bool isFocusRunning;
  final bool isCollapsed;
  final Duration focusElapsed;
  final Duration? focusRemaining;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onToggleMission;
  final VoidCallback onStartFocus;
  final ValueChanged<int> onStartPomodoro;
  final VoidCallback onStartCustomFocus;
  final VoidCallback onStopFocus;

  @override
  Widget build(BuildContext context) {
    final currentNode = node;
    if (currentNode == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final minutes = totalFocusMinutes(currentNode);
    final nextAction = nextFocusAction(currentNode);
    final activeToolCount = actions.length + (isFocusRunning ? 3 : 6);
    if (isCollapsed) {
      return Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.38,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$activeToolCount tools hidden',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              TextButton.icon(
                onPressed: onToggleCollapsed,
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: const Text('Show'),
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.construction_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Node tools', style: theme.textTheme.labelLarge),
                ),
                IconButton.outlined(
                  tooltip: 'Hide node tools',
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleCollapsed,
                  icon: const Icon(Icons.expand_less_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  avatar: Icon(
                    isMission ? Icons.flag : Icons.outlined_flag,
                    size: 16,
                  ),
                  label: Text(isMission ? 'Mission' : 'Add mission'),
                  selected: isMission,
                  onSelected: (_) => onToggleMission(),
                ),
                Chip(
                  avatar: const Icon(Icons.next_plan_outlined, size: 16),
                  label: Text(
                    nextAction,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                ActionChip(
                  avatar: Icon(
                    isFocusRunning
                        ? Icons.timer_off_outlined
                        : Icons.timer_outlined,
                    size: 16,
                  ),
                  label: Text(isFocusRunning ? 'Stop focus' : 'Start focus'),
                  onPressed: isFocusRunning ? onStopFocus : onStartFocus,
                ),
                if (!isFocusRunning) ...[
                  ActionChip(
                    avatar: const Icon(Icons.av_timer_outlined, size: 16),
                    label: const Text('25/5'),
                    onPressed: () => onStartPomodoro(25),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.av_timer_outlined, size: 16),
                    label: const Text('50/10'),
                    onPressed: () => onStartPomodoro(50),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.tune_outlined, size: 16),
                    label: const Text('Custom'),
                    onPressed: onStartCustomFocus,
                  ),
                ],
                Chip(
                  avatar: const Icon(Icons.timelapse_outlined, size: 16),
                  label: Text('${minutes}m focus'),
                  visualDensity: VisualDensity.compact,
                ),
                for (final action in actions)
                  ActionChip(
                    avatar: Icon(action.icon, size: 16),
                    label: Text(action.label),
                    onPressed: action.onPressed,
                  ),
                if (isFocusRunning)
                  Chip(
                    avatar: const Icon(Icons.timer_outlined, size: 16),
                    label: Text(
                      focusRemaining == null
                          ? _formatFocusDuration(focusElapsed)
                          : '${_formatFocusDuration(focusRemaining!)} left',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayEmptyStateCockpit extends StatelessWidget {
  const _DayEmptyStateCockpit({
    required this.onDismiss,
    required this.onPlanDay,
    required this.onImportLeftovers,
    required this.onStartJournal,
    required this.onApplyRoutine,
    required this.onUseTemplate,
    required this.onQuickCapture,
  });

  final VoidCallback onDismiss;
  final VoidCallback onPlanDay;
  final VoidCallback onImportLeftovers;
  final VoidCallback onStartJournal;
  final VoidCallback onApplyRoutine;
  final VoidCallback onUseTemplate;
  final VoidCallback onQuickCapture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final actions = [
      _DayEmptyAction(
        icon: Icons.auto_awesome_outlined,
        label: 'Plan my day',
        description: 'Start from a proven template',
        onTap: onPlanDay,
      ),
      _DayEmptyAction(
        icon: Icons.move_down_outlined,
        label: 'Import yesterday leftovers',
        description: 'Review unfinished work',
        onTap: onImportLeftovers,
      ),
      _DayEmptyAction(
        icon: Icons.rate_review_outlined,
        label: 'Start journal',
        description: 'Open a daily review note',
        onTap: onStartJournal,
      ),
      _DayEmptyAction(
        icon: Icons.auto_awesome_motion_outlined,
        label: 'Apply routine',
        description: 'Materialize ready routines',
        onTap: onApplyRoutine,
      ),
      _DayEmptyAction(
        icon: Icons.dashboard_customize_outlined,
        label: 'Use template',
        description: 'Workday, study, reset, review',
        onTap: onUseTemplate,
      ),
      _DayEmptyAction(
        icon: Icons.flash_on_outlined,
        label: 'Quick capture',
        description: 'Type a fast command',
        onTap: onQuickCapture,
      ),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Card(
        elevation: 0,
        color: colorScheme.surface.withValues(alpha: 0.92),
        shape: DoodleShapeBorder(
          side: BorderSide(color: colorScheme.outlineVariant),
          radius: 28,
          wobble: 2.8,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.edit_note_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Blank board',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Pick one handwritten starter.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hide blank board starters',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onDismiss,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final action in actions)
                    _DayEmptyActionCard(action: action),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _DayEmptyAction {
  const _DayEmptyAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
}

class _DayEmptyActionCard extends StatelessWidget {
  const _DayEmptyActionCard({required this.action});

  final _DayEmptyAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 184,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: action.onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, size: 22),
                const SizedBox(height: 10),
                Text(
                  action.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickCaptureHint extends StatelessWidget {
  const _QuickCaptureHint({required this.text, required this.controller});

  final String text;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        foregroundColor: theme.colorScheme.onSurfaceVariant,
      ),
      onPressed: () {
        controller.text = text;
        controller.selection = TextSelection.collapsed(offset: text.length);
      },
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

final class _DailyMissionStats {
  const _DailyMissionStats({
    required this.totalNodes,
    required this.openTasks,
    required this.completedTasks,
    required this.overdueTasks,
    required this.highPriorityCount,
    required this.readyRoutineCount,
    required this.appliedRoutineCount,
    required this.completedHabits,
    required this.totalHabits,
    required this.completionPercent,
    required this.statusLabel,
  });

  final int totalNodes;
  final int openTasks;
  final int completedTasks;
  final int overdueTasks;
  final int highPriorityCount;
  final int readyRoutineCount;
  final int appliedRoutineCount;
  final int completedHabits;
  final int totalHabits;
  final int completionPercent;
  final String statusLabel;
}

_DailyMissionStats _buildDailyMissionStats(
  List<MindmapNode> nodes,
  DateTime day, {
  required int readyRoutineCount,
}) {
  final activeNodes = nodes.where((node) => !node.isArchived).toList();
  final tasks = activeNodes
      .where((node) => node.type == NodeType.task)
      .toList();
  final completedTasks = tasks
      .where((node) => node.isDone || node.status == NodeStatus.done)
      .length;
  final openTasks = tasks.length - completedTasks;
  final overdueTasks = tasks.where((node) {
    final dueDate = node.dueDate;
    if (dueDate == null || node.isDone || node.status == NodeStatus.done) {
      return false;
    }
    return dueDate.dateOnly.isBefore(day.dateOnly);
  }).length;
  final highPriorityCount = activeNodes
      .where(
        (node) =>
            !node.isDone &&
            node.status != NodeStatus.done &&
            (node.priority == NodePriority.high ||
                node.priority == NodePriority.urgent),
      )
      .length;
  final habits = activeNodes
      .where((node) => node.type == NodeType.habit)
      .toList();
  final completedHabits = habits
      .where((node) => hasHabitCompletionOn(node, day))
      .length;
  final appliedRoutineCount = activeNodes
      .where(
        (node) =>
            node.type == NodeType.routine &&
            (node.isDone ||
                node.status == NodeStatus.done ||
                node.progress >= 1),
      )
      .length;
  final completableCount = tasks.length + habits.length;
  final completedCount = completedTasks + completedHabits;
  final completionPercent = completableCount == 0
      ? 0
      : ((completedCount / completableCount) * 100).round().clamp(0, 100);
  final statusLabel = overdueTasks > 0 || highPriorityCount >= 4
      ? 'Needs care'
      : openTasks >= 6
      ? 'Busy board'
      : 'Clear board';

  return _DailyMissionStats(
    totalNodes: activeNodes.length,
    openTasks: openTasks,
    completedTasks: completedTasks,
    overdueTasks: overdueTasks,
    highPriorityCount: highPriorityCount,
    readyRoutineCount: readyRoutineCount,
    appliedRoutineCount: appliedRoutineCount,
    completedHabits: completedHabits,
    totalHabits: habits.length,
    completionPercent: completionPercent,
    statusLabel: statusLabel,
  );
}

class _DailyMissionDashboard extends StatefulWidget {
  const _DailyMissionDashboard({required this.stats});

  final _DailyMissionStats stats;

  @override
  State<_DailyMissionDashboard> createState() => _DailyMissionDashboardState();
}

class _DailyMissionDashboardState extends State<_DailyMissionDashboard> {
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (widget.stats.statusLabel) {
      'Needs care' => theme.colorScheme.error,
      'Busy board' => Colors.amber,
      _ => theme.colorScheme.tertiary,
    };

    if (_isCollapsed) {
      return Material(
        color: Colors.transparent,
        child: _SmartPlanCockpitPanel(
          accent: accent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _isCollapsed = false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.draw_outlined, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(
                  '${widget.stats.statusLabel} · ${widget.stats.completionPercent}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: _SmartPlanCockpitPanel(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(10),
        accent: accent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.draw_outlined, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(
                  'Board status',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.34)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      widget.stats.statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Minimize board status',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _isCollapsed = true),
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: widget.stats.completionPercent / 100,
              minHeight: 5,
              borderRadius: BorderRadius.circular(999),
              color: accent,
              backgroundColor: accent.withValues(alpha: 0.14),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MissionMetricChip(
                  icon: Icons.hub_outlined,
                  label: 'Nodes',
                  value: '${widget.stats.totalNodes}',
                  accent: accent,
                ),
                _MissionMetricChip(
                  icon: Icons.radio_button_unchecked,
                  label: 'Open',
                  value: '${widget.stats.openTasks}',
                  accent: accent,
                ),
                _MissionMetricChip(
                  icon: Icons.check_circle_outline,
                  label: 'Done',
                  value: '${widget.stats.completedTasks}',
                  accent: accent,
                ),
                _MissionMetricChip(
                  icon: Icons.warning_amber_rounded,
                  label: 'Overdue',
                  value: '${widget.stats.overdueTasks}',
                  accent: widget.stats.overdueTasks > 0
                      ? theme.colorScheme.error
                      : accent,
                ),
                _MissionMetricChip(
                  icon: Icons.priority_high_rounded,
                  label: 'High',
                  value: '${widget.stats.highPriorityCount}',
                  accent: widget.stats.highPriorityCount > 0
                      ? Colors.amber
                      : accent,
                ),
                _MissionMetricChip(
                  icon: Icons.auto_awesome_motion_outlined,
                  label: 'Routines',
                  value:
                      '${widget.stats.appliedRoutineCount}/${widget.stats.readyRoutineCount}',
                  accent: accent,
                ),
                _MissionMetricChip(
                  icon: Icons.local_fire_department_outlined,
                  label: 'Habits',
                  value:
                      '${widget.stats.completedHabits}/${widget.stats.totalHabits}',
                  accent: accent,
                ),
                _MissionMetricChip(
                  icon: Icons.percent_rounded,
                  label: 'Day',
                  value: '${widget.stats.completionPercent}%',
                  accent: accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayMiniInsightsStrip extends StatelessWidget {
  const _DayMiniInsightsStrip({
    required this.insights,
    required this.selectedDay,
    required this.onDaySelected,
  });

  final List<DayMiniInsight> insights;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, size: 16),
                const SizedBox(width: 8),
                Text(
                  '7-day pulse',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final insight in insights)
                  Expanded(
                    child: _DayMiniInsightBar(
                      insight: insight,
                      isSelected: insight.day.isSameDay(selectedDay),
                      onTap: () => onDaySelected(insight.day),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayMiniInsightBar extends StatelessWidget {
  const _DayMiniInsightBar({
    required this.insight,
    required this.isSelected,
    required this.onTap,
  });

  final DayMiniInsight insight;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = insight.score;
    final color = score >= 70
        ? theme.colorScheme.tertiary
        : score >= 35
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final height = 18.0 + (score / 100 * 44);
    return Tooltip(
      message:
          '${dayKey(insight.day)} · ${insight.completedTasks}/${insight.totalTasks} tasks · ${insight.completedHabits}/${insight.totalHabits} habits · ${insight.focusMinutes}m focus${insight.hasReview ? ' · review' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 66,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 18,
                    height: height,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isSelected ? 0.95 : 0.62),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.onSurface
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _weekdayShort(insight.day),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                ),
              ),
              if (insight.hasReview)
                Icon(
                  Icons.rate_review_outlined,
                  size: 11,
                  color: theme.colorScheme.tertiary,
                )
              else
                const SizedBox(height: 11),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissionMetricChip extends StatelessWidget {
  const _MissionMetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _DailyPlanningSuggestion {
  const _DailyPlanningSuggestion({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

class _DailyPlanningSuggestionsBar extends StatefulWidget {
  const _DailyPlanningSuggestionsBar({required this.suggestions});

  final List<_DailyPlanningSuggestion> suggestions;

  @override
  State<_DailyPlanningSuggestionsBar> createState() =>
      _DailyPlanningSuggestionsBarState();
}

class _DailyPlanningSuggestionsBarState
    extends State<_DailyPlanningSuggestionsBar> {
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isCollapsed) {
      return _SmartPlanMiniToggle(
        count: widget.suggestions.length,
        onPressed: () => setState(() => _isCollapsed = false),
      );
    }
    return Material(
      color: Colors.transparent,
      child: _SmartPlanCockpitPanel(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(10),
        accent: theme.colorScheme.primary,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Smart plan',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Minimize smart plan',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _isCollapsed = true),
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in widget.suggestions)
                  _SmartPlanActionChip(
                    icon: suggestion.icon,
                    label: suggestion.label,
                    onPressed: suggestion.onPressed,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartPlanCockpitPanel extends StatelessWidget {
  const _SmartPlanCockpitPanel({
    required this.child,
    required this.accent,
    this.constraints,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = 18,
  });

  final Widget child;
  final Color accent;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: constraints,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _SmartPlanCockpitPainter(
          accent: accent,
          surface: theme.colorScheme.surface,
          radius: borderRadius,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _SmartPlanCockpitPainter extends CustomPainter {
  const _SmartPlanCockpitPainter({
    required this.accent,
    required this.surface,
    required this.radius,
  });

  final Color accent;
  final Color surface;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    canvas.drawRRect(rrect, Paint()..color = surface.withValues(alpha: 0.94));

    canvas.save();
    canvas.clipPath(path);
    final chalk = Paint()
      ..color = NeutralColors.darkBorder.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (var y = 10.0; y < size.height; y += 11) {
      canvas.drawLine(
        Offset(8, y),
        Offset(size.width - 8, y + math.sin(y) * 0.8),
        chalk,
      );
    }
    canvas.restore();

    canvas.drawRRect(
      rrect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = NeutralColors.darkBorder.withValues(alpha: 0.86),
    );

    final accentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..color = accent.withValues(alpha: 0.78);
    canvas.drawLine(
      const Offset(12, 8),
      Offset(size.width * 0.3, 6),
      accentPaint,
    );
    canvas.drawCircle(Offset(size.width - 14, 12), 4, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _SmartPlanCockpitPainter oldDelegate) {
    return oldDelegate.accent != accent ||
        oldDelegate.surface != surface ||
        oldDelegate.radius != radius;
  }
}

class _SmartPlanActionChip extends StatelessWidget {
  const _SmartPlanActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.16),
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(color: accent.withValues(alpha: 0.08), blurRadius: 12),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartPlanMiniToggle extends StatelessWidget {
  const _SmartPlanMiniToggle({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: _SmartPlanCockpitPanel(
          borderRadius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          accent: theme.colorScheme.primary,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Smart plan · $count',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayNodeBoardView extends StatelessWidget {
  const _DayNodeBoardView({
    required this.nodes,
    required this.selectedNodeId,
    required this.onNodeSelected,
    required this.onNodeUpdated,
  });

  final List<MindmapNode> nodes;
  final String? selectedNodeId;
  final ValueChanged<MindmapNode> onNodeSelected;
  final NodeUpdateCallback onNodeUpdated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (nodes.isEmpty) {
      return Center(
        child: Text('No nodes yet', style: theme.textTheme.bodyMedium),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final status in NodeStatus.values)
              _DayBoardColumn(
                status: status,
                nodes: nodes.where((node) => node.status == status).toList(),
                selectedNodeId: selectedNodeId,
                onNodeSelected: onNodeSelected,
                onNodeUpdated: onNodeUpdated,
              ),
          ],
        ),
      ),
    );
  }
}

class _DayBoardColumn extends StatelessWidget {
  const _DayBoardColumn({
    required this.status,
    required this.nodes,
    required this.selectedNodeId,
    required this.onNodeSelected,
    required this.onNodeUpdated,
  });

  final NodeStatus status;
  final List<MindmapNode> nodes;
  final String? selectedNodeId;
  final ValueChanged<MindmapNode> onNodeSelected;
  final NodeUpdateCallback onNodeUpdated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<MindmapNode>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) {
        final node = details.data;
        onNodeUpdated(
          node.copyWith(
            status: status,
            isDone: status == NodeStatus.done,
            progress: status == NodeStatus.done ? 1 : node.progress,
            updatedAt: DateTime.now(),
          ),
        );
      },
      builder: (context, candidateNodes, rejectedNodes) {
        final isHovering = candidateNodes.isNotEmpty;
        return Container(
          width: 280,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: isHovering
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.22)
                : theme.colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isHovering
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Row(
                  children: [
                    Icon(_statusIcon(status), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${nodes.length}'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: nodes.isEmpty
                    ? Center(
                        child: Text(
                          isHovering ? 'Drop here' : 'Empty',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: nodes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final node = nodes[index];
                          final card = _DayBoardCard(
                            node: node,
                            selected: node.id == selectedNodeId,
                            onTap: () => onNodeSelected(node),
                            onNodeUpdated: onNodeUpdated,
                          );
                          return LongPressDraggable<MindmapNode>(
                            data: node,
                            feedback: Material(
                              color: Colors.transparent,
                              child: SizedBox(
                                width: 260,
                                child: _DayBoardCard(
                                  node: node,
                                  selected: true,
                                  onTap: () {},
                                  onNodeUpdated: onNodeUpdated,
                                ),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.35,
                              child: card,
                            ),
                            child: card,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DayBoardCard extends StatelessWidget {
  const _DayBoardCard({
    required this.node,
    required this.selected,
    required this.onTap,
    required this.onNodeUpdated,
  });

  final MindmapNode node;
  final bool selected;
  final VoidCallback onTap;
  final NodeUpdateCallback onNodeUpdated;

  Future<void> _applyPriority(NodePriority priority) async {
    await onNodeUpdated(
      node.copyWith(priority: priority, updatedAt: DateTime.now()),
    );
  }

  Future<void> _togglePinned() async {
    await onNodeUpdated(
      node.copyWith(isPinned: !node.isPinned, updatedAt: DateTime.now()),
    );
  }

  Future<void> _archive() async {
    await onNodeUpdated(
      node.copyWith(isArchived: true, updatedAt: DateTime.now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = nodeColor(node.type);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(nodeIcon(node.type), color: accent, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      node.type.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                      ),
                    ),
                  ),
                  if (node.priority != NodePriority.none)
                    Text(
                      node.priority.label,
                      style: theme.textTheme.labelSmall,
                    ),
                  if (node.isPinned) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.push_pin_outlined, size: 14),
                  ],
                  SizedBox.square(
                    dimension: 28,
                    child: PopupMenuButton<String>(
                      key: ValueKey('day-board-card-menu-${node.id}'),
                      tooltip: 'Card actions',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      onSelected: (value) async {
                        switch (value) {
                          case 'pin':
                            await _togglePinned();
                          case 'archive':
                            await _archive();
                          case 'priority-none':
                            await _applyPriority(NodePriority.none);
                          case 'priority-low':
                            await _applyPriority(NodePriority.low);
                          case 'priority-medium':
                            await _applyPriority(NodePriority.medium);
                          case 'priority-high':
                            await _applyPriority(NodePriority.high);
                          case 'priority-urgent':
                            await _applyPriority(NodePriority.urgent);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'pin',
                          child: Text(node.isPinned ? 'Unpin' : 'Pin'),
                        ),
                        const PopupMenuItem(
                          value: 'priority-none',
                          child: Text('Priority: None'),
                        ),
                        const PopupMenuItem(
                          value: 'priority-low',
                          child: Text('Priority: Low'),
                        ),
                        const PopupMenuItem(
                          value: 'priority-medium',
                          child: Text('Priority: Medium'),
                        ),
                        const PopupMenuItem(
                          value: 'priority-high',
                          child: Text('Priority: High'),
                        ),
                        const PopupMenuItem(
                          value: 'priority-urgent',
                          child: Text('Priority: Urgent'),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'archive',
                          child: Text('Archive'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                node.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (node.project.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  node.project,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (node.relatedNodeIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.hub_outlined, size: 14),
                    const SizedBox(width: 4),
                    Text('${node.relatedNodeIds.length} links'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

IconData _statusIcon(NodeStatus status) {
  return switch (status) {
    NodeStatus.open => Icons.radio_button_unchecked,
    NodeStatus.planned => Icons.event_note_outlined,
    NodeStatus.doing => Icons.timelapse_rounded,
    NodeStatus.waiting => Icons.hourglass_empty_rounded,
    NodeStatus.done => Icons.check_circle_outline,
  };
}

void _disposeTextControllerAfterRouteFrame(TextEditingController controller) {
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
}

class _DayNodeTableView extends StatelessWidget {
  const _DayNodeTableView({
    required this.nodes,
    required this.selectedNodeId,
    required this.view,
    required this.sortMode,
    required this.onViewChanged,
    required this.onSortModeChanged,
    required this.onNodeSelected,
    required this.onNodeUpdated,
  });

  final List<MindmapNode> nodes;
  final String? selectedNodeId;
  final _TableQuickView view;
  final _TableSortMode sortMode;
  final ValueChanged<_TableQuickView> onViewChanged;
  final ValueChanged<_TableSortMode> onSortModeChanged;
  final ValueChanged<MindmapNode> onNodeSelected;
  final NodeUpdateCallback onNodeUpdated;

  List<MindmapNode> get _filteredNodes {
    final filtered = switch (view) {
      _TableQuickView.all => nodes,
      _TableQuickView.open =>
        nodes
            .where((node) => node.status != NodeStatus.done && !node.isDone)
            .toList(),
      _TableQuickView.done =>
        nodes
            .where((node) => node.status == NodeStatus.done || node.isDone)
            .toList(),
      _TableQuickView.tasks =>
        nodes.where((node) => node.type == NodeType.task).toList(),
      _TableQuickView.priority =>
        nodes
            .where(
              (node) =>
                  node.priority == NodePriority.high ||
                  node.priority == NodePriority.urgent,
            )
            .toList(),
      _TableQuickView.due =>
        nodes
            .where(
              (node) =>
                  node.dueDate != null &&
                  node.status != NodeStatus.done &&
                  !node.isDone,
            )
            .toList(),
      _TableQuickView.pinned => nodes.where((node) => node.isPinned).toList(),
      _TableQuickView.archived =>
        nodes.where((node) => node.isArchived).toList(),
      _TableQuickView.linked =>
        nodes.where((node) => node.relatedNodeIds.isNotEmpty).toList(),
    };
    return _sortNodes(filtered);
  }

  List<MindmapNode> _sortNodes(List<MindmapNode> input) {
    final sorted = [...input];
    int compareNullableDates(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    sorted.sort(
      (a, b) => switch (sortMode) {
        _TableSortMode.updatedDesc => b.updatedAt.compareTo(a.updatedAt),
        _TableSortMode.titleAsc => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        _TableSortMode.priorityDesc => b.priority.index.compareTo(
          a.priority.index,
        ),
        _TableSortMode.dueAsc => compareNullableDates(a.dueDate, b.dueDate),
      },
    );
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (nodes.isEmpty) {
      return Center(
        child: Text('No nodes yet', style: theme.textTheme.bodyMedium),
      );
    }
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final view in _TableQuickView.values)
                  ChoiceChip(
                    selected: this.view == view,
                    avatar: Icon(view.icon, size: 16),
                    label: Text('${view.label} (${_countFor(view)})'),
                    onSelected: (_) => onViewChanged(view),
                  ),
                const SizedBox(width: 8),
                DropdownButton<_TableSortMode>(
                  value: sortMode,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final mode in _TableSortMode.values)
                      DropdownMenuItem(
                        value: mode,
                        child: Text('Sort: ${mode.label}'),
                      ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) onSortModeChanged(mode);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: WidgetStatePropertyAll(
                      theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.55,
                      ),
                    ),
                    columns: const [
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Title')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Priority')),
                      DataColumn(label: Text('Project')),
                      DataColumn(label: Text('Area')),
                      DataColumn(label: Text('Tags')),
                      DataColumn(label: Text('Due')),
                      DataColumn(label: Text('Links')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: [
                      for (final node in _filteredNodes)
                        DataRow(
                          selected: node.id == selectedNodeId,
                          onSelectChanged: (_) => onNodeSelected(node),
                          cells: [
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    nodeIcon(node.type),
                                    color: nodeColor(node.type),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(node.type.label),
                                ],
                              ),
                            ),
                            DataCell(
                              Text(node.title),
                              showEditIcon: true,
                              onTap: () => _editTitle(context, node),
                            ),
                            DataCell(
                              DropdownButton<NodeStatus>(
                                value: node.status,
                                underline: const SizedBox.shrink(),
                                items: [
                                  for (final status in NodeStatus.values)
                                    DropdownMenuItem(
                                      value: status,
                                      child: Text(status.label),
                                    ),
                                ],
                                onChanged: (status) {
                                  if (status == null || status == node.status) {
                                    return;
                                  }
                                  onNodeUpdated(
                                    node.copyWith(
                                      status: status,
                                      isDone: status == NodeStatus.done,
                                      progress: status == NodeStatus.done
                                          ? 1
                                          : node.progress,
                                      updatedAt: DateTime.now(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            DataCell(
                              DropdownButton<NodePriority>(
                                value: node.priority,
                                underline: const SizedBox.shrink(),
                                items: [
                                  for (final priority in NodePriority.values)
                                    DropdownMenuItem(
                                      value: priority,
                                      child: Text(priority.label),
                                    ),
                                ],
                                onChanged: (priority) {
                                  if (priority == null ||
                                      priority == node.priority) {
                                    return;
                                  }
                                  onNodeUpdated(
                                    node.copyWith(
                                      priority: priority,
                                      updatedAt: DateTime.now(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            DataCell(
                              Text(node.project.isEmpty ? '-' : node.project),
                              showEditIcon: true,
                              onTap: () => _editProject(context, node),
                            ),
                            DataCell(
                              Text(node.area.isEmpty ? '-' : node.area),
                              showEditIcon: true,
                              onTap: () => _editArea(context, node),
                            ),
                            DataCell(
                              Text(
                                node.tags.isEmpty ? '-' : node.tags.join(', '),
                              ),
                              showEditIcon: true,
                              onTap: () => _editTags(context, node),
                            ),
                            DataCell(
                              Text(
                                node.dueDate == null
                                    ? '-'
                                    : dayKey(node.dueDate!),
                              ),
                              showEditIcon: true,
                              onTap: () => _editDueDate(context, node),
                            ),
                            DataCell(Text('${node.relatedNodeIds.length}')),
                            DataCell(
                              _TableNodeActions(
                                node: node,
                                onNodeUpdated: onNodeUpdated,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTitle(BuildContext context, MindmapNode node) async {
    final controller = TextEditingController(text: node.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _disposeTextControllerAfterRouteFrame(controller);
    final trimmed = title?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == node.title) return;
    await onNodeUpdated(
      node.copyWith(title: trimmed, updatedAt: DateTime.now()),
    );
  }

  Future<void> _editDueDate(BuildContext context, MindmapNode node) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: node.dueDate ?? node.day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    await onNodeUpdated(
      node.copyWith(dueDate: picked.dateOnly, updatedAt: DateTime.now()),
    );
  }

  Future<void> _editProject(BuildContext context, MindmapNode node) async {
    final controller = TextEditingController(text: node.project);
    final project = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Project',
            helperText: 'Leave empty to clear project.',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _disposeTextControllerAfterRouteFrame(controller);
    final trimmed = project?.trim();
    if (trimmed == null || trimmed == node.project) return;
    await onNodeUpdated(
      node.copyWith(project: trimmed, updatedAt: DateTime.now()),
    );
  }

  Future<void> _editArea(BuildContext context, MindmapNode node) async {
    final controller = TextEditingController(text: node.area);
    final area = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit area'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Area',
            helperText: 'Leave empty to clear area.',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _disposeTextControllerAfterRouteFrame(controller);
    final trimmed = area?.trim();
    if (trimmed == null || trimmed == node.area) return;
    await onNodeUpdated(
      node.copyWith(area: trimmed, updatedAt: DateTime.now()),
    );
  }

  Future<void> _editTags(BuildContext context, MindmapNode node) async {
    final controller = TextEditingController(text: node.tags.join(', '));
    final tagsText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit tags'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tags',
            helperText: 'Comma separated. Empty clears tags.',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _disposeTextControllerAfterRouteFrame(controller);
    if (tagsText == null) return;
    final tags = tagsText
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    if (tags.join(',') == node.tags.join(',')) return;
    await onNodeUpdated(node.copyWith(tags: tags, updatedAt: DateTime.now()));
  }

  int _countFor(_TableQuickView view) {
    return switch (view) {
      _TableQuickView.all => nodes.length,
      _TableQuickView.open =>
        nodes
            .where((node) => node.status != NodeStatus.done && !node.isDone)
            .length,
      _TableQuickView.done =>
        nodes
            .where((node) => node.status == NodeStatus.done || node.isDone)
            .length,
      _TableQuickView.tasks =>
        nodes.where((node) => node.type == NodeType.task).length,
      _TableQuickView.priority =>
        nodes
            .where(
              (node) =>
                  node.priority == NodePriority.high ||
                  node.priority == NodePriority.urgent,
            )
            .length,
      _TableQuickView.due =>
        nodes
            .where(
              (node) =>
                  node.dueDate != null &&
                  node.status != NodeStatus.done &&
                  !node.isDone,
            )
            .length,
      _TableQuickView.pinned => nodes.where((node) => node.isPinned).length,
      _TableQuickView.archived => nodes.where((node) => node.isArchived).length,
      _TableQuickView.linked =>
        nodes.where((node) => node.relatedNodeIds.isNotEmpty).length,
    };
  }
}

class _TableNodeActions extends StatelessWidget {
  const _TableNodeActions({required this.node, required this.onNodeUpdated});

  final MindmapNode node;
  final NodeUpdateCallback onNodeUpdated;

  Future<void> _togglePinned() async {
    await onNodeUpdated(
      node.copyWith(isPinned: !node.isPinned, updatedAt: DateTime.now()),
    );
  }

  Future<void> _clearDueDate() async {
    await onNodeUpdated(
      node.copyWith(clearDueDate: true, updatedAt: DateTime.now()),
    );
  }

  Future<void> _archive() async {
    await onNodeUpdated(
      node.copyWith(isArchived: true, updatedAt: DateTime.now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: ValueKey('day-table-node-actions-${node.id}'),
      tooltip: 'Node actions',
      onSelected: (value) async {
        switch (value) {
          case 'pin':
            await _togglePinned();
          case 'clear-due':
            await _clearDueDate();
          case 'archive':
            await _archive();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'pin',
          child: Text(node.isPinned ? 'Unpin' : 'Pin'),
        ),
        PopupMenuItem(
          value: 'clear-due',
          enabled: node.dueDate != null,
          child: const Text('Clear due date'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'archive', child: Text('Archive')),
      ],
    );
  }
}

enum _TableQuickView {
  all('All', Icons.table_rows_outlined),
  open('Open', Icons.radio_button_unchecked),
  done('Done', Icons.check_circle_outline),
  tasks('Tasks', Icons.check_box_outlined),
  priority('Priority', Icons.priority_high_rounded),
  due('Due', Icons.event_available_outlined),
  pinned('Pinned', Icons.push_pin_outlined),
  archived('Archived', Icons.archive_outlined),
  linked('Linked', Icons.hub_outlined);

  const _TableQuickView(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum _TableSortMode {
  updatedDesc('Updated'),
  titleAsc('Title'),
  priorityDesc('Priority'),
  dueAsc('Due');

  const _TableSortMode(this.label);

  final String label;
}

enum _DayViewMode { canvas, timeline, board, table }

enum _DayContextFilter {
  all('All', Icons.all_inclusive_rounded),
  open('Open', Icons.radio_button_unchecked_rounded),
  high('High', Icons.priority_high_rounded),
  done('Done', Icons.check_circle_outline_rounded),
  work('Work', Icons.work_outline_rounded),
  personal('Personal', Icons.self_improvement_outlined),
  missions('Missions', Icons.flag_outlined);

  const _DayContextFilter(this.label, this.icon);

  final String label;
  final IconData icon;

  bool matches(MindmapNode node) {
    return switch (this) {
      _DayContextFilter.all => true,
      _DayContextFilter.open => !node.isDone && !node.isArchived,
      _DayContextFilter.high => node.priority == NodePriority.high,
      _DayContextFilter.done => node.isDone,
      _DayContextFilter.work => _hasContext(node, 'work'),
      _DayContextFilter.personal => _hasContext(node, 'personal'),
      _DayContextFilter.missions => isTodayMission(node),
    };
  }
}

bool _hasContext(MindmapNode node, String context) {
  final normalized = context.toLowerCase();
  return node.project.toLowerCase() == normalized ||
      node.area.toLowerCase() == normalized ||
      node.tags.any((tag) => tag.toLowerCase() == normalized);
}

String _workspaceContextFilterKey(WorkspaceContext context) {
  return _workspaceContextFilterKeyFor(context.type, context.name);
}

String _workspaceContextFilterKeyFor(WorkspaceContextType type, String name) {
  return '${type.name}:${workspaceContextKey(name)}';
}

WorkspaceContext? _workspaceContextForKey(
  WorkspaceContexts? contexts,
  String? key,
) {
  if (contexts == null || key == null) return null;
  for (final context in [...contexts.projects, ...contexts.areas]) {
    if (_workspaceContextFilterKey(context) == key) return context;
  }
  return null;
}

const String _defaultRelationLabel = 'relates to';

List<Map<String, Object?>> _relationDataForIds(
  MindmapNode source,
  Iterable<String> ids,
) {
  final existing = _relationLabelMap(source);
  return [
    for (final id in ids)
      {'targetId': id, 'label': existing[id] ?? _defaultRelationLabel},
  ];
}

Map<String, String> _relationLabelMap(MindmapNode node) {
  final raw = node.data['relations'];
  if (raw is! List<Object?>) return const {};
  return {
    for (final item in raw)
      if (item is Map<Object?, Object?> && item['targetId'] is String)
        item['targetId']! as String:
            item['label'] is String && (item['label']! as String).isNotEmpty
            ? item['label']! as String
            : _defaultRelationLabel,
  };
}

_DayViewMode? _dayViewModeFromName(String? name) {
  for (final mode in _DayViewMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}

_DayContextFilter? _dayContextFilterFromName(String? name) {
  for (final filter in _DayContextFilter.values) {
    if (filter.name == name) return filter;
  }
  return null;
}

_TableQuickView? _tableQuickViewFromName(String? name) {
  for (final view in _TableQuickView.values) {
    if (view.name == name) return view;
  }
  return null;
}

_TableSortMode? _tableSortModeFromName(String? name) {
  for (final mode in _TableSortMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}

class _DayContextSwitcher extends StatelessWidget {
  const _DayContextSwitcher({
    required this.filter,
    required this.workspaceContext,
    required this.workspaceContexts,
    required this.onChanged,
    required this.onWorkspaceChanged,
  });

  final _DayContextFilter filter;
  final WorkspaceContext? workspaceContext;
  final WorkspaceContexts? workspaceContexts;
  final ValueChanged<_DayContextFilter> onChanged;
  final ValueChanged<WorkspaceContext> onWorkspaceChanged;

  @override
  Widget build(BuildContext context) {
    final activeLabel = workspaceContext == null
        ? filter.label
        : '${workspaceContext!.type.label}: ${workspaceContext!.name}';
    final activeIcon = workspaceContext?.type == WorkspaceContextType.project
        ? Icons.workspaces_outline
        : workspaceContext?.type == WorkspaceContextType.area
        ? Icons.category_outlined
        : filter.icon;
    final dynamicContexts = workspaceContexts == null
        ? const <WorkspaceContext>[]
        : [
            ...workspaceContexts!.projects,
            ...workspaceContexts!.areas,
          ].where((context) => context.activeNodeCount > 0).take(8).toList();

    return PopupMenuButton<Object>(
      tooltip: 'Day context',
      onSelected: (value) {
        if (value is _DayContextFilter) onChanged(value);
        if (value is WorkspaceContext) onWorkspaceChanged(value);
      },
      itemBuilder: (context) => [
        for (final item in _DayContextFilter.values)
          PopupMenuItem<Object>(
            value: item,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(item.icon, size: 18),
              title: Text(item.label),
              trailing: workspaceContext == null && item == filter
                  ? const Icon(Icons.check_rounded, size: 18)
                  : null,
            ),
          ),
        if (dynamicContexts.isNotEmpty) const PopupMenuDivider(),
        for (final item in dynamicContexts)
          PopupMenuItem<Object>(
            value: item,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                item.type == WorkspaceContextType.project
                    ? Icons.workspaces_outline
                    : Icons.category_outlined,
                size: 18,
              ),
              title: Text('${item.type.label}: ${item.name}'),
              subtitle: Text('${item.activeNodeCount} active'),
              trailing: item == workspaceContext
                  ? const Icon(Icons.check_rounded, size: 18)
                  : null,
            ),
          ),
      ],
      child: Chip(
        avatar: Icon(activeIcon, size: 16),
        label: Text('Context: $activeLabel'),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}

class _DayViewModeToggle extends StatelessWidget {
  const _DayViewModeToggle({required this.mode, required this.onChanged});

  final _DayViewMode mode;
  final ValueChanged<_DayViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SegmentedButton<_DayViewMode>(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        selectedBackgroundColor: theme.colorScheme.primaryContainer,
        selectedForegroundColor: theme.colorScheme.onPrimaryContainer,
      ),
      segments: const [
        ButtonSegment<_DayViewMode>(
          value: _DayViewMode.canvas,
          label: Text('Canvas'),
          icon: Icon(Icons.hub_outlined, size: 16),
        ),
        ButtonSegment<_DayViewMode>(
          value: _DayViewMode.timeline,
          label: Text('Timeline'),
          icon: Icon(Icons.calendar_view_day_outlined, size: 16),
        ),
        ButtonSegment<_DayViewMode>(
          value: _DayViewMode.board,
          label: Text('Board'),
          icon: Icon(Icons.view_kanban_outlined, size: 16),
        ),
        ButtonSegment<_DayViewMode>(
          value: _DayViewMode.table,
          label: Text('Table'),
          icon: Icon(Icons.table_rows_outlined, size: 16),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _ActivityLogSheet extends StatelessWidget {
  const _ActivityLogSheet({
    required this.undoEntries,
    required this.redoEntries,
    required this.onUndo,
    required this.onRedo,
  });

  final List<_UndoEntry> undoEntries;
  final List<_UndoEntry> redoEntries;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = [
      for (final entry in undoEntries)
        _ActivityEntry(entry: entry, isRedo: false),
      for (final entry in redoEntries)
        _ActivityEntry(entry: entry, isRedo: true),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.manage_history_rounded),
              title: const Text('Activity log'),
              subtitle: Text(
                '${undoEntries.length} undo / ${redoEntries.length} redo',
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Undo latest',
                    onPressed: onUndo,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Redo latest',
                    onPressed: onRedo,
                    icon: const Icon(Icons.redo_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No recent activity yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemBuilder: (context, index) {
                    final item = entries[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(item.icon),
                      title: Text(item.title),
                      subtitle: Text(item.subtitle),
                      trailing: item.isRedo
                          ? const Chip(label: Text('Redo'))
                          : const Chip(label: Text('Undo')),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemCount: entries.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _ActivityEntry {
  const _ActivityEntry({required this.entry, required this.isRedo});

  final _UndoEntry entry;
  final bool isRedo;

  IconData get icon {
    return switch (entry.kind) {
      _UndoKind.create => Icons.add_circle_outline,
      _UndoKind.delete => Icons.delete_outline,
      _UndoKind.save => _saveIcon,
    };
  }

  IconData get _saveIcon {
    final before = entry.before;
    final after = entry.after;
    if (before != null && after != null) {
      if (!before.isDone && after.isDone) return Icons.check_circle_outline;
      if (before.day != after.day) return Icons.drive_file_move_outline;
      if (before.status != after.status) return Icons.change_circle_outlined;
    }
    return Icons.edit_outlined;
  }

  String get title {
    return switch (entry.kind) {
      _UndoKind.create => 'Created node',
      _UndoKind.delete => 'Deleted node',
      _UndoKind.save => _saveTitle,
    };
  }

  String get _saveTitle {
    final before = entry.before;
    final after = entry.after;
    if (before != null && after != null) {
      if (!before.isDone && after.isDone) return 'Completed task';
      if (before.day != after.day) return 'Moved node';
      if (before.status != after.status) return 'Edited status';
    }
    return 'Edited node';
  }

  String get subtitle => isRedo ? 'Redo available' : 'Undo available';
}

class _UndoRedoIndicator extends StatelessWidget {
  const _UndoRedoIndicator({
    required this.undoCount,
    required this.redoCount,
    required this.onUndo,
    required this.onRedo,
    required this.onHistory,
  });

  final int undoCount;
  final int redoCount;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    if (undoCount == 0 && redoCount == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Undo ()',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onUndo,
              icon: const Icon(Icons.undo_rounded),
            ),
          ),
          Text('$undoCount / $redoCount', style: theme.textTheme.labelSmall),
          Tooltip(
            message: 'Redo ()',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onRedo,
              icon: const Icon(Icons.redo_rounded),
            ),
          ),
          Tooltip(
            message: 'Activity log',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              onPressed: onHistory,
              icon: const Icon(Icons.manage_history_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayQuickCreateFab extends StatefulWidget {
  const _DayQuickCreateFab({required this.onSelectType, required this.onMore});

  final ValueChanged<NodeType> onSelectType;
  final VoidCallback onMore;

  @override
  State<_DayQuickCreateFab> createState() => _DayQuickCreateFabState();
}

class _DayQuickCreateFabState extends State<_DayQuickCreateFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isOpen = false;

  static const List<NodeType> _types = <NodeType>[
    NodeType.task,
    NodeType.note,
    NodeType.kanban,
    NodeType.habit,
    NodeType.event,
    NodeType.idea,
    NodeType.question,
    NodeType.bookmark,
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _isOpen = !_isOpen);
    if (_isOpen) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _select(NodeType type) {
    _toggle();
    widget.onSelectType(type);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizeTransition(
          sizeFactor: CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutCubic,
          ),
          axisAlignment: -1,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(20),
              color: theme.colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final type in _types)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: ActionChip(
                          avatar: Icon(nodeIcon(type), size: 16),
                          label: Text(type.label),
                          onPressed: () => _select(type),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: widget.onMore,
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: const Text('More'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: GestureDetector(
            onLongPress: _toggle,
            child: FloatingActionButton.small(
              key: const ValueKey('day-fab'),
              tooltip: _isOpen
                  ? 'Close quick create menu'
                  : 'Quick create (long press for menu)',
              onPressed: widget.onMore,
              child: AnimatedRotation(
                turns: _isOpen ? 0.125 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(_isOpen ? Icons.close_rounded : Icons.add_rounded),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
  NodeType.event => Icons.event_outlined,
  NodeType.decision => Icons.rule_outlined,
  NodeType.resource => Icons.inventory_2_outlined,
  NodeType.idea => Icons.lightbulb_outline,
  NodeType.question => Icons.help_outline,
  NodeType.contact => Icons.person_outline,
  NodeType.metric => Icons.query_stats_outlined,
  NodeType.expense => Icons.payments_outlined,
  NodeType.bookmark => Icons.bookmark_border,
  NodeType.routine => Icons.repeat_on_outlined,
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

String _weekdayShort(DateTime day) {
  return switch (day.weekday) {
    DateTime.monday => 'Mon',
    DateTime.tuesday => 'Tue',
    DateTime.wednesday => 'Wed',
    DateTime.thursday => 'Thu',
    DateTime.friday => 'Fri',
    DateTime.saturday => 'Sat',
    DateTime.sunday => 'Sun',
    _ => '',
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

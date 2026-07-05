/// Calendar page — the app's home screen.
///
/// Renders the month grid, day summaries, search, keyboard navigation, and
/// route handoff into the selected day's mindmap.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/layout/adaptive_scaffold.dart';
import '../../shared/widgets/animated_empty_state.dart';
import '../../shared/widgets/doodle_border.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/skeleton_loader.dart';
import '../command/domain/quick_create_command_parser.dart';
import '../mindmap/application/mindmap_mutation_controller.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/application/recurring_routine_application.dart';
import '../mindmap/domain/day_node_summary.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/mindmap_node_data.dart';
import '../mindmap/domain/recurring_routine.dart';
import '../mindmap/domain/workspace_context.dart';
import '../mindmap/presentation/add_node_dialog.dart';
import '../onboarding/onboarding_overlay.dart';
import '../workspace/data/workspace_title_repository.dart';
import 'application/calendar_agenda_builder.dart';
import 'application/calendar_day_summary.dart';
import 'application/calendar_heatmap.dart';
import 'application/calendar_markdown_export.dart';
import 'application/calendar_planning_engine.dart';
import 'application/calendar_range_summary.dart';
import 'application/calendar_template_planner.dart';
import 'application/calendar_view_controller.dart';
import 'application/calendar_week_summary.dart';
import 'application/day_templates.dart';
import 'application/node_filtering.dart';
import 'application/workload_balancer.dart';
import 'domain/calendar_node_payload.dart';

final calendarSearchQueryProvider = StateProvider<String>((ref) => '');

enum CalendarDensityMode { compact, comfortable, detailed }

final calendarTypeFiltersProvider = StateProvider<Set<NodeType>>((ref) => {});
final calendarDoneFilterProvider = StateProvider<bool>((ref) => false);
final calendarDensityModeProvider = StateProvider<CalendarDensityMode>(
  (ref) => CalendarDensityMode.compact,
);
final selectedAgendaNodeIdProvider = StateProvider<String?>((ref) => null);
final calendarHeatmapModeProvider = StateProvider<CalendarHeatmapMode>(
  (ref) => CalendarHeatmapMode.workload,
);
final calendarRangeSelectionProvider = StateProvider<Set<DateTime>>(
  (ref) => {},
);
final calendarActivityLogProvider = StateProvider<List<String>>((ref) => []);
final calendarUndoStackProvider = StateProvider<List<CalendarUndoAction>>(
  (ref) => [],
);
final calendarAdvancedFilterProvider = StateProvider<CalendarNodeFilter>(
  (ref) => const CalendarNodeFilter(),
);

final class CalendarUndoAction {
  const CalendarUndoAction({required this.label, required this.undo});

  final String label;
  final Future<void> Function(WidgetRef ref) undo;
}

final calendarRoutinePlanProvider = FutureProvider.autoDispose
    .family<RecurringRoutinePlan, DateTime>((ref, day) async {
      return previewRecurringRoutines(
        repository: ref.watch(mindmapRepositoryProvider),
        day: day,
      );
    });

void _showRescheduleSnackBar({
  required BuildContext context,
  required WidgetRef ref,
  required MindmapNode node,
  required DateTime previousDay,
  required DateTime targetDay,
}) {
  final normalizedPreviousDay = previousDay.dateOnly;
  final normalizedTargetDay = targetDay.dateOnly;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Moved "${node.title}" to ${DateFormat('MMM d, y').format(normalizedTargetDay)}',
      ),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          unawaited(
            ref
                .read(mindmapMutationControllerProvider)
                .rescheduleNode(
                  node.copyWith(day: normalizedTargetDay),
                  day: normalizedPreviousDay,
                ),
          );
        },
      ),
    ),
  );
}

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _visibleMonth;
  late DateTime _focusedDay;
  DateTime? _previewDay;
  bool _isPreviewPanelCollapsed = false;
  bool _showCalendarControls = false;
  bool _slideForward = true;
  final Set<String> _dismissedMonths = {};
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final now = ref.read(currentDateProvider);
    _visibleMonth = now.dateOnly.firstOfMonth;
    _focusedDay = now.dateOnly;
    _previewDay = now.dateOnly;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _clearCalendarSearch() {
    _searchController.clear();
    ref.read(calendarSearchQueryProvider.notifier).state = '';
    setState(() {});
  }

  void _resetAgendaFilters() {
    _clearCalendarSearch();
    unawaited(
      ref.read(agendaFilterProvider.notifier).setFilter(AgendaFilter.all),
    );
    ref.read(calendarTypeFiltersProvider.notifier).state = {};
    ref.read(calendarDoneFilterProvider.notifier).state = false;
    ref.read(calendarAdvancedFilterProvider.notifier).state =
        const CalendarNodeFilter();
  }

  bool _isTextEntryFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorStateOfType<EditableTextState>() != null;
  }

  Future<void> _showCalendarControlsSheet(Widget controlsPanel) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(height: 520, child: controlsPanel),
        ),
      ),
    );
  }

  Future<void> _showCalendarActionsSheet({required DateTime selectedDay}) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _QuickAddToolbar(
                  selectedDay: selectedDay,
                  onAddNode: _addNodeQuick,
                  onQuickCapture: _showQuickCaptureSheet,
                ),
                const SizedBox(height: 12),
                _CalendarAdvancedTools(
                  focusedDay: selectedDay,
                  onApplyTemplate: _showTemplatePicker,
                  onExportDay: _copyFocusedDayMarkdown,
                  onExportWeek: _copyWeekMarkdown,
                  onExportMonth: _copyVisibleMonthMarkdown,
                  onBalanceWeek: _balanceFocusedWeek,
                  onUndoLast: _undoLastCalendarAction,
                  onToggleFocusedDay: _toggleFocusedRangeDay,
                  onSelectFocusedWeek: _selectFocusedWeek,
                  onBalanceRange: _balanceSelectedRange,
                  onClearRange: _clearRangeSelection,
                  onExportRange: _copySelectedRangeMarkdown,
                  onApplyRangeTemplate: _showSelectedRangeTemplatePicker,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(currentDateProvider);
    final viewMode = ref.watch(calendarViewModeProvider);
    final typeFilters = ref.watch(calendarTypeFiltersProvider);
    final doneOnly = ref.watch(calendarDoneFilterProvider);
    final isDesktop =
        MediaQuery.sizeOf(context).width >= LayoutConstants.desktopBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const AppRouteChromeTabs(currentRoute: AppRoute.calendar),
        actions: [
          SearchField(
            key: const ValueKey('calendar-search-field'),
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: 'Search calendar...',
            onChanged: (value) {
              ref.read(calendarSearchQueryProvider.notifier).state = value
                  .trim()
                  .toLowerCase();
            },
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Quick add (Ctrl+N)',
            child: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _showQuickCaptureSheet(_focusedDay),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Today',
            child: OutlinedButton(
              onPressed: () => _jumpToToday(today),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                shape: const DoodleShapeBorder(radius: 10, wobble: 1.4),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                fixedSize: const Size.fromHeight(36),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PulsingDot(),
                  SizedBox(width: 6),
                  Icon(Icons.today, size: 16),
                  SizedBox(width: 6),
                  Text('Today'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Focus(
              autofocus: true,
              onKeyEvent: (FocusNode node, KeyEvent event) {
                if (event is KeyDownEvent) {
                  if (_isTextEntryFocused()) return KeyEventResult.ignored;
                  final shortcutResult = _handleCalendarShortcut(
                    event,
                    viewMode,
                  );
                  if (shortcutResult == KeyEventResult.handled) {
                    return shortcutResult;
                  }

                  DateTime? nextDay;
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    nextDay = _focusedDay.subtract(const Duration(days: 1));
                  } else if (event.logicalKey ==
                      LogicalKeyboardKey.arrowRight) {
                    nextDay = _focusedDay.add(const Duration(days: 1));
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    nextDay = _focusedDay.subtract(const Duration(days: 7));
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    nextDay = _focusedDay.add(const Duration(days: 7));
                  } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                    try {
                      context.go('/calendar/${dayKey(_focusedDay)}');
                    } on AssertionError {
                      _openDayPreview(_focusedDay);
                    }
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.space) {
                    _openDayPreview(_focusedDay);
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.escape &&
                      _previewDay != null) {
                    _closeDayPreview();
                    return KeyEventResult.handled;
                  }

                  if (nextDay != null) {
                    _showFocusedDay(nextDay);
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final previewDay = _previewDay;
                  final useSideControls = isDesktop && _showCalendarControls;
                  final controlsPanel = _CalendarControlPanel(
                    focusedDay: _focusedDay,
                    today: today,
                    selectedTypes: typeFilters,
                    doneOnly: doneOnly,
                    onClose: isDesktop
                        ? () => setState(() => _showCalendarControls = false)
                        : null,
                  );
                  final calendarContent = Column(
                    children: [
                      _MonthHeader(
                        month: _visibleMonth,
                        focusedDay: _focusedDay,
                        viewMode: viewMode,
                        onPrevious: () => _showPreviousPeriod(viewMode),
                        onNext: () => _showNextPeriod(viewMode),
                        onJumpToDate: _showDatePicker,
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (!useSideControls) ...[
                              OutlinedButton.icon(
                                key: const ValueKey('calendar-controls-toggle'),
                                onPressed: () {
                                  if (isDesktop) {
                                    setState(
                                      () => _showCalendarControls = true,
                                    );
                                    return;
                                  }
                                  _showCalendarControlsSheet(controlsPanel);
                                },
                                icon: const Icon(Icons.tune_outlined, size: 18),
                                label: const Text('Tools'),
                              ),
                              const SizedBox(width: 8),
                            ],
                            const _CalendarViewModeSwitch(),
                            if (!useSideControls &&
                                viewMode != CalendarViewMode.agenda) ...[
                              const SizedBox(width: 8),
                              TextButton.icon(
                                key: const ValueKey(
                                  'calendar-filter-advanced-inline',
                                ),
                                onPressed: () =>
                                    _showAdvancedCalendarFilters(context, ref),
                                icon: const Icon(
                                  Icons.filter_alt_outlined,
                                  size: 18,
                                ),
                                label: const Text('Advanced'),
                              ),
                              const SizedBox(width: 8),
                              _CalendarFilterStrip(
                                selectedTypes: typeFilters,
                                doneOnly: doneOnly,
                                wrap: true,
                                showAdvancedChip: false,
                              ),
                            ],
                            const SizedBox(width: 8),
                            IconButton.outlined(
                              key: const ValueKey('calendar-actions-menu'),
                              tooltip: 'Calendar actions',
                              icon: const Icon(Icons.more_horiz, size: 18),
                              onPressed: () => _showCalendarActionsSheet(
                                selectedDay: _previewDay ?? _focusedDay,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (viewMode == CalendarViewMode.agenda)
                        _RoutineApplyBanner(day: today),
                      const SizedBox(height: 8),
                      if (viewMode != CalendarViewMode.agenda) ...[
                        const _WeekdayHeader(),
                        const SizedBox(height: 6),
                      ],
                      Expanded(
                        child: Stack(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder:
                                  (Widget child, Animation<double> animation) {
                                    final offset = _slideForward
                                        ? Tween<Offset>(
                                            begin: const Offset(0.3, 0.0),
                                            end: Offset.zero,
                                          )
                                        : Tween<Offset>(
                                            begin: const Offset(-0.3, 0.0),
                                            end: Offset.zero,
                                          );
                                    return SlideTransition(
                                      position: offset.animate(
                                        CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeInOutCubic,
                                        ),
                                      ),
                                      child: FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                    );
                                  },
                              child: KeyedSubtree(
                                key: ValueKey(
                                  '${_visibleMonth.toIso8601String()}-${viewMode.name}',
                                ),
                                child: switch (viewMode) {
                                  CalendarViewMode.month => _MonthGrid(
                                    visibleMonth: _visibleMonth,
                                    today: today,
                                    focusedDay: _focusedDay,
                                    onDayPreview: _openDayPreview,
                                  ),
                                  CalendarViewMode.week => _WeekCalendarView(
                                    focusedDay: _focusedDay,
                                    today: today,
                                    onDayPreview: _openDayPreview,
                                  ),
                                  CalendarViewMode.agenda =>
                                    _AgendaCalendarView(
                                      focusedDay: _focusedDay,
                                      today: today,
                                      onAddNode: _addNodeForDay,
                                      onClearSearch: _clearCalendarSearch,
                                      onResetFilters: _resetAgendaFilters,
                                    ),
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      _CalendarEmptyBanner(
                        visibleMonth: _visibleMonth,
                        today: today,
                        isDismissed: _dismissedMonths.contains(_monthKey),
                        onAddNode: _addNodeForDay,
                        onDismiss: () {
                          setState(() => _dismissedMonths.add(_monthKey));
                        },
                      ),
                    ],
                  );

                  final primaryContent = useSideControls
                      ? Row(
                          children: [
                            SizedBox(width: 260, child: controlsPanel),
                            const SizedBox(width: 12),
                            Expanded(child: calendarContent),
                          ],
                        )
                      : calendarContent;

                  if (previewDay == null ||
                      constraints.maxWidth <
                          LayoutConstants.desktopBreakpoint) {
                    return primaryContent;
                  }

                  final panelWidth = (constraints.maxWidth * 0.3).clamp(
                    340.0,
                    420.0,
                  );
                  return Row(
                    children: [
                      Expanded(child: primaryContent),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: _isPreviewPanelCollapsed ? 48 : panelWidth,
                        child: _isPreviewPanelCollapsed
                            ? _CollapsedDayPreviewRail(
                                day: previewDay,
                                onExpand: () => setState(
                                  () => _isPreviewPanelCollapsed = false,
                                ),
                              )
                            : _DayPreviewPanel(
                                day: previewDay,
                                today: today,
                                onClose: () => setState(
                                  () => _isPreviewPanelCollapsed = true,
                                ),
                                onAddNode: () => _addNodeForDay(previewDay),
                                onApplyTemplate: () =>
                                    _showTemplatePicker(previewDay),
                                onClearSearch: _clearCalendarSearch,
                                onOpenDay: () => _openFullDay(previewDay),
                                onOpenNode: (nodeId) => _openFullDay(
                                  previewDay,
                                  highlightNodeId: nodeId,
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const OnboardingOverlay(),
        ],
      ),
    );
  }

  void _showMonth(DateTime month) {
    final newMonth = month.dateOnly.firstOfMonth;
    if (newMonth.isAtSameMomentAs(_visibleMonth)) return;
    setState(() {
      _slideForward = newMonth.isAfter(_visibleMonth);
      _visibleMonth = newMonth;
    });
  }

  void _showPreviousPeriod(CalendarViewMode viewMode) {
    switch (viewMode) {
      case CalendarViewMode.month:
        _showMonth(_visibleMonth.addMonths(-1));
      case CalendarViewMode.week:
        _showFocusedDay(_focusedDay.subtract(const Duration(days: 7)));
      case CalendarViewMode.agenda:
        _showFocusedDay(_focusedDay.subtract(const Duration(days: 30)));
    }
  }

  void _showNextPeriod(CalendarViewMode viewMode) {
    switch (viewMode) {
      case CalendarViewMode.month:
        _showMonth(_visibleMonth.addMonths(1));
      case CalendarViewMode.week:
        _showFocusedDay(_focusedDay.add(const Duration(days: 7)));
      case CalendarViewMode.agenda:
        _showFocusedDay(_focusedDay.add(const Duration(days: 30)));
    }
  }

  void _showFocusedDay(DateTime day) {
    final normalized = day.dateOnly;
    setState(() {
      _slideForward = normalized.isAfter(_focusedDay);
      _focusedDay = normalized;
      _visibleMonth = normalized.firstOfMonth;
    });
  }

  void _jumpToToday(DateTime today) {
    final normalized = today.dateOnly;
    _searchController.clear();
    ref.read(calendarSearchQueryProvider.notifier).state = '';
    setState(() {
      _slideForward = normalized.isAfter(_focusedDay);
      _focusedDay = normalized;
      _visibleMonth = normalized.firstOfMonth;
      _previewDay = normalized;
    });
  }

  void _openDayPreview(DateTime day) {
    final normalized = day.dateOnly;
    final isNarrow =
        MediaQuery.sizeOf(context).width < LayoutConstants.desktopBreakpoint;
    setState(() {
      _slideForward = normalized.isAfter(_focusedDay);
      _focusedDay = normalized;
      _visibleMonth = normalized.firstOfMonth;
      _previewDay = normalized;
    });

    if (isNarrow) {
      unawaited(_showDayPreviewSheet(normalized));
    }
  }

  void _closeDayPreview() {
    setState(() => _previewDay = null);
  }

  void _openFullDay(DateTime day, {String? highlightNodeId}) {
    goToDay(context, day, highlightNodeId: highlightNodeId);
  }

  Future<void> _addNodeForDay(DateTime day) async {
    final draft = await showAddNodeDialog(context);
    if (draft == null || !mounted) return;

    final normalizedDay = day.dateOnly;
    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: draft.type,
      title: draft.title,
      body: draft.body,
      day: normalizedDay,
      status: draft.status,
      priority: draft.priority,
      project: draft.project,
      area: draft.area,
      tags: draft.tags,
      dueDate: draft.dueDate,
      progress: draft.progress,
      isPinned: draft.isPinned,
      isArchived: draft.isArchived,
      checklist: draft.checklist,
      relatedNodeIds: draft.relatedNodeIds,
      data: draft.data,
      now: DateTime.now(),
    );

    try {
      final saved = await ref
          .read(mindmapMutationControllerProvider)
          .saveNode(node);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added "${saved.title}" to ${DateFormat('MMM d, y').format(normalizedDay)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add node: $error')));
    }
  }

  Future<void> _showSelectedRangeTemplatePicker() async {
    final selectedDays = ref.read(calendarRangeSelectionProvider).toList()
      ..sort();
    if (selectedDays.isEmpty) return;
    await _showTemplatePickerForDays(selectedDays);
  }

  Future<void> _showTemplatePicker(DateTime day) async {
    await _showTemplatePickerForDays([day.dateOnly]);
  }

  Future<void> _showTemplatePickerForDays(List<DateTime> days) async {
    final normalizedDays = days.map((day) => day.dateOnly).toSet().toList()
      ..sort();
    if (normalizedDays.isEmpty) return;
    final allNodes = await ref.read(allMindmapNodesProvider.future);
    final normalizedDay = normalizedDays.first;
    final existingNodes = allNodes
        .where((node) => normalizedDays.any((day) => node.day.isSameDay(day)))
        .toList(growable: false);
    if (!mounted) return;
    final suggestedTemplates = suggestedCalendarTemplatesForDay(normalizedDay);
    final suggestedIds = suggestedTemplates
        .map((template) => template.id)
        .toSet();
    final orderedTemplates = [
      ...suggestedTemplates,
      for (final template in dayTemplates)
        if (!suggestedIds.contains(template.id)) template,
    ];
    final selectedTemplate = await showModalBottomSheet<DayTemplate>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                normalizedDays.length == 1
                    ? 'Apply day template'
                    : 'Apply template to ${normalizedDays.length} dates',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                normalizedDays.length == 1
                    ? DateFormat('EEEE, MMM d').format(normalizedDay)
                    : '${DateFormat('MMM d').format(normalizedDays.first)} - ${DateFormat('MMM d').format(normalizedDays.last)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final template in orderedTemplates)
                ListTile(
                  key: ValueKey('calendar-template-${template.id}'),
                  enabled:
                      _templateAppliedCount(
                        nodes: existingNodes,
                        templateId: template.id,
                        days: normalizedDays,
                      ) <
                      normalizedDays.length,
                  leading: Icon(
                    suggestedIds.contains(template.id)
                        ? Icons.auto_awesome_outlined
                        : Icons.dashboard_customize_outlined,
                  ),
                  title: Text(template.label),
                  subtitle: Text(
                    _templateAppliedCount(
                              nodes: existingNodes,
                              templateId: template.id,
                              days: normalizedDays,
                            ) >
                            0
                        ? 'Already applied to ${_templateAppliedCount(nodes: existingNodes, templateId: template.id, days: normalizedDays)}/${normalizedDays.length} dates'
                        : template.description,
                  ),
                  onTap: () => Navigator.of(context).pop(template),
                ),
            ],
          ),
        );
      },
    );
    if (selectedTemplate == null || !mounted) return;

    final now = DateTime.now();
    final createdNodes = <MindmapNode>[];
    for (final day in normalizedDays) {
      final dayNodes = allNodes
          .where((node) => node.day.isSameDay(day))
          .toList(growable: false);
      createdNodes.addAll(
        buildDayTemplateNodes(
          template: selectedTemplate,
          day: day,
          now: now,
          idFactory: () => const Uuid().v4(),
          existingNodes: dayNodes,
        ),
      );
    }
    if (createdNodes.isEmpty) return;

    final mutationController = ref.read(mindmapMutationControllerProvider);
    for (final node in createdNodes) {
      await mutationController.saveNode(node);
    }
    if (!mounted) return;
    _pushCalendarUndo(
      CalendarUndoAction(
        label: 'template ${selectedTemplate.label}',
        undo: (ref) async {
          final controller = ref.read(mindmapMutationControllerProvider);
          for (final node in createdNodes) {
            await controller.deleteNode(node);
          }
        },
      ),
    );
    _recordCalendarActivity('Applied ${selectedTemplate.label} template');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Applied ${selectedTemplate.label} template to ${normalizedDays.length} date(s) (${createdNodes.length} nodes)',
        ),
      ),
    );
  }

  /// Quick-add a node of given [type] for [day] without showing dialog.
  int _templateAppliedCount({
    required List<MindmapNode> nodes,
    required String templateId,
    required List<DateTime> days,
  }) {
    return days
        .where(
          (day) => isCalendarTemplateApplied(
            nodes: nodes,
            templateId: templateId,
            day: day,
          ),
        )
        .length;
  }

  void _toggleFocusedRangeDay() {
    final day = _focusedDay.dateOnly;
    final notifier = ref.read(calendarRangeSelectionProvider.notifier);
    final next = {...ref.read(calendarRangeSelectionProvider)};
    if (next.contains(day)) {
      next.remove(day);
    } else {
      next.add(day);
    }
    notifier.state = next;
  }

  void _selectFocusedWeek() {
    ref.read(calendarRangeSelectionProvider.notifier).state = {
      for (final day in calendarWeekDays(_focusedDay)) day.dateOnly,
    };
  }

  void _clearRangeSelection() {
    ref.read(calendarRangeSelectionProvider.notifier).state = {};
  }

  Future<void> _copyFocusedDayMarkdown() async {
    final day = _focusedDay.dateOnly;
    final nodes = await ref.read(nodesForDayProvider(day).future);
    final week = buildCalendarWeekSummary(
      selectedDay: day,
      nodes: ref.read(allMindmapNodesProvider).valueOrNull ?? nodes,
    );
    final suggestions = buildCalendarPlanningSuggestions(
      week: week,
      today: ref.read(currentDateProvider),
    );
    await Clipboard.setData(
      ClipboardData(
        text: exportCalendarDayMarkdown(
          summary: buildCalendarDaySummary(day, nodes),
          nodes: nodes,
          suggestions: suggestions,
        ),
      ),
    );
    _recordCalendarActivity('Exported day summary');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Day markdown copied')));
  }

  Future<void> _copyWeekMarkdown() async {
    final nodes = await ref.read(allMindmapNodesProvider.future);
    final week = buildCalendarWeekSummary(
      selectedDay: _focusedDay,
      nodes: nodes,
    );
    final suggestions = buildCalendarPlanningSuggestions(
      week: week,
      today: ref.read(currentDateProvider),
    );
    final range = buildCalendarRangeSummary(
      start: week.startDay,
      end: week.endDay,
      nodes: nodes,
    );
    await Clipboard.setData(
      ClipboardData(
        text: exportCalendarRangeMarkdown(
          summary: range,
          suggestions: suggestions,
        ),
      ),
    );
    _recordCalendarActivity('Exported week summary');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Week markdown copied')));
  }

  Future<void> _copyVisibleMonthMarkdown() async {
    final nodes = await ref.read(allMindmapNodesProvider.future);
    final suggestions = buildCalendarPlanningSuggestions(
      week: buildCalendarWeekSummary(selectedDay: _focusedDay, nodes: nodes),
      today: ref.read(currentDateProvider),
    );
    await Clipboard.setData(
      ClipboardData(
        text: exportCalendarMonthMarkdown(
          month: _visibleMonth,
          nodes: nodes,
          suggestions: suggestions,
        ),
      ),
    );
    _recordCalendarActivity('Exported month summary');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Month markdown copied')));
  }

  Future<void> _copySelectedRangeMarkdown() async {
    final selectedDays = ref.read(calendarRangeSelectionProvider).toList()
      ..sort();
    if (selectedDays.isEmpty) return;
    final nodes = await ref.read(allMindmapNodesProvider.future);
    final range = buildCalendarRangeSummary(
      start: selectedDays.first,
      end: selectedDays.last,
      nodes: nodes,
    );
    await Clipboard.setData(
      ClipboardData(text: exportCalendarRangeMarkdown(summary: range)),
    );
    _recordCalendarActivity('Exported selected range');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Range markdown copied')));
  }

  Future<void> _balanceFocusedWeek() async {
    await _balanceDays(calendarWeekDays(_focusedDay));
  }

  Future<void> _balanceSelectedRange() async {
    final days = ref.read(calendarRangeSelectionProvider).toList()..sort();
    if (days.isEmpty) return;
    await _balanceDays(days);
  }

  Future<void> _balanceDays(List<DateTime> days) async {
    final nodes = await ref.read(allMindmapNodesProvider.future);
    final plan = buildWorkloadBalancePlan(candidateDays: days, nodes: nodes);
    if (!mounted) return;
    if (plan.moves.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            plan.overloadedDays.isEmpty
                ? 'No overloaded days found'
                : 'No safe workload moves found',
          ),
        ),
      );
      return;
    }
    final selectedMoves = await showDialog<List<WorkloadMoveSuggestion>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Balance workload (${plan.moves.length} move preview)'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final move in plan.moves)
                  ListTile(
                    title: Text(move.node.title),
                    subtitle: Text(
                      '${DateFormat('MMM d').format(move.fromDay)} → ${DateFormat('MMM d').format(move.toDay)}',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop([plan.moves.first]),
              child: const Text('Move one'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(plan.moves),
              child: const Text('Spread all'),
            ),
          ],
        );
      },
    );
    if (selectedMoves == null || selectedMoves.isEmpty) return;
    final mutationController = ref.read(mindmapMutationControllerProvider);
    for (final move in selectedMoves) {
      await mutationController.rescheduleNode(move.node, day: move.toDay);
    }
    _pushCalendarUndo(
      CalendarUndoAction(
        label: 'workload balance',
        undo: (ref) async {
          final controller = ref.read(mindmapMutationControllerProvider);
          for (final move in selectedMoves) {
            await controller.rescheduleNode(
              move.node.copyWith(day: move.toDay),
              day: move.fromDay,
            );
          }
        },
      ),
    );
    _recordCalendarActivity('Balanced ${selectedMoves.length} tasks');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved ${selectedMoves.length} tasks')),
    );
  }

  void _recordCalendarActivity(String message) {
    final notifier = ref.read(calendarActivityLogProvider.notifier);
    notifier.state = [
      message,
      ...ref.read(calendarActivityLogProvider),
    ].take(8).toList(growable: false);
  }

  void _pushCalendarUndo(CalendarUndoAction action) {
    final notifier = ref.read(calendarUndoStackProvider.notifier);
    notifier.state = [
      action,
      ...ref.read(calendarUndoStackProvider),
    ].take(8).toList(growable: false);
  }

  Future<void> _undoLastCalendarAction() async {
    final stack = ref.read(calendarUndoStackProvider);
    if (stack.isEmpty) return;
    final action = stack.first;
    ref.read(calendarUndoStackProvider.notifier).state = stack.skip(1).toList();
    await action.undo(ref);
    _recordCalendarActivity('Undid ${action.label}');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Undid ${action.label}')));
  }

  Future<void> _showQuickCaptureSheet(DateTime day) async {
    final normalizedDay = day.dateOnly;
    var draftText = '';
    final query = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick capture',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Default day: ${DateFormat('EEE, MMM d').format(normalizedDay)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('calendar-quick-capture-input'),
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Command',
                  hintText: 'task bayar listrik p:high #home',
                  prefixIcon: Icon(Icons.flash_on_outlined),
                ),
                onChanged: (value) => draftText = value,
                onSubmitted: (value) => Navigator.of(context).pop(value),
              ),
              const SizedBox(height: 10),
              const Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _QuickCaptureExampleChip(text: 'task Pay bills p:high #home'),
                  _QuickCaptureExampleChip(text: 'event Meeting at:14:00'),
                  _QuickCaptureExampleChip(text: 'habit Workout daily'),
                  _QuickCaptureExampleChip(text: 'note Product idea #var'),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('calendar-quick-capture-submit'),
                  onPressed: () => Navigator.of(context).pop(draftText),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create'),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (query == null || query.trim().isEmpty) return;
    await _createNodeFromQuickCapture(query, normalizedDay);
  }

  Future<void> _createNodeFromQuickCapture(String query, DateTime day) async {
    final normalizedQuery = query.trim();
    final command = quickCreateCommandFromQuery(
      normalizedQuery,
      today: ref.read(currentDateProvider).dateOnly,
      defaultDay: day.dateOnly,
    );
    final nodeDay = command?.day ?? day.dateOnly;
    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: command?.type ?? NodeType.note,
      title: command?.title ?? normalizedQuery,
      body: command?.body ?? '',
      day: nodeDay,
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
      now: DateTime.now(),
    );
    try {
      await ref.read(mindmapMutationControllerProvider).saveNode(node);
      _pushCalendarUndo(
        CalendarUndoAction(
          label: 'quick capture',
          undo: (ref) async {
            await ref.read(mindmapMutationControllerProvider).deleteNode(node);
          },
        ),
      );
      _recordCalendarActivity('Quick captured ${node.type.label}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Captured "${node.title}"'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _openFullDay(node.day, highlightNodeId: node.id),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to capture: $error')));
    }
  }

  Future<void> _addNodeQuick(DateTime day, NodeType type) async {
    final normalizedDay = day.dateOnly;
    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: type,
      title: 'New ${type.label}',
      body: '',
      day: normalizedDay,
      now: DateTime.now(),
    );
    try {
      await ref.read(mindmapMutationControllerProvider).saveNode(node);
      _recordCalendarActivity('Created ${type.label}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created ${type.label} on ${DateFormat('MMM d').format(normalizedDay)}',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showDayPreviewSheet(DateTime day) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: _DayPreviewPanel(
                day: day,
                today: ref.read(currentDateProvider),
                onClose: () => Navigator.of(context).pop(),
                onAddNode: () => _addNodeForDay(day),
                onApplyTemplate: () => _showTemplatePicker(day),
                onClearSearch: _clearCalendarSearch,
                onOpenDay: () => goToDay(context, day),
                onOpenNode: (nodeId) =>
                    goToDay(context, day, highlightNodeId: nodeId),
              ),
            ),
          ),
        );
      },
    );
    if (mounted && _previewDay?.isSameDay(day) == true) {
      setState(() => _previewDay = null);
    }
  }

  KeyEventResult _handleCalendarShortcut(
    KeyDownEvent event,
    CalendarViewMode viewMode,
  ) {
    if (event.logicalKey == LogicalKeyboardKey.slash) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyT) {
      _jumpToToday(ref.read(currentDateProvider));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _showPreviousPeriod(viewMode);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _showNextPeriod(viewMode);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _showFocusedDay(_focusedDay.startOfWeek);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _showFocusedDay(_focusedDay.startOfWeek.add(const Duration(days: 6)));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      unawaited(_addNodeForDay(_previewDay ?? _focusedDay));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyM) {
      ref
          .read(calendarViewModeProvider.notifier)
          .setViewMode(CalendarViewMode.month);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      ref
          .read(calendarViewModeProvider.notifier)
          .setViewMode(CalendarViewMode.week);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyA) {
      ref
          .read(calendarViewModeProvider.notifier)
          .setViewMode(CalendarViewMode.agenda);
      return KeyEventResult.handled;
    }
    if (viewMode == CalendarViewMode.agenda) {
      final isShiftArrow =
          HardwareKeyboard.instance.isShiftPressed &&
          (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight);
      if (isShiftArrow) {
        final days = event.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1;
        unawaited(_moveSelectedAgendaNodeByDays(days));
        return KeyEventResult.handled;
      }
      final filter = switch (event.logicalKey) {
        LogicalKeyboardKey.digit1 => AgendaFilter.all,
        LogicalKeyboardKey.digit2 => AgendaFilter.tasks,
        LogicalKeyboardKey.digit3 => AgendaFilter.events,
        LogicalKeyboardKey.digit4 => AgendaFilter.habits,
        LogicalKeyboardKey.digit5 => AgendaFilter.routines,
        LogicalKeyboardKey.digit6 => AgendaFilter.done,
        _ => null,
      };
      if (filter != null) {
        ref.read(agendaFilterProvider.notifier).setFilter(filter);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _moveSelectedAgendaNodeByDays(int days) async {
    final nodeId = ref.read(selectedAgendaNodeIdProvider);
    if (nodeId == null) return;
    final node = await ref.read(mindmapRepositoryProvider).getNode(nodeId);
    if (node == null || !mounted) return;
    final targetDay = node.day.add(Duration(days: days)).dateOnly;
    await ref
        .read(mindmapMutationControllerProvider)
        .rescheduleNode(node, day: targetDay);
    _pushCalendarUndo(
      CalendarUndoAction(
        label: 'agenda move',
        undo: (ref) async {
          await ref
              .read(mindmapMutationControllerProvider)
              .rescheduleNode(node.copyWith(day: targetDay), day: node.day);
        },
      ),
    );
    _recordCalendarActivity('Moved ${node.title}');
    if (!mounted) return;
    _showRescheduleSnackBar(
      context: context,
      ref: ref,
      node: node,
      previousDay: node.day,
      targetDay: targetDay,
    );
  }

  String get _monthKey => '${_visibleMonth.year}-${_visibleMonth.month}';

  Future<void> _showDatePicker() async {
    final now = ref.read(currentDateProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _focusedDay,
      firstDate: now.subtract(const Duration(days: 365 * 10)),
      lastDate: now.add(const Duration(days: 365 * 10)),
    );
    if (picked != null && mounted) {
      _showFocusedDay(picked);
    }
  }
}

class _CalendarEmptyBanner extends ConsumerWidget {
  const _CalendarEmptyBanner({
    required this.visibleMonth,
    required this.today,
    required this.isDismissed,
    required this.onAddNode,
    required this.onDismiss,
  });

  final DateTime visibleMonth;
  final DateTime today;
  final bool isDismissed;
  final Future<void> Function(DateTime day) onAddNode;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isDismissed) return const SizedBox.shrink();

    final firstDay = visibleMonth.dateOnly.firstOfMonth;
    final lastDay = DateTime(visibleMonth.year, visibleMonth.month + 1, 0);
    final allNodesAsync = ref.watch(allMindmapNodesProvider);
    final allNodes = allNodesAsync.valueOrNull;
    if (allNodes == null) return const SizedBox.shrink();
    final hasNodes = allNodes.any(
      (n) =>
          n.day.isAfter(firstDay.subtract(const Duration(days: 1))) &&
          n.day.isBefore(lastDay.add(const Duration(days: 1))),
    );
    if (hasNodes) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: ShapeDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
              shape: DoodleShapeBorder(
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
                radius: 10,
                wobble: 1.4,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No nodes yet in ${DateFormat('MMMM').format(visibleMonth)} \u2014 tap a day to add one',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('calendar-empty-add-node'),
                  onPressed: () {
                    unawaited(onAddNode(visibleMonth.dateOnly.firstOfMonth));
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add node'),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    tooltip: 'Dismiss',
                    icon: Icon(
                      Icons.close,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    onPressed: onDismiss,
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

class _CollapsedDayPreviewRail extends StatelessWidget {
  const _CollapsedDayPreviewRail({required this.day, required this.onExpand});

  final DateTime day;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        customBorder: const DoodleShapeBorder(radius: 12, wobble: 1.4),
        onTap: onExpand,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(
                Icons.chevron_left_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 8),
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  DateFormat('MMM d').format(day),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarControlPanel extends StatelessWidget {
  const _CalendarControlPanel({
    required this.focusedDay,
    required this.today,
    required this.selectedTypes,
    required this.doneOnly,
    this.onClose,
  });

  final DateTime focusedDay;
  final DateTime today;
  final Set<NodeType> selectedTypes;
  final bool doneOnly;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: ShapeDecoration(
                  shape: DoodleShapeBorder(
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                    radius: 10,
                    wobble: 1.4,
                  ),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tools',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onClose != null)
                IconButton.outlined(
                  tooltip: 'Hide tools',
                  icon: const Icon(Icons.keyboard_double_arrow_left, size: 18),
                  onPressed: onClose,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Filters and planning actions stay here so the calendar stays clean.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text('Filters', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          _CalendarFilterStrip(
            selectedTypes: selectedTypes,
            doneOnly: doneOnly,
            wrap: true,
          ),
          const SizedBox(height: 18),
          const _CalendarMissionLegend(),
          const SizedBox(height: 8),
          _SelectedDayMissionCard(day: focusedDay),
          const SizedBox(height: 12),
          _WeeklySummaryStrip(focusedDay: focusedDay, today: today),
        ],
      ),
    );
  }
}

class _CalendarAdvancedTools extends StatelessWidget {
  const _CalendarAdvancedTools({
    required this.focusedDay,
    required this.onApplyTemplate,
    required this.onExportDay,
    required this.onExportWeek,
    required this.onExportMonth,
    required this.onBalanceWeek,
    required this.onUndoLast,
    required this.onToggleFocusedDay,
    required this.onSelectFocusedWeek,
    required this.onBalanceRange,
    required this.onClearRange,
    required this.onExportRange,
    required this.onApplyRangeTemplate,
  });

  final DateTime focusedDay;
  final Future<void> Function(DateTime day) onApplyTemplate;
  final Future<void> Function() onExportDay;
  final Future<void> Function() onExportWeek;
  final Future<void> Function() onExportMonth;
  final Future<void> Function() onBalanceWeek;
  final VoidCallback onUndoLast;
  final VoidCallback onToggleFocusedDay;
  final VoidCallback onSelectFocusedWeek;
  final Future<void> Function() onBalanceRange;
  final VoidCallback onClearRange;
  final Future<void> Function() onExportRange;
  final Future<void> Function() onApplyRangeTemplate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: const DoodleShapeBorder(radius: 12, wobble: 1.4),
        collapsedShape: const DoodleShapeBorder(radius: 12, wobble: 1.4),
        title: Text(
          'Planning tools',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          'Templates, exports, workload, range actions',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        children: [
          const _CalendarHeatmapModeStrip(),
          const SizedBox(height: 6),
          _CalendarPlanningPanel(
            focusedDay: focusedDay,
            onApplyTemplate: onApplyTemplate,
            onExportDay: onExportDay,
            onExportWeek: onExportWeek,
            onExportMonth: onExportMonth,
            onBalanceWeek: onBalanceWeek,
            onUndoLast: () async => onUndoLast(),
          ),
          const SizedBox(height: 6),
          _CalendarRangePanel(
            focusedDay: focusedDay,
            onToggleFocusedDay: onToggleFocusedDay,
            onSelectFocusedWeek: onSelectFocusedWeek,
            onBalanceRange: onBalanceRange,
            onClear: onClearRange,
            onExport: onExportRange,
            onApplyTemplate: onApplyRangeTemplate,
          ),
        ],
      ),
    );
  }
}

class _CalendarFilterStrip extends ConsumerWidget {
  const _CalendarFilterStrip({
    required this.selectedTypes,
    required this.doneOnly,
    this.wrap = false,
    this.showAdvancedChip = true,
  });

  final Set<NodeType> selectedTypes;
  final bool doneOnly;
  final bool wrap;
  final bool showAdvancedChip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final density = ref.watch(calendarDensityModeProvider);
    final filters = <NodeType>[
      NodeType.task,
      NodeType.event,
      NodeType.habit,
      NodeType.note,
      NodeType.goal,
      NodeType.routine,
    ];

    Widget buildChip(int index) {
      if (index == 0) {
        final isActive = selectedTypes.isEmpty && !doneOnly;
        return _CalendarFilterChip(
          chipKey: const ValueKey('calendar-filter-all'),
          label: 'All',
          icon: Icons.all_inclusive_rounded,
          color: theme.colorScheme.primary,
          isSelected: isActive,
          onTap: () {
            ref.read(calendarTypeFiltersProvider.notifier).state = {};
            ref.read(calendarDoneFilterProvider.notifier).state = false;
          },
        );
      }
      if (index == filters.length + 1) {
        return _CalendarFilterChip(
          chipKey: const ValueKey('calendar-filter-done'),
          label: 'Done',
          icon: Icons.check_circle_outline_rounded,
          color: theme.colorScheme.tertiary,
          isSelected: doneOnly,
          onTap: () {
            ref.read(calendarDoneFilterProvider.notifier).state = !doneOnly;
          },
        );
      }
      if (showAdvancedChip && index == filters.length + 2) {
        final advanced = ref.watch(calendarAdvancedFilterProvider);
        final isAdvanced =
            advanced.hasSchedule == true ||
            advanced.hasJournal == true ||
            advanced.hasOverdue == true ||
            advanced.priority != null ||
            advanced.status != null ||
            advanced.type != null ||
            advanced.project.trim().isNotEmpty ||
            advanced.area.trim().isNotEmpty ||
            advanced.tag.trim().isNotEmpty;
        return _CalendarFilterChip(
          chipKey: const ValueKey('calendar-filter-advanced'),
          label: 'Advanced',
          icon: Icons.filter_alt_outlined,
          color: theme.colorScheme.primary,
          isSelected: isAdvanced,
          onTap: () => _showAdvancedCalendarFilters(context, ref),
        );
      }
      final densityIndex = filters.length + (showAdvancedChip ? 3 : 2);
      if (index == densityIndex) {
        return _CalendarFilterChip(
          chipKey: const ValueKey('calendar-filter-density'),
          label: switch (density) {
            CalendarDensityMode.compact => 'Compact',
            CalendarDensityMode.comfortable => 'Comfort',
            CalendarDensityMode.detailed => 'Detail',
          },
          icon: Icons.view_agenda_outlined,
          color: theme.colorScheme.secondary,
          isSelected: density != CalendarDensityMode.compact,
          onTap: () {
            final next = switch (density) {
              CalendarDensityMode.compact => CalendarDensityMode.comfortable,
              CalendarDensityMode.comfortable => CalendarDensityMode.detailed,
              CalendarDensityMode.detailed => CalendarDensityMode.compact,
            };
            ref.read(calendarDensityModeProvider.notifier).state = next;
          },
        );
      }
      final type = filters[index - 1];
      final isSelected = selectedTypes.contains(type);
      return _CalendarFilterChip(
        chipKey: ValueKey('calendar-filter-${type.name}'),
        label: type.label,
        icon: _nodeIcon(type),
        color: _nodeColor(type),
        isSelected: isSelected,
        onTap: () {
          final next = {...selectedTypes};
          if (isSelected) {
            next.remove(type);
          } else {
            next.add(type);
          }
          ref.read(calendarTypeFiltersProvider.notifier).state = next;
        },
      );
    }

    final itemCount = filters.length + (showAdvancedChip ? 4 : 3);
    if (wrap) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var index = 0; index < itemCount; index++) buildChip(index),
        ],
      );
    }

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) => buildChip(index),
      ),
    );
  }
}

Future<void> _showAdvancedCalendarFilters(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = ref.read(calendarAdvancedFilterProvider);
  var project = current.project;
  var area = current.area;
  var tag = current.tag;
  var type = current.type;
  var priority = current.priority;
  var status = current.status;
  var hasSchedule = current.hasSchedule;
  var hasJournal = current.hasJournal;
  var hasOverdue = current.hasOverdue;
  final result = await showDialog<CalendarNodeFilter>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          const fieldGap = SizedBox(height: 14);
          const sectionGap = SizedBox(height: 20);
          final theme = Theme.of(context);
          final inputDecoration = InputDecoration(
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.34,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          );

          Widget toggleRow({
            required String label,
            required bool value,
            required ValueChanged<bool> onChanged,
          }) {
            return Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: ShapeDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.22,
                ),
                shape: DoodleShapeBorder(
                  radius: 12,
                  wobble: 0.8,
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.55,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: theme.textTheme.labelLarge),
                  ),
                  Switch(value: value, onChanged: onChanged),
                ],
              ),
            );
          }

          return AlertDialog(
            title: const Text('Advanced filters'),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      key: const ValueKey('calendar-advanced-filter-fields'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          initialValue: project,
                          decoration: inputDecoration.copyWith(
                            labelText: 'Project',
                          ),
                          onChanged: (value) => project = value,
                        ),
                        fieldGap,
                        TextFormField(
                          initialValue: area,
                          decoration: inputDecoration.copyWith(
                            labelText: 'Area',
                          ),
                          onChanged: (value) => area = value,
                        ),
                        fieldGap,
                        TextFormField(
                          initialValue: tag,
                          decoration: inputDecoration.copyWith(
                            labelText: 'Tag',
                          ),
                          onChanged: (value) => tag = value,
                        ),
                        fieldGap,
                        DropdownButtonFormField<NodeType?>(
                          initialValue: type,
                          isExpanded: true,
                          decoration: inputDecoration.copyWith(
                            labelText: 'Type',
                          ),
                          items: [
                            const DropdownMenuItem<NodeType?>(
                              value: null,
                              child: Text('Any'),
                            ),
                            for (final value in NodeType.values)
                              DropdownMenuItem<NodeType?>(
                                value: value,
                                child: Text(value.label),
                              ),
                          ],
                          onChanged: (value) => setState(() => type = value),
                        ),
                        fieldGap,
                        DropdownButtonFormField<NodePriority?>(
                          initialValue: priority,
                          isExpanded: true,
                          decoration: inputDecoration.copyWith(
                            labelText: 'Priority',
                          ),
                          items: [
                            const DropdownMenuItem<NodePriority?>(
                              value: null,
                              child: Text('Any'),
                            ),
                            for (final value in NodePriority.values)
                              DropdownMenuItem<NodePriority?>(
                                value: value,
                                child: Text(value.label),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => priority = value),
                        ),
                        fieldGap,
                        DropdownButtonFormField<NodeStatus?>(
                          initialValue: status,
                          isExpanded: true,
                          decoration: inputDecoration.copyWith(
                            labelText: 'Status',
                          ),
                          items: [
                            const DropdownMenuItem<NodeStatus?>(
                              value: null,
                              child: Text('Any'),
                            ),
                            for (final value in NodeStatus.values)
                              DropdownMenuItem<NodeStatus?>(
                                value: value,
                                child: Text(value.label),
                              ),
                          ],
                          onChanged: (value) => setState(() => status = value),
                        ),
                      ],
                    ),
                    sectionGap,
                    Column(
                      key: const ValueKey('calendar-advanced-filter-toggles'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Node state',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        toggleRow(
                          label: 'Has schedule',
                          value: hasSchedule == true,
                          onChanged: (value) =>
                              setState(() => hasSchedule = value ? true : null),
                        ),
                        const SizedBox(height: 8),
                        toggleRow(
                          label: 'Has journal',
                          value: hasJournal == true,
                          onChanged: (value) =>
                              setState(() => hasJournal = value ? true : null),
                        ),
                        const SizedBox(height: 8),
                        toggleRow(
                          label: 'Has overdue',
                          value: hasOverdue == true,
                          onChanged: (value) =>
                              setState(() => hasOverdue = value ? true : null),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              Row(
                key: const ValueKey('calendar-advanced-filter-footer'),
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(const CalendarNodeFilter()),
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      CalendarNodeFilter(
                        project: project,
                        area: area,
                        tag: tag,
                        type: type,
                        priority: priority,
                        status: status,
                        hasSchedule: hasSchedule,
                        hasJournal: hasJournal,
                        hasOverdue: hasOverdue,
                      ),
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
  if (result != null) {
    ref.read(calendarAdvancedFilterProvider.notifier).state = result;
  }
}

class _CalendarFilterChip extends StatelessWidget {
  const _CalendarFilterChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.chipKey,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final Key? chipKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: chipKey,
      button: true,
      selected: isSelected,
      label: 'Calendar filter: $label',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.26,
                      ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected ? theme.colorScheme.onPrimary : color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _DayPreviewAction { template, openDay }

class _DayPreviewPanel extends ConsumerWidget {
  const _DayPreviewPanel({
    required this.day,
    required this.today,
    required this.onClose,
    required this.onAddNode,
    required this.onApplyTemplate,
    required this.onClearSearch,
    required this.onOpenDay,
    required this.onOpenNode,
  });

  final DateTime day;
  final DateTime today;
  final VoidCallback onClose;
  final Future<void> Function() onAddNode;
  final Future<void> Function() onApplyTemplate;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenDay;
  final ValueChanged<String> onOpenNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final normalizedDay = day.dateOnly;
    final nodesAsync = ref.watch(nodesForDayProvider(normalizedDay));
    final searchQuery = ref.watch(calendarSearchQueryProvider).trim();
    final normalizedQuery = searchQuery.toLowerCase();
    final typeFilters = ref.watch(calendarTypeFiltersProvider);
    final doneOnly = ref.watch(calendarDoneFilterProvider);
    final advancedFilter = ref.watch(calendarAdvancedFilterProvider);
    final selectedNodeId = ref.watch(selectedAgendaNodeIdProvider);
    final titleMap = ref.watch(workspaceTitleProvider);
    final titleKey =
        '${WorkspaceContextType.daily.name}_${dayKey(normalizedDay)}';
    final customTitle = titleMap[titleKey];
    final hasCustomTitle = customTitle != null && customTitle.isNotEmpty;
    final title = hasCustomTitle
        ? customTitle
        : DateFormat('EEEE, MMMM d').format(normalizedDay);

    return Card(
      key: const ValueKey('calendar-day-preview'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (normalizedDay.isSameDay(today)) ...[
                            const SizedBox(width: 8),
                            const _PulsingDot(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEE, MMM d, y').format(normalizedDay),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('calendar-day-preview-close'),
                  tooltip: 'Close preview',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 12),
            nodesAsync.when(
              loading: () => const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: SkeletonAgendaList(itemCount: 3),
                ),
              ),
              error: (error, stackTrace) => const Expanded(
                child: AnimatedErrorState(error: 'Unable to load day preview'),
              ),
              data: (nodes) {
                final visibleNodes = _applyCalendarFilters(
                  nodes,
                  query: normalizedQuery,
                  typeFilters: typeFilters,
                  doneOnly: doneOnly,
                  advancedFilter: advancedFilter,
                  today: today,
                );
                final summary = DayNodeSummary.fromNodes(
                  normalizedDay,
                  visibleNodes,
                );
                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _SummaryChip(
                            label: _countLabel(summary.totalCount),
                            color: theme.colorScheme.primary,
                          ),
                          if (summary.doneCount > 0)
                            _SummaryChip(
                              label: '${summary.doneCount} done',
                              color: theme.colorScheme.tertiary,
                            ),
                          if (summary.highPriorityCount > 0)
                            _SummaryChip(
                              label: '${summary.highPriorityCount} high',
                              color: theme.colorScheme.secondary,
                            ),
                          if (summary.overdueCount > 0)
                            _SummaryChip(
                              label: '${summary.overdueCount} overdue',
                              color: theme.colorScheme.error,
                            ),
                        ],
                      ),
                      if (searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Matching "$searchQuery"',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _CollapsibleDayMindmapMiniMap(
                        nodes: nodes,
                        visibleNodeIds: visibleNodes
                            .map((node) => node.id)
                            .toSet(),
                        onOpenDay: onOpenDay,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: visibleNodes.isEmpty
                            ? _DayPreviewEmptyState(
                                hasQuery: searchQuery.isNotEmpty,
                                onClearSearch: onClearSearch,
                              )
                            : ListView.separated(
                                itemCount: visibleNodes.length,
                                separatorBuilder: (_, separatorIndex) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final node = visibleNodes[index];
                                  return _DayPreviewNodeTile(
                                    node: node,
                                    isSelected: node.id == selectedNodeId,
                                    onTap: () {
                                      ref
                                              .read(
                                                selectedAgendaNodeIdProvider
                                                    .notifier,
                                              )
                                              .state =
                                          node.id;
                                      onOpenNode(node.id);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('calendar-day-preview-add-node'),
                    onPressed: () {
                      unawaited(onAddNode());
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add node'),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<_DayPreviewAction>(
                  key: const ValueKey('calendar-day-preview-more-actions'),
                  tooltip: 'More day actions',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) {
                    switch (action) {
                      case _DayPreviewAction.template:
                        unawaited(onApplyTemplate());
                      case _DayPreviewAction.openDay:
                        onOpenDay();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      key: ValueKey('calendar-day-preview-template'),
                      value: _DayPreviewAction.template,
                      child: ListTile(
                        leading: Icon(Icons.dashboard_customize_outlined),
                        title: Text('Apply template'),
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      key: ValueKey('calendar-day-preview-open-day'),
                      value: _DayPreviewAction.openDay,
                      child: ListTile(
                        leading: Icon(Icons.open_in_new),
                        title: Text('Open full day'),
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapsibleDayMindmapMiniMap extends StatefulWidget {
  const _CollapsibleDayMindmapMiniMap({
    required this.nodes,
    required this.visibleNodeIds,
    required this.onOpenDay,
  });

  final List<MindmapNode> nodes;
  final Set<String> visibleNodeIds;
  final VoidCallback onOpenDay;

  @override
  State<_CollapsibleDayMindmapMiniMap> createState() =>
      _CollapsibleDayMindmapMiniMapState();
}

class _CollapsibleDayMindmapMiniMapState
    extends State<_CollapsibleDayMindmapMiniMap> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeNodes = widget.nodes.where((node) => !node.isArchived).length;
    if (activeNodes == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('calendar-day-preview-minimap-toggle'),
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(
            _expanded ? Icons.account_tree : Icons.account_tree_outlined,
            size: 18,
          ),
          label: Text(_expanded ? 'Hide map' : 'Show map ($activeNodes)'),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            foregroundColor: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _expanded
              ? Padding(
                  key: const ValueKey('calendar-day-preview-minimap-body'),
                  padding: const EdgeInsets.only(top: 8),
                  child: _DayMindmapMiniMap(
                    nodes: widget.nodes,
                    visibleNodeIds: widget.visibleNodeIds,
                    onOpenDay: widget.onOpenDay,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _DayMindmapMiniMap extends StatelessWidget {
  const _DayMindmapMiniMap({
    required this.nodes,
    required this.visibleNodeIds,
    required this.onOpenDay,
  });

  final List<MindmapNode> nodes;
  final Set<String> visibleNodeIds;
  final VoidCallback onOpenDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeNodes = nodes.where((node) => !node.isArchived).toList();
    final connectionCount = activeNodes.fold<int>(
      0,
      (count, node) => count + node.relatedNodeIds.length,
    );

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDay,
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _DayMindmapMiniMapPainter(
                    nodes: activeNodes,
                    visibleNodeIds: visibleNodeIds,
                    colorScheme: theme.colorScheme,
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 10,
                child: Row(
                  children: [
                    Icon(
                      Icons.hub_rounded,
                      size: 15,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Mindmap mini',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 10,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      '${activeNodes.length} nodes • $connectionCount links',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              if (activeNodes.isEmpty)
                Center(
                  child: Text(
                    'No mindmap nodes yet',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Positioned(
                right: 10,
                bottom: 8,
                child: Icon(
                  Icons.open_in_new_rounded,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayMindmapMiniMapPainter extends CustomPainter {
  const _DayMindmapMiniMapPainter({
    required this.nodes,
    required this.visibleNodeIds,
    required this.colorScheme,
  });

  final List<MindmapNode> nodes;
  final Set<String> visibleNodeIds;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colorScheme.surface.withValues(alpha: 0.65),
          const Color(0xFF070A12).withValues(alpha: 0.82),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final starPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    for (var i = 0; i < 34; i++) {
      final x = (math.sin(i * 12.9898) * 43758.5453).abs() % size.width;
      final y = (math.sin(i * 78.233) * 24634.6345).abs() % size.height;
      canvas.drawCircle(Offset(x, y), i.isEven ? 0.8 : 0.45, starPaint);
    }

    if (nodes.isEmpty) return;

    var minX = nodes.first.position.dx;
    var maxX = nodes.first.position.dx;
    var minY = nodes.first.position.dy;
    var maxY = nodes.first.position.dy;
    for (final node in nodes) {
      minX = math.min(minX, node.position.dx);
      maxX = math.max(maxX, node.position.dx);
      minY = math.min(minY, node.position.dy);
      maxY = math.max(maxY, node.position.dy);
    }

    final contentWidth = math.max(120.0, maxX - minX + 220);
    final contentHeight = math.max(80.0, maxY - minY + 150);
    final scale = math.min(
      (size.width - 32) / contentWidth,
      (size.height - 42) / contentHeight,
    );
    final origin = Offset(
      (size.width - (maxX - minX) * scale) / 2 - minX * scale,
      (size.height - (maxY - minY) * scale) / 2 - minY * scale + 8,
    );

    Offset mapNode(MindmapNode node) {
      return Offset(
        origin.dx + node.position.dx * scale,
        origin.dy + node.position.dy * scale,
      );
    }

    final nodeById = {for (final node in nodes) node.id: node};
    final linePaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.18)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (final node in nodes) {
      final from = mapNode(node);
      for (final relatedId in node.relatedNodeIds) {
        final related = nodeById[relatedId];
        if (related == null) continue;
        canvas.drawLine(from, mapNode(related), linePaint);
      }
    }

    for (final node in nodes) {
      final point = mapNode(node);
      final isMatch = visibleNodeIds.contains(node.id);
      final color = _nodeColor(node.type);
      final glowPaint = Paint()
        ..shader = ui.Gradient.radial(point, isMatch ? 18 : 12, [
          color.withValues(alpha: isMatch ? 0.28 : 0.12),
          Colors.transparent,
        ]);
      canvas.drawCircle(point, isMatch ? 18 : 12, glowPaint);

      final nodePaint = Paint()
        ..color = color.withValues(alpha: isMatch ? 0.95 : 0.42);
      final radius = node.isDone ? 3.4 : 4.8;
      canvas.drawCircle(point, radius, nodePaint);

      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isMatch ? 1.5 : 0.8
        ..color = colorScheme.onSurface.withValues(
          alpha: isMatch ? 0.42 : 0.16,
        );
      canvas.drawCircle(point, radius + 2.4, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DayMindmapMiniMapPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.visibleNodeIds != visibleNodeIds ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _DayPreviewEmptyState extends StatelessWidget {
  const _DayPreviewEmptyState({
    required this.hasQuery,
    required this.onClearSearch,
  });

  final bool hasQuery;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    if (hasQuery) {
      return AnimatedEmptyState(
        icon: Icons.event_note_outlined,
        label: 'No matching nodes',
        subtitle: 'Clear search to see all nodes for this day.',
        actionLabel: 'Clear search',
        onAction: onClearSearch,
        actionKey: const ValueKey('calendar-day-preview-clear-search'),
        pulseIcon: true,
      );
    }

    return const AnimatedEmptyState(
      icon: Icons.event_note_outlined,
      label: 'No nodes yet for this day',
      subtitle: 'Use the actions below to add a node or open the full day.',
      pulseIcon: false,
    );
  }
}

class _DayPreviewNodeTile extends StatelessWidget {
  const _DayPreviewNodeTile({
    required this.node,
    required this.isSelected,
    required this.onTap,
  });

  final MindmapNode node;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = _previewNodeMetadata(node);
    return Material(
      color: _nodeColor(node.type).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('calendar-day-preview-node-${node.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(
                _nodeIcon(node.type),
                size: 18,
                color: _nodeColor(node.type),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.title.trim().isEmpty
                          ? 'Untitled ${node.type.name}'
                          : node.title.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        metadata,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (_bodyPreview != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _bodyPreview!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _previewNodeMetadata(MindmapNode node) {
    final parts = <String>[node.type.label];
    final timeBlock = timeBlockForNode(node);
    if (timeBlock.isValid) parts.insert(0, timeBlock.block!.rangeLabel);
    if (node.priority != NodePriority.none) parts.add(node.priority.label);
    if (node.status != NodeStatus.open) parts.add(node.status.label);
    return parts.join(' · ');
  }

  String? get _bodyPreview {
    final body = node.body.trim();
    if (body.isEmpty) return null;
    final lines = body.split('\n');
    for (final l in lines) {
      final t = l.trim();
      if (t.isNotEmpty) {
        return t.length > 80 ? '\u2026' : t;
      }
    }
    return null;
  }
}

class _RoutineApplyBanner extends ConsumerWidget {
  const _RoutineApplyBanner({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(calendarRoutinePlanProvider(day.dateOnly));
    return planAsync.maybeWhen(
      data: (plan) {
        if (plan.readyCount == 0) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - value)),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              key: const ValueKey('calendar-routine-apply-banner'),
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_motion_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${plan.readyCount} routines ready for today',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    FilledButton.tonal(
                      key: const ValueKey('calendar-apply-routines'),
                      onPressed: () => _showRoutineActions(context, ref, plan),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Future<void> _showRoutineActions(
    BuildContext context,
    WidgetRef ref,
    RecurringRoutinePlan plan,
  ) async {
    final readyItems = plan.items
        .where((item) => item.willCreate)
        .toList(growable: false);
    final result = await showDialog<_RoutineDialogResult>(
      context: context,
      builder: (context) {
        final selectedRoutineIds = readyItems
            .map((item) => item.routine.id)
            .toSet();
        return StatefulBuilder(
          builder: (context, setState) {
            void toggleRoutine(String id, bool selected) {
              setState(() {
                if (selected) {
                  selectedRoutineIds.add(id);
                } else {
                  selectedRoutineIds.remove(id);
                }
              });
            }

            void selectAllRoutines() {
              setState(() {
                selectedRoutineIds
                  ..clear()
                  ..addAll(readyItems.map((item) => item.routine.id));
              });
            }

            void clearRoutines() {
              setState(selectedRoutineIds.clear);
            }

            void submit(_RoutineAction action) {
              Navigator.of(context).pop(
                _RoutineDialogResult(
                  action: action,
                  selectedRoutineIds: Set.unmodifiable(selectedRoutineIds),
                ),
              );
            }

            final selectedCount = selectedRoutineIds.length;
            final size = MediaQuery.sizeOf(context);
            final dialogWidth = math.min(360.0, size.width - 48.0);
            final listMaxHeight = math.min(320.0, size.height * 0.45);
            return AlertDialog(
              key: const ValueKey('calendar-routine-apply-dialog'),
              title: const Text('Apply routines?'),
              content: SizedBox(
                width: dialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$selectedCount of ${readyItems.length} routines selected.',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          key: const ValueKey('calendar-select-all-routines'),
                          onPressed: selectedCount == readyItems.length
                              ? null
                              : selectAllRoutines,
                          child: const Text('Select all'),
                        ),
                        TextButton(
                          key: const ValueKey('calendar-clear-routines'),
                          onPressed: selectedCount == 0 ? null : clearRoutines,
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: listMaxHeight),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final item in readyItems)
                            CheckboxListTile(
                              key: ValueKey(
                                'calendar-routine-select-${item.routine.id}',
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: selectedRoutineIds.contains(
                                item.routine.id,
                              ),
                              onChanged: (value) {
                                toggleRoutine(item.routine.id, value ?? false);
                              },
                              title: Text(
                                item.node?.title ?? item.routine.label,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('calendar-skip-routines'),
                  onPressed: selectedCount == 0
                      ? null
                      : () => submit(_RoutineAction.skip),
                  child: const Text('Skip today'),
                ),
                TextButton(
                  key: const ValueKey('calendar-snooze-routines'),
                  onPressed: selectedCount == 0
                      ? null
                      : () => submit(_RoutineAction.snooze),
                  child: const Text('Snooze'),
                ),
                TextButton(
                  onPressed: () => submit(_RoutineAction.cancel),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey('calendar-confirm-apply-routines'),
                  onPressed: selectedCount == 0
                      ? null
                      : () => submit(_RoutineAction.apply),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null ||
        result.action == _RoutineAction.cancel ||
        result.selectedRoutineIds.isEmpty ||
        !context.mounted) {
      return;
    }

    final repository = ref.read(mindmapRepositoryProvider);
    final selectedRoutines = readyItems
        .where((item) => result.selectedRoutineIds.contains(item.routine.id))
        .map((item) => item.routine)
        .toList(growable: false);
    final snoozeTargetDay = result.action == _RoutineAction.snooze
        ? await showDatePicker(
            context: context,
            initialDate: day.add(const Duration(days: 1)),
            firstDate: day.add(const Duration(days: 1)),
            lastDate: day.add(const Duration(days: 365)),
          )
        : null;
    if (result.action == _RoutineAction.snooze &&
        (snoozeTargetDay == null || !context.mounted)) {
      return;
    }
    final saved = switch (result.action) {
      _RoutineAction.apply => await applyRecurringRoutines(
        repository: repository,
        day: day,
        routines: selectedRoutines,
      ),
      _RoutineAction.skip => await skipRecurringRoutines(
        repository: repository,
        day: day,
        routines: selectedRoutines,
      ),
      _RoutineAction.snooze => await snoozeRecurringRoutines(
        repository: repository,
        day: day,
        targetDay: snoozeTargetDay!,
        routines: selectedRoutines,
      ),
      _RoutineAction.cancel => <MindmapNode>[],
    };
    invalidateMindmapState(ref, day: day, extraDay: snoozeTargetDay?.dateOnly);
    _invalidateRoutinePlanDays(ref, [day, snoozeTargetDay?.dateOnly]);
    if (!context.mounted) return;
    final message = switch (result.action) {
      _RoutineAction.apply => 'Applied ${saved.length} routines',
      _RoutineAction.skip => 'Skipped ${saved.length} routines today',
      _RoutineAction.snooze =>
        'Snoozed ${saved.length} routines to ${DateFormat('MMM d, y').format(snoozeTargetDay!)}',
      _RoutineAction.cancel => '',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: switch (result.action) {
          _RoutineAction.skip || _RoutineAction.snooze => SnackBarAction(
            label: 'Undo',
            onPressed: () {
              unawaited(_undoRoutineMarkers(ref, saved));
            },
          ),
          _RoutineAction.apply || _RoutineAction.cancel => null,
        },
      ),
    );
  }

  Future<void> _undoRoutineMarkers(
    WidgetRef ref,
    List<MindmapNode> markers,
  ) async {
    final repository = ref.read(mindmapRepositoryProvider);
    for (final marker in markers) {
      await repository.deleteNode(marker.id);
    }
    invalidateMindmapState(ref, day: day);
    _invalidateRoutinePlanDays(ref, [
      day,
      for (final marker in markers) _routineMarkerSnoozedToDate(marker),
    ]);
  }
}

enum _RoutineAction { apply, skip, snooze, cancel }

final class _RoutineDialogResult {
  const _RoutineDialogResult({
    required this.action,
    required this.selectedRoutineIds,
  });

  final _RoutineAction action;
  final Set<String> selectedRoutineIds;
}

class _CalendarHeatmapModeStrip extends ConsumerWidget {
  const _CalendarHeatmapModeStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(calendarHeatmapModeProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final mode in CalendarHeatmapMode.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: ValueKey('calendar-heatmap-${mode.name}'),
                label: Text(calendarHeatmapModeLabel(mode)),
                selected: selected == mode,
                onSelected: (_) =>
                    ref.read(calendarHeatmapModeProvider.notifier).state = mode,
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarPlanningPanel extends ConsumerWidget {
  const _CalendarPlanningPanel({
    required this.focusedDay,
    required this.onApplyTemplate,
    required this.onExportDay,
    required this.onExportWeek,
    required this.onExportMonth,
    required this.onBalanceWeek,
    required this.onUndoLast,
  });

  final DateTime focusedDay;
  final Future<void> Function(DateTime day) onApplyTemplate;
  final Future<void> Function() onExportDay;
  final Future<void> Function() onExportWeek;
  final Future<void> Function() onExportMonth;
  final Future<void> Function() onBalanceWeek;
  final Future<void> Function() onUndoLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesAsync = ref.watch(allMindmapNodesProvider);
    final activities = ref.watch(calendarActivityLogProvider);
    final undoStack = ref.watch(calendarUndoStackProvider);
    return nodesAsync.maybeWhen(
      data: (nodes) {
        final week = buildCalendarWeekSummary(
          selectedDay: focusedDay,
          nodes: nodes,
        );
        final suggestions = buildCalendarPlanningSuggestions(
          week: week,
          today: ref.watch(currentDateProvider),
        );
        if (suggestions.isEmpty && activities.isEmpty) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Tooltip(
                      message:
                          'Shortcuts: arrows move, PgUp/PgDn period, Home/End week, Enter open, Space preview, T today, N add, / search',
                      child: Text(
                        'Planning HUD · ? shortcuts',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    ActionChip(
                      label: const Text('Template'),
                      avatar: const Icon(Icons.dashboard_customize_outlined),
                      onPressed: () => unawaited(onApplyTemplate(focusedDay)),
                    ),
                    ActionChip(
                      label: const Text('Balance'),
                      avatar: const Icon(Icons.tune_outlined),
                      onPressed: () => unawaited(onBalanceWeek()),
                    ),
                    ActionChip(
                      label: const Text('Export day'),
                      avatar: const Icon(Icons.today_outlined),
                      onPressed: () => unawaited(onExportDay()),
                    ),
                    ActionChip(
                      label: const Text('Export week'),
                      avatar: const Icon(Icons.copy_outlined),
                      onPressed: () => unawaited(onExportWeek()),
                    ),
                    ActionChip(
                      label: const Text('Export month'),
                      avatar: const Icon(Icons.calendar_month_outlined),
                      onPressed: () => unawaited(onExportMonth()),
                    ),
                    ActionChip(
                      label: const Text('Undo'),
                      avatar: const Icon(Icons.undo_outlined),
                      onPressed: undoStack.isEmpty
                          ? null
                          : () => unawaited(onUndoLast()),
                    ),
                  ],
                ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final suggestion in suggestions.take(2))
                    Text(
                      '• ${suggestion.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
                if (activities.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Last: ${activities.first}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _CalendarRangePanel extends ConsumerWidget {
  const _CalendarRangePanel({
    required this.focusedDay,
    required this.onToggleFocusedDay,
    required this.onSelectFocusedWeek,
    required this.onBalanceRange,
    required this.onClear,
    required this.onExport,
    required this.onApplyTemplate,
  });

  final DateTime focusedDay;
  final VoidCallback onToggleFocusedDay;
  final VoidCallback onSelectFocusedWeek;
  final Future<void> Function() onBalanceRange;
  final VoidCallback onClear;
  final Future<void> Function() onExport;
  final Future<void> Function() onApplyTemplate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDays = ref.watch(calendarRangeSelectionProvider).toList()
      ..sort();
    if (selectedDays.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('calendar-range-toggle'),
              onPressed: onToggleFocusedDay,
              icon: const Icon(Icons.checklist_outlined),
              label: const Text('Select date'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('calendar-range-select-week'),
              onPressed: onSelectFocusedWeek,
              icon: const Icon(Icons.view_week_outlined),
              label: const Text('Select week'),
            ),
          ],
        ),
      );
    }
    final nodesAsync = ref.watch(allMindmapNodesProvider);
    return nodesAsync.maybeWhen(
      data: (nodes) {
        final summary = buildCalendarRangeSummary(
          start: selectedDays.first,
          end: selectedDays.last,
          nodes: nodes,
        );
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${selectedDays.length} dates'),
                Text('${summary.totalTasks} tasks'),
                Text('${summary.completedTasks} done'),
                Text('${summary.overdueTasks} overdue'),
                Text('${summary.focusMinutes} focus min'),
                Text('${summary.journals} journals'),
                Text('${summary.habitCompletions} habits'),
                ActionChip(
                  label: const Text('Add focused'),
                  onPressed: onToggleFocusedDay,
                ),
                ActionChip(
                  label: const Text('Select week'),
                  onPressed: onSelectFocusedWeek,
                ),
                ActionChip(
                  label: const Text('Template'),
                  onPressed: () => unawaited(onApplyTemplate()),
                ),
                ActionChip(
                  label: const Text('Balance'),
                  onPressed: () => unawaited(onBalanceRange()),
                ),
                ActionChip(
                  label: const Text('Export'),
                  onPressed: () => unawaited(onExport()),
                ),
                ActionChip(label: const Text('Clear'), onPressed: onClear),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _CalendarViewModeSwitch extends ConsumerWidget {
  const _CalendarViewModeSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(calendarViewModeProvider);
    final theme = Theme.of(context);
    return Row(
      children: [
        SegmentedButton<CalendarViewMode>(
          key: const ValueKey('calendar-view-mode-switch'),
          selected: {mode},
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
          ),
          segments: CalendarViewMode.values
              .map((mode) {
                return ButtonSegment<CalendarViewMode>(
                  value: mode,
                  label: Text(mode.label),
                );
              })
              .toList(growable: false),
          onSelectionChanged: (selection) {
            ref
                .read(calendarViewModeProvider.notifier)
                .setViewMode(selection.first);
          },
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          key: const ValueKey('calendar-shortcuts-help'),
          tooltip: 'Calendar shortcuts',
          icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (context) => const _CalendarShortcutHelpDialog(),
            );
          },
        ),
      ],
    );
  }
}

class _CalendarShortcutHelpDialog extends StatelessWidget {
  const _CalendarShortcutHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Calendar shortcuts'),
      content: const SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ShortcutHelpRow(keys: 'M', action: 'Month view'),
              _ShortcutHelpRow(keys: 'W', action: 'Week view'),
              _ShortcutHelpRow(keys: 'A', action: 'Agenda view'),
              _ShortcutHelpRow(keys: 'N', action: 'Add node to focused day'),
              Divider(),
              _ShortcutHelpRow(keys: '1', action: 'All agenda items'),
              _ShortcutHelpRow(keys: '2', action: 'Tasks'),
              _ShortcutHelpRow(keys: '3', action: 'Events'),
              _ShortcutHelpRow(keys: '4', action: 'Habits'),
              _ShortcutHelpRow(keys: '5', action: 'Routines'),
              _ShortcutHelpRow(keys: '6', action: 'Done'),
              Divider(),
              _ShortcutHelpRow(
                keys: 'Shift+←',
                action: 'Move selected agenda item back one day',
              ),
              _ShortcutHelpRow(
                keys: 'Shift+→',
                action: 'Move selected agenda item forward one day',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ShortcutHelpRow extends StatelessWidget {
  const _ShortcutHelpRow({required this.keys, required this.action});

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              keys,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(action)),
        ],
      ),
    );
  }
}

class _WeekCalendarView extends StatelessWidget {
  const _WeekCalendarView({
    required this.focusedDay,
    required this.today,
    required this.onDayPreview,
  });

  final DateTime focusedDay;
  final DateTime today;
  final ValueChanged<DateTime> onDayPreview;

  @override
  Widget build(BuildContext context) {
    final weekStart = focusedDay.subtract(
      Duration(days: focusedDay.weekday - 1),
    );
    final days = List.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return ListView.separated(
            key: const ValueKey('calendar-week-strip'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: days.length,
            separatorBuilder: (_, separatorIndex) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final day = days[index];
              return SizedBox(
                width: 132,
                child: _DayCell(
                  day: day,
                  isInVisibleMonth: true,
                  isToday: day.isSameDay(today),
                  focusedDay: focusedDay,
                  rowIndex: 0,
                  colIndex: index,
                  totalRows: 1,
                  onPreview: onDayPreview,
                ),
              );
            },
          );
        }
        const crossAxisCount = 7;
        const spacing = 0.0;
        final cellWidth =
            (constraints.maxWidth - (crossAxisCount - 1) * spacing) /
            crossAxisCount;
        final cellHeight = constraints.maxHeight;
        final aspectRatio = cellHeight <= 0 ? 0.8 : cellWidth / cellHeight;
        return GridView.builder(
          key: const ValueKey('calendar-week-grid'),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
          itemCount: days.length,
          itemBuilder: (context, index) {
            final day = days[index];
            return _DayCell(
              day: day,
              isInVisibleMonth: true,
              isToday: day.isSameDay(today),
              focusedDay: focusedDay,
              rowIndex: 0,
              colIndex: index,
              totalRows: 1,
              onPreview: onDayPreview,
            );
          },
        );
      },
    );
  }
}

class _AgendaCalendarView extends ConsumerWidget {
  const _AgendaCalendarView({
    required this.focusedDay,
    required this.today,
    required this.onAddNode,
    required this.onClearSearch,
    required this.onResetFilters,
  });

  final DateTime focusedDay;
  final DateTime today;
  final Future<void> Function(DateTime day) onAddNode;
  final VoidCallback onClearSearch;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesAsync = ref.watch(allMindmapNodesProvider);
    final filter = ref.watch(agendaFilterProvider);
    final searchQuery = ref
        .watch(calendarSearchQueryProvider)
        .trim()
        .toLowerCase();
    final typeFilters = ref.watch(calendarTypeFiltersProvider);
    final doneOnly = ref.watch(calendarDoneFilterProvider);
    final advancedFilter = ref.watch(calendarAdvancedFilterProvider);
    final theme = Theme.of(context);
    return Column(
      children: [
        _AgendaFilterBar(
          counts: _buildFilterCounts(
            nodesAsync.valueOrNull,
            start: focusedDay.dateOnly,
            query: searchQuery,
            typeFilters: typeFilters,
            doneOnly: doneOnly,
            advancedFilter: advancedFilter,
            today: today,
          ),
        ),
        const SizedBox(height: 8),
        _CalendarFilterStrip(
          selectedTypes: typeFilters,
          doneOnly: doneOnly,
          wrap: true,
        ),

        const SizedBox(height: 10),
        Expanded(
          child: nodesAsync.when(
            loading: () => const _AgendaLoadingState(),
            error: (error, stackTrace) => _AgendaErrorState(error: error),
            data: (nodes) {
              final start = focusedDay.dateOnly;
              final end = start.add(const Duration(days: 30));
              final agendaNodes =
                  nodes
                      .where(
                        (node) =>
                            (!node.isArchived || _isRoutineMarker(node)) &&
                            !node.day.isBefore(start) &&
                            node.day.isBefore(end) &&
                            _applyCalendarFilters(
                              [node],
                              query: searchQuery,
                              typeFilters: typeFilters,
                              doneOnly: doneOnly,
                              advancedFilter: advancedFilter,
                              today: today,
                            ).isNotEmpty &&
                            _matchesFilter(node, filter),
                      )
                      .toList()
                    ..sort((a, b) {
                      final dayCompare = a.day.compareTo(b.day);
                      if (dayCompare != 0) return dayCompare;
                      final timeCompare = _agendaStartMinute(
                        a,
                      ).compareTo(_agendaStartMinute(b));
                      if (timeCompare != 0) return timeCompare;
                      final priorityCompare = b.priority.index.compareTo(
                        a.priority.index,
                      );
                      if (priorityCompare != 0) return priorityCompare;
                      return a.title.toLowerCase().compareTo(
                        b.title.toLowerCase(),
                      );
                    });
              final grouped = <DateTime, List<MindmapNode>>{};
              for (final node in agendaNodes) {
                grouped.putIfAbsent(node.day.dateOnly, () => []).add(node);
              }
              return agendaNodes.isEmpty
                  ? _AgendaEmptyState(
                      filter: filter,
                      day: focusedDay,
                      searchQuery: searchQuery,
                      onAddNode: () => onAddNode(focusedDay),
                      onClearSearch: onClearSearch,
                      hasCalendarFilters:
                          searchQuery.isNotEmpty ||
                          typeFilters.isNotEmpty ||
                          doneOnly,
                      onResetFilters: onResetFilters,
                    )
                  : ListView.separated(
                      key: const ValueKey('calendar-agenda-list'),
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: grouped.length,
                      separatorBuilder: (_, separatorIndex) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final day = grouped.keys.elementAt(index);
                        final dayNodes = grouped[day]!;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => goToDay(context, day),
                                  child: Row(
                                    children: [
                                      Text(
                                        _agendaDayLabel(day),
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      if (day.isSameDay(today)) ...[
                                        const SizedBox(width: 8),
                                        const _PulsingDot(),
                                      ],
                                      const Spacer(),
                                      Text(_agendaDayCountLabel(dayNodes)),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        key: ValueKey(
                                          'calendar-agenda-add-${dayKey(day)}',
                                        ),
                                        tooltip: 'Add node to day',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          unawaited(onAddNode(day));
                                        },
                                      ),
                                      IconButton(
                                        key: ValueKey(
                                          'calendar-agenda-open-${dayKey(day)}',
                                        ),
                                        tooltip: 'Open day',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.open_in_new,
                                          size: 18,
                                        ),
                                        onPressed: () => goToDay(context, day),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                for (final section
                                    in buildCalendarAgendaSections(
                                      today: today,
                                      nodes: dayNodes,
                                    )) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      section.label,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  ...section.nodes.take(5).map((node) {
                                    final selectedId = ref.watch(
                                      selectedAgendaNodeIdProvider,
                                    );
                                    final isSelected = selectedId == node.id;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: InkWell(
                                        key: ValueKey(
                                          'calendar-agenda-node-${node.id}',
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () {
                                          ref
                                                  .read(
                                                    selectedAgendaNodeIdProvider
                                                        .notifier,
                                                  )
                                                  .state =
                                              node.id;
                                          goToDay(
                                            context,
                                            day,
                                            highlightNodeId: node.id,
                                          );
                                        },
                                        child: AnimatedContainer(
                                          key: ValueKey(
                                            'calendar-agenda-selection-${node.id}',
                                          ),
                                          duration: const Duration(
                                            milliseconds: 120,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? theme.colorScheme.primary
                                                      .withValues(alpha: 0.1)
                                                : null,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: isSelected
                                                ? Border.all(
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                  )
                                                : null,
                                          ),
                                          child: Row(
                                            children: [
                                              IconButton(
                                                key: ValueKey(
                                                  'calendar-agenda-select-${node.id}',
                                                ),
                                                tooltip: isSelected
                                                    ? 'Selected for shortcuts'
                                                    : 'Select for shortcuts',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: Icon(
                                                  isSelected
                                                      ? Icons.check_circle
                                                      : Icons
                                                            .radio_button_unchecked,
                                                  size: 18,
                                                ),
                                                onPressed: () {
                                                  ref
                                                      .read(
                                                        selectedAgendaNodeIdProvider
                                                            .notifier,
                                                      )
                                                      .state = node
                                                      .id;
                                                },
                                              ),
                                              Icon(
                                                _nodeIcon(node.type),
                                                size: 16,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      node.title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    if (_routineMarkerLabel(
                                                          node,
                                                        ) !=
                                                        null) ...[
                                                      const SizedBox(height: 4),
                                                      _RoutineMarkerBadge(
                                                        label:
                                                            _routineMarkerLabel(
                                                              node,
                                                            )!,
                                                      ),
                                                    ],
                                                    if (_agendaNodeMetadata(
                                                      node,
                                                    ).isNotEmpty)
                                                      Text(
                                                        _agendaNodeMetadata(
                                                          node,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: theme
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                key: ValueKey(
                                                  'calendar-agenda-done-${node.id}',
                                                ),
                                                tooltip: 'Mark done',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(
                                                  Icons.check_circle_outline,
                                                  size: 18,
                                                ),
                                                onPressed: node.isDone
                                                    ? null
                                                    : () {
                                                        unawaited(
                                                          _markNodeDone(
                                                            ref,
                                                            node,
                                                          ),
                                                        );
                                                      },
                                              ),
                                              IconButton(
                                                key: ValueKey(
                                                  'calendar-agenda-tomorrow-${node.id}',
                                                ),
                                                tooltip: 'Move tomorrow',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(
                                                  Icons.redo_rounded,
                                                  size: 18,
                                                ),
                                                onPressed: () {
                                                  unawaited(
                                                    _moveNodeToTomorrow(
                                                      context,
                                                      ref,
                                                      node,
                                                      today,
                                                    ),
                                                  );
                                                },
                                              ),
                                              IconButton(
                                                key: ValueKey(
                                                  'calendar-agenda-move-${node.id}',
                                                ),
                                                tooltip: 'Move to date',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                icon: const Icon(
                                                  Icons.drive_file_move_outline,
                                                  size: 18,
                                                ),
                                                onPressed: () {
                                                  ref
                                                      .read(
                                                        selectedAgendaNodeIdProvider
                                                            .notifier,
                                                      )
                                                      .state = node
                                                      .id;
                                                  _moveNodeToDate(
                                                    context,
                                                    ref,
                                                    node,
                                                  );
                                                },
                                              ),
                                              if (_isRoutineMarker(node))
                                                _RoutineMarkerActionsMenu(
                                                  node: node,
                                                  today: today,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                                if (dayNodes.length > 5)
                                  Text(
                                    '+${dayNodes.length - 5} more',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
            },
          ),
        ),
      ],
    );
  }

  bool _matchesFilter(MindmapNode node, AgendaFilter filter) {
    return switch (filter) {
      AgendaFilter.all => true,
      AgendaFilter.tasks => node.type == NodeType.task,
      AgendaFilter.events => calendarNodePayloadFromData(node.data) != null,
      AgendaFilter.habits => node.type == NodeType.habit,
      AgendaFilter.routines => _isRoutineNode(node),
      AgendaFilter.done => node.isDone || node.status == NodeStatus.done,
    };
  }

  int _agendaStartMinute(MindmapNode node) {
    final parsed = timeBlockForNode(node);
    if (!parsed.isValid) return 1440;
    return parsed.block!.startMinute;
  }

  String _agendaNodeMetadata(MindmapNode node) {
    final parts = <String>[];
    final timeBlock = timeBlockForNode(node);
    if (timeBlock.isValid) parts.add(timeBlock.block!.rangeLabel);
    final payload = calendarNodePayloadFromData(node.data);
    if (payload != null) parts.add(payload.subtitle);
    final snoozedTargetLabel = _routineSnoozedTargetLabel(node);
    if (snoozedTargetLabel != null) parts.add(snoozedTargetLabel);
    if (node.priority != NodePriority.none) parts.add(node.priority.label);
    if (node.status != NodeStatus.open) parts.add(node.status.label);
    return parts.join(' · ');
  }

  String? _routineMarkerLabel(MindmapNode node) {
    final state = _routineAutomationData(node)['state'];
    return switch (state) {
      'skipped' => 'Skipped routine',
      'snoozed' => 'Snoozed routine',
      _ => null,
    };
  }

  bool _isRoutineMarker(MindmapNode node) {
    return _routineMarkerLabel(node) != null;
  }

  bool _isRoutineNode(MindmapNode node) {
    if (_isRoutineMarker(node) || node.type == NodeType.routine) return true;
    final automation = _routineAutomationData(node);
    return automation['routineId'] is String || node.tags.contains('routine');
  }

  String _agendaDayLabel(DateTime day) {
    if (day.isSameDay(today)) {
      return 'Today · ${DateFormat('EEE, MMM d').format(day)}';
    }
    if (day.isSameDay(today.add(const Duration(days: 1)))) {
      return 'Tomorrow · ${DateFormat('EEE, MMM d').format(day)}';
    }
    return DateFormat('EEE, MMM d').format(day);
  }

  String _agendaDayCountLabel(List<MindmapNode> nodes) {
    final scheduled = nodes
        .where((node) => timeBlockForNode(node).isValid)
        .length;
    final itemLabel = nodes.length == 1 ? '1 item' : '${nodes.length} items';
    if (scheduled == 0) return itemLabel;
    final scheduledLabel = scheduled == 1
        ? '1 scheduled'
        : '$scheduled scheduled';
    return '$itemLabel · $scheduledLabel';
  }

  Future<void> _markNodeDone(WidgetRef ref, MindmapNode node) async {
    final updated = node.copyWith(
      isDone: true,
      status: NodeStatus.done,
      progress: 1,
      updatedAt: DateTime.now(),
    );
    await ref.read(mindmapMutationControllerProvider).saveNode(updated);
  }

  Future<void> _moveNodeToTomorrow(
    BuildContext context,
    WidgetRef ref,
    MindmapNode node,
    DateTime today,
  ) async {
    final targetDay = today.dateOnly.add(const Duration(days: 1));
    await ref
        .read(mindmapMutationControllerProvider)
        .rescheduleNode(node, day: targetDay);
    if (!context.mounted) return;
    _showRescheduleSnackBar(
      context: context,
      ref: ref,
      node: node,
      previousDay: node.day,
      targetDay: targetDay,
    );
  }

  Future<void> _moveNodeToDate(
    BuildContext context,
    WidgetRef ref,
    MindmapNode node,
  ) async {
    final targetDay = await showDatePicker(
      context: context,
      initialDate: node.day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (targetDay == null || !context.mounted) return;
    await ref
        .read(mindmapMutationControllerProvider)
        .rescheduleNode(node, day: targetDay.dateOnly);
    if (!context.mounted) return;
    _showRescheduleSnackBar(
      context: context,
      ref: ref,
      node: node,
      previousDay: node.day,
      targetDay: targetDay,
    );
  }

  Map<AgendaFilter, int> _buildFilterCounts(
    List<MindmapNode>? allNodes, {
    required DateTime start,
    required String query,
    required Set<NodeType> typeFilters,
    required bool doneOnly,
    required CalendarNodeFilter advancedFilter,
    required DateTime today,
  }) {
    if (allNodes == null || allNodes.isEmpty) return {};
    final normalizedStart = start.dateOnly;
    final end = normalizedStart.add(const Duration(days: 30));
    final inRange = allNodes.where(
      (node) =>
          (!node.isArchived || _isRoutineMarker(node)) &&
          !node.day.isBefore(normalizedStart) &&
          node.day.isBefore(end) &&
          _applyCalendarFilters(
            [node],
            query: query,
            typeFilters: typeFilters,
            doneOnly: doneOnly,
            advancedFilter: advancedFilter,
            today: today,
          ).isNotEmpty,
    );
    return {
      for (final filter in AgendaFilter.values)
        filter: inRange.where((node) => _matchesFilter(node, filter)).length,
    };
  }
}

Map<String, Object?> _routineAutomationData(MindmapNode node) {
  final automation = node.data['automation'];
  if (automation is! Map) return const {};
  final result = <String, Object?>{};
  for (final entry in automation.entries) {
    final key = entry.key;
    if (key is String) result[key] = entry.value;
  }
  return result;
}

DateTime? _routineMarkerSnoozedToDate(MindmapNode node) {
  final value = _routineAutomationData(node)['snoozedTo'];
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim())?.dateOnly;
}

String? _routineSnoozedTargetLabel(MindmapNode node) {
  final target = _routineMarkerSnoozedToDate(node);
  if (target == null) return null;
  return 'Snoozed to ${DateFormat('MMM d, y').format(target)}';
}

DateTime _clampDate(DateTime date, DateTime firstDate, DateTime lastDate) {
  final normalized = date.dateOnly;
  if (normalized.isBefore(firstDate)) return firstDate;
  if (normalized.isAfter(lastDate)) return lastDate;
  return normalized;
}

void _invalidateRoutinePlanDays(WidgetRef ref, Iterable<DateTime?> days) {
  final seen = <String>{};
  for (final day in days) {
    if (day == null) continue;
    final normalized = day.dateOnly;
    if (seen.add(dayKey(normalized))) {
      ref.invalidate(calendarRoutinePlanProvider(normalized));
    }
  }
}

void _invalidateRoutineMarkerPlanDays(
  WidgetRef ref,
  MindmapNode marker, {
  DateTime? extraDay,
  DateTime? previousSnoozedTo,
}) {
  _invalidateRoutinePlanDays(ref, [
    marker.day,
    _routineMarkerSnoozedToDate(marker),
    previousSnoozedTo,
    extraDay,
  ]);
}

class _AgendaFilterBar extends ConsumerWidget {
  const _AgendaFilterBar({this.counts});

  final Map<AgendaFilter, int>? counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(agendaFilterProvider);
    final theme = Theme.of(context);
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: AgendaFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final filter = AgendaFilter.values[index];
                final count = counts?[filter] ?? 0;
                final isSelected = selected == filter;
                final countLabel = count == 1 ? '1 item' : '$count items';
                return Semantics(
                  key: ValueKey('agenda-filter-${filter.name}'),
                  button: true,
                  selected: isSelected,
                  label: 'Agenda filter: ${filter.label}, $countLabel',
                  onTap: () {
                    ref.read(agendaFilterProvider.notifier).setFilter(filter);
                  },
                  child: ExcludeSemantics(
                    child: Material(
                      color: isSelected
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          ref
                              .read(agendaFilterProvider.notifier)
                              .setFilter(filter);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                filter.label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (count > 0) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? theme.colorScheme.primary.withValues(
                                            alpha: 0.2,
                                          )
                                        : theme
                                              .colorScheme
                                              .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _compactCount(count),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10,
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _compactCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }
}

class _AgendaLoadingState extends StatelessWidget {
  const _AgendaLoadingState();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      key: ValueKey('calendar-agenda-loading'),
      padding: EdgeInsets.only(top: 8),
      child: SkeletonAgendaList(),
    );
  }
}

class _AgendaErrorState extends StatelessWidget {
  const _AgendaErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return AnimatedErrorState(error: error);
  }
}

class _RoutineMarkerBadge extends StatelessWidget {
  const _RoutineMarkerBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: ValueKey('calendar-routine-marker-$label'),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _RoutineMarkerActionsMenu extends ConsumerStatefulWidget {
  const _RoutineMarkerActionsMenu({required this.node, required this.today});

  final MindmapNode node;
  final DateTime today;

  @override
  ConsumerState<_RoutineMarkerActionsMenu> createState() =>
      _RoutineMarkerActionsMenuState();
}

class _RoutineMarkerActionsMenuState
    extends ConsumerState<_RoutineMarkerActionsMenu> {
  @override
  Widget build(BuildContext context) {
    final automation = _routineAutomationData(widget.node);
    final isSnoozed = automation['state'] == 'snoozed';

    return PopupMenuButton<_MarkerAction>(
      key: ValueKey('calendar-routine-marker-actions-${widget.node.id}'),
      tooltip: 'Marker actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: _handleAction,
      itemBuilder: (context) => [
        const PopupMenuItem<_MarkerAction>(
          value: _MarkerAction.delete,
          child: Text('Delete marker'),
        ),
        if (isSnoozed)
          const PopupMenuItem<_MarkerAction>(
            value: _MarkerAction.resnooze,
            child: Text('Resnooze'),
          ),
        const PopupMenuItem<_MarkerAction>(
          value: _MarkerAction.applyNow,
          child: Text('Apply now'),
        ),
      ],
    );
  }

  Future<void> _handleAction(_MarkerAction action) async {
    switch (action) {
      case _MarkerAction.delete:
        await _deleteMarker();
      case _MarkerAction.resnooze:
        await _resnoozeMarker();
      case _MarkerAction.applyNow:
        await _applyFromMarker();
    }
  }

  Future<void> _deleteMarker() async {
    final repository = ref.read(mindmapRepositoryProvider);
    final savedJson = widget.node.toJson();
    await repository.deleteNode(widget.node.id);
    invalidateMindmapState(ref, day: widget.node.day);
    _invalidateRoutineMarkerPlanDays(ref, widget.node);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Routine marker deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(_undoDeleteMarker(savedJson));
          },
        ),
      ),
    );
  }

  Future<void> _undoDeleteMarker(Map<String, Object?> savedJson) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final marker = MindmapNode.fromJson(savedJson);
    await repository.saveNode(marker);
    invalidateMindmapState(ref, day: marker.day);
    _invalidateRoutineMarkerPlanDays(ref, marker);
  }

  Future<void> _resnoozeMarker() async {
    final originalJson = widget.node.toJson();
    final oldSnoozedTo = _routineMarkerSnoozedToDate(widget.node);
    final firstDate = widget.today.dateOnly;
    final lastDate = firstDate.add(const Duration(days: 365));
    final initialDate = _clampDate(
      oldSnoozedTo ?? firstDate.add(const Duration(days: 1)),
      firstDate,
      lastDate,
    );

    final newDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (newDate == null || !mounted) return;

    final newDay = newDate.dateOnly;
    final newDayKey = dayKey(newDay);
    final updatedData = <String, Object?>{
      ...widget.node.data,
      'automation': <String, Object?>{
        ..._routineAutomationData(widget.node),
        'snoozedTo': newDayKey,
      },
    };

    final repository = ref.read(mindmapRepositoryProvider);
    final updatedMarker = widget.node.copyWith(
      data: updatedData,
      updatedAt: DateTime.now(),
    );
    await repository.saveNode(updatedMarker);
    invalidateMindmapState(ref, day: widget.node.day);
    _invalidateRoutineMarkerPlanDays(
      ref,
      updatedMarker,
      previousSnoozedTo: oldSnoozedTo,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Resnoozed to ${DateFormat('MMM d, y').format(newDate.dateOnly)}',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(_undoResnooze(originalJson, newDay));
          },
        ),
      ),
    );
  }

  Future<void> _undoResnooze(
    Map<String, Object?> originalJson,
    DateTime currentSnoozedTo,
  ) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final marker = MindmapNode.fromJson(originalJson);
    await repository.saveNode(marker);
    invalidateMindmapState(ref, day: marker.day);
    _invalidateRoutineMarkerPlanDays(
      ref,
      marker,
      previousSnoozedTo: currentSnoozedTo,
    );
  }

  Future<void> _applyFromMarker() async {
    final savedJson = widget.node.toJson();
    final repository = ref.read(mindmapRepositoryProvider);
    final automation = _routineAutomationData(widget.node);
    final routineId = automation['routineId'];
    if (routineId is! String) return;

    // Find the routine definition
    final allRoutines = await loadRecurringRoutines(repository: repository);
    RecurringNodeRoutine? routine;
    for (final r in allRoutines) {
      if (r.id == routineId) {
        routine = r;
        break;
      }
    }
    if (routine == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Routine "$routineId" not found')),
        );
      }
      return;
    }

    // Delete marker then apply routine for today
    await repository.deleteNode(widget.node.id);
    final nodes = await applyRecurringRoutines(
      repository: repository,
      day: widget.today,
      routines: [routine],
      forceDue: true,
    );

    invalidateMindmapState(ref, day: widget.node.day, extraDay: widget.today);
    _invalidateRoutineMarkerPlanDays(ref, widget.node, extraDay: widget.today);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied "${routine.label}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(_undoApplyNow(savedJson, nodes));
          },
        ),
      ),
    );
  }

  Future<void> _undoApplyNow(
    Map<String, Object?> savedMarkerJson,
    List<MindmapNode> createdNodes,
  ) async {
    final repository = ref.read(mindmapRepositoryProvider);

    // Delete created routine nodes
    for (final node in createdNodes) {
      await repository.deleteNode(node.id);
    }

    // Restore marker
    final marker = MindmapNode.fromJson(savedMarkerJson);
    await repository.saveNode(marker);

    invalidateMindmapState(ref, day: marker.day, extraDay: widget.today);
    _invalidateRoutineMarkerPlanDays(ref, marker, extraDay: widget.today);
  }
}

enum _MarkerAction { delete, resnooze, applyNow }

class _AgendaEmptyState extends StatelessWidget {
  const _AgendaEmptyState({
    required this.filter,
    required this.day,
    required this.searchQuery,
    required this.hasCalendarFilters,
    required this.onAddNode,
    required this.onClearSearch,
    required this.onResetFilters,
  });

  final AgendaFilter filter;
  final DateTime day;
  final String searchQuery;
  final bool hasCalendarFilters;
  final Future<void> Function() onAddNode;
  final VoidCallback onClearSearch;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSearch = searchQuery.isNotEmpty;
    final label = hasSearch
        ? 'No matching agenda items'
        : switch (filter) {
            AgendaFilter.all => 'No agenda items',
            AgendaFilter.tasks => 'No task items',
            AgendaFilter.events => 'No event items',
            AgendaFilter.habits => 'No habit items',
            AgendaFilter.routines => 'No routine items',
            AgendaFilter.done => 'No completed items',
          };
    final (icon, subtitle) = hasSearch
        ? (Icons.search_off, 'Try another search or clear filters.')
        : switch (filter) {
            AgendaFilter.all => (
              Icons.event_note_outlined,
              'Create your first node to start building your day.',
            ),
            AgendaFilter.tasks => (
              Icons.check_circle_outline,
              'No tasks yet. Add one from any day.',
            ),
            AgendaFilter.events => (
              Icons.event_outlined,
              'No events scheduled.',
            ),
            AgendaFilter.habits => (
              Icons.repeat_outlined,
              'No habits tracked yet.',
            ),
            AgendaFilter.routines => (
              Icons.auto_awesome_outlined,
              'No routines configured.',
            ),
            AgendaFilter.done => (Icons.task_alt, 'Nothing completed yet.'),
          };
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 300;
        return Align(
          key: const ValueKey('calendar-agenda-empty'),
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!tight) ...[
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      icon,
                      size: 26,
                      color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!tight) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                SizedBox(height: tight ? 8 : 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (hasSearch)
                      FilledButton.icon(
                        key: const ValueKey(
                          'calendar-agenda-empty-clear-search',
                        ),
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.search_off),
                        label: const Text('Clear search'),
                      ),
                    if (filter != AgendaFilter.all || hasCalendarFilters)
                      FilledButton.tonalIcon(
                        key: const ValueKey('calendar-agenda-empty-show-all'),
                        onPressed: onResetFilters,
                        icon: const Icon(Icons.filter_alt_off),
                        label: const Text('Reset filters'),
                      ),
                    FilledButton.tonalIcon(
                      key: const ValueKey('calendar-agenda-empty-add-node'),
                      onPressed: () {
                        unawaited(onAddNode());
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add node'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('calendar-agenda-empty-open-day'),
                      onPressed: () => goToDay(context, day),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open day'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.focusedDay,
    required this.viewMode,
    required this.onPrevious,
    required this.onNext,
    this.onJumpToDate,
  });

  final DateTime month;
  final DateTime focusedDay;
  final CalendarViewMode viewMode;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onJumpToDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _titleForMode();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous ${viewMode.label.toLowerCase()}',
              icon: const Icon(Icons.chevron_left),
              onPressed: onPrevious,
            ),
            Expanded(
              child: Tooltip(
                message: 'Pick visible date',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onJumpToDate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          viewMode.label.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            letterSpacing: 1.8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.expand_more,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next ${viewMode.label.toLowerCase()}',
              icon: const Icon(Icons.chevron_right),
              onPressed: onNext,
            ),
            IconButton(
              tooltip: 'Jump to date',
              icon: const Icon(Icons.calendar_today_outlined, size: 20),
              onPressed: onJumpToDate,
            ),
          ],
        ),
      ),
    );
  }

  String _titleForMode() {
    return switch (viewMode) {
      CalendarViewMode.month => DateFormat.yMMMM().format(month),
      CalendarViewMode.week => _weekTitle(focusedDay),
      CalendarViewMode.agenda =>
        'Next 30 days from ${DateFormat.MMMd().format(focusedDay)}',
    };
  }

  String _weekTitle(DateTime day) {
    final start = day.subtract(Duration(days: day.weekday - 1));
    final end = start.add(const Duration(days: 6));
    if (start.year == end.year && start.month == end.month) {
      return '${DateFormat.MMM().format(start)} ${start.day}–${end.day}, ${start.year}';
    }
    if (start.year == end.year) {
      return '${DateFormat.MMMd().format(start)}–${DateFormat.MMMd().format(end)}, ${start.year}';
    }
    return '${DateFormat.yMMMd().format(start)}–${DateFormat.yMMMd().format(end)}';
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final label in kWeekdayLabelsShort)
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.today,
    required this.focusedDay,
    required this.onDayPreview,
  });

  final DateTime visibleMonth;
  final DateTime today;
  final DateTime focusedDay;
  final ValueChanged<DateTime> onDayPreview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _calendarDropRects.clear();
    final days = visibleDaysForMonth(visibleMonth);
    return LayoutBuilder(
      builder: (context, constraints) {
        const crossAxisCount = 7;
        const rowCount = 6;
        const spacing = 5.0;
        final cellWidth =
            (constraints.maxWidth - (crossAxisCount - 1) * spacing) /
            crossAxisCount;
        final cellHeight =
            (constraints.maxHeight - (rowCount - 1) * spacing) / rowCount;
        final aspectRatio = cellHeight <= 0 ? 1.2 : cellWidth / cellHeight;

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            for (final entry in _calendarDragSourceRects.entries) {
              if (entry.value.contains(event.position)) {
                _activeCalendarDragNode = entry.key;
                break;
              }
            }
          },

          onPointerUp: (event) async {
            final node = _activeCalendarDragNode;
            _activeCalendarDragNode = null;
            if (node == null) return;
            MapEntry<String, Rect>? bestEntry;
            var bestDistance = double.infinity;
            for (final entry in _calendarDropRects.entries) {
              if (!entry.value.contains(event.position)) continue;
              final distance = (entry.value.center - event.position).distance;
              if (distance < bestDistance) {
                bestEntry = entry;
                bestDistance = distance;
              }
            }
            final targetDay = bestEntry == null
                ? null
                : DateTime.tryParse(bestEntry.key);
            if (targetDay == null || node.day.dateOnly.isSameDay(targetDay)) {
              return;
            }
            await ref
                .read(mindmapMutationControllerProvider)
                .rescheduleNode(node, day: targetDay);
            if (!context.mounted) return;
            _showRescheduleSnackBar(
              context: context,
              ref: ref,
              node: node,
              previousDay: node.day,
              targetDay: targetDay,
            );
          },
          child: GridView.builder(
            key: const ValueKey('calendar-month-grid'),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: aspectRatio,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];
              final rowIndex = index ~/ crossAxisCount;
              final colIndex = index % crossAxisCount;
              return _DayCell(
                day: day,
                isInVisibleMonth:
                    day.year == visibleMonth.year &&
                    day.month == visibleMonth.month,
                isToday: day.isSameDay(today),
                focusedDay: focusedDay,
                rowIndex: rowIndex,
                colIndex: colIndex,
                totalRows: rowCount,
                onPreview: onDayPreview,
              );
            },
          ),
        );
      },
    );
  }
}

class _DayCell extends ConsumerStatefulWidget {
  const _DayCell({
    required this.day,
    required this.isInVisibleMonth,
    required this.isToday,
    required this.focusedDay,
    required this.rowIndex,
    required this.colIndex,
    required this.totalRows,
    required this.onPreview,
  });

  final DateTime day;
  final bool isInVisibleMonth;
  final bool isToday;
  final DateTime focusedDay;
  final int rowIndex;
  final int colIndex;
  final int totalRows;
  final ValueChanged<DateTime> onPreview;

  @override
  ConsumerState<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends ConsumerState<_DayCell> {
  bool _isHovered = false;
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  void _showOverlay(BuildContext context, bool isUpperHalf) {
    _hideOverlay();

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final overlay = Overlay.of(context);
    final overlayRenderBox = overlay.context.findRenderObject() as RenderBox?;
    final overlaySize = overlayRenderBox?.size ?? MediaQuery.sizeOf(context);

    final isLeftColumn = widget.colIndex <= 1;
    final isRightColumn = widget.colIndex >= 5;

    double? left;
    double? right;
    double? top;
    double? bottom;

    if (isUpperHalf) {
      top = position.dy + size.height + 8.0;
    } else {
      bottom = overlaySize.height - position.dy + 8.0;
    }

    if (isLeftColumn) {
      left = position.dx;
    } else if (isRightColumn) {
      right = overlaySize.width - (position.dx + size.width);
    } else {
      left = (position.dx + size.width / 2) - 110;
    }

    final theme = Theme.of(context);
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned(
          left: left,
          right: right,
          top: top,
          bottom: bottom,
          child: UnconstrainedBox(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                final slideDistance =
                    (1.0 - value) * (isUpperHalf ? -8.0 : 8.0);
                return Transform.translate(
                  offset: Offset(0, slideDistance),
                  child: Transform.scale(
                    scale: 0.9 + (0.1 * value),
                    alignment: isUpperHalf
                        ? Alignment.topCenter
                        : Alignment.bottomCenter,
                    child: Opacity(
                      opacity: value.clamp(0.0, 1.0),
                      child: child,
                    ),
                  ),
                );
              },
              child: IgnorePointer(
                child: Container(
                  width: 220,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.15,
                        ),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Consumer(
                    builder: (context, ref, child) {
                      final searchQuery = ref
                          .watch(calendarSearchQueryProvider)
                          .trim()
                          .toLowerCase();
                      final nodesAsync = ref.watch(
                        nodesForDayProvider(widget.day),
                      );
                      var nodes = nodesAsync.value ?? [];
                      if (searchQuery.isNotEmpty) {
                        nodes = nodes
                            .where((n) => _nodeMatches(n, searchQuery))
                            .toList();
                      }

                      final titleMap = ref.watch(workspaceTitleProvider);
                      final titleKey =
                          '${WorkspaceContextType.daily.name}_${dayKey(widget.day)}';
                      final customTitle = titleMap[titleKey];
                      final hasCustomTitle =
                          customTitle != null && customTitle.isNotEmpty;

                      if (nodes.isEmpty && !hasCustomTitle) {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasCustomTitle) ...[
                            Text(
                              customTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat(
                                'EEEE, MMMM d, yyyy',
                              ).format(widget.day),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ] else
                            Text(
                              DateFormat(
                                'EEEE, MMMM d, yyyy',
                              ).format(widget.day),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          if (nodes.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ...nodes.take(8).map((n) {
                              final title = n.title.trim().isEmpty
                                  ? 'Untitled ${n.type.name}'
                                  : n.title.trim();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _nodeIcon(n.type),
                                      size: 14,
                                      color: _nodeColor(n.type),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (nodes.length > 8)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '+ ${nodes.length - 8} more',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onHoverChange(bool isHovered, bool isUpperHalf, bool hasContent) {
    if (_isHovered == isHovered) return;
    setState(() => _isHovered = isHovered);
    if (isHovered && hasContent) {
      _showOverlay(context, isUpperHalf);
    } else {
      _hideOverlay();
    }
  }

  String _dayCellSemanticsLabel({
    required DateTime day,
    required bool isToday,
    required bool isFocused,
    required bool isInVisibleMonth,
    required String? customTitle,
    required int nodeCount,
  }) {
    final parts = <String>[DateFormat('EEEE, MMMM d, yyyy').format(day)];
    if (!isInVisibleMonth) parts.add('outside visible month');
    if (isToday) parts.add('today');
    if (isFocused) parts.add('selected');
    if (customTitle != null && customTitle.isNotEmpty) {
      parts.add(customTitle);
    }
    if (nodeCount > 0) parts.add(_countLabel(nodeCount));
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFocused = widget.day.isSameDay(widget.focusedDay);
    final restingBorderColor = widget.isInVisibleMonth
        ? theme.colorScheme.outline.withValues(alpha: 0.86)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.26);
    final borderColor = widget.isToday
        ? theme.colorScheme.primary
        : (isFocused
              ? theme.colorScheme.primary.withValues(alpha: 0.6)
              : restingBorderColor);

    final searchQuery = ref
        .watch(calendarSearchQueryProvider)
        .trim()
        .toLowerCase();
    final typeFilters = ref.watch(calendarTypeFiltersProvider);
    final doneOnly = ref.watch(calendarDoneFilterProvider);
    final advancedFilter = ref.watch(calendarAdvancedFilterProvider);
    final densityMode = ref.watch(calendarDensityModeProvider);
    final selectedNodeId = ref.watch(selectedAgendaNodeIdProvider);
    final heatmapMode = ref.watch(calendarHeatmapModeProvider);
    final nodesAsync = ref.watch(nodesForDayProvider(widget.day));

    final titleMap = ref.watch(workspaceTitleProvider);
    final titleKey = '${WorkspaceContextType.daily.name}_${dayKey(widget.day)}';
    final customTitle = titleMap[titleKey];
    final hasCustomTitle = customTitle != null && customTitle.isNotEmpty;

    // Filter nodes based on query
    final allNodes = nodesAsync.valueOrNull ?? [];
    final filteredNodes = _applyCalendarFilters(
      allNodes,
      query: searchQuery,
      typeFilters: typeFilters,
      doneOnly: doneOnly,
      advancedFilter: advancedFilter,
      today: DateTime.now(),
    );
    final hasNodes = filteredNodes.isNotEmpty;

    final matchesCustomTitle =
        hasCustomTitle && customTitle.toLowerCase().contains(searchQuery);
    final matchesQuery = searchQuery.isEmpty || matchesCustomTitle || hasNodes;
    final calendarSummary = buildCalendarDaySummary(widget.day, allNodes);
    final heatmapScore = scoreCalendarDay(calendarSummary, heatmapMode);
    final densityAlpha = (allNodes.length / 10).clamp(0.0, 1.0) * 0.12;
    final heatmapAlpha = heatmapScore.value * 0.16;
    final baseCellColor = widget.isInVisibleMonth
        ? Color.alphaBlend(
            theme.colorScheme.primary.withValues(
              alpha: math.max(densityAlpha, heatmapAlpha) * 0.7,
            ),
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
          )
        : Color.alphaBlend(
            theme.colorScheme.surface.withValues(alpha: 0.42),
            theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.38),
          );
    final hoveredCellColor = widget.isInVisibleMonth
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.82)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.32);
    final todayCellColor = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: _isHovered ? 0.20 : 0.13),
      theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.40),
    );
    const todayBadgeForeground = Color(0xFF071006);

    final container = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      transformAlignment: Alignment.center,
      transform: Matrix4.identity(),
      decoration: ShapeDecoration(
        color: widget.isToday
            ? todayCellColor
            : (_isHovered ? hoveredCellColor : baseCellColor),
        shape: DoodleShapeBorder(
          radius: 12,
          wobble: widget.isToday || isFocused ? 1.8 : 1.2,
          side: BorderSide(
            color: _isHovered
                ? theme.colorScheme.primary.withValues(
                    alpha: widget.isInVisibleMonth ? 0.82 : 0.38,
                  )
                : (isFocused ? theme.colorScheme.primary : borderColor),
            width: widget.isToday || _isHovered || isFocused ? 2.4 : 1.4,
          ),
        ),
        shadows: widget.isToday
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final summaryHeight = math.max(20.0, constraints.maxHeight - 34.0);
            final isTinyCell = constraints.maxWidth < 62;
            final visibleNodes = _applyCalendarFilters(
              allNodes,
              query: searchQuery,
              typeFilters: typeFilters,
              doneOnly: doneOnly,
              advancedFilter: advancedFilter,
              today: DateTime.now(),
            );

            return ClipRect(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${widget.day.day}',
                            key: ValueKey(
                              'calendar-day-number-${dayKey(widget.day)}',
                            ),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: widget.isToday
                                  ? theme.colorScheme.primary
                                  : widget.isInVisibleMonth
                                  ? (_isHovered
                                        ? theme.colorScheme.primary
                                        : null)
                                  : theme.textTheme.bodySmall?.color,
                              fontWeight: widget.isToday || isFocused
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (!isTinyCell && _isHovered)
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () async {
                              final draft = await showAddNodeDialog(context);
                              if (draft == null || !context.mounted) return;
                              final node = MindmapNode.create(
                                id: const Uuid().v4(),
                                type: draft.type,
                                title: draft.title,
                                body: draft.body,
                                day: widget.day.dateOnly,
                                status: draft.status,
                                priority: draft.priority,
                                project: draft.project,
                                area: draft.area,
                                tags: draft.tags,
                                dueDate: draft.dueDate,
                                progress: draft.progress,
                                isPinned: draft.isPinned,
                                isArchived: draft.isArchived,
                                checklist: draft.checklist,
                                relatedNodeIds: draft.relatedNodeIds,
                                data: draft.data,
                                now: DateTime.now(),
                              );
                              await ref
                                  .read(mindmapMutationControllerProvider)
                                  .saveNode(node);
                            },
                            child: Icon(
                              Icons.add_circle_outline_rounded,
                              size: 15,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        else if (!isTinyCell && widget.isToday)
                          Container(
                            key: ValueKey(
                              'calendar-today-badge-${dayKey(widget.day)}',
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: ShapeDecoration(
                              color: theme.colorScheme.primary,
                              shape: DoodleShapeBorder(
                                radius: 999,
                                wobble: 0.9,
                                side: BorderSide(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            child: Text(
                              'Today',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: todayBadgeForeground,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          )
                        else if (!isTinyCell && hasCustomTitle)
                          Icon(
                            Icons.turned_in,
                            size: 12,
                            color: theme.colorScheme.secondary,
                          ),
                      ],
                    ),
                    if (isFocused) ...[
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          key: ValueKey(
                            'calendar-focused-${dayKey(widget.day)}',
                          ),
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (hasCustomTitle) ...[
                      const SizedBox(height: 2),
                      Text(
                        customTitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    _CellSummary(
                      maxHeight: summaryHeight,
                      summary: DayNodeSummary.fromNodes(
                        widget.day,
                        visibleNodes,
                      ),
                      nodes: visibleNodes,
                      densityMode: densityMode,
                      selectedNodeId: selectedNodeId,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    // Use actual grid row to decide popup direction
    final isUpperHalf = widget.rowIndex < (widget.totalRows / 2).ceil();

    final hasContent = hasNodes || hasCustomTitle;
    final semanticsLabel = _dayCellSemanticsLabel(
      day: widget.day,
      isToday: widget.isToday,
      isFocused: isFocused,
      isInVisibleMonth: widget.isInVisibleMonth,
      customTitle: customTitle,
      nodeCount: filteredNodes.length,
    );
    final heatmapSemantics = '${heatmapMode.name}: ${heatmapScore.label}';

    Widget cellWidget = container;
    if (searchQuery.isNotEmpty && !matchesQuery) {
      cellWidget = Opacity(
        opacity: 0.25,
        child: IgnorePointer(child: container),
      );
    }

    final draggableCell = DragTarget<MindmapNode>(
      hitTestBehavior: HitTestBehavior.opaque,
      onWillAcceptWithDetails: (details) =>
          !details.data.day.dateOnly.isSameDay(widget.day),
      onAcceptWithDetails: (details) async {
        _hideOverlay();
        _activeCalendarDragNode = null;
        final node = details.data;
        await ref
            .read(mindmapMutationControllerProvider)
            .rescheduleNode(node, day: widget.day.dateOnly);
        if (!context.mounted) return;
        _showRescheduleSnackBar(
          context: context,
          ref: ref,
          node: node,
          previousDay: node.day,
          targetDay: widget.day,
        );
      },
      builder: (context, candidateData, rejectedData) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final renderObject = context.findRenderObject();
          final renderBox = renderObject is RenderBox ? renderObject : null;
          if (renderBox == null || !renderBox.attached) return;
          final offset = renderBox.localToGlobal(Offset.zero);
          _calendarDropRects[dayKey(widget.day)] = offset & renderBox.size;
        });
        final hasCandidate = candidateData.isNotEmpty;
        final hasRejected = rejectedData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: hasCandidate || hasRejected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasCandidate
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    width: 2,
                  ),
                  color: hasCandidate
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.35,
                        ),
                )
              : null,
          child: SizedBox.expand(
            key: ValueKey('calendar-drop-${dayKey(widget.day)}'),
            child: MouseRegion(
              onEnter: (_) => _onHoverChange(true, isUpperHalf, hasContent),
              onExit: (_) => _onHoverChange(false, isUpperHalf, hasContent),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey('calendar-cell-${dayKey(widget.day)}'),
                onTap: () {
                  _hideOverlay();
                  widget.onPreview(widget.day);
                },
                child: cellWidget,
              ),
            ),
          ),
        );
      },
    );

    return Semantics(
      label: '$semanticsLabel, $heatmapSemantics',
      button: true,
      selected: isFocused,
      onTap: () {
        _hideOverlay();
        widget.onPreview(widget.day);
      },
      child: draggableCell,
    );
  }
}

class _CellSummary extends StatelessWidget {
  const _CellSummary({
    required this.maxHeight,
    required this.summary,
    required this.nodes,
    required this.densityMode,
    required this.selectedNodeId,
  });

  final double maxHeight;
  final DayNodeSummary summary;
  final List<MindmapNode> nodes;
  final CalendarDensityMode densityMode;
  final String? selectedNodeId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!summary.hasNodes) return const SizedBox.shrink();

    final taskCount = summary.countFor(NodeType.task);
    final doneRatio = taskCount > 0 ? summary.doneCount / taskCount : 0.0;
    final isCompact = maxHeight < 50;
    final visibleCount = switch (densityMode) {
      CalendarDensityMode.compact => isCompact ? 3 : 8,
      CalendarDensityMode.comfortable => isCompact ? 2 : 4,
      CalendarDensityMode.detailed => isCompact ? 1 : 3,
    };
    final hiddenCount = math.max(0, nodes.length - visibleCount);
    final showNodes = nodes.take(visibleCount).toList();

    return ClipRect(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isCompact && taskCount > 0) ...[
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: doneRatio.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  doneRatio >= 1.0
                      ? theme.colorScheme.primary
                      : _nodeColor(NodeType.task),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          if (showNodes.isEmpty)
            Text(
              _countLabel(summary.totalCount),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Wrap(
              spacing: 3,
              runSpacing: 2,
              children: [
                for (final node in showNodes)
                  _DraggableCalendarNode(
                    node: node,
                    showTitle: densityMode == CalendarDensityMode.detailed,
                    isSelected: node.id == selectedNodeId,
                  ),
                if (hiddenCount > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+$hiddenCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
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

MindmapNode? _activeCalendarDragNode;

final Map<String, Rect> _calendarDropRects = <String, Rect>{};
final Map<MindmapNode, Rect> _calendarDragSourceRects = <MindmapNode, Rect>{};

class _DraggableCalendarNode extends ConsumerWidget {
  const _DraggableCalendarNode({
    required this.node,
    this.showTitle = false,
    this.isSelected = false,
  });

  final MindmapNode node;
  final bool showTitle;
  final bool isSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final renderObject = context.findRenderObject();
      final renderBox = renderObject is RenderBox ? renderObject : null;
      if (renderBox == null || !renderBox.attached) return;
      _calendarDragSourceRects[node] =
          renderBox.localToGlobal(Offset.zero) & renderBox.size;
    });
    final accent = _nodeColor(node.type);
    final muted = node.isDone;
    final title = node.title.trim().isEmpty
        ? 'Untitled ${node.type.name}'
        : node.title.trim();
    Widget buildChip({Key? key}) => Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isSelected
            ? accent.withValues(alpha: 0.26)
            : muted
            ? accent.withValues(alpha: 0.06)
            : accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accent.withValues(
            alpha: isSelected
                ? 0.78
                : muted
                ? 0.08
                : 0.28,
          ),
        ),
      ),
      child: showTitle
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _nodeIcon(node.type),
                  size: 11,
                  color: muted ? accent.withValues(alpha: 0.45) : accent,
                ),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 72),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            )
          : Icon(
              _nodeIcon(node.type),
              size: 11,
              color: muted ? accent.withValues(alpha: 0.45) : accent,
            ),
    );

    return MouseRegion(
      key: ValueKey('calendar-draggable-node-${node.id}'),
      cursor: SystemMouseCursors.grab,
      child: LongPressDraggable<MindmapNode>(
        data: node,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: buildChip(),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: buildChip()),
        child: buildChip(),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _countLabel(int count) => count == 1 ? '1 node' : '$count nodes';

Color _nodeColor(NodeType type) => switch (type) {
  NodeType.task => NodeColors.task,
  NodeType.kanban => NodeColors.kanban,
  NodeType.plan => NodeColors.plan,
  NodeType.note => NodeColors.note,
  NodeType.journal => NodeColors.journal,
  NodeType.habit => NodeColors.habit,
  NodeType.goal => NodeColors.goal,
  NodeType.link => NodeColors.link,
  NodeType.event => NodeColors.event,
  NodeType.decision => NodeColors.decision,
  NodeType.resource => NodeColors.resource,
  NodeType.idea => NodeColors.idea,
  NodeType.question => NodeColors.question,
  NodeType.contact => NodeColors.contact,
  NodeType.metric => NodeColors.metric,
  NodeType.expense => NodeColors.expense,
  NodeType.bookmark => NodeColors.bookmark,
  NodeType.routine => NodeColors.routine,
  NodeType.empty => Colors.grey,
};

IconData _nodeIcon(NodeType type) => switch (type) {
  NodeType.task => Icons.check_box_outlined,
  NodeType.kanban => Icons.view_column_outlined,
  NodeType.plan => Icons.account_tree_outlined,
  NodeType.note => Icons.description_outlined,
  NodeType.journal => Icons.menu_book_outlined,
  NodeType.habit => Icons.loop_outlined,
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
  NodeType.empty => Icons.circle_outlined,
};

class _QuickCaptureExampleChip extends StatelessWidget {
  const _QuickCaptureExampleChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      avatar: const Icon(Icons.bolt_outlined, size: 16),
    );
  }
}

/// Desktop quick-add toolbar showing common node types.
class _QuickAddToolbar extends StatelessWidget {
  const _QuickAddToolbar({
    required this.selectedDay,
    required this.onAddNode,
    required this.onQuickCapture,
  });

  final DateTime selectedDay;
  final Future<void> Function(DateTime day, NodeType type) onAddNode;
  final Future<void> Function(DateTime day) onQuickCapture;

  @override
  Widget build(BuildContext context) {
    final nodeTypes = [
      NodeType.task,
      NodeType.note,
      NodeType.habit,
      NodeType.journal,
      NodeType.goal,
      NodeType.event,
      NodeType.idea,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Quick add (Ctrl+N)',
            child: IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 18),
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                fixedSize: const Size(32, 32),
              ),
              onPressed: () => onQuickCapture(selectedDay),
            ),
          ),
          const SizedBox(width: 4),
          ...nodeTypes.map(
            (type) => _QuickAddTypeButton(
              type: type,
              onTap: () => onAddNode(selectedDay, type),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAddTypeButton extends StatefulWidget {
  const _QuickAddTypeButton({required this.type, required this.onTap});

  final NodeType type;
  final VoidCallback onTap;

  @override
  State<_QuickAddTypeButton> createState() => _QuickAddTypeButtonState();
}

class _QuickAddTypeButtonState extends State<_QuickAddTypeButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Add ${widget.type.label}',
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() => _isPressed = true);
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) setState(() => _isPressed = false);
              });
              widget.onTap();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _nodeColor(
                  widget.type,
                ).withValues(alpha: _isPressed ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _nodeColor(
                    widget.type,
                  ).withValues(alpha: _isPressed ? 0.6 : 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _nodeIcon(widget.type),
                    size: 14,
                    color: _nodeColor(widget.type),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.type.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _nodeColor(widget.type),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );

    if (!isTest) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(
                  alpha: 0.6 * _controller.value,
                ),
                blurRadius: 4 + 8 * _controller.value,
                spreadRadius: 2 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CalendarMissionLegend extends StatelessWidget {
  const _CalendarMissionLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <(CalendarDayStatus, String)>[
      (CalendarDayStatus.clear, 'Clear'),
      (CalendarDayStatus.busy, 'Busy'),
      (CalendarDayStatus.critical, 'Critical'),
      (CalendarDayStatus.complete, 'Complete'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Board status',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in items)
              _StatusLegendPill(status: item.$1, label: item.$2),
          ],
        ),
      ],
    );
  }
}

class _StatusLegendPill extends StatelessWidget {
  const _StatusLegendPill({required this.status, required this.label});

  final CalendarDayStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _calendarDayStatusColor(theme, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.1),
        shape: DoodleShapeBorder(
          side: BorderSide(color: color.withValues(alpha: 0.35)),
          radius: 999,
          wobble: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedDayMissionCard extends ConsumerWidget {
  const _SelectedDayMissionCard({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nodesAsync = ref.watch(allMindmapNodesProvider);
    return nodesAsync.when(
      data: (nodes) {
        final summary = buildCalendarDaySummary(day, nodes);
        final statusColor = _calendarDayStatusColor(theme, summary.status);
        return Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(12),
          decoration: ShapeDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.24,
            ),
            shape: DoodleShapeBorder(
              side: BorderSide(color: statusColor.withValues(alpha: 0.28)),
              radius: 14,
              wobble: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: ShapeDecoration(
                      shape: DoodleShapeBorder(
                        side: BorderSide(
                          color: statusColor.withValues(alpha: 0.38),
                        ),
                        radius: 10,
                        wobble: 1.3,
                      ),
                    ),
                    child: Icon(
                      Icons.radar_outlined,
                      color: statusColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEE, MMM d').format(summary.day),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _calendarDayStatusLabel(summary.status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  _MissionMiniMetric(label: 'Nodes', value: summary.totalNodes),
                  _MissionMiniMetric(label: 'Open', value: summary.openTasks),
                  _MissionMiniMetric(
                    label: 'Done',
                    value: summary.completedTasks,
                  ),
                  _MissionMiniMetric(
                    label: 'Late',
                    value: summary.overdueTasks,
                  ),
                  _MissionMiniMetric(
                    label: 'High',
                    value: summary.highPriorityCount,
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 44),
      error: (error, stackTrace) => const SizedBox.shrink(),
    );
  }
}

class _MissionMiniMetric extends StatelessWidget {
  const _MissionMiniMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 34,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

Color _calendarDayStatusColor(ThemeData theme, CalendarDayStatus status) {
  return switch (status) {
    CalendarDayStatus.clear => theme.colorScheme.primary,
    CalendarDayStatus.busy => Colors.amber,
    CalendarDayStatus.critical => theme.colorScheme.error,
    CalendarDayStatus.complete => theme.colorScheme.tertiary,
  };
}

String _calendarDayStatusLabel(CalendarDayStatus status) {
  return switch (status) {
    CalendarDayStatus.clear => 'Clear board',
    CalendarDayStatus.busy => 'Busy board',
    CalendarDayStatus.critical => 'Needs care',
    CalendarDayStatus.complete => 'Complete',
  };
}

class _WeeklySummaryStrip extends ConsumerWidget {
  const _WeeklySummaryStrip({required this.focusedDay, required this.today});

  final DateTime focusedDay;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final weekDays = calendarWeekDays(focusedDay);
    final allNodesAsync = ref.watch(allMindmapNodesProvider);
    final loadedNodes = allNodesAsync.valueOrNull;
    if (loadedNodes != null) {
      final startOfWeek = weekDays.first;
      final endOfWeek = weekDays.last;
      final weekNodeCount = loadedNodes
          .where(
            (node) =>
                node.day.isAfter(
                  startOfWeek.subtract(const Duration(days: 1)),
                ) &&
                node.day.isBefore(endOfWeek.add(const Duration(days: 1))),
          )
          .length;
      if (weekNodeCount == 0) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.22,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.insights_outlined,
                size: 15,
                color: theme.colorScheme.primary.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Selected week • 0 planned',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  'Tap day',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.72,
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.insights_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Weekly workload',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              allNodesAsync.when(
                data: (nodes) {
                  final startOfWeek = weekDays.first;
                  final endOfWeek = weekDays.last;
                  final thisWeekNodes = nodes.where(
                    (n) =>
                        n.day.isAfter(
                          startOfWeek.subtract(const Duration(days: 1)),
                        ) &&
                        n.day.isBefore(endOfWeek.add(const Duration(days: 1))),
                  );

                  final total = thisWeekNodes.length;
                  final completed = thisWeekNodes.where((n) => n.isDone).length;

                  return Flexible(
                    child: Text(
                      '$completed/$total done',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (err, stack) => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: weekDays.map((day) {
              final isToday = day.isSameDay(today);
              final isFocused = day.isSameDay(focusedDay);

              return Expanded(
                child: allNodesAsync.when(
                  data: (nodes) {
                    final dayNodes = nodes
                        .where((n) => n.day.isSameDay(day))
                        .toList();
                    final total = dayNodes.length;
                    final completed = dayNodes.where((n) => n.isDone).length;

                    Color? dotColor;
                    if (total > 0) {
                      if (completed == total) {
                        dotColor = theme.colorScheme.primary; // fully completed
                      } else if (completed > 0) {
                        dotColor = Colors.amber; // partially completed
                      } else {
                        dotColor =
                            theme.colorScheme.secondary; // planned/pending
                      }
                    }

                    final semanticsParts = <String>[
                      DateFormat('EEEE, MMMM d, yyyy').format(day),
                      _countLabel(total),
                      '$completed completed',
                    ];
                    if (isToday) semanticsParts.add('today');
                    if (isFocused) semanticsParts.add('selected');

                    return Semantics(
                      label: semanticsParts.join(', '),
                      button: true,
                      selected: isFocused,
                      onTap: () => goToDay(context, day),
                      child: InkWell(
                        onTap: () => goToDay(context, day),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                DateFormat('E').format(day).substring(0, 1),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: isToday
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.6),
                                  fontWeight: isToday ? FontWeight.bold : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isFocused
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: 0.15,
                                        )
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isFocused
                                        ? theme.colorScheme.primary
                                        : Colors.transparent,
                                    width: isFocused ? 1.5 : 1.0,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${day.day}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: isFocused
                                        ? FontWeight.bold
                                        : null,
                                    color: isFocused
                                        ? theme.colorScheme.primary
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: dotColor ?? Colors.transparent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox(height: 40),
                  error: (err, stack) => const SizedBox.shrink(),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

List<MindmapNode> _applyCalendarFilters(
  List<MindmapNode> nodes, {
  required String query,
  required Set<NodeType> typeFilters,
  required bool doneOnly,
  CalendarNodeFilter advancedFilter = const CalendarNodeFilter(),
  DateTime? today,
}) {
  return nodes.where((node) {
    if (query.isNotEmpty && !_nodeMatches(node, query)) return false;
    if (typeFilters.isNotEmpty &&
        !_matchesCalendarTypeFilter(node, typeFilters)) {
      return false;
    }
    if (doneOnly && !node.isDone && node.status != NodeStatus.done) {
      return false;
    }
    return matchesCalendarNodeFilter(
      node,
      advancedFilter,
      today: today ?? DateTime.now(),
    );
  }).toList();
}

bool _matchesCalendarTypeFilter(MindmapNode node, Set<NodeType> typeFilters) {
  if (typeFilters.contains(node.type)) return true;
  return typeFilters.contains(NodeType.event) &&
      calendarNodePayloadFromData(node.data) != null;
}

bool _nodeMatches(MindmapNode node, String query) {
  return node.title.toLowerCase().contains(query) ||
      node.body.toLowerCase().contains(query) ||
      node.project.toLowerCase().contains(query) ||
      node.area.toLowerCase().contains(query) ||
      node.tags.any((tag) => tag.toLowerCase().contains(query));
}

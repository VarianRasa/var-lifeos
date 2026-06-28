/// Calendar page — the app's home screen.
///
/// Renders the month grid, day summaries, search, keyboard navigation, and
/// route handoff into the selected day's mindmap.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/search_field.dart';
import '../mindmap/application/mindmap_mutation_controller.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/application/recurring_routine_application.dart';
import '../mindmap/domain/day_node_summary.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/mindmap_node_data.dart';
import '../mindmap/domain/recurring_routine.dart';
import '../mindmap/domain/workspace_context.dart';
import '../onboarding/onboarding_overlay.dart';
import '../workspace/data/workspace_title_repository.dart';
import 'application/calendar_view_controller.dart';
import 'domain/calendar_node_payload.dart';

final calendarSearchQueryProvider = StateProvider<String>((ref) => '');
final selectedAgendaNodeIdProvider = StateProvider<String?>((ref) => null);
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
  bool _slideForward = true;
  final Set<String> _dismissedMonths = {};
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = ref.read(currentDateProvider);
    _visibleMonth = now.dateOnly.firstOfMonth;
    _focusedDay = now.dateOnly;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(currentDateProvider);
    final viewMode = ref.watch(calendarViewModeProvider);
    final isDesktop =
        MediaQuery.sizeOf(context).width >= LayoutConstants.desktopBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          SearchField(
            key: const ValueKey('calendar-search-field'),
            controller: _searchController,
            hintText: 'Search calendar...',
            onChanged: (value) {
              ref.read(calendarSearchQueryProvider.notifier).state = value
                  .trim()
                  .toLowerCase();
            },
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Today',
            child: OutlinedButton.icon(
              onPressed: () {
                _showFocusedDay(today);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
                fixedSize: const Size.fromHeight(36),
              ),
              icon: const Icon(Icons.today, size: 16),
              label: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text('Today'), SizedBox(width: 6), _PulsingDot()],
              ),
            ),
          ),
          if (isDesktop)
            const SizedBox(width: 460)
          else
            const SizedBox(width: 16),
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
                  } else if (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space) {
                    goToDay(context, _focusedDay);
                    return KeyEventResult.handled;
                  }

                  if (nextDay != null) {
                    _showFocusedDay(nextDay);
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Column(
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
                  const _CalendarViewModeSwitch(),
                  const SizedBox(height: 4),
                  _WeeklySummaryStrip(today: today),
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
                              ),
                              CalendarViewMode.week => _WeekCalendarView(
                                focusedDay: _focusedDay,
                                today: today,
                              ),
                              CalendarViewMode.agenda => _AgendaCalendarView(
                                focusedDay: _focusedDay,
                                today: today,
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
                    onDismiss: () {
                      setState(() => _dismissedMonths.add(_monthKey));
                    },
                  ),
                ],
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

  KeyEventResult _handleCalendarShortcut(
    KeyDownEvent event,
    CalendarViewMode viewMode,
  ) {
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
    required this.onDismiss,
  });

  final DateTime visibleMonth;
  final DateTime today;
  final bool isDismissed;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isDismissed) return const SizedBox.shrink();

    final firstDay = visibleDaysForMonth(visibleMonth).first;
    final lastDay = visibleDaysForMonth(visibleMonth).last;
    final allNodesAsync = ref.watch(allMindmapNodesProvider);
    final hasNodes =
        allNodesAsync.valueOrNull?.any(
          (n) =>
              n.day.isAfter(firstDay.subtract(const Duration(days: 1))) &&
              n.day.isBefore(lastDay.add(const Duration(days: 1))),
        ) ??
        false;
    if (hasNodes) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
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
                  'No nodes yet in ${DateFormat('MMMM').format(visibleMonth)} — tap a day to add one',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ),
              ),
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
    );
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
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            key: const ValueKey('calendar-routine-apply-banner'),
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            return AlertDialog(
              key: const ValueKey('calendar-routine-apply-dialog'),
              title: const Text('Apply routines?'),
              content: SizedBox(
                width: 360,
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
                    for (final item in readyItems)
                      CheckboxListTile(
                        key: ValueKey(
                          'calendar-routine-select-${item.routine.id}',
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selectedRoutineIds.contains(item.routine.id),
                        onChanged: (value) {
                          toggleRoutine(item.routine.id, value ?? false);
                        },
                        title: Text(item.node?.title ?? item.routine.label),
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
            firstDate: day,
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
    invalidateMindmapState(ref, day: day);
    ref.invalidate(calendarRoutinePlanProvider(day.dateOnly));
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
    ref.invalidate(calendarRoutinePlanProvider(day.dateOnly));
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
  const _WeekCalendarView({required this.focusedDay, required this.today});

  final DateTime focusedDay;
  final DateTime today;

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
                ),
              );
            },
          );
        }
        const crossAxisCount = 7;
        const spacing = 5.0;
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
            );
          },
        );
      },
    );
  }
}

class _AgendaCalendarView extends ConsumerWidget {
  const _AgendaCalendarView({required this.focusedDay, required this.today});

  final DateTime focusedDay;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesAsync = ref.watch(allMindmapNodesProvider);
    final filter = ref.watch(agendaFilterProvider);
    final theme = Theme.of(context);
    return Column(
      children: [
        const _AgendaFilterBar(),
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
                  ? _AgendaEmptyState(filter: filter, day: focusedDay)
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
                                          'calendar-agenda-open-${dayKey(day)}',
                                        ),
                                        tooltip: 'Open day to add node',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          size: 18,
                                        ),
                                        onPressed: () => goToDay(context, day),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ...dayNodes.take(5).map((node) {
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
                                                  color:
                                                      theme.colorScheme.primary,
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
                                              color: theme.colorScheme.primary,
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
                                                      _agendaNodeMetadata(node),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
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
      AgendaFilter.routines => _isRoutineMarker(node),
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
    if (node.priority != NodePriority.none) parts.add(node.priority.label);
    if (node.status != NodeStatus.open) parts.add(node.status.label);
    return parts.join(' · ');
  }

  String? _routineMarkerLabel(MindmapNode node) {
    final automation = node.data['automation'];
    if (automation is! Map) return null;
    final state = automation['state'];
    return switch (state) {
      'skipped' => 'Skipped routine',
      'snoozed' => 'Snoozed routine',
      _ => null,
    };
  }

  bool _isRoutineMarker(MindmapNode node) {
    return _routineMarkerLabel(node) != null;
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
}

class _AgendaFilterBar extends ConsumerWidget {
  const _AgendaFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(agendaFilterProvider);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: AgendaFilter.values.length,
        separatorBuilder: (_, separatorIndex) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = AgendaFilter.values[index];
          return FilterChip(
            key: ValueKey('agenda-filter-${filter.name}'),
            tooltip: '${filter.label} (${index + 1})',
            label: Text(filter.label),
            selected: selected == filter,
            onSelected: (_) {
              ref.read(agendaFilterProvider.notifier).setFilter(filter);
            },
          );
        },
      ),
    );
  }
}

class _AgendaLoadingState extends StatelessWidget {
  const _AgendaLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: ValueKey('calendar-agenda-loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Loading agenda...'),
        ],
      ),
    );
  }
}

class _AgendaErrorState extends StatelessWidget {
  const _AgendaErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey('calendar-agenda-error'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 44,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text('Unable to load agenda', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
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

class _AgendaEmptyState extends StatelessWidget {
  const _AgendaEmptyState({required this.filter, required this.day});

  final AgendaFilter filter;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (filter) {
      AgendaFilter.all => 'No agenda items',
      AgendaFilter.tasks => 'No task items',
      AgendaFilter.events => 'No event items',
      AgendaFilter.habits => 'No habit items',
      AgendaFilter.routines => 'No routine items',
      AgendaFilter.done => 'No done items',
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 140;
        return Center(
          key: const ValueKey('calendar-agenda-empty'),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!tight) ...[
                  Icon(
                    Icons.event_note_outlined,
                    size: 40,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 10),
                ],
                Text(label, style: theme.textTheme.titleMedium),
                if (!tight) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Create nodes on a day to build your agenda.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                SizedBox(height: tight ? 8 : 12),
                FilledButton.icon(
                  key: const ValueKey('calendar-agenda-empty-open-day'),
                  onPressed: () => goToDay(context, day),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Open day'),
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
    return Row(
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
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

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.today,
    required this.focusedDay,
  });

  final DateTime visibleMonth;
  final DateTime today;
  final DateTime focusedDay;

  @override
  Widget build(BuildContext context) {
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

        return GridView.builder(
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
              isInVisibleMonth: day.month == visibleMonth.month,
              isToday: day.isSameDay(today),
              focusedDay: focusedDay,
              rowIndex: rowIndex,
              colIndex: colIndex,
              totalRows: rowCount,
            );
          },
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
  });

  final DateTime day;
  final bool isInVisibleMonth;
  final bool isToday;
  final DateTime focusedDay;
  final int rowIndex;
  final int colIndex;
  final int totalRows;

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
    final borderColor = widget.isToday
        ? theme.colorScheme.primary
        : (isFocused
              ? theme.colorScheme.primary.withValues(alpha: 0.6)
              : Theme.of(context).dividerColor);

    final searchQuery = ref
        .watch(calendarSearchQueryProvider)
        .trim()
        .toLowerCase();
    final nodesAsync = ref.watch(nodesForDayProvider(widget.day));

    final titleMap = ref.watch(workspaceTitleProvider);
    final titleKey = '${WorkspaceContextType.daily.name}_${dayKey(widget.day)}';
    final customTitle = titleMap[titleKey];
    final hasCustomTitle = customTitle != null && customTitle.isNotEmpty;

    // Filter nodes based on query
    final allNodes = nodesAsync.valueOrNull ?? [];
    final filteredNodes = searchQuery.isEmpty
        ? allNodes
        : allNodes.where((n) => _nodeMatches(n, searchQuery)).toList();
    final hasNodes = filteredNodes.isNotEmpty;

    final matchesCustomTitle =
        hasCustomTitle && customTitle.toLowerCase().contains(searchQuery);
    final matchesQuery = searchQuery.isEmpty || matchesCustomTitle || hasNodes;

    final container = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack, // liquidy transition
      transformAlignment: Alignment.center,
      transform: Matrix4.translationValues(0.0, _isHovered ? -4.0 : 0.0, 0.0)
        ..multiply(
          Matrix4.diagonal3Values(
            1.0 + (_isHovered ? 0.03 : 0.0),
            1.0 + (_isHovered ? 0.03 : 0.0),
            1.0,
          ),
        ),
      decoration: BoxDecoration(
        color: widget.isToday
            ? theme.colorScheme.primary.withValues(
                alpha: _isHovered ? 0.15 : 0.08,
              )
            : (_isHovered
                  ? theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.8,
                    )
                  : theme.cardTheme.color),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isHovered
              ? theme.colorScheme.primary.withValues(alpha: 0.8)
              : (isFocused ? theme.colorScheme.primary : borderColor),
          width: widget.isToday || _isHovered || isFocused ? 2.0 : 1.0,
        ),
        boxShadow: _isHovered
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.0),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${widget.day.day}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: widget.isInVisibleMonth
                          ? (_isHovered ? theme.colorScheme.primary : null)
                          : theme.textTheme.bodySmall?.color,
                      fontWeight: widget.isToday || isFocused
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  if (hasCustomTitle)
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
                    key: ValueKey('calendar-focused-${dayKey(widget.day)}'),
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
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
              nodesAsync.when(
                data: (nodes) => _CellSummary(
                  summary: DayNodeSummary.fromNodes(
                    widget.day,
                    searchQuery.isEmpty
                        ? nodes
                        : nodes
                              .where((n) => _nodeMatches(n, searchQuery))
                              .toList(),
                  ),
                  nodes: searchQuery.isEmpty
                      ? nodes
                      : nodes
                            .where((n) => _nodeMatches(n, searchQuery))
                            .toList(),
                ),
                loading: () => const SizedBox.shrink(),
                error: (error, _) => Icon(
                  Icons.error_outline,
                  size: 14,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
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

    Widget cellWidget = container;
    if (searchQuery.isNotEmpty && !matchesQuery) {
      cellWidget = Opacity(
        opacity: 0.25,
        child: IgnorePointer(child: container),
      );
    }

    final draggableCell = DragTarget<MindmapNode>(
      key: ValueKey('calendar-drop-${dayKey(widget.day)}'),
      onWillAcceptWithDetails: (details) =>
          !details.data.day.dateOnly.isSameDay(widget.day),
      onAcceptWithDetails: (details) async {
        _hideOverlay();
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
          child: MouseRegion(
            onEnter: (_) => _onHoverChange(true, isUpperHalf, hasContent),
            onExit: (_) => _onHoverChange(false, isUpperHalf, hasContent),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: ValueKey('calendar-cell-${dayKey(widget.day)}'),
              onTap: () {
                _hideOverlay();
                goToDay(context, widget.day);
              },
              child: cellWidget,
            ),
          ),
        );
      },
    );

    return Semantics(
      label: semanticsLabel,
      button: true,
      selected: isFocused,
      onTap: () {
        _hideOverlay();
        goToDay(context, widget.day);
      },
      child: draggableCell,
    );
  }
}

class _CellSummary extends StatelessWidget {
  const _CellSummary({required this.summary, required this.nodes});

  final DayNodeSummary summary;
  final List<MindmapNode> nodes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!summary.hasNodes) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _countLabel(summary.totalCount),
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: 4),
        ...nodes.take(3).map((node) => _DraggableCalendarNode(node: node)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 3,
          runSpacing: 3,
          children: [
            for (final type in NodeType.values)
              if (summary.countFor(type) > 0)
                _DensityDot(color: _nodeColor(type)),
          ],
        ),
        if (summary.overdueCount > 0 ||
            summary.highPriorityCount > 0 ||
            summary.doneCount > 0) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              if (summary.overdueCount > 0)
                _SummaryChip(
                  label: '${summary.overdueCount} overdue',
                  color: theme.colorScheme.error,
                ),
              if (summary.highPriorityCount > 0)
                _SummaryChip(
                  label: '${summary.highPriorityCount} high',
                  color: theme.colorScheme.tertiary,
                ),
              if (summary.doneCount > 0)
                _SummaryChip(
                  label: '${summary.doneCount}/${summary.totalCount} done',
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DraggableCalendarNode extends StatelessWidget {
  const _DraggableCalendarNode({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = node.title.trim().isEmpty
        ? 'Untitled ${node.type.name}'
        : node.title.trim();
    final chip = Container(
      key: ValueKey('calendar-draggable-node-${node.id}'),
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: _nodeColor(node.type).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_nodeIcon(node.type), size: 11, color: _nodeColor(node.type)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: 'Drag to move date',
      child: Semantics(
        label: 'Drag ${node.title} to another date',
        button: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: LongPressDraggable<MindmapNode>(
            data: node,
            feedback: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: chip,
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: chip),
            child: chip,
          ),
        ),
      ),
    );
  }
}

class _DensityDot extends StatelessWidget {
  const _DensityDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox.square(dimension: 6),
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
  NodeType.empty => Icons.circle_outlined,
};

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

class _WeeklySummaryStrip extends ConsumerWidget {
  const _WeeklySummaryStrip({required this.today});

  final DateTime today;

  List<DateTime> _getCurrentWeekDays() {
    final weekday = today.weekday; // 1 = Monday, 7 = Sunday
    final monday = today.subtract(Duration(days: weekday - 1));
    return List.generate(7, (index) => monday.add(Duration(days: index)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final weekDays = _getCurrentWeekDays();
    final allNodesAsync = ref.watch(allMindmapNodesProvider);

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
                  'Weekly Summary',
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

                  return Text(
                    '$completed / $total completed',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
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
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekDays.map((day) {
              final isToday = day.isSameDay(today);

              return allNodesAsync.when(
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
                      dotColor = theme.colorScheme.secondary; // planned/pending
                    }
                  }

                  final semanticsParts = <String>[
                    DateFormat('EEEE, MMMM d, yyyy').format(day),
                    _countLabel(total),
                    '$completed completed',
                  ];
                  if (isToday) semanticsParts.add('today');

                  return Semantics(
                    label: semanticsParts.join(', '),
                    button: true,
                    selected: isToday,
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
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isToday
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: 0.15,
                                      )
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isToday
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${day.day}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: isToday ? FontWeight.bold : null,
                                  color: isToday
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
                loading: () => const SizedBox(width: 40, height: 40),
                error: (err, stack) => const SizedBox.shrink(),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

bool _nodeMatches(MindmapNode node, String query) {
  return node.title.toLowerCase().contains(query) ||
      node.body.toLowerCase().contains(query) ||
      node.project.toLowerCase().contains(query) ||
      node.area.toLowerCase().contains(query) ||
      node.tags.any((tag) => tag.toLowerCase().contains(query));
}

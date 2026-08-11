/// App navigation via go_router.
///
/// Routes are deliberately flat and URL-friendly so the index menu can deep-link
/// to a specific day with an optional `?highlight=<nodeId>` query param:
///   /calendar/2026-06-18?highlight=node_abc
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/calendar/calendar_page.dart';
import '../../features/calendar/day_page.dart';
import '../../features/focus/focus_page.dart';
import '../../features/graph/graph_page.dart';
import '../../features/insights/insights_page.dart';
import '../../features/life_os/goals_habits_page.dart';
import '../../features/life_os/notes_journal_page.dart';
import '../../features/mindmap/presentation/collab_page.dart';
import '../../features/mindmap/presentation/node_detail_page.dart';
import '../../features/search/presentation/search_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/sync/presentation/recovery_center.dart';
import '../../features/workspace/workspace_detail_page.dart';
import '../../features/workspace/workspaces_page.dart';
import '../../shared/layout/adaptive_scaffold.dart';
import '../constants/app_constants.dart';
import '../theme/app_design_tokens.dart';
import '../utils/date_utils.dart';

final appRouterProvider = Provider<GoRouter>((ref) => createAppRouter());

GoRouter createAppRouter({String? initialLocation}) {
  final todayStr = dayKey(DateTime.now());
  final nodeDetailExitController = NodeDetailExitController();
  return GoRouter(
    initialLocation: initialLocation ?? '/calendar/$todayStr',
    debugLogDiagnostics: false,
    routes: [
      // A shell wraps every top-level route in the adaptive nav (rail/bar).
      ShellRoute(
        pageBuilder: (context, state, child) => NoTransitionPage<void>(
          key: state.pageKey,
          child: AdaptiveScaffold(body: child),
        ),
        routes: [
          // Calendar (home is now Canvas DayPage).
          GoRoute(
            path: '/calendar',
            name: AppRoute.calendar.name,
            redirect: (context, state) {
              if (state.uri.path == '/calendar') {
                return '/calendar/${dayKey(DateTime.now())}';
              }
              return null;
            },
            routes: [
              // A specific day canvas page.
              // :date is an ISO date string (yyyy-MM-dd).
              GoRoute(
                path: ':date',
                name: 'day',
                pageBuilder: (context, state) {
                  final date = _parseDateParam(state.pathParameters['date']);
                  final highlight = state.uri.queryParameters['highlight'];
                  final boardId = state.uri.queryParameters['board'];
                  final panel = AppRoute.fromPanel(
                    state.uri.queryParameters['panel'],
                  );
                  return NoTransitionPage<void>(
                    key: state.pageKey,
                    child: _DayWithPanel(
                      date: date,
                      highlightNodeId: highlight,
                      initialBoardId: boardId,
                      panel: panel,
                    ),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/calendar/:date/node/:nodeId',
            name: 'node_detail',
            onExit: (context, state) => nodeDetailExitController.prepareExit(),
            pageBuilder: (context, state) {
              final date = _parseDateParam(state.pathParameters['date']);
              final nodeId = state.pathParameters['nodeId']!;
              return NoTransitionPage<void>(
                key: state.pageKey,
                child: NodeDetailPage(
                  date: date,
                  nodeId: nodeId,
                  exitController: nodeDetailExitController,
                ),
              );
            },
          ),
          GoRoute(
            path: '/focus',
            name: AppRoute.focus.name,
            redirect: (context, state) =>
                _legacyPanelLocation(state, AppRoute.focus, todayStr),
          ),
          GoRoute(
            path: '/goals-habits',
            name: AppRoute.goalsHabits.name,
            redirect: (context, state) =>
                _legacyPanelLocation(state, AppRoute.goalsHabits, todayStr),
          ),
          GoRoute(
            path: '/notes-journal',
            name: AppRoute.notesJournal.name,
            redirect: (context, state) =>
                _legacyPanelLocation(state, AppRoute.notesJournal, todayStr),
          ),
          GoRoute(
            path: '/insights',
            name: AppRoute.insights.name,
            redirect: (context, state) =>
                _legacyPanelLocation(state, AppRoute.insights, todayStr),
          ),
          GoRoute(
            path: '/graph',
            name: AppRoute.graph.name,
            redirect: (context, state) =>
                _legacyPanelLocation(state, AppRoute.graph, todayStr),
          ),
          GoRoute(
            path: '/workspaces',
            name: AppRoute.workspaces.name,
            redirect: (context, state) => state.uri.path == '/workspaces'
                ? _legacyPanelLocation(state, AppRoute.workspaces, todayStr)
                : null,
            routes: [
              GoRoute(
                path: ':type/:name',
                name: 'workspace_detail',
                redirect: (context, state) {
                  if (state.uri.queryParameters['view'] != 'canvas') {
                    return null;
                  }
                  final boardId = state.uri.queryParameters['board'];
                  final boardQuery = boardId == null
                      ? ''
                      : '?board=${Uri.encodeQueryComponent(boardId)}';
                  return '/calendar/${dayKey(DateTime.now())}$boardQuery';
                },
                pageBuilder: (context, state) {
                  final type = state.pathParameters['type'] ?? 'project';
                  final name = Uri.decodeComponent(
                    state.pathParameters['name'] ?? '',
                  );
                  return NoTransitionPage<void>(
                    key: state.pageKey,
                    child: WorkspaceDetailPage(
                      typeName: type,
                      name: name,
                      initialCanvas: false,
                      initialBoardId: state.uri.queryParameters['board'],
                    ),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/search',
            name: AppRoute.search.name,
            pageBuilder: (context, state) => NoTransitionPage<void>(
              key: state.pageKey,
              child: SearchPage(
                initialQuery: state.uri.queryParameters['q'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/settings',
            name: AppRoute.settings.name,
            redirect: (context, state) =>
                _legacyPanelLocation(state, AppRoute.settings, todayStr),
          ),
          GoRoute(
            path: '/recovery',
            name: 'recovery',
            pageBuilder: (context, state) => NoTransitionPage<void>(
              key: state.pageKey,
              child: const RecoveryCenterPage(),
            ),
          ),
          GoRoute(
            path: '/collab',
            name: AppRoute.collab.name,
            redirect: (context, state) =>
                _legacyPanelLocation(state, AppRoute.collab, todayStr),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _RouteError(error: state.error),
  );
}

String _legacyPanelLocation(GoRouterState state, AppRoute panel, String today) {
  return Uri(
    path: '/calendar/$today',
    queryParameters: <String, String>{
      ...state.uri.queryParameters,
      'panel': panel.name,
    },
  ).toString();
}

class _DayWithPanel extends StatelessWidget {
  const _DayWithPanel({
    required this.date,
    this.highlightNodeId,
    this.initialBoardId,
    this.panel,
  });

  final DateTime date;
  final String? highlightNodeId;
  final String? initialBoardId;
  final AppRoute? panel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DayPage(
            date: date,
            highlightNodeId: highlightNodeId,
            initialBoardId: initialBoardId,
          ),
        ),
        if (panel case final panel?)
          Positioned.fill(
            child: ValueListenableBuilder<int>(
              valueListenable: routePanelResetController,
              builder: (context, reset, child) => _ResizableRoutePanel(
                key: ValueKey('route-panel-${panel.name}-$reset'),
                panel: panel,
                onClose: () => goToDay(context, date),
              ),
            ),
          ),
      ],
    );
  }
}

class _ResizableRoutePanel extends StatefulWidget {
  const _ResizableRoutePanel({
    required this.panel,
    required this.onClose,
    super.key,
  });

  final AppRoute panel;
  final VoidCallback onClose;

  @override
  State<_ResizableRoutePanel> createState() => _ResizableRoutePanelState();
}

class _ResizableRoutePanelState extends State<_ResizableRoutePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<Offset> _entranceAnimation;
  double? _standardWidth;
  double? _wideWidth;
  double _dragStartWidth = 0;
  double _dragStartGlobalX = 0;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      duration: AppDesignTokens.astryx.motionFast,
      vsync: this,
    );
    _entranceAnimation =
        Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: AppDesignTokens.astryx.motionCurve,
          ),
        );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final media = MediaQuery.of(context);
    final textDirection = Directionality.of(context);
    if (media.disableAnimations || media.accessibleNavigation) {
      _entranceController.value = 1;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth <= LayoutConstants.mobileBreakpoint;
        final wide =
            panel == AppRoute.graph ||
            panel == AppRoute.insights ||
            panel == AppRoute.workspaces;
        final maxWidth = (constraints.maxWidth * 0.8).clamp(0.0, 960.0);
        final minWidth = (constraints.maxWidth * 0.5).clamp(0.0, maxWidth);
        final preferredWidth = wide
            ? _wideWidth ?? constraints.maxWidth * 0.72
            : _standardWidth ?? minWidth;
        final width = mobile
            ? constraints.maxWidth
            : preferredWidth.clamp(minWidth, maxWidth);
        return SlideTransition(
          position: _entranceAnimation,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Material(
              elevation: 0,
              shadowColor: Colors.transparent,

              child: SizedBox(
                key: ValueKey('route-panel-${panel.name}'),

                width: width,
                height: constraints.maxHeight,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        _RoutePanelHeader(
                          label: panel.label,
                          onClose: widget.onClose,
                        ),
                        Expanded(child: _panelPage(panel)),
                      ],
                    ),
                    if (!mobile)
                      Positioned(
                        top: 0,
                        left: textDirection == TextDirection.rtl ? 0 : null,
                        right: textDirection == TextDirection.ltr ? 0 : null,

                        bottom: 0,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeLeftRight,
                          child: GestureDetector(
                            key: const ValueKey('route-panel-resize'),
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragStart: (details) {
                              _dragStartWidth = width;
                              _dragStartGlobalX = details.globalPosition.dx;
                            },
                            onHorizontalDragUpdate: (details) {
                              final displacement =
                                  (details.globalPosition.dx -
                                      _dragStartGlobalX) *
                                  (textDirection == TextDirection.ltr ? 1 : -1);

                              final resized = (_dragStartWidth + displacement)
                                  .clamp(minWidth, maxWidth);
                              setState(() {
                                if (wide) {
                                  _wideWidth = resized;
                                } else {
                                  _standardWidth = resized;
                                }
                              });
                            },
                            child: SizedBox(
                              width: 20,
                              child: Center(
                                child: Container(
                                  key: const ValueKey(
                                    'route-panel-resize-line',
                                  ),
                                  width: 2,
                                  height: 48,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _panelPage(AppRoute panel) => switch (panel) {
    AppRoute.calendar => const CalendarPage(),
    AppRoute.search => const SearchPage(),
    AppRoute.focus => const FocusPage(),
    AppRoute.goalsHabits => const GoalsHabitsPage(),
    AppRoute.notesJournal => const NotesJournalPage(),
    AppRoute.workspaces => const WorkspacesPage(),
    AppRoute.insights => const InsightsPage(),
    AppRoute.graph => const GraphPage(),
    AppRoute.collab => const CollabPage(),
    AppRoute.settings => const SettingsPage(),
  };
}

class _RoutePanelHeader extends StatelessWidget {
  const _RoutePanelHeader({required this.label, required this.onClose});

  final String label;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.only(left: 20, right: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton.filledTonal(
                key: const ValueKey('close-route-panel'),
                onPressed: onClose,
                tooltip: 'Close panel',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String legacyNodeRouteLocation({required String date, required String nodeId}) {
  return Uri(
    path: '/calendar/$date',
    queryParameters: <String, String>{'highlight': nodeId},
  ).toString();
}

String projectCanvasLocation({
  required String workspaceName,
  required String boardId,
}) {
  final separator = workspaceName.indexOf(':');
  final type = separator < 1
      ? ''
      : workspaceName.substring(0, separator).trim();
  final name = separator < 0
      ? ''
      : workspaceName.substring(separator + 1).trim();
  if (type.isEmpty || name.isEmpty || boardId.trim().isEmpty) {
    throw const FormatException('Invalid project board workspace target.');
  }
  return Uri(
    pathSegments: <String>['workspaces', type, name],
    queryParameters: <String, String>{
      'view': 'canvas',
      'board': boardId.trim(),
    },
  ).toString();
}

/// Named route identifiers, used for nav rail / bottom nav active state.
enum AppRoute {
  calendar,
  search,
  focus,
  goalsHabits,
  notesJournal,
  workspaces,
  insights,
  graph,
  collab,
  settings;

  String get path => switch (this) {
    AppRoute.calendar => '/calendar',
    AppRoute.search => '/search',
    AppRoute.focus => '/focus',
    AppRoute.goalsHabits => '/goals-habits',
    AppRoute.notesJournal => '/notes-journal',
    AppRoute.workspaces => '/workspaces',
    AppRoute.insights => '/insights',
    AppRoute.graph => '/graph',
    AppRoute.collab => '/collab',
    AppRoute.settings => '/settings',
  };

  static AppRoute? fromPanel(String? value) {
    for (final route in values) {
      if (route.name == value) return route;
    }
    return null;
  }

  IconData get icon => switch (this) {
    AppRoute.calendar => Icons.calendar_month_outlined,
    AppRoute.search => Icons.search_outlined,
    AppRoute.focus => Icons.timer_outlined,
    AppRoute.goalsHabits => Icons.track_changes_outlined,
    AppRoute.notesJournal => Icons.auto_stories_outlined,
    AppRoute.workspaces => Icons.workspaces_outline,
    AppRoute.insights => Icons.insights_outlined,
    AppRoute.graph => Icons.account_tree_outlined,
    AppRoute.collab => Icons.people_outline,
    AppRoute.settings => Icons.settings_outlined,
  };

  IconData get selectedIcon => switch (this) {
    AppRoute.calendar => Icons.calendar_month_rounded,
    AppRoute.search => Icons.search_rounded,
    AppRoute.focus => Icons.timer_rounded,
    AppRoute.goalsHabits => Icons.track_changes_rounded,
    AppRoute.notesJournal => Icons.auto_stories_rounded,
    AppRoute.workspaces => Icons.workspaces,
    AppRoute.insights => Icons.insights_rounded,
    AppRoute.graph => Icons.account_tree,
    AppRoute.collab => Icons.people,
    AppRoute.settings => Icons.settings_rounded,
  };

  String get label => switch (this) {
    AppRoute.calendar => 'Calendar',
    AppRoute.search => 'Search',
    AppRoute.focus => 'Focus',
    AppRoute.goalsHabits => 'Goals & Habits',
    AppRoute.notesJournal => 'Notes & Journal',
    AppRoute.workspaces => 'Workspaces',
    AppRoute.insights => 'Insights',
    AppRoute.graph => 'Graph',
    AppRoute.collab => 'Collab',
    AppRoute.settings => 'Settings',
  };
}

String appRouteLocation(BuildContext context, AppRoute route) {
  if (route == AppRoute.search) return route.path;
  final state = GoRouterState.of(context);
  final date = state.pathParameters['date'] ?? dayKey(DateTime.now());
  return Uri(
    path: '/calendar/$date',
    queryParameters: <String, String>{'panel': route.name},
  ).toString();
}

/// Navigate to a specific calendar day, optionally highlighting a node.
void goToDay(BuildContext context, DateTime date, {String? highlightNodeId}) {
  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  final dateKey = dayKey(date);
  context.go(
    highlightNodeId == null
        ? '/calendar/$dateKey'
        : Uri(
            path: '/calendar/$dateKey',
            queryParameters: <String, String>{'highlight': highlightNodeId},
          ).toString(),
  );
}

DateTime _parseDateParam(String? raw) {
  if (raw == null) return DateTime.now().dateOnly;
  final parsed = DateTime.tryParse(raw);
  return (parsed ?? DateTime.now()).dateOnly;
}

class _RouteError extends StatelessWidget {
  const _RouteError({required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('Page not found', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoute.calendar.path),
                child: const Text('Back to calendar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

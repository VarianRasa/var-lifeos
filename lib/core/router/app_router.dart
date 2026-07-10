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
import '../../features/graph/graph_page.dart';
import '../../features/insights/insights_page.dart';
import '../../features/mindmap/presentation/collab_page.dart';
import '../../features/mindmap/presentation/node_detail_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/workspace/workspace_detail_page.dart';
import '../../features/workspace/workspaces_page.dart';
import '../../shared/layout/adaptive_scaffold.dart';
import '../utils/date_utils.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/calendar',
    debugLogDiagnostics: false,
    routes: [
      // A shell wraps every top-level route in the adaptive nav (rail/bar).
      ShellRoute(
        builder: (context, state, child) => AdaptiveScaffold(body: child),
        routes: [
          // Calendar (home).
          GoRoute(
            path: '/calendar',
            name: AppRoute.calendar.name,
            builder: (context, state) => const CalendarPage(),
            routes: [
              // A specific day, opened as a detail page.
              // :date is an ISO date string (yyyy-MM-dd).
              GoRoute(
                path: ':date',
                name: 'day',
                builder: (context, state) {
                  final date = _parseDateParam(state.pathParameters['date']);
                  final highlight = state.uri.queryParameters['highlight'];
                  return DayPage(date: date, highlightNodeId: highlight);
                },
                routes: [
                  GoRoute(
                    path: 'node/:nodeId',
                    name: 'node_detail',
                    builder: (context, state) {
                      final date = _parseDateParam(
                        state.pathParameters['date'],
                      );
                      final nodeId = state.pathParameters['nodeId']!;
                      return NodeDetailPage(date: date, nodeId: nodeId);
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/insights',
            name: AppRoute.insights.name,
            builder: (context, state) => const InsightsPage(),
          ),
          GoRoute(
            path: '/graph',
            name: AppRoute.graph.name,
            builder: (context, state) => const GraphPage(),
          ),
          GoRoute(
            path: '/workspaces',
            name: AppRoute.workspaces.name,
            builder: (context, state) => const WorkspacesPage(),
            routes: [
              GoRoute(
                path: ':type/:name',
                name: 'workspace_detail',
                builder: (context, state) {
                  final type = state.pathParameters['type'] ?? 'project';
                  final name = Uri.decodeComponent(
                    state.pathParameters['name'] ?? '',
                  );
                  return WorkspaceDetailPage(typeName: type, name: name);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            name: AppRoute.settings.name,
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: '/collab',
            name: AppRoute.collab.name,
            builder: (context, state) {
              final roomId =
                  state.uri.queryParameters['room'] ??
                  state.uri.queryParameters['id'];
              final dayKey =
                  state.uri.queryParameters['key'] ??
                  state.uri.queryParameters['date'];
              return CollabPage(initialRoomId: roomId, initialDayKey: dayKey);
            },
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _RouteError(error: state.error),
  );
});

/// Named route identifiers, used for nav rail / bottom nav active state.
enum AppRoute { calendar, insights, graph, workspaces, collab, settings }

extension AppRouteX on AppRoute {
  String get path {
    switch (this) {
      case AppRoute.calendar:
        return '/calendar';
      case AppRoute.insights:
        return '/insights';
      case AppRoute.graph:
        return '/graph';
      case AppRoute.workspaces:
        return '/workspaces';
      case AppRoute.collab:
        return '/collab';
      case AppRoute.settings:
        return '/settings';
    }
  }

  IconData get icon => switch (this) {
    AppRoute.calendar => Icons.calendar_month_outlined,
    AppRoute.insights => Icons.insights_outlined,
    AppRoute.graph => Icons.account_tree_outlined,
    AppRoute.workspaces => Icons.workspaces_outline,
    AppRoute.collab => Icons.people_outline,
    AppRoute.settings => Icons.settings_outlined,
  };

  IconData get selectedIcon => switch (this) {
    AppRoute.calendar => Icons.calendar_month_rounded,
    AppRoute.insights => Icons.insights_rounded,
    AppRoute.graph => Icons.account_tree,
    AppRoute.workspaces => Icons.workspaces,
    AppRoute.collab => Icons.people,
    AppRoute.settings => Icons.settings_rounded,
  };

  String get label => switch (this) {
    AppRoute.calendar => 'Calendar',
    AppRoute.insights => 'Insights',
    AppRoute.graph => 'Graph',
    AppRoute.workspaces => 'Workspaces',
    AppRoute.collab => 'Collab',
    AppRoute.settings => 'Settings',
  };
}

/// Navigate to a specific calendar day, optionally highlighting a node.
void goToDay(BuildContext context, DateTime date, {String? highlightNodeId}) {
  final base = '/calendar/${dayKey(date)}';
  final uri = highlightNodeId == null
      ? base
      : '$base?highlight=$highlightNodeId';
  context.go(uri);
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

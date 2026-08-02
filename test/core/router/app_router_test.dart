import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/router/app_router.dart';
import 'package:var_app/features/calendar/day_page.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test('legacy node route redirects to encoded day highlight', () {
    expect(
      legacyNodeRouteLocation(date: '2026-06-18', nodeId: 'node / 1'),
      '/calendar/2026-06-18?highlight=node+%2F+1',
    );
  });

  test('project canvas route preserves exact workspace and board', () {
    final location = projectCanvasLocation(
      workspaceName: 'project:Launch / 日本',
      boardId: 'project:copy/one',
    );
    final uri = Uri.parse(location);

    expect(uri.pathSegments, <String>['workspaces', 'project', 'Launch / 日本']);
    expect(uri.queryParameters['view'], 'canvas');
    expect(uri.queryParameters['board'], 'project:copy/one');
  });

  test('project canvas route rejects invalid workspace metadata', () {
    expect(
      () => projectCanvasLocation(workspaceName: 'project', boardId: 'board'),
      throwsFormatException,
    );
  });

  testWidgets('goToDay uses canonical highlighted day URL', (tester) async {
    final router = GoRouter(
      initialLocation: '/calendar',
      routes: <RouteBase>[
        GoRoute(
          path: '/calendar',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => goToDay(
                context,
                DateTime(2026, 6, 18),
                highlightNodeId: 'node / 1',
              ),
              child: const Text('Open node'),
            ),
          ),
        ),
        GoRoute(
          path: '/calendar/:date',
          builder: (context, state) => const Scaffold(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Open node'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/calendar/2026-06-18?highlight=node+%2F+1',
    );
  });

  testWidgets('legacy app route redirects to inline day highlight', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'legacy-node',
          type: NodeType.note,
          title: 'Legacy node',
          day: day,
          now: day,
        ),
      ],
    );
    final router = createAppRouter(
      initialLocation: '/calendar/2026-06-18/node/legacy-node',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/calendar/2026-06-18?highlight=legacy-node',
    );
    expect(
      find.byKey(const ValueKey('inline-workspace-legacy-node')),
      findsOneWidget,
    );
  });

  testWidgets('legacy route rejects a node from another local day', (
    tester,
  ) async {
    final routeDay = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'cross-day-node',
          type: NodeType.note,
          title: 'Tomorrow node',
          day: routeDay.add(const Duration(days: 1)),
          now: routeDay,
        ),
      ],
    );
    final router = createAppRouter(
      initialLocation: '/calendar/2026-06-18/node/cross-day-node',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/calendar/2026-06-18?highlight=cross-day-node',
    );
    expect(find.text('Node no longer exists'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inline-workspace-cross-day-node')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mindmap-highlight-cross-day-node')),
      findsNothing,
    );
  });

  testWidgets('legacy browser history redirects without blank frame', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'legacy-node',
          type: NodeType.note,
          title: 'Legacy node',
          day: day,
          now: day,
        ),
      ],
    );
    final router = createAppRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await router.routeInformationProvider.didPushRouteInformation(
      RouteInformation(uri: Uri.parse('/calendar/2026-06-18/node/legacy-node')),
    );
    await tester.pump();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/calendar/2026-06-18?highlight=legacy-node',
    );
    await tester.pumpAndSettle();
    expect(find.byType(DayPage), findsOneWidget);

    await router.routeInformationProvider.didPushRouteInformation(
      RouteInformation(
        uri: Uri.parse('/calendar/2026-06-18?highlight=legacy-node'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.toString(),
      '/calendar/2026-06-18?highlight=legacy-node',
    );
  });

  testWidgets('recovery route opens Recovery Center', (tester) async {
    final router = createAppRouter(initialLocation: '/recovery');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.toString(), '/recovery');
    expect(find.text('Recovery Center'), findsOneWidget);
    expect(
      AppRoute.values.map((route) => route.name),
      isNot(contains('recovery')),
    );
  });

  testWidgets('route panel opens left and resizes within standard limits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = createAppRouter(
      initialLocation: '/calendar/2026-06-18?panel=notesJournal',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('route-panel-notesJournal'));
    final resizeHandle = find.byKey(const ValueKey('route-panel-resize'));
    final minimumWidth = tester.getSize(panel).width;
    expect(minimumWidth, greaterThanOrEqualTo(480));
    expect(find.text('Notes & Journal'), findsWidgets);
    expect(find.byKey(const ValueKey('close-route-panel')), findsOneWidget);
    expect(resizeHandle, findsOneWidget);
    expect(tester.getSize(resizeHandle).width, 20);
    expect(
      find.byKey(const ValueKey('route-panel-resize-line')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('route-panel-resize')),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).width, minimumWidth + 200);

    await tester.drag(
      find.byKey(const ValueKey('route-panel-resize')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).width, minimumWidth);
  });

  testWidgets('mobile route panel fills body without resize handle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = createAppRouter(
      initialLocation: '/calendar/2026-06-18?panel=notesJournal',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('route-panel-notesJournal')))
          .width,
      390,
    );
    expect(find.byKey(const ValueKey('route-panel-resize')), findsNothing);
  });

  test('node_detail route name remains compatible', () {
    final router = createAppRouter();
    addTearDown(router.dispose);

    expect(
      router.namedLocation(
        'node_detail',
        pathParameters: const {'date': '2026-06-18', 'nodeId': 'legacy-node'},
      ),
      '/calendar/2026-06-18/node/legacy-node',
    );
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/graph/graph_page.dart';
import 'package:var_app/features/graph/presentation/graph_physics_canvas.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_graph.dart';

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.views.first;
    view.physicalSize = const Size(1024, 1024);
    view.devicePixelRatio = 1.0;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });
  for (final width in [320.0, 768.0, 1024.0, 1440.0]) {
    testWidgets('GraphPage adapts chrome at width $width', (tester) async {
      await _pumpGraphPage(tester, width: width);

      expect(find.byKey(const ValueKey('graph-page-body')), findsOneWidget);
      expect(find.text('Graph'), findsOneWidget);
      expect(
        find.byTooltip('Switch to 2D Physics Force-Directed View'),
        findsOneWidget,
      );
      if (width < 600) {
        expect(
          find.byKey(const ValueKey('graph-search-action')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('graph-search-action')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('graph-search-field')),
          findsOneWidget,
        );
      } else {
        expect(
          find.byKey(const ValueKey('graph-search-field')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull, reason: 'width=$width');
    });
  }

  for (final variant in <({String name, bool disabled, bool accessible})>[
    (name: 'disableAnimations', disabled: true, accessible: false),
    (name: 'accessibleNavigation', disabled: false, accessible: true),
  ]) {
    testWidgets('${variant.name} reveals graph overview immediately', (
      tester,
    ) async {
      await _pumpGraphPage(
        tester,
        width: 1024,
        disableAnimations: variant.disabled,
        accessibleNavigation: variant.accessible,
      );

      await tester.tap(find.text('Show overview'));
      await tester.pump();

      expect(find.text('Map overview'), findsOneWidget);
      final transition = tester.widget<AnimatedSwitcher>(
        find.ancestor(
          of: find.byKey(const ValueKey('graph-overview-panels')),
          matching: find.byType(AnimatedSwitcher),
        ),
      );
      expect(transition.duration, Duration.zero);
    });
  }

  testWidgets('visual and physics canvases expose concise labels', (
    tester,
  ) async {
    await _pumpGraphPage(tester, width: 1024);
    await tester.ensureVisible(find.byType(VisualGraphView));
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            RegExp(
              r'^Graph canvas, \d+ nodes and \d+ links?$',
            ).hasMatch(widget.properties.label ?? ''),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byTooltip('Switch to 2D Physics Force-Directed View'),
    );
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp(r'^Physics graph canvas, \d+ nodes$')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Launch task'), findsOneWidget);
  });

  testWidgets('physics mode preserves graph chrome and filters', (
    tester,
  ) async {
    await _pumpGraphPage(tester, width: 768);
    await tester.tap(
      find.byTooltip('Switch to 2D Physics Force-Directed View'),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('graph-page-body')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('graph-filter-band-toggle')),
      findsOneWidget,
    );
    expect(find.text('Visual Network'), findsOneWidget);
    expect(find.byType(GraphPhysicsCanvas), findsOneWidget);
  });

  testWidgets('physics node tap focuses same graph detail state', (
    tester,
  ) async {
    await _pumpGraphPage(tester, width: 768);
    await tester.tap(
      find.byTooltip('Switch to 2D Physics Force-Directed View'),
    );
    await tester.pump();
    await tester.ensureVisible(find.byType(GraphPhysicsCanvas));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Launch task'));
    await tester.pump();

    final focusedSummary = find.textContaining('Focused on Launch task');
    await tester.ensureVisible(focusedSummary);
    await tester.pump();
    expect(focusedSummary, findsOneWidget);
    expect(find.text('Clear focus'), findsOneWidget);
  });

  testWidgets('compact search autofocuses and restores trigger focus', (
    tester,
  ) async {
    await _pumpGraphPage(tester, width: 320);
    final action = find.byKey(const ValueKey('graph-search-action'));
    await tester.tap(action);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    final actionWidget = tester.widget<IconButton>(action);
    expect(actionWidget.focusNode?.hasFocus, isTrue);
  });

  test('graph chrome avoids reviewed rigid and raw styles', () {
    final source = File(
      'lib/features/graph/graph_page.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('height: 600')));
    expect(source, isNot(contains('width: 156')));
    expect(source, isNot(contains('width: 320')));
    expect(source, isNot(contains('style: TextStyle(fontSize: 10)')));
    expect(source, isNot(contains('Positioned(\n')));
  });

  testWidgets('enabled graph chrome controls have 44 targets', (tester) async {
    await _pumpGraphPage(tester, width: 1440);
    await tester.tap(find.byTooltip('Show graph controls'));
    await tester.pumpAndSettle();

    final controls = find.descendant(
      of: find.byKey(const ValueKey('graph-page-body')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is IconButton && widget.onPressed != null ||
            widget is ButtonStyleButton && widget.enabled,
      ),
    );
    for (final element in controls.evaluate()) {
      final size = tester.getSize(
        find.byElementPredicate((item) => item == element),
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('GraphPage compact chrome supports 200-percent RTL', (
    tester,
  ) async {
    await _pumpGraphPage(
      tester,
      width: 320,
      textScaler: const TextScaler.linear(2),
      textDirection: TextDirection.rtl,
    );

    await tester.tap(find.byKey(const ValueKey('graph-search-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('graph-search-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GraphPage surfaces graph nodes, hubs, and edges', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final tomorrow = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-1',
          type: NodeType.task,
          title: 'Launch task',
          day: today,
          relatedNodeIds: const ['note-1'],
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'note-1',
          type: NodeType.note,
          title: 'Release context',
          day: tomorrow,
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'goal-1',
          type: NodeType.goal,
          title: 'Ship v1',
          day: tomorrow,
          relatedNodeIds: const ['task-1'],
          now: DateTime(2026, 6, 18, 10),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GraphPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Select the list view tab
    await _openExplorerList(tester);

    expect(find.text('Graph'), findsOneWidget);
    expect(find.text('3 nodes'), findsOneWidget);
    expect(find.text('2 links'), findsOneWidget);
    expect(find.text('2 cross-day'), findsOneWidget);
    expect(find.text('Launch task'), findsWidgets);
    expect(find.text('2 connections'), findsOneWidget);
    await _expectGraphText(tester, 'Launch task -> Release context');
    await _expectGraphText(tester, 'Ship v1 -> Launch task');
  });

  testWidgets('GraphPage collapses overview and diagnostics panels', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-1',
          type: NodeType.task,
          title: 'Launch task',
          day: today,
          relatedNodeIds: const ['note-1'],
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'note-1',
          type: NodeType.note,
          title: 'Release context',
          day: today,
          now: DateTime(2026, 6, 18, 9),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GraphPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Show overview'), findsOneWidget);
    expect(find.text('Map overview'), findsNothing);
    expect(find.text('Show diagnostics'), findsOneWidget);
    expect(find.text('Relationship intel'), findsNothing);

    await tester.tap(find.text('Show overview'));
    await tester.pumpAndSettle();
    expect(find.text('Map overview'), findsOneWidget);
    expect(find.text('Hide overview'), findsOneWidget);

    await tester.ensureVisible(find.text('Show diagnostics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Relationship intel'), findsOneWidget);
    expect(find.text('Hide diagnostics'), findsOneWidget);
  });

  testWidgets('GraphPage collapses filter band until toggled', (tester) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-1',
          type: NodeType.task,
          title: 'Launch task',
          day: today,
          now: DateTime(2026, 6, 18, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GraphPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Show filters'), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-type-task')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('graph-filter-band-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('Hide filters'), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-type-task')), findsOneWidget);
  });

  testWidgets('Graph visual controls stay collapsed until toggled', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final graph = NodeGraph.fromNodes([
      MindmapNode.create(
        id: 'task-1',
        type: NodeType.task,
        title: 'Launch task',
        day: today,
        relatedNodeIds: const ['note-1'],
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'note-1',
        type: NodeType.note,
        title: 'Release context',
        day: today,
        now: DateTime(2026, 6, 18, 9),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisualGraphView(
            nodes: graph.nodes,
            edges: graph.edges,
            onNodeTapped: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show graph controls'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsNothing);

    await tester.tap(find.byTooltip('Show graph controls'));
    await tester.pumpAndSettle();

    expect(
      find.text('Drag to pan, pinch to zoom, tap node for details'),
      findsOneWidget,
    );
    expect(find.byTooltip('Zoom out'), findsOneWidget);
    expect(find.byTooltip('Reset graph view'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byTooltip('Show graph node list'), findsOneWidget);

    await tester.tap(find.byTooltip('Show graph node list'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Graph nodes'), findsOneWidget);
    expect(find.text('Launch task'), findsOneWidget);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reset graph view'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Hide graph controls'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show graph controls'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsNothing);
  });

  testWidgets('Graph visual node details stay hidden until node selected', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final graph = NodeGraph.fromNodes([
      MindmapNode.create(
        id: 'task-1',
        type: NodeType.task,
        title: 'Launch task',
        day: today,
        relatedNodeIds: const ['note-1'],
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'note-1',
        type: NodeType.note,
        title: 'Release context',
        day: today,
        now: DateTime(2026, 6, 18, 9),
      ),
    ]);
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisualGraphView(
            nodes: graph.nodes,
            edges: graph.edges,
            onNodeTapped: (_) => opened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final drawer = find.byKey(const ValueKey('graph-node-detail-drawer'));
    expect(drawer, findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisualGraphView(
            key: const ValueKey('selected-graph'),
            nodes: graph.nodes,
            edges: graph.edges,
            initialSelectedNodeId: 'task-1',
            onNodeTapped: (_) => opened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(drawer, findsOneWidget);
    expect(
      find.byKey(const ValueKey('graph-node-detail-open-day')),
      findsOneWidget,
    );
    expect(opened, isFalse);

    await tester.tap(find.byKey(const ValueKey('graph-node-detail-open-day')));
    await tester.pumpAndSettle();
    expect(opened, isTrue);

    await tester.tap(find.byTooltip('Close node details'));
    await tester.pumpAndSettle();
    expect(drawer, findsNothing);
  });

  testWidgets('GraphPage searches and filters graph relationships', (
    tester,
  ) async {
    final repository = InMemoryMindmapRepository(
      seedNodes: _buildExplorerNodes(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GraphPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Select the list view tab
    await _openExplorerList(tester);
    await _openGraphFilters(tester);

    expect(find.byKey(const ValueKey('graph-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-type-habit')), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-cross-day-only')), findsOneWidget);
    expect(find.text('6 nodes'), findsOneWidget);
    expect(find.text('4 links'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('graph-search-field')),
      'ship',
    );
    await tester.pumpAndSettle();

    expect(find.text('1 match'), findsOneWidget);
    expect(find.text('Ship v1 -> Launch task'), findsOneWidget);
    expect(find.text('Launch task -> Release context'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('graph-search-field')),
      '',
    );
    await tester.pumpAndSettle();
    await _tapKey(tester, 'graph-type-habit');
    await tester.pumpAndSettle();

    expect(find.text('Launch task -> Daily standup'), findsOneWidget);
    expect(find.text('Ship v1 -> Launch task'), findsNothing);

    await _tapKey(tester, 'graph-cross-day-only');
    await tester.pumpAndSettle();

    expect(find.text('0 links'), findsOneWidget);
    expect(find.text('No links in this view'), findsOneWidget);
  });

  testWidgets('GraphPage opens focused node as day highlight', (tester) async {
    final repository = InMemoryMindmapRepository(
      seedNodes: _buildExplorerNodes(),
    );
    final router = GoRouter(
      initialLocation: '/graph',
      routes: [
        GoRoute(path: '/graph', builder: (_, _) => const GraphPage()),
        GoRoute(
          path: '/calendar/:date',
          builder: (_, state) => Text(
            'day=${state.pathParameters['date']} highlight=${state.uri.queryParameters['highlight']}',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await _openExplorerList(tester);
    await _openGraphFilters(tester);

    final focusButton = find.byKey(const ValueKey('graph-focus-node-task-1'));
    await tester.ensureVisible(focusButton);
    await tester.tap(focusButton);
    await tester.pumpAndSettle();
    final openNode = find.widgetWithText(ActionChip, 'Open inline');
    await tester.ensureVisible(openNode);
    await tester.tap(openNode);
    await tester.pumpAndSettle();

    expect(find.text('day=2026-06-18 highlight=task-1'), findsOneWidget);
  });

  testWidgets('GraphPage focuses a node neighborhood', (tester) async {
    final repository = InMemoryMindmapRepository(
      seedNodes: _buildExplorerNodes(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GraphPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Select the list view tab
    await _openExplorerList(tester);
    await _openGraphFilters(tester);

    await _expectGraphText(tester, 'Side plan -> Archive idea');

    final focusButton = find.byKey(const ValueKey('graph-focus-node-task-1'));
    await tester.ensureVisible(focusButton);
    await tester.pumpAndSettle();
    await tester.tap(focusButton);
    await tester.pumpAndSettle();

    await _expectGraphText(tester, 'Neighborhood: Launch task');
    await _expectGraphText(tester, 'Related out');
    await _expectGraphText(tester, 'Backlinks in');
    expect(find.text('2 related'), findsOneWidget);
    expect(find.text('1 backlink'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('graph-neighborhood-related-habit-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('graph-neighborhood-backlink-goal-1')),
      findsOneWidget,
    );
    expect(find.text('Launch task -> Daily standup'), findsOneWidget);
    expect(find.text('Side plan -> Archive idea'), findsNothing);

    final clearFocusButton = find.byKey(const ValueKey('graph-clear-focus'));
    await tester.ensureVisible(clearFocusButton);
    await tester.pumpAndSettle();
    await tester.tap(clearFocusButton);
    await tester.pumpAndSettle();

    await _expectGraphText(tester, 'Side plan -> Archive idea');
  });

  testWidgets('GraphPage filters relationships by workspace metadata', (
    tester,
  ) async {
    final repository = InMemoryMindmapRepository(
      seedNodes: _buildExplorerNodes(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GraphPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Select the list view tab
    await _openExplorerList(tester);
    await _openGraphFilters(tester);

    expect(
      find.byKey(const ValueKey('graph-project-launch-app')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('graph-area-work')), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-tag-work')), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-priority-high')), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-status-doing')), findsOneWidget);

    await _tapKey(tester, 'graph-project-launch-app');
    await tester.pumpAndSettle();
    await _tapKey(tester, 'graph-tag-work');
    await tester.pumpAndSettle();
    await _tapKey(tester, 'graph-priority-high');
    await tester.pumpAndSettle();
    await _tapKey(tester, 'graph-status-doing');
    await tester.pumpAndSettle();

    expect(find.text('1 match'), findsOneWidget);
    expect(find.text('4 filters'), findsWidgets);
    expect(find.text('Launch task -> Daily standup'), findsOneWidget);
    expect(find.text('Ship v1 -> Launch task'), findsOneWidget);
    expect(find.text('Side plan -> Archive idea'), findsNothing);

    await _tapKey(tester, 'graph-clear-filters');
    await tester.pumpAndSettle();

    await _tapKey(tester, 'graph-area-work');
    await tester.pumpAndSettle();

    expect(find.text('2 matches'), findsOneWidget);
    expect(find.text('Launch task -> Daily standup'), findsOneWidget);
    expect(find.text('Launch task -> Release context'), findsOneWidget);
    expect(find.text('Ship v1 -> Launch task'), findsNothing);
  });
  testWidgets('GraphPage rejects invalid saved filter JSON', (tester) async {
    final repository = InMemoryMindmapRepository(
      seedNodes: _buildExplorerNodes(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: GraphPage()),
      ),
    );
    await tester.pumpAndSettle();
    await _openGraphFilters(tester);

    await tester.tap(find.byTooltip('Graph filter import/export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import JSON'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Graph filters JSON',
      ),
      '{not valid json}',
    );
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid graph filters JSON'), findsOneWidget);
  });
}

Future<void> _pumpGraphPage(
  WidgetTester tester, {
  required double width,
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection textDirection = TextDirection.ltr,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  final repository = InMemoryMindmapRepository(
    seedNodes: _buildExplorerNodes(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: textScaler,
            disableAnimations: disableAnimations,
            accessibleNavigation: accessibleNavigation,
          ),
          child: Directionality(
            textDirection: textDirection,
            child: const GraphPage(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openGraphFilters(WidgetTester tester) async {
  final toggle = find.byKey(const ValueKey('graph-filter-band-toggle'));
  if (find.text('Show filters').evaluate().isEmpty ||
      toggle.evaluate().isEmpty) {
    return;
  }
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey<String>(key));
  if (finder.evaluate().isEmpty) {
    final toggle = find.byKey(const ValueKey('graph-filter-band-toggle'));
    if (toggle.evaluate().isNotEmpty) {
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openExplorerList(WidgetTester tester) async {
  final tab = find.text('Explorer List');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<void> _expectGraphText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }
  expect(finder, findsOneWidget);
}

List<MindmapNode> _buildExplorerNodes() {
  final today = DateTime(2026, 6, 18);
  final tomorrow = DateTime(2026, 6, 19);
  return [
    MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Launch task',
      body: 'Coordinate release work',
      day: today,
      status: NodeStatus.doing,
      priority: NodePriority.high,
      project: 'Launch App',
      tags: const ['work', 'release'],
      relatedNodeIds: const ['note-1', 'habit-1'],
      now: DateTime(2026, 6, 18, 8),
    ),
    MindmapNode.create(
      id: 'note-1',
      type: NodeType.note,
      title: 'Release context',
      body: 'Launch checklist',
      day: tomorrow,
      area: 'Work',
      tags: const ['release'],
      now: DateTime(2026, 6, 18, 9),
    ),
    MindmapNode.create(
      id: 'habit-1',
      type: NodeType.habit,
      title: 'Daily standup',
      day: today,
      area: 'Work',
      now: DateTime(2026, 6, 18, 9, 30),
    ),
    MindmapNode.create(
      id: 'goal-1',
      type: NodeType.goal,
      title: 'Ship v1',
      day: tomorrow,
      relatedNodeIds: const ['task-1'],
      now: DateTime(2026, 6, 18, 10),
    ),
    MindmapNode.create(
      id: 'plan-1',
      type: NodeType.plan,
      title: 'Side plan',
      day: today,
      relatedNodeIds: const ['archive-1'],
      now: DateTime(2026, 6, 18, 10, 30),
    ),
    MindmapNode.create(
      id: 'archive-1',
      type: NodeType.note,
      title: 'Archive idea',
      day: today,
      isArchived: true,
      now: DateTime(2026, 6, 18, 11),
    ),
  ];
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/graph/graph_page.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.views.first;
    view.physicalSize = const Size(1024, 1024);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
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
    await tester.tap(find.text('Explorer List'));
    await tester.pumpAndSettle();

    expect(find.text('Graph'), findsOneWidget);
    expect(find.text('3 nodes'), findsOneWidget);
    expect(find.text('2 links'), findsOneWidget);
    expect(find.text('2 cross-day'), findsOneWidget);
    expect(find.text('Launch task'), findsWidgets);
    expect(find.text('2 connections'), findsOneWidget);
    await _expectGraphText(tester, 'Launch task -> Release context');
    await _expectGraphText(tester, 'Ship v1 -> Launch task');
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
    await tester.tap(find.text('Explorer List'));
    await tester.pumpAndSettle();

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
    await tester.tap(find.byKey(const ValueKey('graph-type-habit')));
    await tester.pumpAndSettle();

    expect(find.text('Launch task -> Daily standup'), findsOneWidget);
    expect(find.text('Ship v1 -> Launch task'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('graph-cross-day-only')));
    await tester.pumpAndSettle();

    expect(find.text('0 links'), findsOneWidget);
    expect(find.text('No links in this view'), findsOneWidget);
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
    await tester.tap(find.text('Explorer List'));
    await tester.pumpAndSettle();

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
    await tester.tap(find.text('Explorer List'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('graph-project-launch-app')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('graph-area-work')), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-tag-work')), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-priority-high')), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-status-doing')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('graph-project-launch-app')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('graph-tag-work')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('graph-priority-high')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('graph-status-doing')));
    await tester.pumpAndSettle();

    expect(find.text('1 match'), findsOneWidget);
    expect(find.text('4 filters'), findsOneWidget);
    expect(find.text('Launch task -> Daily standup'), findsOneWidget);
    expect(find.text('Ship v1 -> Launch task'), findsOneWidget);
    expect(find.text('Side plan -> Archive idea'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('graph-clear-filters')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('graph-area-work')));
    await tester.pumpAndSettle();

    expect(find.text('2 matches'), findsOneWidget);
    expect(find.text('Launch task -> Daily standup'), findsOneWidget);
    expect(find.text('Launch task -> Release context'), findsOneWidget);
    expect(find.text('Ship v1 -> Launch task'), findsNothing);
  });
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

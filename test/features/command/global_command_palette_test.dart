import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/command/global_command_palette.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.views.first;
    view.physicalSize = const Size(2400, 2400);
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

  testWidgets('GlobalCommandPalette searches and filters node index', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final tomorrow = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-launch',
          type: NodeType.task,
          title: 'Launch task',
          body: 'Coordinate release',
          day: today,
          status: NodeStatus.doing,
          priority: NodePriority.high,
          tags: const ['work', 'release'],
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'note-home',
          type: NodeType.note,
          title: 'Home note',
          body: 'Personal context',
          day: tomorrow,
          status: NodeStatus.planned,
          tags: const ['home'],
          now: DateTime(2026, 6, 18, 9),
        ),
      ],
    );
    MindmapNode? openedNode;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (node) {
                openedNode = node;
              },
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('global-command-search-field')),
      findsOneWidget,
    );
    expect(find.text('Launch task'), findsOneWidget);
    expect(find.text('Home note'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('global-command-search-field')),
      'release',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-type-task')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-status-doing')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-tag-release')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('global-command-date-field')),
      dayKey(today),
    );
    await tester.pumpAndSettle();

    expect(find.text('Launch task'), findsOneWidget);
    expect(find.text('Home note'), findsNothing);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-result-task-launch')),
    );
    await tester.pumpAndSettle();

    expect(openedNode?.id, 'task-launch');
  });

  testWidgets('GlobalCommandPalette quick creates a node for a date', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository();
    MindmapNode? openedNode;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (node) {
                openedNode = node;
              },
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-command-create-title-field')),
      'Command plan',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-create-type-plan')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('global-command-create-date-field')),
      dayKey(today),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-create-button')),
    );

    final nodes = await repository.listNodes(day: today);
    expect(nodes.single.title, 'Command plan');
    expect(nodes.single.type, NodeType.plan);
    expect(openedNode?.id, nodes.single.id);
  });

  testWidgets('GlobalCommandPalette quick creates rich template nodes', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository();
    MindmapNode? openedNode;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (node) {
                openedNode = node;
              },
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-template-sprint-board')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-create-button')),
    );

    final nodes = await repository.listNodes(day: today);
    final created = nodes.single;
    expect(created.title, 'Sprint board');
    expect(created.type, NodeType.kanban);
    expect(created.area, 'Work');
    expect(created.tags, ['sprint']);
    expect(created.body, contains('todo to doing to done'));
    expect(created.data['kanban'], isA<Map<String, Object?>>());
    expect(openedNode?.id, created.id);
  });

  testWidgets(
    'GlobalCommandPalette creates a rich node from the search command',
    (tester) async {
      final today = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository();
      MindmapNode? openedNode;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(repository),
            currentDateProvider.overrideWithValue(today),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GlobalCommandPalette(
                initialDate: today,
                onOpenNode: (node) {
                  openedNode = node;
                },
                onJumpToDate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('global-command-search-field')),
        'task Ship release #Work !high due:besok status:doing project:Launch_App area:Work',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('global-command-quick-create-result')),
        findsOneWidget,
      );
      expect(find.text('Create Task: Ship release'), findsOneWidget);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-quick-create-result')),
      );

      final nodes = await repository.listNodes(day: today);
      final created = nodes.single;
      expect(created.title, 'Ship release');
      expect(created.type, NodeType.task);
      expect(created.status, NodeStatus.doing);
      expect(created.priority, NodePriority.high);
      expect(created.tags, ['work']);
      expect(created.project, 'Launch App');
      expect(created.area, 'Work');
      expect(created.dueDate, DateTime(2026, 6, 19));
      expect(openedNode?.id, created.id);
    },
  );

  testWidgets('GlobalCommandPalette creates natural calendar quick add nodes', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository();
    MindmapNode? openedNode;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (node) {
                openedNode = node;
              },
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-command-search-field')),
      'meeting launch tomorrow 10:00 with Maya, Rafi #work',
    );
    await tester.pumpAndSettle();

    expect(find.text('Create Meeting: launch'), findsOneWidget);
    expect(find.textContaining('Meeting · 2 attendees'), findsOneWidget);
    expect(find.textContaining('10:00 - 11:00'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-quick-create-result')),
    );

    expect(await repository.listNodes(day: today), isEmpty);
    final nodes = await repository.listNodes(day: DateTime(2026, 6, 19));
    final created = nodes.single;
    expect(created.title, 'launch');
    expect(created.body, 'launch');
    expect(created.type, NodeType.event);
    expect(created.tags, ['work']);
    expect(created.data['calendar_kind'], 'meeting');
    expect(created.data['agenda'], 'launch');
    expect(created.data['attendees'], 'Maya\nRafi');
    expect(created.data['time_block'], containsPair('startTime', '10:00'));
    expect(created.data['time_block'], containsPair('endTime', '11:00'));
    expect(openedNode?.id, created.id);
  });

  testWidgets(
    'GlobalCommandPalette creates command nodes with progress and checklist',
    (tester) async {
      final today = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(repository),
            currentDateProvider.overrideWithValue(today),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GlobalCommandPalette(
                initialDate: today,
                onOpenNode: (_) {},
                onJumpToDate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('global-command-search-field')),
        'task Prepare launch progress:75 pin archive check:Brief_scope|Publish_notes',
      );
      await tester.pumpAndSettle();

      expect(find.text('Create Task: Prepare launch'), findsOneWidget);
      expect(find.textContaining('75% progress'), findsOneWidget);
      expect(find.textContaining('2 checklist'), findsOneWidget);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-quick-create-result')),
      );

      final nodes = await repository.listNodes(day: today);
      final created = nodes.single;
      expect(created.title, 'Prepare launch');
      expect(created.progress, 0.75);
      expect(created.isPinned, isTrue);
      expect(created.isArchived, isTrue);
      expect(created.checklist.map((item) => item.title), [
        'Brief scope',
        'Publish notes',
      ]);
    },
  );

  testWidgets('GlobalCommandPalette creates command nodes with relations', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'launch-task',
          type: NodeType.task,
          title: 'Launch task',
          day: today,
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'launch-goal',
          type: NodeType.goal,
          title: 'Launch goal',
          day: today.add(const Duration(days: 1)),
          now: DateTime(2026, 6, 18, 9),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (_) {},
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-command-search-field')),
      'note Launch retro rel:launch-task|launch-goal',
    );
    await tester.pumpAndSettle();

    expect(find.text('Create Note: Launch retro'), findsOneWidget);
    expect(find.textContaining('2 links'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-quick-create-result')),
    );

    final nodes = await repository.listNodes();
    final created = nodes.singleWhere((node) => node.title == 'Launch retro');
    expect(created.relatedNodeIds, ['launch-task', 'launch-goal']);
  });

  testWidgets('GlobalCommandPalette previews and applies selected routines', (
    tester,
  ) async {
    final monday = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();
    MindmapNode? openedNode;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: monday,
              onOpenNode: (node) {
                openedNode = node;
              },
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-apply-routines-button')),
    );

    expect(
      find.byKey(const ValueKey('global-command-routine-planner')),
      findsOneWidget,
    );
    expect(find.text('Ready to create 4'), findsOneWidget);
    expect(find.text('Existing 0'), findsOneWidget);
    expect(find.text('Not due 1'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-routine-select-weekly-review')),
    );

    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey('global-command-apply-selected-routines-button'),
      ),
    );

    var nodes = await repository.listNodes(day: monday);
    expect(
      nodes.map((node) => node.title),
      containsAll(['Daily plan', 'Daily journal', 'Workout']),
    );
    expect(nodes.map((node) => node.title), isNot(contains('Weekly review')));
    expect(nodes.every((node) => node.tags.contains('routine')), isTrue);
    expect(openedNode?.id, 'routine-daily-plan-${dayKey(monday)}');
    expect(find.text('Ready to create 1'), findsOneWidget);
    expect(find.text('Existing 3'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey('global-command-apply-selected-routines-button'),
      ),
    );

    nodes = await repository.listNodes(day: monday);
    expect(nodes.length, 4);
    expect(nodes.map((node) => node.title), contains('Weekly review'));
  });

  testWidgets(
    'GlobalCommandPalette quick create inherits active context filters',
    (tester) async {
      final today = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'launch-seed',
            type: NodeType.task,
            title: 'Launch seed',
            day: today,
            status: NodeStatus.doing,
            project: 'Launch App',
            tags: const ['release'],
            now: DateTime(2026, 6, 18, 8),
          ),
        ],
      );
      MindmapNode? openedNode;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: GlobalCommandPalette(
                initialDate: today,
                onOpenNode: (node) {
                  openedNode = node;
                },
                onJumpToDate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-project-launch-app')),
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-tag-release')),
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-status-doing')),
      );

      await tester.enterText(
        find.byKey(const ValueKey('global-command-create-title-field')),
        'Context task',
      );
      await tester.enterText(
        find.byKey(const ValueKey('global-command-create-date-field')),
        dayKey(today),
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-create-button')),
      );

      final nodes = await repository.listNodes(day: today);
      final created = nodes.singleWhere((node) => node.title == 'Context task');
      expect(created.project, 'Launch App');
      expect(created.tags, ['release']);
      expect(created.status, NodeStatus.doing);
      expect(openedNode?.id, created.id);
      expect(openedNode?.project, 'Launch App');
    },
  );

  testWidgets('GlobalCommandPalette quick create inherits typed query filters', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository();
    MindmapNode? openedNode;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (node) {
                openedNode = node;
              },
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-command-search-field')),
      'type:goal status:doing !high project:Launch_App area:Work #release due:today',
    );
    await tester.enterText(
      find.byKey(const ValueKey('global-command-create-title-field')),
      'Typed context goal',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-create-button')),
    );

    final nodes = await repository.listNodes(day: today);
    final created = nodes.single;
    expect(created.title, 'Typed context goal');
    expect(created.type, NodeType.goal);
    expect(created.status, NodeStatus.doing);
    expect(created.priority, NodePriority.high);
    expect(created.project, 'Launch App');
    expect(created.area, 'Work');
    expect(created.tags, ['release']);
    expect(created.dueDate, today);
    expect(openedNode?.id, created.id);
  });

  testWidgets('GlobalCommandPalette quick create inherits typed date context', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final tomorrow = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (_) {},
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-command-search-field')),
      'on:besok #planning',
    );
    await tester.enterText(
      find.byKey(const ValueKey('global-command-create-title-field')),
      'Tomorrow capture',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-create-button')),
    );

    expect(await repository.listNodes(day: today), isEmpty);
    final tomorrowNodes = await repository.listNodes(day: tomorrow);
    expect(tomorrowNodes.single.title, 'Tomorrow capture');
    expect(tomorrowNodes.single.day, tomorrow);
    expect(tomorrowNodes.single.tags, ['planning']);
  });

  testWidgets(
    'GlobalCommandPalette quick create inherits typed relation context',
    (tester) async {
      final today = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(repository),
            currentDateProvider.overrideWithValue(today),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GlobalCommandPalette(
                initialDate: today,
                onOpenNode: (_) {},
                onJumpToDate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('global-command-search-field')),
        'rel:launch-task|launch-goal',
      );
      await tester.enterText(
        find.byKey(const ValueKey('global-command-create-title-field')),
        'Related capture',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-create-button')),
      );

      final nodes = await repository.listNodes(day: today);
      expect(nodes.single.relatedNodeIds, ['launch-task', 'launch-goal']);
    },
  );

  testWidgets(
    'GlobalCommandPalette quick create inherits active smart view metadata',
    (tester) async {
      final today = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'high-seed',
            type: NodeType.task,
            title: 'High seed',
            day: today,
            priority: NodePriority.high,
            now: DateTime(2026, 6, 18, 8),
          ),
          MindmapNode.create(
            id: 'pinned-seed',
            type: NodeType.note,
            title: 'Pinned seed',
            day: today,
            isPinned: true,
            now: DateTime(2026, 6, 18, 9),
          ),
          MindmapNode.create(
            id: 'archived-seed',
            type: NodeType.note,
            title: 'Archived seed',
            day: today,
            isArchived: true,
            now: DateTime(2026, 6, 18, 10),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(repository),
            currentDateProvider.overrideWithValue(today),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GlobalCommandPalette(
                initialDate: today,
                onOpenNode: (_) {},
                onJumpToDate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final highPriorityView = find.byKey(
        const ValueKey('global-command-view-highPriority'),
      );
      await tester.ensureVisible(highPriorityView);
      await tester.pumpAndSettle();
      await _tapVisible(tester, highPriorityView);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('global-command-create-title-field')),
        'Smart high task',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-create-button')),
      );

      final pinnedView = find.byKey(
        const ValueKey('global-command-view-pinned'),
      );
      await tester.ensureVisible(pinnedView);
      await tester.pumpAndSettle();
      await _tapVisible(tester, pinnedView);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('global-command-create-title-field')),
        'Smart pinned note',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-create-type-note')),
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-create-button')),
      );

      final archivedView = find.byKey(
        const ValueKey('global-command-view-archived'),
      );
      await tester.ensureVisible(archivedView);
      await tester.pumpAndSettle();
      await _tapVisible(tester, archivedView);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('global-command-create-title-field')),
        'Smart archived note',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-create-button')),
      );

      final nodes = await repository.listNodes(day: today);
      final highNode = nodes.singleWhere(
        (node) => node.title == 'Smart high task',
      );
      final pinnedNode = nodes.singleWhere(
        (node) => node.title == 'Smart pinned note',
      );
      final archivedNode = nodes.singleWhere(
        (node) => node.title == 'Smart archived note',
      );

      expect(highNode.priority, NodePriority.high);
      expect(pinnedNode.isPinned, isTrue);
      expect(archivedNode.isArchived, isTrue);
    },
  );

  testWidgets(
    'GlobalCommandPalette quick create inherits advanced smart view context',
    (tester) async {
      final today = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'due-soon-seed',
            type: NodeType.task,
            title: 'Due soon seed',
            day: today,
            dueDate: today.add(const Duration(days: 2)),
            now: DateTime(2026, 6, 18, 8),
          ),
          MindmapNode.create(
            id: 'waiting-seed',
            type: NodeType.task,
            title: 'Waiting seed',
            day: today,
            status: NodeStatus.waiting,
            now: DateTime(2026, 6, 18, 9),
          ),
          MindmapNode.create(
            id: 'routine-seed',
            type: NodeType.plan,
            title: 'Routine seed',
            day: today,
            tags: const ['routine'],
            now: DateTime(2026, 6, 18, 10),
          ),
          MindmapNode.create(
            id: 'review-seed',
            type: NodeType.journal,
            title: 'Review seed',
            day: today,
            tags: const ['review'],
            now: DateTime(2026, 6, 18, 11),
          ),
          MindmapNode.create(
            id: 'goal-seed',
            type: NodeType.goal,
            title: 'Goal seed',
            day: today,
            progress: 0.25,
            now: DateTime(2026, 6, 18, 12),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(repository),
            currentDateProvider.overrideWithValue(today),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GlobalCommandPalette(
                initialDate: today,
                onOpenNode: (_) {},
                onJumpToDate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _selectSmartViewAndCreate(
        tester,
        viewName: 'dueSoon',
        title: 'Soon action',
      );
      await _selectSmartViewAndCreate(
        tester,
        viewName: 'waiting',
        title: 'Waiting vendor',
      );
      await _selectSmartViewAndCreate(
        tester,
        viewName: 'routines',
        title: 'Routine capture',
      );
      await _selectSmartViewAndCreate(
        tester,
        viewName: 'reviews',
        title: 'Review capture',
      );
      await _selectSmartViewAndCreate(
        tester,
        viewName: 'activeGoals',
        title: 'Goal capture',
      );

      final nodes = await repository.listNodes(day: today);
      final soonNode = nodes.singleWhere((node) => node.title == 'Soon action');
      final waitingNode = nodes.singleWhere(
        (node) => node.title == 'Waiting vendor',
      );
      final routineNode = nodes.singleWhere(
        (node) => node.title == 'Routine capture',
      );
      final reviewNode = nodes.singleWhere(
        (node) => node.title == 'Review capture',
      );
      final goalNode = nodes.singleWhere(
        (node) => node.title == 'Goal capture',
      );

      expect(soonNode.dueDate, today);
      expect(waitingNode.status, NodeStatus.waiting);
      expect(routineNode.tags, contains('routine'));
      expect(reviewNode.type, NodeType.journal);
      expect(reviewNode.tags, contains('review'));
      expect(goalNode.type, NodeType.goal);
    },
  );

  testWidgets('GlobalCommandPalette jumps to the entered date', (tester) async {
    final today = DateTime(2026, 6, 18);
    final targetDate = DateTime(2026, 7, 4);
    DateTime? openedDate;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (_) {},
              onJumpToDate: (date) {
                openedDate = date;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-command-date-field')),
      dayKey(targetDate),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-jump-date-button')),
    );

    expect(openedDate, targetDate);
  });

  testWidgets(
    'GlobalCommandPalette shows jump date command from search query',
    (tester) async {
      final today = DateTime(2026, 6, 18);
      DateTime? openedDate;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(
              InMemoryMindmapRepository(),
            ),
            currentDateProvider.overrideWithValue(today),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GlobalCommandPalette(
                initialDate: today,
                onOpenNode: (_) {},
                onJumpToDate: (date) {
                  openedDate = date;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('global-command-search-field')),
        'besok',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('global-command-jump-result-2026-06-19')),
        findsOneWidget,
      );
      expect(find.text('Jump to 2026-06-19'), findsOneWidget);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('global-command-jump-result-2026-06-19')),
      );

      expect(openedDate, DateTime(2026, 6, 19));
    },
  );

  testWidgets('GlobalCommandPalette filters nodes by project and area', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'launch-task',
          type: NodeType.task,
          title: 'Launch task',
          day: today,
          project: 'Launch App',
          area: 'Work',
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'health-habit',
          type: NodeType.habit,
          title: 'Workout',
          day: today,
          area: 'Health',
          now: DateTime(2026, 6, 18, 9),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (_) {},
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-project-launch-app')),
    );

    expect(find.text('Launch task'), findsOneWidget);
    expect(find.text('Workout'), findsNothing);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('global-command-area-health')),
    );

    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Launch task'), findsNothing);
  });

  testWidgets('GlobalCommandPalette filters nodes from typed query modifiers', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final tomorrow = today.add(const Duration(days: 1));
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'launch-task',
          type: NodeType.task,
          title: 'Launch checklist',
          body: 'Release candidate',
          day: today,
          status: NodeStatus.doing,
          priority: NodePriority.high,
          project: 'Launch App',
          area: 'Work',
          tags: const ['release', 'work'],
          dueDate: today,
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'home-task',
          type: NodeType.task,
          title: 'Home checklist',
          day: today,
          status: NodeStatus.doing,
          priority: NodePriority.high,
          area: 'Home',
          tags: const ['home'],
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'launch-note',
          type: NodeType.note,
          title: 'Launch note',
          day: tomorrow,
          status: NodeStatus.planned,
          project: 'Launch App',
          area: 'Work',
          tags: const ['release'],
          now: DateTime(2026, 6, 18, 10),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (_) {},
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-command-search-field')),
      'type:task status:doing !high project:Launch_App area:Work #release due:today',
    );
    await tester.pumpAndSettle();

    expect(find.text('Launch checklist'), findsOneWidget);
    expect(find.text('Home checklist'), findsNothing);
    expect(find.text('Launch note'), findsNothing);
  });

  testWidgets(
    'GlobalCommandPalette filters nodes from typed relation modifier',
    (tester) async {
      final today = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'launch-retro',
            type: NodeType.note,
            title: 'Launch retro',
            day: today,
            relatedNodeIds: const ['launch-task'],
            now: DateTime(2026, 6, 18, 8),
          ),
          MindmapNode.create(
            id: 'home-retro',
            type: NodeType.note,
            title: 'Home retro',
            day: today,
            relatedNodeIds: const ['home-task'],
            now: DateTime(2026, 6, 18, 9),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: GlobalCommandPalette(
                initialDate: today,
                onOpenNode: (_) {},
                onJumpToDate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('global-command-search-field')),
        'rel:launch-task',
      );
      await tester.pumpAndSettle();

      expect(find.text('Launch retro'), findsOneWidget);
      expect(find.text('Home retro'), findsNothing);
    },
  );

  testWidgets('GlobalCommandPalette filters nodes by smart views', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'today-task',
          type: NodeType.task,
          title: 'Today task',
          day: today,
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'overdue-task',
          type: NodeType.task,
          title: 'Overdue task',
          day: yesterday,
          status: NodeStatus.doing,
          dueDate: yesterday,
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'pinned-note',
          type: NodeType.note,
          title: 'Pinned note',
          day: tomorrow,
          isPinned: true,
          now: DateTime(2026, 6, 18, 10),
        ),
        MindmapNode.create(
          id: 'archived-note',
          type: NodeType.note,
          title: 'Archived note',
          day: tomorrow,
          isArchived: true,
          now: DateTime(2026, 6, 18, 11),
        ),
        MindmapNode.create(
          id: 'linked-note',
          type: NodeType.note,
          title: 'Linked note',
          day: tomorrow,
          relatedNodeIds: const ['today-task'],
          now: DateTime(2026, 6, 18, 12),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (_) {},
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final overdueView = find.byKey(
      const ValueKey('global-command-view-overdue'),
    );
    await tester.ensureVisible(overdueView);
    await tester.pumpAndSettle();
    await _tapVisible(tester, overdueView);
    await tester.pumpAndSettle();

    expect(find.text('Overdue task'), findsOneWidget);
    expect(find.text('Today task'), findsNothing);
    expect(find.text('Pinned note'), findsNothing);

    final pinnedView = find.byKey(const ValueKey('global-command-view-pinned'));
    await tester.ensureVisible(pinnedView);
    await tester.pumpAndSettle();
    await tester.tap(pinnedView);
    await tester.pumpAndSettle();

    expect(find.text('Pinned note'), findsOneWidget);
    expect(find.text('Overdue task'), findsNothing);
    expect(find.text('Archived note'), findsNothing);
  });

  testWidgets('GlobalCommandPalette clears state and context via commands', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'launch-task',
          type: NodeType.task,
          title: 'Launch task',
          day: today,
          status: NodeStatus.doing,
          priority: NodePriority.high,
          project: 'Launch App',
          area: 'Work',
          tags: const ['release'],
          now: DateTime(2026, 6, 18, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (_) {},
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final command in [
      'clear status launch',
      'clear priority launch',
      'remove project launch',
      'remove area launch',
      'remove tags launch',
    ]) {
      await tester.enterText(
        find.byKey(const ValueKey('global-command-search-field')),
        command,
      );
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byType(ActionChip).first);
      await tester.pumpAndSettle();
    }

    final node = (await repository.listNodes(day: today)).single;
    expect(node.status, NodeStatus.open);
    expect(node.priority, NodePriority.none);
    expect(node.project, isEmpty);
    expect(node.area, isEmpty);
    expect(node.tags, isEmpty);
  });

  testWidgets('GlobalCommandPalette unpins and restores archived nodes', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'pinned-note',
          type: NodeType.note,
          title: 'Pinned note',
          day: today,
          isPinned: true,
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'archived-note',
          type: NodeType.note,
          title: 'Archived note',
          day: today,
          isArchived: true,
          now: DateTime(2026, 6, 18, 9),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (_) {},
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-command-search-field')),
      'unpin pinned',
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byType(ActionChip).first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('global-command-search-field')),
      'unarchive archived',
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byType(ActionChip).first);
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: today);
    final pinned = nodes.singleWhere((node) => node.id == 'pinned-note');
    final archived = nodes.singleWhere((node) => node.id == 'archived-note');
    expect(pinned.isPinned, isFalse);
    expect(archived.isArchived, isFalse);
  });

  testWidgets('GlobalCommandPalette supports keyboard navigation and actions', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-1',
          type: NodeType.task,
          title: 'First task',
          day: today,
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'task-2',
          type: NodeType.task,
          title: 'Second task',
          day: today,
          now: DateTime(2026, 6, 18, 8),
        ),
      ],
    );
    MindmapNode? openedNode;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: GlobalCommandPalette(
              initialDate: today,
              onOpenNode: (node) {
                openedNode = node;
              },
              onJumpToDate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Type query to show results
    await tester.enterText(
      find.byKey(const ValueKey('global-command-search-field')),
      'task',
    );
    await tester.pumpAndSettle();

    // Press ArrowDown to navigate
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // Press Enter to select
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(openedNode, isNotNull);
  });
}

Future<void> _selectSmartViewAndCreate(
  WidgetTester tester, {
  required String viewName,
  required String title,
}) async {
  await _tapVisible(
    tester,
    find.byKey(ValueKey('global-command-view-$viewName')),
  );
  await tester.enterText(
    find.byKey(const ValueKey('global-command-create-title-field')),
    title,
  );
  await _tapVisible(
    tester,
    find.byKey(const ValueKey('global-command-create-button')),
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final widget = tester.widget(finder);
  switch (widget) {
    case final FilterChip chip:
      chip.onSelected?.call(!chip.selected);
    case final ChoiceChip chip:
      chip.onSelected?.call(!chip.selected);
    case final ActionChip chip:
      chip.onPressed?.call();
    case final ButtonStyleButton button:
      button.onPressed?.call();
    case final IconButton button:
      button.onPressed?.call();
    default:
      await tester.tap(finder, warnIfMissed: false);
  }
  await tester.pumpAndSettle();
}

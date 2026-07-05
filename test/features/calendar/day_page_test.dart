import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/node_inbox.dart';
import 'package:var_app/features/calendar/day_page.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets(
    'DayPage reveals an archived node when opened as the highlighted node',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'active-task',
            type: NodeType.task,
            title: 'Active task',
            day: day,
            now: DateTime(2026, 6, 18, 8),
          ),
          MindmapNode.create(
            id: 'archived-note',
            type: NodeType.note,
            title: 'Archived note',
            day: day,
            isArchived: true,
            now: DateTime(2026, 6, 18, 9),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: DayPage(date: day, highlightNodeId: 'archived-note'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Active task'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Archived note'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mindmap-highlight-archived-note')),
        findsOneWidget,
      );
      expect(find.text('Archived'), findsOneWidget);
    },
  );

  testWidgets('DayPage replaces left palette rail with canvas add FAB', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Expand Palette'), findsNothing);
    expect(find.text('Node Palette'), findsNothing);
    expect(find.byTooltip('Add node'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const ValueKey('canvas-add-node-fab-hover-scale')),
          )
          .scale,
      1,
    );

    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(
      location: tester.getCenter(find.byTooltip('Add node')),
    );
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const ValueKey('canvas-add-node-fab-hover-scale')),
          )
          .scale,
      1.16,
    );

    await tester.pumpAndSettle();

    expect(find.text('Create node'), findsOneWidget);
    expect(find.text('Task'), findsWidgets);
  });

  testWidgets('DayPage table project edit does not reuse disposed controller', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await SharedPreferencesAsync().setString('day_view_mode', 'table');
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'project-node',
          type: NodeType.task,
          title: 'Project task',
          day: day,
          project: 'old',
          now: DateTime(2026, 6, 18, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('old').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'new');
    await tester.tap(find.text('Save').last);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final nodes = await repository.listNodes(day: day);
    expect(nodes.single.project, 'new');
  });

  testWidgets('DayPage quick create uses typed title instead of "New <type>"', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('day-fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText == 'Node title...'),
      ),
      'My custom task',
    );

    await tester.tap(find.text(NodeType.task.label).at(1));
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.first.title, 'My custom task');
  });

  testWidgets('DayPage quick create allows default title when empty', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('day-fab')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(NodeType.note.label).last);
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.first.type, NodeType.note);
    expect(nodes.first.title, 'New ${NodeType.note.label}');
  });

  testWidgets('DayPage quick capture parses command input', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('day-fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText == 'Node title...'),
      ),
      'task bayar listrik p1 #home',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.first.type, NodeType.task);
    expect(nodes.first.title, 'bayar listrik');
    expect(nodes.first.priority, NodePriority.high);
    expect(nodes.first.tags, ['home']);
  });

  testWidgets('DayPage floating quick capture creates parsed command', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Quick capture'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('day-quick-capture-field')),
      'note idea aplikasi baru #product',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.first.type, NodeType.note);
    expect(nodes.first.title, 'idea aplikasi baru');
    expect(nodes.first.tags, ['product']);
  });

  testWidgets(
    'DayPage floating quick capture supports hints and fallback note',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(seedNodes: const []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(home: DayPage(date: day)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quick capture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('habit workout daily'));
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('day-quick-capture-field'));
      expect(
        (tester.widget<TextField>(field).controller?.text),
        'habit workout daily',
      );

      await tester.enterText(field, 'random loose thought');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final nodes = await repository.listNodes(day: day);
      expect(nodes, hasLength(1));
      expect(nodes.first.type, NodeType.note);
      expect(nodes.first.title, 'random loose thought');
    },
  );

  testWidgets('DayPage applies day template from smart plan', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal reset'));
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(3));
    expect(nodes.every((node) => node.tags.contains('template')), isTrue);
    expect(
      nodes.every((node) => node.data['dayTemplateId'] == 'personal-reset'),
      isTrue,
    );
  });

  testWidgets('DayPage disables already applied template', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'template-marker',
          type: NodeType.task,
          title: 'Template marker',
          day: day,
          tags: const ['template'],
          data: const {'dayTemplateId': 'workday'},
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply template'));
    await tester.pumpAndSettle();

    expect(find.text('Already applied'), findsOneWidget);
    final before = await repository.listNodes(day: day);
    await tester.tap(find.text('Workday'));
    await tester.pumpAndSettle();
    final after = await repository.listNodes(day: day);
    expect(after, hasLength(before.length));
  });

  testWidgets('DayPage carry-over sheet moves unfinished prior task', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final yesterday = DateTime(2026, 6, 17);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'old-task',
          type: NodeType.task,
          title: 'Old task',
          day: yesterday,
          dueDate: yesterday,
          now: DateTime(2026, 6, 17, 9),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();

    expect(find.text('Carry over 1 items'), findsOneWidget);

    await tester.tap(find.text('Carry over 1 items'));
    await tester.pumpAndSettle();

    expect(find.text('Carry-over assistant'), findsOneWidget);
    expect(find.text('Old task'), findsWidgets);

    await tester.tap(find.byTooltip('Move to day'));
    await tester.pumpAndSettle();

    final moved = (await repository.listNodes(day: day)).single;
    expect(moved.id, 'old-task');
    expect(moved.day, day);
    expect(moved.dueDate, day);
    expect(await repository.listNodes(day: yesterday), isEmpty);
  });

  testWidgets('DayPage creates tomorrow top tasks from daily review', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final tomorrow = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'review',
          type: NodeType.journal,
          title: 'Daily review — 2026-06-18',
          day: day,
          body: '''
## Tomorrow top 3
- Write docs
- Fix sync
- Plan launch
''',
          tags: const ['daily-review'],
          now: DateTime(2026, 6, 18, 18),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();

    expect(find.text('Create tomorrow top 3'), findsOneWidget);

    await tester.tap(find.text('Create tomorrow top 3'));
    await tester.pumpAndSettle();

    final tomorrowNodes = await repository.listNodes(day: tomorrow);
    expect(tomorrowNodes.map((node) => node.title), [
      'Write docs',
      'Fix sync',
      'Plan launch',
    ]);
    expect(tomorrowNodes.first.priority, NodePriority.high);
    expect(tomorrowNodes.skip(1).map((node) => node.priority), [
      NodePriority.medium,
      NodePriority.medium,
    ]);
    expect(
      tomorrowNodes.every((node) => node.relatedNodeIds.contains('review')),
      isTrue,
    );
  });

  testWidgets('DayPage skips existing tomorrow top tasks', (tester) async {
    final day = DateTime(2026, 6, 18);
    final tomorrow = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'review',
          type: NodeType.journal,
          title: 'Daily review — 2026-06-18',
          day: day,
          body: '''
## Tomorrow top 3
- Write docs
- Fix sync
''',
          tags: const ['daily-review'],
          now: DateTime(2026, 6, 18, 18),
        ),
        MindmapNode.create(
          id: 'existing',
          type: NodeType.task,
          title: 'Write docs',
          day: tomorrow,
          tags: const ['tomorrow-top-3'],
          now: DateTime(2026, 6, 18, 19),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create tomorrow top 2'));
    await tester.pumpAndSettle();

    final tomorrowNodes = await repository.listNodes(day: tomorrow);
    expect(
      tomorrowNodes.where((node) => node.title == 'Write docs'),
      hasLength(1),
    );
    expect(
      tomorrowNodes.where((node) => node.title == 'Fix sync'),
      hasLength(1),
    );
  });

  testWidgets('DayPage inbox sheet assigns loose capture to today', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final yesterday = DateTime(2026, 6, 17);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'capture',
          type: NodeType.note,
          title: 'Loose capture',
          day: yesterday,
          data: const {inboxNodeDataKey: true},
          now: DateTime(2026, 6, 17, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inbox 1'));
    await tester.pumpAndSettle();

    expect(find.text('Loose capture'), findsOneWidget);
    await tester.tap(find.byTooltip('Assign today'));
    await tester.pumpAndSettle();

    final assigned = (await repository.listNodes(day: day)).single;
    expect(assigned.id, 'capture');
    expect(isInboxNode(assigned), isFalse);
    expect(
      assigned.data[inboxAssignedFromDataKey],
      yesterday.toIso8601String(),
    );
  });

  testWidgets('DayPage inbox sheet archives loose capture', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'capture',
          type: NodeType.note,
          title: 'Loose capture',
          day: day,
          data: const {inboxNodeDataKey: true},
          now: DateTime(2026, 6, 18, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inbox 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();

    final archived = (await repository.listNodes()).single;
    expect(archived.id, 'capture');
    expect(archived.isArchived, isTrue);
  });

  testWidgets('DayPage activity log shows recent created node', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('day-fab')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText == 'Node title...'),
      ),
      'Activity task',
    );
    await tester.tap(find.text(NodeType.task.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Activity log'));
    await tester.pumpAndSettle();

    expect(find.text('Activity log'), findsOneWidget);
    expect(find.text('Created node'), findsOneWidget);
    expect(find.textContaining('Activity task'), findsOneWidget);
  });

  testWidgets('DayPage blank board starter can be hidden', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blank board'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide blank board starters'));
    await tester.pumpAndSettle();

    expect(find.text('Blank board'), findsNothing);
  });

  testWidgets('DayPage empty state starts daily journal', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blank board'), findsOneWidget);
    expect(find.text('Plan my day'), findsOneWidget);
    expect(find.text('Import yesterday leftovers'), findsOneWidget);
    expect(find.text('Start journal'), findsOneWidget);
    expect(find.text('Apply routine'), findsOneWidget);
    expect(find.text('Use template'), findsOneWidget);
    expect(find.text('Quick capture'), findsOneWidget);

    await tester.tap(find.text('Start journal'));
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(nodes, hasLength(1));
    expect(nodes.single.type, NodeType.journal);
    expect(nodes.single.tags, contains('daily-review'));
  });

  testWidgets('DayPage selected node actions mark done and create follow-up', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task',
          type: NodeType.task,
          title: 'Selected task',
          day: day,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Selected task'));
    await tester.pumpAndSettle();

    expect(find.text('Node tools'), findsOneWidget);
    final hideTools = find.byTooltip('Hide node tools');
    expect(hideTools, findsOneWidget);
    await tester.tap(hideTools);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ActionChip, 'Mark done'), findsNothing);
    expect(find.textContaining('tools hidden'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Show'));
    await tester.pumpAndSettle();

    final markDoneAction = find.widgetWithText(ActionChip, 'Mark done');
    expect(markDoneAction, findsOneWidget);
    tester.widget<ActionChip>(markDoneAction).onPressed!();
    await tester.pumpAndSettle();

    final task = (await repository.listNodes(day: day)).single;
    expect(task.isDone, isTrue);

    final followUpAction = find.widgetWithText(ActionChip, 'Follow-up');
    expect(followUpAction, findsOneWidget);
    tester.widget<ActionChip>(followUpAction).onPressed!();
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: day);
    expect(
      nodes.map((node) => node.title),
      contains('Follow-up: Selected task'),
    );
  });

  testWidgets('DayPage context switcher filters visible nodes', (tester) async {
    final day = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'launch-task',
          type: NodeType.task,
          title: 'Launch task',
          day: day,
          project: 'launch',
        ),
        MindmapNode.create(
          id: 'personal-task',
          type: NodeType.task,
          title: 'Personal task',
          day: day,
          area: 'personal',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: DayPage(date: day)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Launch task'), findsOneWidget);
    expect(find.text('Personal task'), findsOneWidget);

    await tester.tap(find.byTooltip('Day context'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project: launch').last);
    await tester.pumpAndSettle();

    expect(find.text('Launch task'), findsOneWidget);
    expect(find.text('Personal task'), findsNothing);
    expect(find.text('Context: Project: launch'), findsOneWidget);
  });
}

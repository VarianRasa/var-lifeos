import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/calendar_view_controller.dart';
import 'package:var_app/features/calendar/calendar_page.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/workspace_context.dart';
import 'package:var_app/features/workspace/data/workspace_title_repository.dart';

MindmapNode _taskNode({
  required String id,
  required String title,
  required DateTime day,
}) {
  return MindmapNode.create(
    id: id,
    type: NodeType.task,
    title: title,
    day: day,
    now: DateTime(day.year, day.month, day.day, 8),
  );
}

Future<void> _pumpCalendar(
  WidgetTester tester, {
  required InMemoryMindmapRepository repository,
  required DateTime today,
  ProviderContainer? container,
}) async {
  const child = MaterialApp(home: Scaffold(body: CalendarPage()));
  if (container != null) {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: child),
    );
  } else {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: child,
      ),
    );
  }
  await tester.pumpAndSettle();
}

void _setLargeCalendarSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('calendarViewModeProvider defaults to month', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(calendarViewModeProvider), CalendarViewMode.month);
    expect(container.read(agendaFilterProvider), AgendaFilter.all);
  });

  test(
    'calendar preferences persist selected view and agenda filter',
    () async {
      final first = ProviderContainer();
      addTearDown(first.dispose);

      await first
          .read(calendarViewModeProvider.notifier)
          .setViewMode(CalendarViewMode.agenda);
      await first
          .read(agendaFilterProvider.notifier)
          .setFilter(AgendaFilter.habits);

      final second = ProviderContainer();
      addTearDown(second.dispose);
      second.read(calendarViewModeProvider);
      second.read(agendaFilterProvider);
      await Future<void>.delayed(Duration.zero);

      expect(second.read(calendarViewModeProvider), CalendarViewMode.agenda);
      expect(second.read(agendaFilterProvider), AgendaFilter.habits);
    },
  );

  testWidgets('CalendarPage switches between week and agenda views', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        _taskNode(id: 'agenda-task', title: 'Agenda task', day: today),
      ],
    );

    await _pumpCalendar(tester, repository: repository, today: today);

    expect(find.byKey(const ValueKey('calendar-month-grid')), findsOneWidget);

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-week-grid')), findsOneWidget);

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-agenda-list')), findsOneWidget);
    expect(find.text('Agenda task'), findsOneWidget);
  });

  testWidgets('CalendarPage agenda can move node to another date', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'agenda-task',
          type: NodeType.task,
          title: 'Agenda task',
          day: today,
          now: DateTime(2026, 6, 19, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('calendar-agenda-move-agenda-task')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('22'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final moved = await repository.getNode('agenda-task');
    expect(moved?.day, DateTime(2026, 6, 22));
    expect(find.text('Moved "Agenda task" to Jun 22, 2026'), findsOneWidget);
  });

  testWidgets('CalendarPage move snackbar undo restores original day', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_taskNode(id: 'undo-task', title: 'Undo task', day: today)],
    );

    await _pumpCalendar(tester, repository: repository, today: today);

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('calendar-agenda-move-undo-task')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('22'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect((await repository.getNode('undo-task'))?.day, DateTime(2026, 6, 22));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect((await repository.getNode('undo-task'))?.day, today);
  });

  testWidgets('CalendarPage week drag moves node to target day', (
    tester,
  ) async {
    _setLargeCalendarSurface(tester);

    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_taskNode(id: 'week-task', title: 'Week task', day: today)],
    );

    await _pumpCalendar(tester, repository: repository, today: today);

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    final dragFinder = find.byKey(
      const ValueKey('calendar-draggable-node-week-task'),
    );
    final dropFinder = find.byKey(const ValueKey('calendar-drop-2026-06-18'));
    final gesture = await tester.startGesture(tester.getCenter(dragFinder));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(dropFinder));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final moved = await repository.getNode('week-task');
    expect(moved?.day, DateTime(2026, 6, 18));
    expect(find.text('Moved "Week task" to Jun 18, 2026'), findsOneWidget);
  });

  testWidgets('CalendarPage week drag ignores same-day drop', (tester) async {
    _setLargeCalendarSurface(tester);

    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'same-day-task',
          type: NodeType.task,
          title: 'Same day task',
          day: today,
          now: DateTime(2026, 6, 19, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    final dragFinder = find.byKey(
      const ValueKey('calendar-draggable-node-same-day-task'),
    );
    final dropFinder = find.byKey(const ValueKey('calendar-drop-2026-06-19'));
    final gesture = await tester.startGesture(tester.getCenter(dragFinder));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(dropFinder));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final node = await repository.getNode('same-day-task');
    expect(node?.day, today);
    expect(find.textContaining('Moved "Same day task"'), findsNothing);
  });

  testWidgets('CalendarPage month drag moves node to target day', (
    tester,
  ) async {
    _setLargeCalendarSurface(tester);

    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [_taskNode(id: 'month-task', title: 'Month task', day: today)],
    );

    await _pumpCalendar(tester, repository: repository, today: today);

    expect(find.byKey(const ValueKey('calendar-month-grid')), findsOneWidget);
    final dragFinder = find.byKey(
      const ValueKey('calendar-draggable-node-month-task'),
    );
    final dropFinder = find.byKey(const ValueKey('calendar-drop-2026-06-24'));
    final gesture = await tester.startGesture(tester.getCenter(dragFinder));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(dropFinder));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final moved = await repository.getNode('month-task');
    expect(moved?.day, DateTime(2026, 6, 24));
    expect(find.text('Moved "Month task" to Jun 24, 2026'), findsOneWidget);
  });

  testWidgets('CalendarPage agenda shift arrow moves selected node', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        _taskNode(id: 'keyboard-task', title: 'Keyboard task', day: today),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        mindmapRepositoryProvider.overrideWithValue(repository),
        currentDateProvider.overrideWithValue(today),
      ],
    );
    addTearDown(container.dispose);

    await _pumpCalendar(
      tester,
      repository: repository,
      today: today,
      container: container,
    );

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('calendar-agenda-select-keyboard-task')),
    );
    await tester.pumpAndSettle();
    expect(container.read(selectedAgendaNodeIdProvider), 'keyboard-task');
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    final moved = await repository.getNode('keyboard-task');
    expect(moved?.day, DateTime(2026, 6, 20));
    expect(find.text('Moved "Keyboard task" to Jun 20, 2026'), findsOneWidget);
  });

  testWidgets('CalendarPage applies today recurring routines', (tester) async {
    final today = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('calendar-routine-apply-banner')),
      findsOneWidget,
    );
    expect(find.text('4 routines ready for today'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendar-apply-routines')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('calendar-routine-apply-dialog')),
      findsOneWidget,
    );
    expect(find.text('Apply routines?'), findsOneWidget);
    expect(find.text('Daily plan'), findsOneWidget);
    expect(find.text('Weekly review'), findsOneWidget);
    expect(await repository.listNodes(day: today), isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('calendar-confirm-apply-routines')),
    );
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: today);
    expect(nodes.map((node) => node.title), contains('Daily plan'));
    expect(nodes.map((node) => node.title), contains('Weekly review'));
    expect(find.text('Applied 4 routines'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-routine-apply-banner')),
      findsNothing,
    );
  });

  testWidgets('CalendarPage applies selected recurring routines only', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-apply-routines')));
    await tester.pumpAndSettle();

    expect(find.text('4 of 4 routines selected.'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Daily journal'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 4 routines selected.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('calendar-confirm-apply-routines')),
    );
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: today);
    expect(nodes.map((node) => node.title), contains('Daily plan'));
    expect(nodes.map((node) => node.title), isNot(contains('Daily journal')));
    expect(find.text('Applied 3 routines'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-routine-apply-banner')),
      findsOneWidget,
    );
  });

  testWidgets('CalendarPage routine dialog can clear and select all', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-apply-routines')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('calendar-clear-routines')));
    await tester.pumpAndSettle();
    expect(find.text('0 of 4 routines selected.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('calendar-confirm-apply-routines')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('calendar-select-all-routines')),
    );
    await tester.pumpAndSettle();
    expect(find.text('4 of 4 routines selected.'), findsOneWidget);
  });

  testWidgets('CalendarPage skips today recurring routines', (tester) async {
    final today = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-apply-routines')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-skip-routines')));
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: today);
    expect(nodes.map((node) => node.title), contains('Skipped Daily plan'));
    expect(nodes.map((node) => node.title), isNot(contains('Daily plan')));
    expect(find.text('Skipped routine'), findsWidgets);
    expect(find.text('Skipped 4 routines today'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-routine-apply-banner')),
      findsNothing,
    );
  });

  testWidgets('CalendarPage skip undo restores routine banner', (tester) async {
    final today = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-apply-routines')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-skip-routines')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: today);
    expect(
      nodes.map((node) => node.title),
      isNot(contains('Skipped Daily plan')),
    );
    expect(
      find.byKey(const ValueKey('calendar-routine-apply-banner')),
      findsOneWidget,
    );
  });

  testWidgets('CalendarPage snoozes today recurring routines', (tester) async {
    final today = DateTime(2026, 6, 22);
    final targetDay = DateTime(2026, 6, 25);
    final repository = InMemoryMindmapRepository();

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-apply-routines')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-snooze-routines')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final todayNodes = await repository.listNodes(day: today);
    final targetNodes = await repository.listNodes(day: targetDay);
    expect(
      todayNodes.map((node) => node.title),
      contains('Snoozed Daily plan'),
    );
    expect(targetNodes, isEmpty);
    expect(
      todayNodes.first.data['automation'],
      containsPair('snoozedTo', '2026-06-25'),
    );
    expect(find.text('Snoozed routine'), findsWidgets);
    expect(find.text('Snoozed 4 routines to Jun 25, 2026'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-routine-apply-banner')),
      findsNothing,
    );
  });

  testWidgets('CalendarPage snooze undo restores routine banner', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-apply-routines')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-snooze-routines')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes(day: today);
    expect(
      nodes.map((node) => node.title),
      isNot(contains('Snoozed Daily plan')),
    );
    expect(
      find.byKey(const ValueKey('calendar-routine-apply-banner')),
      findsOneWidget,
    );
  });

  testWidgets('CalendarPage agenda filters nodes by type', (tester) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-node',
          type: NodeType.task,
          title: 'Agenda task',
          day: today,
          now: DateTime(2026, 6, 19, 8),
        ),
        MindmapNode.create(
          id: 'event-node',
          type: NodeType.note,
          title: 'Launch event',
          day: today,
          data: const {'calendar_kind': 'event'},
          now: DateTime(2026, 6, 19, 9),
        ),
        MindmapNode.create(
          id: 'habit-node',
          type: NodeType.habit,
          title: 'Drink water',
          day: today,
          now: DateTime(2026, 6, 19, 10),
        ),
        MindmapNode.create(
          id: 'routine-marker',
          type: NodeType.note,
          title: 'Skipped Daily plan',
          day: today,
          isArchived: true,
          data: const {
            'automation': {'state': 'skipped'},
          },
          now: DateTime(2026, 6, 19, 11),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    expect(find.text('Agenda task'), findsOneWidget);
    expect(find.text('Launch event'), findsOneWidget);
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Skipped Daily plan'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agenda-filter-events')));
    await tester.pumpAndSettle();
    expect(find.text('Launch event'), findsOneWidget);
    expect(find.text('Agenda task'), findsNothing);
    expect(find.text('Drink water'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('agenda-filter-habits')));
    await tester.pumpAndSettle();
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Launch event'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('agenda-filter-routines')));
    await tester.pumpAndSettle();
    expect(find.text('Skipped Daily plan'), findsOneWidget);
    expect(find.text('Skipped routine'), findsOneWidget);
    expect(find.text('Drink water'), findsNothing);
  });

  testWidgets('CalendarPage shows mobile week strip on narrow screens', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(420, 820));
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(seedNodes: []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-week-strip')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-week-grid')), findsNothing);
  });

  testWidgets('CalendarPage agenda empty state names active filter', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-node',
          type: NodeType.task,
          title: 'Agenda task',
          day: today,
          now: DateTime(2026, 6, 19, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-filter-events')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-agenda-empty')), findsOneWidget);
    expect(find.text('No event items'), findsOneWidget);
  });

  testWidgets('CalendarPage agenda empty CTA opens focused day', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(seedNodes: []);
    final router = GoRouter(
      initialLocation: '/calendar',
      routes: [
        GoRoute(
          path: '/calendar',
          builder: (context, state) => const CalendarPage(),
        ),
        GoRoute(
          path: '/calendar/:date',
          builder: (context, state) =>
              Text('day=${state.pathParameters['date']}'),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('calendar-agenda-empty-open-day')),
    );
    await tester.pumpAndSettle();

    expect(find.text('day=2026-06-19'), findsOneWidget);
  });

  testWidgets('CalendarPage keyboard shortcuts switch views and filters', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-node',
          type: NodeType.task,
          title: 'Agenda task',
          day: today,
          now: DateTime(2026, 6, 19, 8),
        ),
        MindmapNode.create(
          id: 'event-node',
          type: NodeType.note,
          title: 'Launch event',
          day: today,
          data: const {'calendar_kind': 'event'},
          now: DateTime(2026, 6, 19, 9),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-week-grid')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-agenda-list')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();
    expect(find.text('Launch event'), findsOneWidget);
    expect(find.text('Agenda task'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-month-grid')), findsOneWidget);
  });

  testWidgets('CalendarPage exposes shortcut help', (tester) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(seedNodes: []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('calendar-shortcuts-help')));
    await tester.pumpAndSettle();

    expect(find.text('Calendar shortcuts'), findsOneWidget);
    expect(find.text('Month view'), findsOneWidget);
    expect(find.text('Agenda view'), findsOneWidget);
    expect(find.text('All agenda items'), findsOneWidget);
    expect(find.text('Routines'), findsWidgets);
    expect(find.text('Done'), findsWidgets);
    expect(find.text('Shift+←'), findsOneWidget);
    expect(find.text('Shift+→'), findsOneWidget);
    expect(
      find.text('Move selected agenda item forward one day'),
      findsOneWidget,
    );
  });

  testWidgets('CalendarPage agenda item opens day with node highlight', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'agenda-task',
          type: NodeType.task,
          title: 'Agenda task',
          day: today,
          now: DateTime(2026, 6, 19, 8),
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/calendar',
      routes: [
        GoRoute(
          path: '/calendar',
          builder: (context, state) => const CalendarPage(),
        ),
        GoRoute(
          path: '/calendar/:date',
          builder: (context, state) => Text(
            'day=${state.pathParameters['date']} highlight=${state.uri.queryParameters['highlight']}',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('calendar-agenda-node-agenda-task')),
    );
    await tester.pumpAndSettle();

    expect(find.text('day=2026-06-19 highlight=agenda-task'), findsOneWidget);
  });

  testWidgets('CalendarPage agenda group action opens the day', (tester) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'agenda-task',
          type: NodeType.task,
          title: 'Agenda task',
          day: today,
          now: DateTime(2026, 6, 19, 8),
        ),
      ],
    );
    final router = GoRouter(
      initialLocation: '/calendar',
      routes: [
        GoRoute(
          path: '/calendar',
          builder: (context, state) => const CalendarPage(),
        ),
        GoRoute(
          path: '/calendar/:date',
          builder: (context, state) => Text(
            'day=${state.pathParameters['date']} highlight=${state.uri.queryParameters['highlight'] ?? ''}',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('calendar-agenda-open-2026-06-19')),
    );
    await tester.pumpAndSettle();

    expect(find.text('day=2026-06-19 highlight='), findsOneWidget);
  });

  testWidgets('CalendarPage agenda sorts timed high-priority items first', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'untimed-task',
          type: NodeType.task,
          title: 'Untimed task',
          day: today,
          now: DateTime(2026, 6, 19, 8),
        ),
        MindmapNode.create(
          id: 'timed-event',
          type: NodeType.note,
          title: 'Timed event',
          day: today,
          priority: NodePriority.high,
          status: NodeStatus.doing,
          data: const {
            'calendar_kind': 'event',
            'location': 'Office',
            'time_block': {'startTime': '09:00', 'endTime': '10:00'},
          },
          now: DateTime(2026, 6, 19, 9),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();

    expect(
      find.text('09:00 - 10:00 · Event @ Office · High · Doing'),
      findsOneWidget,
    );
    expect(find.text('Today · Fri, Jun 19'), findsOneWidget);
    expect(find.text('2 items · 1 scheduled'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Timed event')).dy,
      lessThan(tester.getTopLeft(find.text('Untimed task')).dy),
    );
  });

  testWidgets('CalendarPage navigation follows the active view mode', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(seedNodes: []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('June 2026'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-focused-2026-06-19')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar-focused-2026-06-20')),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.text('Jun 15–21, 2026'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(find.text('Jun 22–28, 2026'), findsOneWidget);

    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    expect(find.text('Next 30 days from Jun 27'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('Next 30 days from May 28'), findsOneWidget);
  });

  testWidgets(
    'CalendarPage renders custom day cell title and displays hover overlay without nodes',
    (tester) async {
      final today = DateTime(2026, 6, 19);
      final repository = InMemoryMindmapRepository(seedNodes: []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(repository),
            currentDateProvider.overrideWithValue(today),
          ],
          child: const MaterialApp(home: Scaffold(body: CalendarPage())),
        ),
      );
      await tester.pumpAndSettle();

      // Verify CalendarPage renders
      expect(find.text('Calendar'), findsOneWidget);

      // Let's seed a custom title for today's date (2026-06-19)
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(CalendarPage)),
      );
      await scope
          .read(workspaceTitleProvider.notifier)
          .setTitle(WorkspaceContextType.daily, '2026-06-19', 'Awesome Friday');
      await tester.pumpAndSettle();

      // Verify custom title is displayed directly on the day cell (which is on the screen)
      expect(find.text('Awesome Friday'), findsOneWidget);

      // Verify navigation controls are present
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // Verify date jump controls
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);

      // Hover over the day cell for 2026-06-19 to trigger overlay popup
      final cellFinder = find.byKey(const ValueKey('calendar-cell-2026-06-19'));
      expect(cellFinder, findsOneWidget);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(cellFinder));
      await tester.pumpAndSettle();

      // Verify hover overlay popped up with the custom title and full formatted date
      expect(
        find.text('Awesome Friday'),
        findsNWidgets(2),
      ); // One on cell, one in overlay popup
      expect(
        find.text(DateFormat('EEEE, MMMM d, yyyy').format(today)),
        findsOneWidget,
      );

      // Move mouse away to hide overlay
      await gesture.moveTo(const Offset(1000, 1000));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('CalendarPage deletes routine marker from actions menu', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'skip-marker-1',
          type: NodeType.note,
          title: 'Skipped Daily plan',
          day: today,
          isArchived: true,
          tags: const ['routine', 'automation-skip'],
          data: {
            'automation': {
              'routineId': 'daily-plan',
              'templateId': 'daily-plan',
              'recurrence': 'daily',
              'state': 'skipped',
            },
          },
          now: DateTime(today.year, today.month, today.day, 8),
        ),
      ],
    );

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-filter-routines')));
    await tester.pumpAndSettle();

    expect(find.text('Skipped Daily plan'), findsOneWidget);
    expect(find.text('Skipped routine'), findsOneWidget);

    // Open marker actions menu and tap Delete
    await tester.tap(
      find.byKey(
        const ValueKey('calendar-routine-marker-actions-skip-marker-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete marker'));
    await tester.pumpAndSettle();

    expect(find.text('Skipped Daily plan'), findsNothing);
    expect(
      find.byKey(const ValueKey('calendar-routine-apply-banner')),
      findsOneWidget,
    );

    final nodes = await repository.listNodes();
    expect(
      nodes.map((node) => node.title),
      isNot(contains('Skipped Daily plan')),
    );
  });

  testWidgets('CalendarPage resnoozes routine marker from actions menu', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'snooze-marker-1',
          type: NodeType.note,
          title: 'Snoozed Daily plan',
          day: today,
          isArchived: true,
          tags: const ['routine', 'automation-snooze'],
          data: {
            'automation': {
              'routineId': 'daily-plan',
              'templateId': 'daily-plan',
              'recurrence': 'daily',
              'state': 'snoozed',
              'snoozedTo': '2026-06-30',
            },
          },
          now: DateTime(today.year, today.month, today.day, 8),
        ),
      ],
    );

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-filter-routines')));
    await tester.pumpAndSettle();

    expect(find.text('Snoozed Daily plan'), findsOneWidget);
    expect(find.text('Snoozed routine'), findsOneWidget);

    // Open marker actions menu and tap Resnooze
    await tester.tap(
      find.byKey(
        const ValueKey('calendar-routine-marker-actions-snooze-marker-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resnooze'));
    await tester.pumpAndSettle();

    // Date picker opens — pick a different future date
    await tester.tap(find.text('29').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Marker exists and snoozedTo was updated
    expect(find.text('Snoozed Daily plan'), findsOneWidget);
    final nodes = await repository.listNodes();
    final marker = nodes.firstWhere((n) => n.id == 'snooze-marker-1');
    final updatedSnoozedTo =
        (marker.data['automation'] as Map)['snoozedTo'] as String;
    expect(updatedSnoozedTo, isNot('2026-06-30'));
  });

  testWidgets('CalendarPage applies routine from skipped marker actions menu', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 23);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'skip-marker-2',
          type: NodeType.note,
          title: 'Skipped Weekly review',
          day: today,
          isArchived: true,
          tags: const ['routine', 'automation-skip'],
          data: {
            'automation': {
              'routineId': 'weekly-review',
              'templateId': 'weekly-review',
              'recurrence': 'weekly',
              'state': 'skipped',
            },
          },
          now: DateTime(today.year, today.month, today.day, 8),
        ),
      ],
    );

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agenda-filter-routines')));
    await tester.pumpAndSettle();

    expect(find.text('Skipped Weekly review'), findsOneWidget);

    // Open marker actions menu and tap Apply now
    await tester.tap(
      find.byKey(
        const ValueKey('calendar-routine-marker-actions-skip-marker-2'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply now'));
    await tester.pumpAndSettle();

    // Marker deleted, routine applied — switch to All to see it
    await tester.tap(find.byKey(const ValueKey('agenda-filter-all')));
    await tester.pumpAndSettle();
    expect(find.text('Weekly review'), findsOneWidget);
    expect(find.text('Applied "Weekly review"'), findsOneWidget);

    final nodesAfter = await repository.listNodes();
    expect(
      nodesAfter.where((n) => n.title == 'Skipped Weekly review'),
      isEmpty,
    );
    expect(
      nodesAfter.where((n) => n.title == 'Weekly review' && !n.isArchived),
      isNotEmpty,
    );
  });

  testWidgets('CalendarPage day cell opens preview instead of routing', (
    tester,
  ) async {
    _setLargeCalendarSurface(tester);
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(seedNodes: []);
    final router = GoRouter(
      initialLocation: '/calendar',
      routes: [
        GoRoute(
          path: '/calendar',
          builder: (context, state) => const CalendarPage(),
        ),
        GoRoute(
          path: '/calendar/:date',
          builder: (context, state) =>
              Text('day=${state.pathParameters['date']}'),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('calendar-cell-2026-06-19')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-day-preview')), findsOneWidget);
    expect(find.text('day=2026-06-19'), findsNothing);
  });

  testWidgets('CalendarPage preview open full day routes to day', (
    tester,
  ) async {
    _setLargeCalendarSurface(tester);
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(seedNodes: []);
    final router = GoRouter(
      initialLocation: '/calendar',
      routes: [
        GoRoute(
          path: '/calendar',
          builder: (context, state) => const CalendarPage(),
        ),
        GoRoute(
          path: '/calendar/:date',
          builder: (context, state) =>
              Text('day=${state.pathParameters['date']}'),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('calendar-cell-2026-06-19')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('calendar-day-preview-open-day')),
    );
    await tester.pumpAndSettle();

    expect(find.text('day=2026-06-19'), findsOneWidget);
  });

  testWidgets('CalendarPage keyboard opens and closes day preview', (
    tester,
  ) async {
    _setLargeCalendarSurface(tester);
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(seedNodes: []);

    await _pumpCalendar(tester, repository: repository, today: today);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-day-preview')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-day-preview')), findsNothing);
  });

  testWidgets('CalendarPage preview lists nodes and summary', (tester) async {
    _setLargeCalendarSurface(tester);
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        _taskNode(id: 'preview-task', title: 'Preview task', day: today),
        MindmapNode.create(
          id: 'preview-high',
          type: NodeType.task,
          title: 'High preview task',
          day: today,
          priority: NodePriority.high,
          now: DateTime(2026, 6, 19, 9),
        ),
      ],
    );

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.byKey(const ValueKey('calendar-cell-2026-06-19')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-day-preview')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-day-preview-node-preview-task')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-day-preview-node-preview-high')),
      findsOneWidget,
    );
    expect(find.text('2 nodes'), findsWidgets);
    expect(find.text('1 high'), findsWidgets);
  });

  testWidgets('CalendarPage preview close hides panel', (tester) async {
    _setLargeCalendarSurface(tester);
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(seedNodes: []);

    await _pumpCalendar(tester, repository: repository, today: today);
    await tester.tap(find.byKey(const ValueKey('calendar-cell-2026-06-19')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-day-preview-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('calendar-day-preview')), findsNothing);
  });
}

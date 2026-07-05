import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/insights/insights_page.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/automation_rule.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/recurring_routine.dart';

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.views.first;
    view.physicalSize = const Size(1024, 1200);
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
  testWidgets('InsightsPage hides secondary dashboard panels until toggled', (
    tester,
  ) async {
    final today = DateTime(2026, 7, 2);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'done-task',
          type: NodeType.task,
          title: 'Done task',
          day: today,
          status: NodeStatus.done,
          now: DateTime(2026, 7, 2, 9),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(home: InsightsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show dashboard panels'), findsOneWidget);
    expect(find.text('Life rhythm'), findsNothing);

    await tester.tap(find.byTooltip('Show dashboard panels'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Hide dashboard panels'), findsOneWidget);
    expect(find.text('Life rhythm'), findsOneWidget);
  });

  testWidgets('InsightsPage searches and filters nodes by metadata', (
    tester,
  ) async {
    final today = DateTime.now();
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-launch',
          type: NodeType.task,
          title: 'Launch checklist',
          body: 'Coordinate the release',
          day: today,
          status: NodeStatus.doing,
          priority: NodePriority.high,
          tags: const ['work', 'release'],
          dueDate: today,
          progress: 0.5,
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'note-home',
          type: NodeType.note,
          title: 'Home note',
          body: 'Personal context',
          day: today.add(const Duration(days: 1)),
          status: NodeStatus.planned,
          priority: NodePriority.low,
          tags: const ['home'],
          now: DateTime(2026, 6, 18, 9),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('insights-search-field')), findsOneWidget);
    expect(find.text('2 nodes'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('insights-search-field')),
      'release',
    );
    await tester.pumpAndSettle();

    expect(find.text('Launch checklist'), findsOneWidget);
    expect(find.text('Home note'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('insights-priority-high')));
    await tester.tap(find.byKey(const ValueKey('insights-status-doing')));
    await tester.pumpAndSettle();

    expect(find.text('Launch checklist'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Doing'), findsOneWidget);
    expect(find.text('#release'), findsOneWidget);
    expect(find.text('Due Today'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('InsightsPage filters nodes with smart views', (tester) async {
    final today = DateTime(2026, 6, 18);
    final yesterday = today.subtract(const Duration(days: 1));
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'overdue-task',
          type: NodeType.task,
          title: 'Overdue launch',
          day: yesterday,
          status: NodeStatus.doing,
          dueDate: yesterday,
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'today-plan',
          type: NodeType.plan,
          title: 'Today plan',
          day: today,
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'linked-note',
          type: NodeType.note,
          title: 'Linked reference',
          day: today,
          relatedNodeIds: const ['today-plan'],
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
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Overdue 1'), findsOneWidget);
    expect(find.text('Linked 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('insights-smart-overdue')));
    await tester.pumpAndSettle();

    expect(find.text('Overdue launch'), findsOneWidget);
    expect(find.text('Today plan'), findsNothing);
    expect(find.text('Linked reference'), findsNothing);

    final linkedView = find.byKey(const ValueKey('insights-smart-linked'));
    await tester.ensureVisible(linkedView);
    await tester.pumpAndSettle();
    await tester.tap(linkedView);
    await tester.pumpAndSettle();

    expect(find.text('Linked reference'), findsOneWidget);
    expect(find.text('Overdue launch'), findsNothing);
  });

  testWidgets('InsightsPage filters nodes by project and area context', (
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
          id: 'launch-note',
          type: NodeType.note,
          title: 'Launch notes',
          day: today,
          project: 'Launch App',
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'health-habit',
          type: NodeType.habit,
          title: 'Workout',
          day: today,
          area: 'Health',
          now: DateTime(2026, 6, 18, 10),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Project Launch App 2'), findsOneWidget);
    expect(find.text('Area Health 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('insights-project-launch-app')));
    await tester.pumpAndSettle();
    final insightsScroll = find
        .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
        .first;
    await tester.scrollUntilVisible(
      find.text('Launch task'),
      220,
      scrollable: insightsScroll,
    );
    await tester.pumpAndSettle();

    expect(find.text('Launch task'), findsOneWidget);
    expect(find.text('Launch notes'), findsOneWidget);
    expect(find.text('Workout'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('insights-area-health')),
      -220,
      scrollable: insightsScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('insights-area-health')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Workout'),
      220,
      scrollable: insightsScroll,
    );
    await tester.pumpAndSettle();

    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Launch task'), findsNothing);
  });

  testWidgets('InsightsPage surfaces workspace focus rollups', (tester) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'launch-done',
          type: NodeType.task,
          title: 'Launch done',
          day: today,
          project: 'Launch App',
          area: 'Work',
          status: NodeStatus.done,
          priority: NodePriority.high,
          now: DateTime(2026, 6, 19, 8),
        ),
        MindmapNode.create(
          id: 'launch-overdue',
          type: NodeType.task,
          title: 'Launch overdue',
          day: today.subtract(const Duration(days: 2)),
          project: 'Launch App',
          area: 'Work',
          status: NodeStatus.doing,
          priority: NodePriority.high,
          dueDate: today.subtract(const Duration(days: 1)),
          now: DateTime(2026, 6, 19, 9),
        ),
        MindmapNode.create(
          id: 'launch-goal',
          type: NodeType.goal,
          title: 'Launch goal',
          day: today,
          project: 'Launch App',
          area: 'Work',
          progress: 0.5,
          now: DateTime(2026, 6, 19, 10),
        ),
        MindmapNode.create(
          id: 'health-habit',
          type: NodeType.habit,
          title: 'Workout',
          day: today,
          area: 'Health',
          progress: 0.25,
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
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final insightsScroll = find
        .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
        .first;
    await tester.scrollUntilVisible(
      find.text('Workspace focus'),
      220,
      scrollable: insightsScroll,
    );
    await tester.pumpAndSettle();

    expect(find.text('Workspace focus'), findsOneWidget);
    expect(find.text('Project Launch App'), findsOneWidget);
    expect(find.text('Area Work'), findsOneWidget);
    expect(
      find.text('1 overdue / 2 high / 50% progress'),
      findsAtLeastNWidgets(1),
    );
    await tester.ensureVisible(find.text('Area Health'));
    await tester.pumpAndSettle();

    expect(find.text('Area Health'), findsOneWidget);
    expect(find.text('25% progress'), findsOneWidget);
  });

  testWidgets('InsightsPage surfaces Life OS summary metrics', (tester) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'habit-1',
          type: NodeType.habit,
          title: 'Workout',
          day: today,
          data: const {
            'habit': {
              'completions': ['2026-06-16', '2026-06-17', '2026-06-18'],
            },
          },
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'goal-1',
          type: NodeType.goal,
          title: 'Launch v1',
          day: today,
          data: const {
            'goal': {
              'milestones': ['Prototype', 'Beta'],
              'completedMilestones': ['Prototype'],
            },
          },
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'journal-1',
          type: NodeType.journal,
          title: 'Daily journal',
          day: today,
          data: const {
            'journal': {'mood': 4, 'energy': 3, 'isWeeklyReview': true},
          },
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
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 habit streak'), findsOneWidget);
    expect(find.text('4.0 mood'), findsOneWidget);
    expect(find.text('50% goals'), findsOneWidget);
    expect(find.text('1 weekly review'), findsOneWidget);
  });

  testWidgets('InsightsPage surfaces Life OS rhythm panel', (tester) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'habit-1',
          type: NodeType.habit,
          title: 'Workout',
          day: today,
          data: const {
            'habit': {
              'completions': ['2026-06-14', '2026-06-16', '2026-06-18'],
            },
          },
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'habit-2',
          type: NodeType.habit,
          title: 'Read',
          day: today,
          data: const {
            'habit': {
              'completions': ['2026-06-17'],
            },
          },
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'journal-1',
          type: NodeType.journal,
          title: 'Journal one',
          day: DateTime(2026, 6, 16),
          now: DateTime(2026, 6, 16, 8),
        ),
        MindmapNode.create(
          id: 'journal-2',
          type: NodeType.journal,
          title: 'Journal two',
          day: DateTime(2026, 6, 17),
          data: const {
            'journal': {'isWeeklyReview': true},
          },
          now: DateTime(2026, 6, 17, 8),
        ),
        MindmapNode.create(
          id: 'journal-3',
          type: NodeType.journal,
          title: 'Journal three',
          day: today,
          now: DateTime(2026, 6, 18, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final insightsScroll = find
        .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
        .first;
    await tester.scrollUntilVisible(
      find.text('Life rhythm'),
      220,
      scrollable: insightsScroll,
    );
    await tester.pumpAndSettle();

    expect(find.text('Life rhythm'), findsOneWidget);
    expect(find.text('67% rhythm'), findsOneWidget);
    expect(find.text('3/7 journal days'), findsOneWidget);
    expect(find.text('4/7 habit days'), findsOneWidget);
    expect(find.text('Weekly review done'), findsOneWidget);
  });

  testWidgets('InsightsPage surfaces Life OS attention signals', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'overdue-task',
          type: NodeType.task,
          title: 'Pay invoice',
          day: today.subtract(const Duration(days: 3)),
          status: NodeStatus.doing,
          dueDate: today.subtract(const Duration(days: 1)),
          now: DateTime(2026, 6, 14, 8),
        ),
        MindmapNode.create(
          id: 'habit',
          type: NodeType.habit,
          title: 'Workout',
          day: today,
          data: const {
            'habit': {
              'recurrence': 'daily',
              'completions': ['2026-06-17'],
            },
          },
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'goal',
          type: NodeType.goal,
          title: 'Launch v1',
          day: today.subtract(const Duration(days: 20)),
          data: const {
            'goal': {
              'milestones': ['Prototype', 'Beta'],
              'completedMilestones': <String>[],
            },
          },
          now: DateTime(2026, 5, 25, 8),
        ),
        MindmapNode.create(
          id: 'journal',
          type: NodeType.journal,
          title: 'Daily journal',
          day: today,
          data: const {
            'journal': {'mood': 0, 'energy': 3},
          },
          now: DateTime(2026, 6, 18, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('1 critical'), findsOneWidget);
    expect(find.text('2 warning'), findsOneWidget);
    expect(find.text('1 info'), findsOneWidget);
    expect(find.text('Pay invoice'), findsOneWidget);
    expect(find.text('Overdue since 2026-06-17'), findsOneWidget);
    expect(find.text('Keep the streak alive today'), findsOneWidget);
    expect(find.text('No progress update in 24 days'), findsOneWidget);
    expect(find.text('Add mood and energy to complete today'), findsOneWidget);
  });

  testWidgets('InsightsPage surfaces recurring automation suggestions', (
    tester,
  ) async {
    final monday = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(monday),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('insights-automation-panel')),
      findsOneWidget,
    );
    expect(find.text('Automation'), findsOneWidget);
    expect(find.text('Review 4 automations'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('insights-automation-panel')),
        matching: find.text('Daily plan'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('insights-automation-panel')),
        matching: find.text('Weekly review'),
      ),
      findsOneWidget,
    );
    expect(find.text('Ready to create from Daily plan'), findsOneWidget);
  });

  testWidgets('InsightsPage shows the automation schedule manager', (
    tester,
  ) async {
    final tuesday = DateTime(2026, 6, 23);
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(tuesday),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review 3 automations'));
    await tester.pumpAndSettle();

    expect(find.text('Schedule manager'), findsOneWidget);
    expect(find.text('Weekly review', skipOffstage: false), findsWidgets);
    expect(find.text('Weekly Monday', skipOffstage: false), findsOneWidget);
    expect(find.text('Not due', skipOffstage: false), findsWidgets);
    expect(find.text('Next 2026-06-29', skipOffstage: false), findsOneWidget);
    expect(find.text('Monthly day 1', skipOffstage: false), findsOneWidget);
    expect(find.text('Next 2026-07-01', skipOffstage: false), findsOneWidget);
  });

  testWidgets('InsightsPage surfaces automation forecast', (tester) async {
    final tuesday = DateTime(2026, 6, 23);
    final repository = InMemoryMindmapRepository();
    await repository.saveNode(
      createAutomationRuleNode(
        id: 'daily-research',
        label: 'Daily research',
        templateId: 'research-note',
        rule: RecurringRule.daily(),
        day: tuesday,
        now: DateTime(2026, 6, 23, 8),
      ),
    );
    await repository.saveNode(
      createAutomationRuleNode(
        id: 'project-review',
        label: 'Project review',
        templateId: 'sprint-board',
        rule: RecurringRule.weekly(weekday: DateTime.friday),
        day: tuesday,
        now: DateTime(2026, 6, 23, 8),
      ),
    );
    await repository.saveNode(
      createAutomationRuleNode(
        id: 'paused-research',
        label: 'Paused research',
        templateId: 'research-note',
        rule: RecurringRule.daily(),
        enabled: false,
        day: tuesday,
        now: DateTime(2026, 6, 23, 8),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(tuesday),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final forecastPanel = find.byKey(
      const ValueKey('insights-automation-forecast-panel'),
    );
    await tester.scrollUntilVisible(
      forecastPanel,
      240,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
          .first,
    );

    expect(forecastPanel, findsOneWidget);
    expect(
      find.descendant(
        of: forecastPanel,
        matching: find.text('Automation forecast'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: forecastPanel, matching: find.text('4 tomorrow')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: forecastPanel, matching: find.text('6 next 7d')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: forecastPanel, matching: find.text('1 paused')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: forecastPanel, matching: find.text('Daily research')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: forecastPanel, matching: find.text('Project review')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: forecastPanel,
        matching: find.text('Paused: Paused research'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('InsightsPage surfaces automation health conflicts', (
    tester,
  ) async {
    final wednesday = DateTime(2026, 6, 24);
    final repository = InMemoryMindmapRepository();
    await repository.saveNode(
      createAutomationRuleNode(
        id: 'daily-startup-copy',
        label: 'Daily startup copy',
        templateId: 'daily-plan',
        rule: RecurringRule.daily(),
        day: wednesday,
        now: DateTime(2026, 6, 24, 8),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(wednesday),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final healthPanel = find.byKey(
      const ValueKey('insights-automation-health-panel'),
    );
    await tester.scrollUntilVisible(
      healthPanel,
      240,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
          .first,
    );

    expect(healthPanel, findsOneWidget);
    expect(
      find.descendant(
        of: healthPanel,
        matching: find.text('Automation health'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: healthPanel, matching: find.text('1 conflict')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: healthPanel,
        matching: find.text('Duplicate Daily plan automation'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: healthPanel,
        matching: find.text('Daily plan, Daily startup copy'),
      ),
      findsOneWidget,
    );

    final pauseAction = find.descendant(
      of: healthPanel,
      matching: find.text('Pause duplicates'),
    );
    expect(pauseAction, findsOneWidget);

    await tester.tap(pauseAction);
    await tester.pumpAndSettle();

    final ruleNode = await repository.getNode(
      'automation-rule-daily-startup-copy',
    );
    expect(ruleNode?.data['automationRule'], containsPair('enabled', false));

    final eventNode = (await repository.listNodes()).singleWhere(
      (node) => node.tags.contains('automation-event'),
    );
    expect(eventNode.isArchived, isTrue);
    expect(eventNode.data['automationEvent'], {
      'id': isA<String>(),
      'type': 'pauseDuplicateRules',
      'title': 'Paused duplicate automation rules',
      'message':
          'Paused Daily startup copy to resolve duplicate Daily plan automation.',
      'occurredAt': isA<String>(),
      'affectedRuleNodeIds': ['automation-rule-daily-startup-copy'],
      'affectedLabels': ['Daily startup copy'],
    });
    expect(
      find.byKey(const ValueKey('insights-automation-health-panel')),
      findsNothing,
    );

    final historyPanel = find.byKey(
      const ValueKey('insights-automation-history-panel'),
    );
    expect(historyPanel, findsOneWidget);
    expect(
      find.descendant(
        of: historyPanel,
        matching: find.text('Automation history'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: historyPanel,
        matching: find.text('Paused duplicate automation rules'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: historyPanel,
        matching: find.text(
          'Paused Daily startup copy to resolve duplicate Daily plan automation.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('InsightsPage creates a custom automation rule', (tester) async {
    final monday = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(monday),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review 4 automations'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('automation-center-add-rule-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('automation-rule-label-field')),
      'Daily research',
    );
    await tester.tap(find.byKey(const ValueKey('automation-rule-save-button')));
    await tester.pumpAndSettle();

    final savedNodes = await repository.listNodes();
    final ruleNode = savedNodes.singleWhere(
      (node) => node.tags.contains('automation-rule'),
    );

    expect(ruleNode.isArchived, isTrue);
    expect(
      ruleNode.data['automationRule'],
      containsPair('label', 'Daily research'),
    );
    expect(find.text('Review 5 automations'), findsOneWidget);

    await tester.tap(find.text('Review 5 automations'));
    await tester.pumpAndSettle();

    expect(find.text('Daily research', skipOffstage: false), findsWidgets);
  });

  testWidgets('InsightsPage creates automation rules from presets', (
    tester,
  ) async {
    final monday = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(monday),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review 4 automations'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('automation-center-add-rule-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('automation-rule-preset-weekly-review')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('automation-rule-save-button')));
    await tester.pumpAndSettle();

    final ruleNode = (await repository.listNodes()).singleWhere(
      (node) => node.tags.contains('automation-rule'),
    );

    expect(ruleNode.data['automationRule'], {
      'id': isA<String>(),
      'label': 'Weekly review',
      'templateId': 'weekly-review',
      'frequency': 'weekly',
      'weekday': DateTime.monday,
      'enabled': true,
    });
    expect(find.text('Review 5 automations'), findsOneWidget);
  });

  testWidgets('InsightsPage manages custom automation rules', (tester) async {
    final monday = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();
    await repository.saveNode(
      createAutomationRuleNode(
        id: 'custom-research',
        label: 'Daily research',
        templateId: 'research-note',
        rule: RecurringRule.daily(),
        day: monday,
        now: DateTime(2026, 6, 22, 8),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(monday),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review 5 automations'));
    await tester.pumpAndSettle();
    expect(find.text('Daily research', skipOffstage: false), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('automation-rule-toggle-custom-research')),
    );
    await tester.pumpAndSettle();

    final disabledNode = (await repository.listNodes()).singleWhere(
      (node) => node.id == 'automation-rule-custom-research',
    );
    expect(disabledNode.data['automationRule'], containsPair('enabled', false));
    expect(find.text('Review 4 automations'), findsOneWidget);

    await tester.tap(find.text('Review 4 automations'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('automation-rule-delete-custom-research')),
    );
    await tester.pumpAndSettle();

    expect(await repository.getNode('automation-rule-custom-research'), isNull);
    expect(find.text('Review 4 automations'), findsOneWidget);
  });

  testWidgets('InsightsPage reviews and applies selected automations', (
    tester,
  ) async {
    final monday = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(monday),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final reviewAction = find.text('Review 4 automations');
    await tester.ensureVisible(reviewAction);
    await tester.tap(reviewAction);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('automation-center-dialog')),
      findsOneWidget,
    );
    expect(find.text('Automation center'), findsOneWidget);
    expect(find.text('Apply selected 4'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('automation-center-routine-daily-journal')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apply selected 3'), findsOneWidget);

    await tester.tap(find.text('Apply selected 3'));
    await tester.pumpAndSettle();

    final createdNodes = await repository.listNodes(day: monday);
    final createdTitles = createdNodes.map((node) => node.title);

    expect(createdTitles, containsAll(['Daily plan', 'Workout']));
    expect(createdTitles, contains('Weekly review'));
    expect(createdTitles, isNot(contains('Daily journal')));
    expect(
      find.byKey(const ValueKey('automation-center-dialog')),
      findsNothing,
    );
    expect(find.text('Review 1 automation'), findsOneWidget);

    final eventNode = (await repository.listNodes()).singleWhere(
      (node) => node.tags.contains('automation-event'),
    );
    expect(eventNode.data['automationEvent'], {
      'id': isA<String>(),
      'type': 'applyRoutines',
      'title': 'Applied automation routines',
      'message': 'Applied Daily plan, Workout habit, Weekly review.',
      'occurredAt': isA<String>(),
      'affectedRuleNodeIds': <String>[],
      'affectedLabels': ['Daily plan', 'Workout habit', 'Weekly review'],
    });

    final historyPanel = find.byKey(
      const ValueKey('insights-automation-history-panel'),
    );
    await tester.scrollUntilVisible(
      historyPanel,
      240,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
          .first,
    );
    expect(
      find.descendant(
        of: historyPanel,
        matching: find.text('Applied automation routines'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('InsightsPage keeps completed automation history visible', (
    tester,
  ) async {
    final monday = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(monday),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review 4 automations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply selected 4'));
    await tester.pumpAndSettle();

    final savedNodes = await repository.listNodes(day: monday);
    expect(
      savedNodes.where((node) => !node.tags.contains('automation-event')),
      hasLength(4),
    );
    expect(
      find.byKey(const ValueKey('automation-center-dialog')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('insights-automation-panel'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text('Review automation history', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('4 completed', skipOffstage: false), findsOneWidget);

    final historyAction = find.text(
      'Review automation history',
      skipOffstage: false,
    );
    await tester.ensureVisible(historyAction);
    await tester.pumpAndSettle();
    await tester.tap(historyAction);
    await tester.pumpAndSettle();

    expect(find.text('Completed today'), findsOneWidget);
    expect(find.text('Daily plan'), findsWidgets);
  });

  testWidgets('InsightsPage skips selected automations for today', (
    tester,
  ) async {
    final monday = DateTime(2026, 6, 22);
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(monday),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review 4 automations'));
    await tester.pumpAndSettle();

    expect(find.text('Skip selected 4'), findsOneWidget);

    await tester.tap(find.text('Skip selected 4'));
    await tester.pumpAndSettle();

    final savedNodes = await repository.listNodes(day: monday);
    final markerNodes = [
      for (final node in savedNodes)
        if (!node.tags.contains('automation-event')) node,
    ];

    expect(markerNodes, hasLength(4));
    expect(markerNodes.every((node) => node.isArchived), isTrue);
    expect(
      markerNodes.every((node) => node.tags.contains('automation-skip')),
      isTrue,
    );
    expect(
      markerNodes.map((node) => node.title),
      contains('Skipped Daily plan'),
    );
    final eventNode = savedNodes.singleWhere(
      (node) => node.tags.contains('automation-event'),
    );
    expect(eventNode.data['automationEvent'], {
      'id': isA<String>(),
      'type': 'skipRoutines',
      'title': 'Skipped automation routines',
      'message':
          'Skipped Daily plan, Daily journal, Workout habit, Weekly review for 2026-06-22.',
      'occurredAt': isA<String>(),
      'affectedRuleNodeIds': <String>[],
      'affectedLabels': [
        'Daily plan',
        'Daily journal',
        'Workout habit',
        'Weekly review',
      ],
    });
    expect(
      find.byKey(const ValueKey('automation-center-dialog')),
      findsNothing,
    );
    expect(find.text('4 skipped', skipOffstage: false), findsOneWidget);

    final historyAction = find.text(
      'Review automation history',
      skipOffstage: false,
    );
    await tester.ensureVisible(historyAction);
    await tester.pumpAndSettle();
    await tester.tap(historyAction);
    await tester.pumpAndSettle();

    expect(find.text('Skipped today'), findsOneWidget);
    expect(find.text('Skipped Daily plan'), findsOneWidget);
    expect(find.text('Skipped automation routines'), findsOneWidget);
  });

  testWidgets('InsightsPage snoozes selected automations to tomorrow', (
    tester,
  ) async {
    final monday = DateTime(2026, 6, 22);
    final tuesday = DateTime(2026, 6, 23);
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(monday),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review 4 automations'));
    await tester.pumpAndSettle();

    expect(find.text('Snooze selected 4'), findsOneWidget);

    await tester.tap(find.text('Snooze selected 4'));
    await tester.pumpAndSettle();

    final savedNodes = await repository.listNodes(day: monday);
    final markerNodes = [
      for (final node in savedNodes)
        if (!node.tags.contains('automation-event')) node,
    ];

    expect(markerNodes, hasLength(4));
    expect(markerNodes.every((node) => node.isArchived), isTrue);
    expect(
      markerNodes.every((node) => node.tags.contains('automation-snooze')),
      isTrue,
    );
    expect(
      markerNodes.map((node) => node.title),
      contains('Snoozed Daily plan'),
    );
    expect(
      markerNodes.every((node) {
        final automation = node.data['automation'];
        return automation is Map && automation['snoozedTo'] == dayKey(tuesday);
      }),
      isTrue,
    );
    final eventNode = savedNodes.singleWhere(
      (node) => node.tags.contains('automation-event'),
    );
    expect(eventNode.data['automationEvent'], {
      'id': isA<String>(),
      'type': 'snoozeRoutines',
      'title': 'Snoozed automation routines',
      'message':
          'Snoozed Daily plan, Daily journal, Workout habit, Weekly review to 2026-06-23.',
      'occurredAt': isA<String>(),
      'affectedRuleNodeIds': <String>[],
      'affectedLabels': [
        'Daily plan',
        'Daily journal',
        'Workout habit',
        'Weekly review',
      ],
    });
    expect(find.text('4 snoozed', skipOffstage: false), findsOneWidget);

    final historyAction = find.text(
      'Review automation history',
      skipOffstage: false,
    );
    await tester.ensureVisible(historyAction);
    await tester.pumpAndSettle();
    await tester.tap(historyAction);
    await tester.pumpAndSettle();

    expect(find.text('Snoozed today'), findsOneWidget);
    expect(find.text('Snoozed Daily plan'), findsOneWidget);
    expect(find.text('Snoozed automation routines'), findsOneWidget);
  });

  testWidgets('InsightsPage surfaces dashboard analytics metrics', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final yesterday = today.subtract(const Duration(days: 1));
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'done-task',
          type: NodeType.task,
          title: 'Done task',
          day: today,
          status: NodeStatus.done,
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
          id: 'habit',
          type: NodeType.habit,
          title: 'Workout',
          day: today,
          data: const {
            'habit': {
              'completions': [
                '2026-06-14',
                '2026-06-15',
                '2026-06-16',
                '2026-06-17',
                '2026-06-18',
              ],
            },
          },
          now: DateTime(2026, 6, 18, 10),
        ),
        MindmapNode.create(
          id: 'goal',
          type: NodeType.goal,
          title: 'Launch v1',
          day: yesterday,
          data: const {
            'goal': {
              'milestones': ['Prototype', 'Beta'],
              'completedMilestones': ['Prototype'],
            },
          },
          now: DateTime(2026, 6, 18, 11),
        ),
        MindmapNode.create(
          id: 'monthly-journal',
          type: NodeType.journal,
          title: 'Monthly review',
          day: today,
          data: const {
            'journal': {'isMonthlyReview': true},
          },
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
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('50% task completion'), findsOneWidget);
    expect(find.text('1 overdue'), findsOneWidget);
    expect(find.text('2 productive days'), findsOneWidget);
    expect(find.text('71% habit consistency'), findsOneWidget);
    expect(find.text('2 active days'), findsOneWidget);
    expect(find.text('2.5 nodes/day'), findsOneWidget);
    expect(find.text('50% goal progress'), findsOneWidget);
    expect(find.text('1 monthly review'), findsOneWidget);
  });

  testWidgets('InsightsPage surfaces weekly pulse analytics', (tester) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'done-task',
          type: NodeType.task,
          title: 'Done task',
          day: today,
          status: NodeStatus.done,
          dueDate: today,
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'upcoming-task',
          type: NodeType.task,
          title: 'Upcoming task',
          day: today,
          dueDate: today.add(const Duration(days: 2)),
          now: DateTime(2026, 6, 18, 9),
        ),
        MindmapNode.create(
          id: 'today-note',
          type: NodeType.note,
          title: 'Today note',
          day: today,
          now: DateTime(2026, 6, 18, 10),
        ),
        MindmapNode.create(
          id: 'yesterday-habit',
          type: NodeType.habit,
          title: 'Workout',
          day: today.subtract(const Duration(days: 1)),
          now: DateTime(2026, 6, 17, 8),
        ),
        MindmapNode.create(
          id: 'week-task',
          type: NodeType.task,
          title: 'Week task',
          day: today.subtract(const Duration(days: 2)),
          status: NodeStatus.doing,
          dueDate: today.subtract(const Duration(days: 2)),
          now: DateTime(2026, 6, 16, 8),
        ),
        MindmapNode.create(
          id: 'week-journal',
          type: NodeType.journal,
          title: 'Week journal',
          day: today.subtract(const Duration(days: 2)),
          now: DateTime(2026, 6, 16, 9),
        ),
        MindmapNode.create(
          id: 'older-note',
          type: NodeType.note,
          title: 'Older note',
          day: today.subtract(const Duration(days: 4)),
          now: DateTime(2026, 6, 14, 8),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final insightsScroll = find
        .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
        .first;
    await tester.scrollUntilVisible(
      find.text('Weekly pulse'),
      220,
      scrollable: insightsScroll,
    );
    await tester.pumpAndSettle();

    expect(find.text('Weekly pulse'), findsOneWidget);
    expect(find.text('4 active / 3 quiet'), findsOneWidget);
    expect(find.text('Busiest 2026-06-18'), findsOneWidget);
    expect(find.text('1 upcoming task'), findsOneWidget);
    expect(find.text('33% week completion'), findsOneWidget);
    expect(find.text('2026-06-18 3'), findsOneWidget);
  });

  testWidgets('InsightsPage surfaces knowledge graph metrics', (tester) async {
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
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    final graphPanel = find.byKey(
      const ValueKey('insights-knowledge-graph-panel'),
    );
    expect(graphPanel, findsOneWidget);
    expect(
      find.descendant(of: graphPanel, matching: find.text('Knowledge graph')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: graphPanel, matching: find.text('3 graph nodes')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: graphPanel, matching: find.text('2 links')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: graphPanel, matching: find.text('2 cross-day')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: graphPanel, matching: find.text('Launch task')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: graphPanel, matching: find.text('2 connections')),
      findsOneWidget,
    );
  });

  testWidgets('InsightsPage shows drill-down expansion panels', (tester) async {
    final today = DateTime(2026, 7, 2);
    final yesterday = today.subtract(const Duration(days: 1));
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'late-task',
          type: NodeType.task,
          title: 'Late task detail',
          day: yesterday,
          priority: NodePriority.high,
          dueDate: yesterday,
          project: 'Launch',
          now: yesterday,
        ),
        MindmapNode.create(
          id: 'habit-risk',
          type: NodeType.habit,
          title: 'Morning routine',
          day: today,
          data: {
            'completions': [dayKey(yesterday)],
          },
          now: today,
        ),
        MindmapNode.create(
          id: 'stalled-goal',
          type: NodeType.goal,
          title: 'Stalled goal detail',
          day: today,
          now: today.subtract(const Duration(days: 20)),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('insights-drill-down-panel')),
      800,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('insights-drill-down-panel')),
      findsOneWidget,
    );

    await tester.tap(find.text('Overdue tasks detail'));
    await tester.pumpAndSettle();
    expect(find.text('Late task detail'), findsWidgets);

    await tester.tap(find.text('Project / area detail'));
    await tester.pumpAndSettle();
    expect(find.text('Launch'), findsWidgets);
  });

  testWidgets('InsightsPage shows empty state for new workspace', (
    tester,
  ) async {
    final repository = InMemoryMindmapRepository(seedNodes: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('insights-empty-state')), findsOneWidget);
    expect(find.text('No insight signals yet'), findsOneWidget);
  });

  testWidgets('InsightsPage shows loading skeleton', (tester) async {
    final completer = Completer<Never>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smartNodeViewsProvider.overrideWith((ref) => completer.future),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Loading insights'), findsWidgets);
  });

  testWidgets('InsightsPage shows retryable error state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smartNodeViewsProvider.overrideWith(
            (ref) => throw StateError('boom'),
          ),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unable to load insights'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('InsightsPage keyboard slash focuses search', (tester) async {
    final today = DateTime(2026, 7, 2);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task',
          type: NodeType.task,
          title: 'Shortcut task',
          day: today,
          now: today,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.focusNode?.hasFocus, isTrue);
    expect(find.text('T'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
  });

  testWidgets('InsightsPage keyboard export copies markdown report', (
    tester,
  ) async {
    final today = DateTime(2026, 7, 2);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task',
          type: NodeType.task,
          title: 'Export shortcut task',
          day: today,
          now: today,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle();

    expect(find.text('Markdown report copied to clipboard'), findsOneWidget);
  });

  testWidgets('InsightsPage trend panel summarizes workload totals', (
    tester,
  ) async {
    final today = DateTime(2026, 7, 2);
    final yesterday = today.subtract(const Duration(days: 1));
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'done-task',
          type: NodeType.task,
          title: 'Done trend task',
          day: today,
          status: NodeStatus.done,
          now: today,
        ),
        MindmapNode.create(
          id: 'late-high-task',
          type: NodeType.task,
          title: 'Late high trend task',
          day: yesterday,
          status: NodeStatus.doing,
          priority: NodePriority.high,
          dueDate: yesterday,
          now: yesterday,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          currentDateProvider.overrideWithValue(today),
        ],
        child: const MaterialApp(
          home: InsightsPage(initialShowDashboardPanels: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('insights-workload-trend-panel')),
      700,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Done 1'), findsOneWidget);
    expect(find.text('Open 1'), findsOneWidget);
    expect(find.text('Overdue 1'), findsOneWidget);
    expect(find.text('High 1'), findsOneWidget);
  });
}

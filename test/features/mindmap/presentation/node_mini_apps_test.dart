import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/focus/application/focus_audio_player_service.dart';
import 'package:var_app/features/mindmap/application/focus_timer_provider.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/domain/hybrid_timer.dart';
import 'package:var_app/features/mindmap/domain/kanban_board.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_mini_app_data.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/domain/project_plan.dart';
import 'package:var_app/features/mindmap/presentation/node_mini_apps/knowledge_mini_apps.dart';
import 'package:var_app/features/mindmap/presentation/node_mini_apps/life_mini_apps.dart';
import 'package:var_app/features/mindmap/presentation/node_mini_apps/node_analytics_tab.dart';
import 'package:var_app/features/mindmap/presentation/node_mini_apps/productivity_mini_apps.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  MindmapNode node(NodeType type, {Map<String, Object?> data = const {}}) =>
      MindmapNode.create(
        id: 'node-${type.name}',
        type: type,
        title: type.label,
        body: '# Heading\nBody copy',
        day: DateTime(2026, 8, 11),
        data: data,
      );

  Widget app(Widget child, {List<MindmapNode> nodes = const []}) =>
      ProviderScope(
        overrides: [
          allMindmapNodesProvider.overrideWith((ref) async => nodes),
          focusAudioPlayerServiceProvider.overrideWith(
            (ref) => _NoopFocusAudioNotifier(),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('renders productivity Task mini-app', (tester) async {
    await tester.pumpWidget(
      app(
        buildProductivityMiniApp(
          node: node(NodeType.task),
          onChanged: (_) {},
          editor: const Text('Task editor'),
        )!,
      ),
    );

    expect(find.text('Task command center'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('task-eisenhower-matrix')),
      findsOneWidget,
    );
    expect(find.text('Do now'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Delegate'), findsOneWidget);
    expect(find.text('Eliminate'), findsOneWidget);
    expect(find.text('Task editor'), findsOneWidget);
  });

  testWidgets('Task focus button selects node and starts shared timer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late ProviderContainer container;
    final task = node(NodeType.task);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusAudioPlayerServiceProvider.overrideWith(
            (ref) => _NoopFocusAudioNotifier(),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              home: Scaffold(
                body: TaskMiniApp(
                  node: task,
                  onChanged: (_) {},
                  editor: const Text('Task editor'),
                ),
              ),
            );
          },
        ),
      ),
    );

    final focusButton = find.byKey(const ValueKey('task-focus-timer-toggle'));
    await tester.ensureVisible(focusButton);
    await tester.tap(focusButton);
    await tester.pump();

    expect(container.read(focusTimerProvider).selectedNodeId, task.id);
    expect(container.read(focusTimerProvider).isRunning, isTrue);
  });

  testWidgets('Task focus switch keeps running timer active', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late ProviderContainer container;
    final first = node(NodeType.task);
    final second = MindmapNode.create(
      id: 'other-task',
      type: NodeType.task,
      title: 'Other task',
      day: DateTime(2026, 8, 11),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusAudioPlayerServiceProvider.overrideWith(
            (ref) => _NoopFocusAudioNotifier(),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              home: Scaffold(
                body: TaskMiniApp(
                  node: second,
                  onChanged: (_) {},
                  editor: const Text('Task editor'),
                ),
              ),
            );
          },
        ),
      ),
    );
    final notifier = container.read(focusTimerProvider.notifier)
      ..selectNode(first.id, first.title)
      ..start();
    await tester.pump();

    final focusButton = find.byKey(const ValueKey('task-focus-timer-toggle'));
    await tester.ensureVisible(focusButton);
    await tester.tap(focusButton);
    await tester.pump();

    expect(container.read(focusTimerProvider).selectedNodeId, second.id);
    expect(container.read(focusTimerProvider).isRunning, isTrue);
    notifier.pause();
  });

  test('Kanban CSV escapes cells and includes rich fields', () {
    const payload = KanbanPayload(
      columns: [KanbanColumnDefinition(id: 'todo', title: 'Todo', order: 0)],
      cards: [
        KanbanCard(
          id: 'a',
          title: 'Say "hello", ship',
          customColumnId: 'todo',
          priority: KanbanPriority.high,
          labels: ['release'],
        ),
      ],
    );

    final csv = kanbanBoardCsv(payload);

    expect(csv, contains('"Say ""hello"", ship"'));
    expect(csv, contains('"Todo"'));
    expect(csv, contains('"high"'));
  });

  testWidgets('Kanban mini-app renders saved swimlanes and WIP meter', (
    tester,
  ) async {
    const payload = KanbanPayload(
      columns: [
        KanbanColumnDefinition(
          id: 'doing',
          title: 'Doing',
          order: 0,
          wipLimit: 2,
        ),
      ],
      cards: [
        KanbanCard(
          id: 'a',
          title: 'Ship',
          customColumnId: 'doing',
          priority: KanbanPriority.high,
        ),
      ],
    );
    final boardNode = node(
      NodeType.kanban,
      data: payload.toData(const <String, Object?>{
        'miniApp': <String, Object?>{
          'kanban': <String, Object?>{'swimlane': 'priority'},
        },
      }),
    );

    await tester.pumpWidget(
      app(
        KanbanMiniApp(
          node: boardNode,
          onChanged: (_) {},
          editor: const Text('Kanban editor'),
        ),
      ),
    );

    expect(find.text('Doing WIP'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Ship'), findsOneWidget);
    expect(find.byKey(const ValueKey('kanban-export-png')), findsOneWidget);
  });

  testWidgets('Plan mini-app renders date-scaled Gantt task bars', (
    tester,
  ) async {
    final planNode = node(NodeType.plan);
    final project = ProjectPlan(
      startDate: DateTime(2026, 8, 1),
      targetDate: DateTime(2026, 8, 31),
      phases: <ProjectPhase>[
        ProjectPhase(
          id: 'phase',
          title: 'Delivery',
          order: 0,
          milestones: <ProjectMilestone>[
            ProjectMilestone(
              id: 'milestone',
              title: 'Beta',
              order: 0,
              tasks: <ProjectTask>[
                ProjectTask(
                  id: 'ship',
                  title: 'Ship beta',
                  order: 0,
                  startDate: DateTime(2026, 8, 10),
                  deadline: DateTime(2026, 8, 20),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final populated = planNode.copyWith(
      data: PlanPayload(project: project).toData(planNode.data),
    );

    await tester.pumpWidget(
      app(
        PlanMiniApp(
          node: populated,
          onChanged: (_) {},
          editor: const Text('Plan editor'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('plan-gantt-chart')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('plan-gantt-phase-phase')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('plan-gantt-milestone-milestone')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('plan-gantt-task-ship')), findsOneWidget);
    expect(find.text('31 days'), findsOneWidget);
  });

  test('Timer focus buckets normalize UTC timestamps to local days', () {
    final completedAt = DateTime.utc(2026, 8, 11, 23, 30);
    final record = TimerSessionRecord(
      id: 'session',
      mode: TimerMode.focus,
      label: 'Deep work',
      startedAt: completedAt.subtract(const Duration(minutes: 25)),
      completedAt: completedAt,
      plannedSeconds: 1500,
      actualSeconds: 1500,
      completed: true,
      segment: FocusSegment.focus,
    );

    final totals = timerFocusSecondsByLocalDay([record]);
    final local = completedAt.toLocal();

    expect(totals[DateTime(local.year, local.month, local.day)], 1500);
  });

  testWidgets('Timer mini-app exposes analytics, audio, and Zen view', (
    tester,
  ) async {
    final timerNode = node(NodeType.timer);
    final timer = HybridTimerState(
      history: <TimerSessionRecord>[
        TimerSessionRecord(
          id: 'session',
          mode: TimerMode.focus,
          label: 'Deep work',
          startedAt: DateTime.now().subtract(const Duration(minutes: 30)),
          completedAt: DateTime.now(),
          plannedSeconds: 1500,
          actualSeconds: 1500,
          completed: true,
          segment: FocusSegment.focus,
        ),
      ],
    );
    final populated = timerNode.copyWith(
      data: TimerPayload(timer: timer).toData(timerNode.data),
    );
    await tester.pumpWidget(
      app(
        TimerMiniApp(
          node: populated,
          onChanged: (_) {},
          editor: const Text('Timer editor'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('timer-focus-buckets')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('timer-ambient-audio-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Play ambient'), findsOneWidget);
    expect(find.text('Lofi Study Beats'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('timer-zen-fullscreen')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('timer-zen-fullscreen-page')),
      findsOneWidget,
    );
  });

  testWidgets('Note mini-app splits editor and Markdown preview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        buildKnowledgeMiniApp(
          node: node(NodeType.note),
          onChanged: (_) {},
          editor: const Text('Note editor'),
        )!,
      ),
    );

    expect(find.text('Markdown workspace'), findsOneWidget);
    expect(find.text('Heading'), findsWidgets);
    expect(
      find.byKey(const ValueKey('note-editor-preview-split')),
      findsOneWidget,
    );
    expect(find.text('Note editor'), findsOneWidget);
  });

  testWidgets('Journal mini-app and analytics aggregate recent entries', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final journals = <MindmapNode>[
      for (final entry in <(int, int, int)>[
        (20, 1, 9),
        (10, 3, 7),
        (6, 8, 4),
        (5, 8, 4),
        (4, 8, 4),
        (3, 8, 4),
        (2, 8, 4),
        (1, 8, 4),
        (0, 8, 4),
      ])
        MindmapNode.create(
          id: 'journal-${entry.$1}',
          type: NodeType.journal,
          title: 'Journal ${entry.$1}',
          day: today.subtract(Duration(days: entry.$1)),
          data: JournalPayload(
            date: today.subtract(Duration(days: entry.$1)),
            mood: entry.$2,
            energy: entry.$3,
          ).toData(const <String, Object?>{}),
        ),
    ];

    await tester.pumpWidget(
      app(
        JournalMiniApp(
          node: journals.last,
          editor: const Text('Journal editor'),
        ),
        nodes: journals,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('journal-mood-energy-trend')),
      findsOneWidget,
    );
    expect(find.text('8.0'), findsOneWidget);
    expect(find.text('4.0'), findsOneWidget);
    expect(find.text('6.7'), findsOneWidget);
    expect(find.text('4.9'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('journal-contextual-prompts')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('journal-markdown-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('journal-markdown-outline')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      app(NodeAnalyticsTab(node: journals.last), nodes: journals),
    );
    await tester.pumpAndSettle();

    expect(find.text('Journal analytics'), findsOneWidget);
    expect(find.text('6.7'), findsOneWidget);
    expect(find.text('4.9'), findsOneWidget);
  });

  testWidgets('Journal trend uses calendar-day windows', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    MindmapNode journal(String id, int daysAgo, int mood) {
      final day = today.subtract(Duration(days: daysAgo));
      return MindmapNode.create(
        id: id,
        type: NodeType.journal,
        title: id,
        day: day,
        data: JournalPayload(
          date: day,
          mood: mood,
          energy: mood,
        ).toData(const <String, Object?>{}),
      );
    }

    final current = journal('today', 0, 8);
    final boundary = journal('boundary', 29, 2);
    final stale = journal('stale', 20, 1);
    await tester.pumpWidget(
      app(
        JournalMiniApp(node: current, editor: const Text('Journal editor')),
        nodes: [stale, boundary, current],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('8.0'), findsNWidgets(2));
    expect(find.text('3.7'), findsNWidgets(2));
  });

  testWidgets('Idea mini-app renders hypothesis evidence journal', (
    tester,
  ) async {
    final base = node(NodeType.idea);
    final idea = base.copyWith(
      data: const IdeaPayload(
        maturity: 'exploring',
        hypothesis: 'Teams will adopt daily planning.',
        evidence: 'Three interviews confirmed recurring pain.',
        nextAction: 'Run a one-week pilot.',
      ).toData(base.data),
    );

    await tester.pumpWidget(
      app(IdeaMiniApp(node: idea, editor: const Text('Idea editor'))),
    );

    expect(
      find.byKey(const ValueKey('idea-validation-journal')),
      findsOneWidget,
    );
    expect(find.text('Hypothesis'), findsOneWidget);
    expect(find.text('Teams will adopt daily planning.'), findsOneWidget);
    expect(find.text('Evidence'), findsOneWidget);
    expect(
      find.text('Three interviews confirmed recurring pain.'),
      findsOneWidget,
    );
    expect(find.text('Next action'), findsOneWidget);
    expect(find.text('Run a one-week pilot.'), findsOneWidget);
  });

  test('Canvas SVG exports structured elements and arrowheads', () {
    const payload = CanvasPayload(
      elements: <CanvasElement>[
        CanvasTextElement(
          id: 'text',
          color: 'blue',
          position: CanvasPoint(0.2, 0.3),
          text: 'Ship & learn',
        ),
        CanvasShapeElement(
          id: 'shape',
          color: 'green',
          shape: 'rectangle',
          start: CanvasPoint(0.1, 0.1),
          end: CanvasPoint(0.4, 0.5),
        ),
        CanvasArrowElement(
          id: 'arrow',
          color: 'rose',
          start: CanvasPoint(0.2, 0.2),
          end: CanvasPoint(0.8, 0.8),
        ),
      ],
    );

    final svg = canvasPayloadSvg(payload);

    expect(svg, startsWith('<svg'));
    expect(svg, contains('Ship &amp; learn'));
    expect(svg, contains('<rect'));
    expect(svg, contains('marker-end="url(#arrow-rose)"'));
    expect(svg, contains('<marker id="arrow-rose"'));
  });

  testWidgets('Canvas mini-app exposes reorder and export controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final canvasNode = node(NodeType.canvas);
    const payload = CanvasPayload(
      elements: <CanvasElement>[
        CanvasTextElement(
          id: 'bottom',
          color: 'blue',
          position: CanvasPoint(0.2, 0.3),
          text: 'Bottom',
        ),
        CanvasTextElement(
          id: 'top',
          color: 'green',
          position: CanvasPoint(0.4, 0.3),
          text: 'Top',
        ),
      ],
    );
    MindmapNode? changed;
    final populated = canvasNode.copyWith(
      data: payload.toData(canvasNode.data),
    );
    await tester.pumpWidget(
      app(
        CanvasMiniApp(
          node: populated,
          onChanged: (value) => changed = value,
          editor: const Text('Canvas editor'),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Canvas export actions'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('canvas-export-svg')), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-export-png')), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('canvas-layer-list')), findsOneWidget);
    final moveUp = find.byTooltip('Move layer up').first;
    await tester.ensureVisible(moveUp);
    await tester.tap(moveUp);
    await tester.pump();
    expect(changed, isNotNull);
    expect(CanvasPayload.fromNode(changed!).elements.last.id, 'bottom');
  });

  testWidgets('Fitness mini-app builds exercises and sets', (tester) async {
    final fitNode = node(NodeType.fit);
    MindmapNode? changed;
    await tester.pumpWidget(
      app(
        FitnessMiniApp(
          node: fitNode,
          onChanged: (value) => changed = value,
          editor: const Text('Fitness editor'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('fitness-exercise-add')));
    await tester.pump();
    expect(FitPayload.fromNode(changed!).exercises, hasLength(1));

    final withExercise = changed!;
    changed = null;
    await tester.pumpWidget(
      app(
        FitnessMiniApp(
          node: withExercise,
          onChanged: (value) => changed = value,
          editor: const Text('Fitness editor'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('fitness-set-add-exercise-1')));
    await tester.pump();

    var payload = FitPayload.fromNode(changed!);
    expect(payload.exercises.single.sets.single.reps, 10);

    final withSet = changed!;
    changed = null;
    await tester.pumpWidget(
      app(
        FitnessMiniApp(
          node: withSet,
          onChanged: (value) => changed = value,
          editor: const Text('Fitness editor'),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Delete set'));
    await tester.pump();

    final withoutSet = changed!;
    changed = null;
    await tester.pumpWidget(
      app(
        FitnessMiniApp(
          node: withoutSet,
          onChanged: (value) => changed = value,
          editor: const Text('Fitness editor'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('fitness-set-add-exercise-1')));
    await tester.pump();

    payload = FitPayload.fromNode(changed!);
    expect(payload.exercises.single.sets.single.id, 'set-1');
    expect(payload.validate(title: 'Fitness'), isEmpty);
  });

  testWidgets(
    'Expense mini-app shows monthly income expense net and categories',
    (tester) async {
      final month = DateTime(2026, 8, 11);
      MindmapNode expenseNode(
        String id,
        double amount, {
        ExpenseTransactionType type = ExpenseTransactionType.expense,
        String category = 'Food',
      }) {
        final base = MindmapNode.create(
          id: id,
          type: NodeType.expense,
          title: id,
          day: month,
        );
        return base.copyWith(
          data: ExpensePayload(
            amount: amount,
            category: category,
            currency: 'USD',
            transactionType: type,
          ).toData(base.data),
        );
      }

      final food = expenseNode('food', 25);
      final salary = expenseNode(
        'salary',
        100,
        type: ExpenseTransactionType.income,
        category: 'Salary',
      );
      await tester.pumpWidget(
        app(
          ExpenseMiniApp(
            node: food,
            onChanged: (_) {},
            editor: const Text('Expense editor'),
          ),
          nodes: [food, salary],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('USD 25.00'), findsWidgets);
      expect(find.text('USD 100.00'), findsOneWidget);
      expect(find.text('USD 75.00'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('expense-monthly-category-chart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('expense-monthly-category-pie')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('expense-receipt-add')), findsNothing);
    },
  );

  testWidgets('Expense chart folds excess categories into Other', (
    tester,
  ) async {
    final month = DateTime(2026, 8, 11);
    final expenses = <MindmapNode>[
      for (var index = 0; index < 9; index++)
        () {
          final expense = MindmapNode.create(
            id: 'expense-$index',
            type: NodeType.expense,
            title: 'Expense $index',
            day: month,
          );
          return expense.copyWith(
            data: ExpensePayload(
              amount: (10 - index).toDouble(),
              category: 'Category $index',
              currency: 'USD',
            ).toData(expense.data),
          );
        }(),
    ];

    await tester.pumpWidget(
      app(
        ExpenseMiniApp(
          node: expenses.first,
          onChanged: (_) {},
          editor: const Text('Expense editor'),
        ),
        nodes: expenses,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Other ·'), findsOneWidget);
    expect(find.textContaining('Category 7 ·'), findsNothing);
    expect(find.textContaining('Category 8 ·'), findsNothing);
  });

  testWidgets('Itinerary mini-app compares planned actual and budget', (
    tester,
  ) async {
    final base = node(NodeType.itinerary);
    final itinerary = base.copyWith(
      data: ItineraryPayload(
        destination: 'Bandung',
        startDate: DateTime(2026, 8, 11),
        endDate: DateTime(2026, 8, 12),
        timezone: 'Asia/Jakarta',
        agenda: const [
          ItineraryAgendaItem(
            id: 'agenda',
            title: 'Train',
            startMinutes: 480,
            durationMinutes: 180,
            cost: 100,
          ),
        ],
        budget: 500,
        actualCost: 125,
        currency: 'USD',
      ).toData(base.data),
    );

    await tester.pumpWidget(
      app(ItineraryMiniApp(node: itinerary, editor: const Text('Editor'))),
    );

    expect(find.text('USD 100'), findsWidgets);
    expect(find.text('USD 125'), findsOneWidget);
    expect(find.text('USD 500'), findsOneWidget);
    expect(find.text('Planned budget usage'), findsOneWidget);
    expect(find.text('Actual budget usage'), findsOneWidget);
  });

  testWidgets('Expense receipt gallery exposes lifecycle actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const receipt = ResourceAsset(
      id: 'receipt-1',
      kind: 'file',
      label: 'receipt.pdf',
      attachmentId: '123e4567-e89b-12d3-a456-426614174000',
      mimeType: 'application/octet-stream',
      sizeBytes: 4,
      fileName: 'receipt.pdf',
      extension: 'pdf',
    );
    final base = node(NodeType.expense);
    final expense = base.copyWith(
      data: const ExpensePayload(
        amount: 25,
        currency: 'USD',
        receipts: [receipt],
      ).toData(base.data),
    );
    var added = false;
    var opened = false;
    var exported = false;
    var deleted = false;
    await tester.pumpWidget(
      app(
        ExpenseMiniApp(
          node: expense,
          onChanged: (_) {},
          onReceiptAdd: () async => added = true,
          onReceiptOpen: (_) async => opened = true,
          onReceiptExport: (_) async => exported = true,
          onReceiptDelete: (_) async => deleted = true,
          editor: const Text('Expense editor'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('expense-receipt-add')));
    final receiptCard = find.byKey(const ValueKey('expense-receipt-receipt-1'));
    await tester.ensureVisible(receiptCard);
    await tester.tap(receiptCard);
    final receiptActions = find.byKey(
      const ValueKey('expense-receipt-actions-receipt-1'),
    );
    await tester.ensureVisible(receiptActions);
    await tester.tap(receiptActions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(receiptActions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(added, isTrue);
    expect(opened, isTrue);
    expect(exported, isTrue);
    expect(deleted, isTrue);
  });

  testWidgets('renders Habit life mini-app and stores reminder schedule', (
    tester,
  ) async {
    MindmapNode? changed;
    await tester.pumpWidget(
      app(
        buildLifeMiniApp(
          node: node(NodeType.habit),
          onChanged: (value) => changed = value,
          editor: const Text('Habit editor'),
        )!,
      ),
    );

    expect(find.text('Habit streak lab'), findsOneWidget);
    expect(find.text('365-day consistency'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(nodeMiniAppSection(changed!, 'habit')['reminderEnabled'], isTrue);

    final enabled = changed!;
    changed = null;
    await tester.pumpWidget(
      app(
        buildLifeMiniApp(
          node: enabled,
          onChanged: (value) => changed = value,
          editor: const Text('Habit editor'),
        )!,
      ),
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '18:00'));
    await tester.pump();
    expect(nodeMiniAppSection(changed!, 'habit')['reminderTime'], '18:00');
  });

  testWidgets('renders type-aware analytics', (tester) async {
    await tester.pumpWidget(app(NodeAnalyticsTab(node: node(NodeType.idea))));

    expect(find.text('Idea analytics'), findsOneWidget);
    expect(find.text('Validation'), findsOneWidget);
  });
}

class _NoopFocusAudioNotifier extends FocusAudioPlayerNotifier {
  _NoopFocusAudioNotifier() : super(subscribeToPlayer: false);

  @override
  Future<void> play() async {}
}

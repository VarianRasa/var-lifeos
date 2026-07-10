import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/workspace_context.dart';
import 'package:var_app/features/workspace/data/workspace_title_repository.dart';
import 'package:var_app/features/workspace/workspaces_page.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('WorkspacesPage summarizes projects, areas, and next actions', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'launch-done',
          type: NodeType.task,
          title: 'Launch done',
          day: today,
          project: 'Launch App',
          status: NodeStatus.done,
          priority: NodePriority.high,
          now: DateTime(2026, 6, 19, 8),
        ),
        MindmapNode.create(
          id: 'launch-overdue',
          type: NodeType.task,
          title: 'Overdue launch task',
          day: today.subtract(const Duration(days: 1)),
          project: 'Launch App',
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
        child: const MaterialApp(home: WorkspacesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workspaces'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Areas'), findsOneWidget);
    final projectCard = find.byKey(
      const ValueKey('workspace-context-project-launch-app'),
    );
    expect(projectCard, findsOneWidget);
    expect(
      find.descendant(of: projectCard, matching: find.text('3 active')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: projectCard, matching: find.text('33% done')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: projectCard, matching: find.text('1 overdue')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('workspace-context-details-project-launch-app'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: projectCard, matching: find.text('1 overdue')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: projectCard, matching: find.text('2 high')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: projectCard, matching: find.text('50% progress')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: projectCard,
        matching: find.text('Overdue launch task'),
      ),
      findsOneWidget,
    );

    final areaCard = find.byKey(
      const ValueKey('workspace-context-area-health'),
    );
    expect(areaCard, findsOneWidget);
    expect(
      find.descendant(of: areaCard, matching: find.text('25% progress')),
      findsNothing,
    );
  });

  testWidgets(
    'WorkspacesPage displays and supports renaming daily workspaces',
    (tester) async {
      final today = DateTime(2026, 6, 19);
      final repository = InMemoryMindmapRepository(
        seedNodes: [
          MindmapNode.create(
            id: 'daily-task',
            type: NodeType.task,
            title: 'A daily task',
            day: today,
            status: NodeStatus.open,
            priority: NodePriority.medium,
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
          child: const MaterialApp(home: WorkspacesPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Dailies header is visible
      expect(find.text('Dailies'), findsOneWidget);

      // Default title is "Daily 2026-06-19"
      expect(find.text('Daily 2026-06-19'), findsOneWidget);

      // Let's seed a custom title for the daily workspace
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(WorkspacesPage)),
      );
      await scope
          .read(workspaceTitleProvider.notifier)
          .setTitle(WorkspaceContextType.daily, '2026-06-19', 'My Custom Day');
      await tester.pumpAndSettle();

      // Verify custom title is displayed instead of the default date label
      expect(find.text('Daily 2026-06-19'), findsNothing);
      expect(find.text('My Custom Day'), findsOneWidget);

      final cardFinder = find.byKey(
        const ValueKey('workspace-context-daily-2026-06-19'),
      );
      expect(cardFinder, findsOneWidget);
    },
  );

  testWidgets('WorkspacesPage collapses filters until toggled', (tester) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'launch-task',
          type: NodeType.task,
          title: 'Launch task',
          day: today,
          project: 'Launch App',
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
        child: const MaterialApp(home: WorkspacesPage()),
      ),
    );
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('workspace-filter-panel'));
    expect(
      find.byKey(const ValueKey('workspace-filter-toggle')),
      findsOneWidget,
    );
    expect(panel, findsNothing);

    await tester.tap(find.byKey(const ValueKey('workspace-filter-toggle')));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(find.text('All types'), findsOneWidget);

    await tester.tap(find.text('All types'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workspace-active-filter-chips')), findsOneWidget);
    expect(find.text('Type: Project'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-active-filter-chips')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('workspace-filter-toggle')));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
  });

  testWidgets('WorkspacesPage hides stats until toggled', (tester) async {
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'launch-task',
          type: NodeType.task,
          title: 'Launch task',
          day: today,
          project: 'Launch App',
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
        child: const MaterialApp(home: WorkspacesPage()),
      ),
    );
    await tester.pumpAndSettle();

    final focusStrip = find.byKey(const ValueKey('workspace-focus-strip'));
    expect(focusStrip, findsNothing);

    await tester.tap(find.byTooltip('Show stats'));
    await tester.pumpAndSettle();
    expect(focusStrip, findsOneWidget);

    await tester.tap(find.byTooltip('Hide stats'));
    await tester.pumpAndSettle();
    expect(focusStrip, findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/workspace/workspace_detail_page.dart';

void main() {
  late InMemoryMindmapRepository repository;
  late DateTime today;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    today = DateTime(2026, 7, 1);
    repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'task-open',
          type: NodeType.task,
          title: 'Design homepage',
          day: today,
          project: 'Alpha',
          status: NodeStatus.open,
          now: DateTime(2026, 7, 1, 8),
        ),
        MindmapNode.create(
          id: 'task-doing',
          type: NodeType.task,
          title: 'Build API',
          day: today,
          project: 'Alpha',
          status: NodeStatus.doing,
          dueDate: today.add(const Duration(days: 3)),
          now: DateTime(2026, 7, 1, 9),
        ),
        MindmapNode.create(
          id: 'task-done',
          type: NodeType.task,
          title: 'Write tests',
          day: today.subtract(const Duration(days: 2)),
          project: 'Alpha',
          status: NodeStatus.done,
          isDone: true,
          now: DateTime(2026, 7, 1, 10),
        ),
        MindmapNode.create(
          id: 'task-other',
          type: NodeType.task,
          title: 'Other project task',
          day: today,
          project: 'Beta',
          now: DateTime(2026, 7, 1, 11),
        ),
      ],
    );
  });

  Widget buildPage({String typeName = 'project', String name = 'Alpha'}) {
    return ProviderScope(
      overrides: [
        mindmapRepositoryProvider.overrideWithValue(repository),
        currentDateProvider.overrideWithValue(today),
      ],
      child: MaterialApp(
        home: WorkspaceDetailPage(typeName: typeName, name: name),
      ),
    );
  }

  group('WorkspaceDetailPage', () {
    testWidgets('shows workspace title and list view by default', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Title should contain the workspace name
      expect(find.textContaining('Alpha'), findsWidgets);

      // List view is the default - should show active and completed sections
      expect(find.textContaining('Active'), findsWidgets);
      expect(find.textContaining('Completed'), findsOneWidget);

      // Should show the tasks belonging to this workspace only
      expect(find.text('Design homepage'), findsOneWidget);
      expect(find.text('Build API'), findsOneWidget);
      expect(find.text('Write tests'), findsOneWidget);
      // Should NOT show tasks from other workspaces
      expect(find.text('Other project task'), findsNothing);
    });

    testWidgets('shows segmented button with List, Kanban, Gantt options', (
      tester,
    ) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('List'), findsOneWidget);
      expect(find.text('Kanban'), findsOneWidget);
      expect(find.text('Gantt'), findsOneWidget);
    });

    testWidgets('switches to Kanban view and shows columns', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Tap Kanban button
      await tester.tap(find.text('Kanban'));
      await tester.pumpAndSettle();

      // Kanban columns should be visible
      expect(find.text('To Do'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      // Tasks should appear in correct columns
      expect(find.text('Design homepage'), findsOneWidget); // open -> To Do
      expect(find.text('Build API'), findsOneWidget); // doing -> In Progress
      expect(find.text('Write tests'), findsOneWidget); // done -> Done
    });

    testWidgets('switches to Gantt view and shows legend', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Tap Gantt button
      await tester.tap(find.text('Gantt'));
      await tester.pumpAndSettle();

      // Gantt legend should be visible
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
    });

    testWidgets('shows stats card in list view', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // Stats card should show labels
      expect(find.text('Total'), findsOneWidget);
      expect(
        find.text('Active'),
        findsWidgets,
      ); // Active appears in section header too
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
    });

    testWidgets('shows empty state for workspace with no nodes', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildPage(typeName: 'project', name: 'Nonexistent'),
      );
      await tester.pumpAndSettle();

      expect(find.text('No tasks yet'), findsOneWidget);
    });

    testWidgets('Kanban card shows due date when present', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kanban'));
      await tester.pumpAndSettle();

      // Build API has a due date, should show it
      expect(find.text('2026-07-04'), findsOneWidget);
    });
  });
}

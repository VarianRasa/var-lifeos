import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
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
}

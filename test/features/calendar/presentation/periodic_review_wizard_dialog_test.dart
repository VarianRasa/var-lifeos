import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/presentation/periodic_review_wizard_dialog.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1200, 900);
    view.devicePixelRatio = 1;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('weekly wizard saves one deterministic review journal', (
    tester,
  ) async {
    final today = DateTime(2026, 7, 22);
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPeriodicReviewWizardDialog(
                  context,
                  today: today,
                  start: DateTime(2026, 7, 20),
                  end: today,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'Shipped weekly review',
    );
    for (var step = 0; step < 4; step++) {
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed!();
      await tester.pumpAndSettle();
    }
    tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed!();
    await tester.pumpAndSettle();

    final review = (await repository.listNodes()).single;
    expect(review.id, 'weekly-review_2026-07-20_2026-07-22');
    expect(review.type, NodeType.journal);
    expect(review.title, 'Weekly Review — 2026-07-20 to 2026-07-22');
    expect(review.body, contains('## 🏆 Wins & Accomplishments'));
    expect(review.body, contains('Shipped weekly review'));
    expect(review.body, contains('## 💡 Key Lessons & Reflection'));
    expect(review.body, contains('## 🎯 Next Week Core Focus'));
    expect(review.body, contains('**Weekly Mood Score:** 4.0 / 5.0'));
    expect(
      review.data['journal'],
      containsPair('periodKey', '2026-07-20_2026-07-22'),
    );
  });

  testWidgets('wizard overdue list uses due date and excludes complete tasks', (
    tester,
  ) async {
    final today = DateTime(2026, 7, 22);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'late',
          type: NodeType.task,
          title: 'Due overdue',
          day: today,
          dueDate: today.subtract(const Duration(days: 1)),
        ),
        MindmapNode.create(
          id: 'done',
          type: NodeType.task,
          title: 'Done overdue',
          day: today,
          dueDate: today.subtract(const Duration(days: 1)),
          progress: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: PeriodicReviewWizardDialog(
            today: today,
            start: DateTime(2026, 7, 20),
            end: today,
          ),
        ),
      ),
    );
    tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Due overdue'), findsOneWidget);
    expect(find.text('Done overdue'), findsNothing);
  });
}

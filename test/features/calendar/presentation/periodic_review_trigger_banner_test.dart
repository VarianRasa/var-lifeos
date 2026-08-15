import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/calendar/presentation/periodic_review_trigger_banner.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';

void main() {
  testWidgets(
    'PeriodicReviewTriggerBanner renders on Sunday when review is due',
    (tester) async {
      final sunday = DateTime(2026, 7, 26); // Sunday
      final repository = InMemoryMindmapRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PeriodicReviewTriggerBanner(
                  today: sunday,
                  nodes: const [],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Waktunya Refleksi Mingguan!'), findsOneWidget);
      expect(find.text('Mulai Review'), findsOneWidget);
    },
  );

  testWidgets('PeriodicReviewTriggerBanner dismisses on close button click', (
    tester,
  ) async {
    final sunday = DateTime(2026, 7, 26);
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PeriodicReviewTriggerBanner(
                today: sunday,
                nodes: const [],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Waktunya Refleksi Mingguan!'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Waktunya Refleksi Mingguan!'), findsNothing);
  });
}

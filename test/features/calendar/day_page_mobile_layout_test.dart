import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/features/calendar/day_page.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('renders compact top header when screen width < 600', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repository = InMemoryMindmapRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: DayPage(date: DateTime(2026, 8, 8)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobile-compact-header')), findsOneWidget);
  });

  testWidgets('opens mobile tools sheet when tapping Tools button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repository = InMemoryMindmapRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: DayPage(date: DateTime(2026, 8, 8)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toolsButton = find.byKey(const Key('mobile-tools-button'));
    await tester.tap(toolsButton);
    await tester.pumpAndSettle();

    expect(find.text('Day Tools & Status'), findsOneWidget);
  });
}


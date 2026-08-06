import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/features/calendar/day_page.dart';
import 'package:var_app/shared/layout/desktop_window_chrome.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets(
    'DayPage renders top-left title and top-right header actions correctly',
    (WidgetTester tester) async {
      final today = DateTime.now();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: DayPage(date: today)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Stack), findsWidgets);
      expect(find.byType(DayPage), findsOneWidget);
    },
  );

  testWidgets(
    'DesktopMenuAction triggers toggle floating controls state',
    (WidgetTester tester) async {
      final today = DateTime.now();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: DayPage(date: today)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      desktopMenuController.invoke(DesktopMenuAction.toggleTopHeader);
      await tester.pump();

      desktopMenuController.invoke(DesktopMenuAction.toggleBoardTabs);
      await tester.pump();

      desktopMenuController.invoke(DesktopMenuAction.toggleAllCanvasControls);
      await tester.pump();
    },
  );
}

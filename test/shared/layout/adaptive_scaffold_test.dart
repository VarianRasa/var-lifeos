import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:var_app/core/theme/app_colors.dart';
import 'package:var_app/core/theme/app_theme.dart';
import 'package:var_app/core/theme/theme_controller.dart';
import 'package:var_app/features/command/presentation/quick_capture_dock.dart';
import 'package:var_app/shared/layout/adaptive_scaffold.dart';
import 'package:var_app/shared/layout/desktop_window_chrome.dart';

void main() {
  Future<GoRouter> pumpShell(
    WidgetTester tester, {
    required double width,
    String location = '/calendar',
    ThemeData? theme,
    bool windowsDesktop = false,
  }) async {
    tester.view
      ..physicalSize = Size(width, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              AdaptiveScaffold(windowsDesktop: windowsDesktop, body: child),
          routes: [
            GoRoute(
              path: '/calendar/:date',
              builder: (context, state) => const SizedBox.expand(),
            ),
            for (final path in <String>[
              '/calendar',
              '/focus',
              '/goals-habits',
              '/notes-journal',
              '/workspaces',
              '/insights',
              '/graph',
              '/collab',
              '/settings',
              '/recovery',
            ])
              GoRoute(
                path: path,
                builder: (context, state) => const SizedBox.expand(),
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          navigationSidebarCollapsedProvider.overrideWith((ref) => false),
        ],
        child: MaterialApp.router(
          theme: theme ?? AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  for (final themeCase in <({String name, ThemeData theme})>[
    (name: 'neutral light', theme: AppTheme.light),
    (name: 'neutral dark', theme: AppTheme.dark),
    (
      name: 'matcha light',
      theme: AppTheme.forVariant(
        Brightness.light,
        AppThemeVariant.astryxMatcha,
        AppFontSize.medium,
      ),
    ),
  ]) {
    for (final viewport in <({double width, String expectedKey})>[
      (width: 390, expectedKey: 'astryx-mobile-menu'),
      (width: 768, expectedKey: 'astryx-mobile-menu'),
      (width: 1280, expectedKey: 'astryx-extended-rail'),
    ]) {
      testWidgets(
        '${themeCase.name} uses expected shell at ${viewport.width}px',
        (tester) async {
          await pumpShell(
            tester,
            width: viewport.width,
            theme: themeCase.theme,
          );
          expect(find.byKey(ValueKey(viewport.expectedKey)), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('mobile uses navigation drawer through 768 px', (tester) async {
    final router = await pumpShell(tester, width: 768);
    expect(find.byKey(const ValueKey('astryx-mobile-menu')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('astryx-mobile-quick-capture')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('astryx-compact-rail')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('astryx-mobile-quick-capture')));
    await tester.pumpAndSettle();
    expect(find.byType(QuickCaptureDock), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('astryx-mobile-quick-capture')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('astryx-mobile-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('astryx-mobile-drawer')), findsOneWidget);

    final drawer = tester.widget<NavigationDrawer>(
      find.byType(NavigationDrawer),
    );
    expect(drawer.selectedIndex, 0);
    await tester.tap(find.byKey(const ValueKey('astryx-drawer-settings')));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      startsWith('/calendar/'),
    );
    expect(
      router.routeInformationProvider.value.uri.queryParameters['panel'],
      'settings',
    );
    expect(find.byKey(const ValueKey('astryx-mobile-drawer')), findsNothing);
  });

  testWidgets('medium uses compact rail from 769 through 1024 px', (
    tester,
  ) async {
    final router = await pumpShell(tester, width: 769);
    expect(find.byKey(const ValueKey('astryx-compact-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('astryx-mobile-menu')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('astryx-rail-insights')));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      startsWith('/calendar/'),
    );
    expect(
      router.routeInformationProvider.value.uri.queryParameters['panel'],
      'insights',
    );

    await pumpShell(tester, width: 1024);
    expect(find.byKey(const ValueKey('astryx-compact-rail')), findsOneWidget);
  });

  testWidgets('desktop uses extended rail above 1024 px', (tester) async {
    await pumpShell(tester, width: 1025, location: '/settings');
    expect(find.byKey(const ValueKey('astryx-extended-rail')), findsOneWidget);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(rail.selectedIndex, 9);
  });

  testWidgets('desktop navigation can collapse and expand', (tester) async {
    await pumpShell(tester, width: 1440);
    expect(find.byKey(const ValueKey('astryx-extended-rail')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('astryx-rail-collapse')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('astryx-compact-rail')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('astryx-extended-rail')), findsOneWidget);
  });

  testWidgets('Windows desktop removes navigation rail', (tester) async {
    await pumpShell(tester, width: 1440, windowsDesktop: true);

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationDrawer), findsNothing);
  });

  testWidgets('Windows title menu actions control shell', (tester) async {
    final router = await pumpShell(tester, width: 1440, windowsDesktop: true);

    desktopMenuController.invoke(DesktopMenuAction.insights);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters['panel'],
      'insights',
    );

    desktopMenuController.invoke(DesktopMenuAction.quickCapture);
    await tester.pumpAndSettle();
    expect(find.byType(QuickCaptureDock), findsOneWidget);

    desktopMenuController.invoke(DesktopMenuAction.recoveryCenter);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/recovery');
  });

  testWidgets('recovery maps to Settings active destination', (tester) async {
    await pumpShell(tester, width: 1440, location: '/recovery');
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, 9);
  });
}

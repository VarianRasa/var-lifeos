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
import 'package:window_manager/window_manager.dart';

void main() {
  Future<GoRouter> pumpShell(
    WidgetTester tester, {
    required double width,
    String location = '/calendar',
    ThemeData? theme,
    bool windowsDesktop = false,
    bool withWindowChrome = false,
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
          builder: (context, state, child) {
            final shell = AdaptiveScaffold(
              windowsDesktop: windowsDesktop,
              body: child,
            );
            return withWindowChrome
                ? DesktopWindowChrome(
                    controller: _ShellWindowController(),
                    enabled: true,
                    child: shell,
                  )
                : shell;
          },
          routes: [
            GoRoute(
              path: '/calendar/:date',
              builder: (context, state) => const SizedBox.expand(),
            ),
            for (final path in <String>[
              '/calendar',
              '/search',
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
      (width: 1280, expectedKey: 'astryx-topnav-search'),
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

  testWidgets('shell switches at compact boundary without overflow', (
    tester,
  ) async {
    for (final width in <double>[320, 768, 769, 1024, 1440]) {
      await pumpShell(tester, width: width, location: '/search');
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('astryx-mobile-menu')),
        width <= 768 ? findsOneWidget : findsNothing,
      );
    }
  });

  testWidgets('drawer selection follows grouped route order', (tester) async {
    await pumpShell(tester, width: 320, location: '/settings');
    await tester.tap(find.byKey(const ValueKey('astryx-mobile-menu')));
    await tester.pumpAndSettle();
    final drawer = tester.widget<NavigationDrawer>(
      find.byType(NavigationDrawer),
    );
    expect(drawer.selectedIndex, 9);
    expect(
      find.byKey(const ValueKey('astryx-drawer-settings')),
      findsOneWidget,
    );
  });

  testWidgets('shell remains usable at two times text scale', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpShell(tester, width: 320);
    expect(find.byKey(const ValueKey('astryx-mobile-menu')), findsOneWidget);
    final context = tester.element(find.text('Calendar'));
    expect(
      tester.widget<Text>(find.text('Calendar')).style,
      Theme.of(context).textTheme.titleLarge,
    );
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('widescreen shows AstryxTopNav above 768 px', (tester) async {
    final router = await pumpShell(tester, width: 769);
    expect(find.byKey(const ValueKey('astryx-topnav-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('astryx-mobile-menu')), findsNothing);
    expect(find.byKey(const ValueKey('astryx-compact-rail')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('astryx-topnav-settings')));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters['panel'],
      'settings',
    );

    await pumpShell(tester, width: 1024);
    expect(find.byKey(const ValueKey('astryx-topnav-search')), findsOneWidget);
  });

  testWidgets('Ctrl+Q opens quick capture in dark mode', (tester) async {
    await pumpShell(tester, width: 1024, theme: AppTheme.dark);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(QuickCaptureDock), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(QuickCaptureDock))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('Ctrl+B toggles visible desktop navigation', (tester) async {
    await pumpShell(tester, width: 1440);
    expect(find.text('Navigate'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Navigate'), findsNothing);
    expect(find.byKey(const ValueKey('astryx-topnav-search')), findsOneWidget);
  });

  testWidgets('Ctrl+B opens Windows Navigate menu without hidden mutation', (
    tester,
  ) async {
    await pumpShell(
      tester,
      width: 1440,
      windowsDesktop: true,
      withWindowChrome: true,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdaptiveScaffold)),
    );
    expect(container.read(navigationSidebarCollapsedProvider), isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(container.read(navigationSidebarCollapsedProvider), isFalse);
    expect(find.byKey(const ValueKey('windows-menu-search')), findsOneWidget);
  });

  testWidgets('Ctrl+B does not replay last Windows menu action', (
    tester,
  ) async {
    await pumpShell(
      tester,
      width: 1440,
      windowsDesktop: true,
      withWindowChrome: true,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdaptiveScaffold)),
    );
    var dispatches = 0;
    final subscription = container.listen<bool>(quickCaptureVisibleProvider, (
      previous,
      next,
    ) {
      dispatches++;
    });
    addTearDown(subscription.close);

    desktopMenuController.invoke(DesktopMenuAction.quickCapture);
    await tester.pumpAndSettle();
    expect(dispatches, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(dispatches, 1);
    expect(find.byKey(const ValueKey('windows-menu-search')), findsOneWidget);
  });

  testWidgets('Navigate Search menu routes to search', (tester) async {
    final router = await pumpShell(tester, width: 1440);

    await tester.tap(find.text('Navigate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/search');
  });

  testWidgets('Windows Search menu action routes shell to search', (
    tester,
  ) async {
    final router = await pumpShell(
      tester,
      width: 1440,
      windowsDesktop: true,
      withWindowChrome: true,
    );

    await tester.tap(find.byKey(const ValueKey('windows-menu-navigate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('windows-menu-search')));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/search');
  });

  testWidgets('top navigation triggers meet 44 px target', (tester) async {
    await pumpShell(tester, width: 1440);

    for (final finder in <Finder>[
      find.byKey(const ValueKey('astryx-topnav-search')),
      find.byKey(const ValueKey('astryx-topnav-menu-file')),
      find.byKey(const ValueKey('astryx-topnav-menu-navigate')),
      find.byKey(const ValueKey('astryx-topnav-menu-tools')),
    ]) {
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('desktop shell supports two times text scale', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final width in <double>[1024, 1440]) {
      await pumpShell(tester, width: width);
      expect(
        find.byKey(const ValueKey('astryx-topnav-search')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
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
    expect(find.byKey(const ValueKey('astryx-topnav-search')), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });
}

class _ShellWindowController implements DesktopWindowController {
  @override
  void addListener(WindowListener listener) {}

  @override
  void removeListener(WindowListener listener) {}

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<void> minimize() async {}

  @override
  Future<void> maximize() async {}

  @override
  Future<void> unmaximize() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> startDragging() async {}

  @override
  Future<void> popUpWindowMenu() async {}
}

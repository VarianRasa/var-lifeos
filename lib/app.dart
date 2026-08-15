/// Root widget: wires the theme controller to [MaterialApp.router].
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/mindmap/application/database_lock_provider.dart';
import 'features/mindmap/application/mindmap_providers.dart';
import 'features/mindmap/presentation/pin_lock_screen.dart';
import 'features/settings/application/reminder_auto_scheduler.dart';
import 'features/settings/application/reminder_notification_navigation.dart';
import 'shared/layout/desktop_window_chrome.dart';

class VarApp extends ConsumerWidget {
  const VarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(databaseLockProvider);
    final mode = ref.watch(themeModeProvider);
    final variant = ref.watch(themeVariantProvider);
    final fontSize = ref.watch(themeFontSizeProvider);
    final effectiveMode = variant.effectiveThemeMode(mode);
    ref.listen(allMindmapNodesProvider, (previous, next) {
      next.whenData(ref.read(reminderAutoSchedulerProvider).schedule);
    });
    if (!lock.isLocked) ref.watch(startupSearchIndexRebuildProvider);

    if (lock.isLocked) {
      return MaterialApp(
        title: AppInfo.name,
        debugShowCheckedModeBanner: false,
        themeMode: effectiveMode,
        theme: AppTheme.forVariant(Brightness.light, variant, fontSize),
        darkTheme: AppTheme.forVariant(Brightness.dark, variant, fontSize),
        builder: _buildDesktopWindowChrome,
        home: const PinLockScreen(),
      );
    }

    final router = ref.watch(appRouterProvider);
    ref.listen(reminderNotificationTapProvider, (previous, next) {
      next.whenData((payload) {
        final route = reminderRouteFromPayload(payload);
        if (route != null) router.go(route);
      });
    });
    return MaterialApp.router(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      themeMode: effectiveMode,
      theme: AppTheme.forVariant(Brightness.light, variant, fontSize),
      darkTheme: AppTheme.forVariant(Brightness.dark, variant, fontSize),
      routerConfig: router,
      scrollBehavior: const _AppScrollBehavior(),
      builder: _buildDesktopWindowChrome,
    );
  }
}

Widget _buildDesktopWindowChrome(BuildContext context, Widget? child) {
  return Overlay(
    initialEntries: [
      OverlayEntry(
        builder: (context) =>
            DesktopWindowChrome(child: child ?? const SizedBox.shrink()),
      ),
    ],
  );
}

/// Custom scroll behavior for smooth desktop/web scrolling.
///
/// Enables drag scrolling with a mouse on desktop/web and provides
/// smoother scroll physics across all platforms.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.mouse,
  };
}

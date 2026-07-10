/// Root widget: wires the theme controller to [MaterialApp.router].
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/mindmap/application/database_lock_provider.dart';
import 'features/mindmap/presentation/pin_lock_screen.dart';

class VarApp extends ConsumerWidget {
  const VarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(databaseLockProvider);
    final mode = ref.watch(themeModeProvider);
    final accentColor = ref.watch(themeAccentColorProvider);
    final variant = ref.watch(themeVariantProvider);
    final fontSize = ref.watch(themeFontSizeProvider);
    ThemeVariantConfig.active = variant;

    if (lock.isLocked) {
      return MaterialApp(
        title: AppInfo.name,
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: AppTheme.lightWithAccent(accentColor, variant, fontSize),
        darkTheme: AppTheme.darkWithAccent(accentColor, variant, fontSize),
        home: const PinLockScreen(),
      );
    }

    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: AppTheme.lightWithAccent(accentColor, variant, fontSize),
      darkTheme: AppTheme.darkWithAccent(accentColor, variant, fontSize),
      routerConfig: router,
      scrollBehavior: const _AppScrollBehavior(),
    );
  }
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

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      decelerationRate: ScrollDecelerationRate.fast,
    );
  }
}

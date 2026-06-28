/// Material 3 theme definitions for Var.
///
/// Dark is the primary experience (see [darkTheme]); light is provided for
/// accessibility. Themes are tuned for data density: tighter spacing, smaller
/// corner radii, and readable typography that doesn't waste vertical space.
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  const AppTheme._();

  /// Brand accent used for the seed color and primary actions.
  static const Color seed = NodeColors.task;

  static ThemeData get dark => _base(Brightness.dark, seed);

  static ThemeData get light => _base(Brightness.light, seed);

  static ThemeData darkWithAccent(Color accent) =>
      _base(Brightness.dark, accent);

  static ThemeData lightWithAccent(Color accent) =>
      _base(Brightness.light, accent);

  /// Smooth page transition used across all routes.
  static const pageTransitionsTheme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: _FadeSlideTransitionBuilder(),
      TargetPlatform.macOS: _FadeSlideTransitionBuilder(),
      TargetPlatform.windows: _FadeSlideTransitionBuilder(),
    },
  );

  static ThemeData _base(Brightness brightness, Color seedColor) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      surface: isDark ? NeutralColors.darkBg : NeutralColors.lightBg,
    );

    final textPrimary = isDark
        ? NeutralColors.darkTextPrimary
        : NeutralColors.lightTextPrimary;
    final textSecondary = isDark
        ? NeutralColors.darkTextSecondary
        : NeutralColors.lightTextSecondary;
    final border = isDark
        ? NeutralColors.darkBorder
        : NeutralColors.lightBorder;
    final surface = isDark
        ? NeutralColors.darkSurface
        : NeutralColors.lightSurface;
    final surfaceHigh = isDark
        ? NeutralColors.darkSurfaceHigh
        : NeutralColors.lightSurfaceHigh;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? NeutralColors.darkBg
          : NeutralColors.lightBg,
      // Smooth page transitions
      pageTransitionsTheme: pageTransitionsTheme,
      // Dense, modern typography.
      textTheme: _buildTextTheme(textPrimary, textSecondary),
      // Tighter, sharper shapes for a pro look.
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? NeutralColors.darkBg : NeutralColors.lightBg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        isDense: true,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: scheme.primary.withValues(alpha: 0.18),
        labelStyle: TextStyle(color: textPrimary, fontSize: 12),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        highlightElevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      // Dialog theme — premium glassmorphic feel
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? NeutralColors.darkSurface
            : NeutralColors.lightSurface,
        elevation: 24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        contentTextStyle: TextStyle(color: textSecondary, fontSize: 14),
      ),
      // SnackBar theme — sleek and informative
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? NeutralColors.darkSurfaceHigh
            : scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: isDark ? textPrimary : scheme.onInverseSurface,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      // Bottom sheet theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? NeutralColors.darkSurface
            : NeutralColors.lightSurface,
        elevation: 16,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        dragHandleColor: border,
        dragHandleSize: const Size(40, 4),
        showDragHandle: true,
      ),
      // Navigation Rail / Bar themes
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? NeutralColors.darkBg : NeutralColors.lightBg,
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 22),
        unselectedIconTheme: IconThemeData(color: textSecondary, size: 22),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: textSecondary, fontSize: 12),
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? NeutralColors.darkBg : NeutralColors.lightBg,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
        height: 64,
      ),
      // PopupMenu theme
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? NeutralColors.darkSurface : NeutralColors.lightSurface,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border.withValues(alpha: 0.5)),
        ),
        textStyle: TextStyle(color: textPrimary, fontSize: 13),
      ),
      // ListTile theme
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        dense: true,
      ),
      // Tab bar theme
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerHeight: 0,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
      // Tooltip theme
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark
              ? NeutralColors.darkSurfaceHigh
              : NeutralColors.lightTextPrimary,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        textStyle: TextStyle(
          color: isDark ? textPrimary : NeutralColors.lightBg,
          fontSize: 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      // Scrollbar theme
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(border.withValues(alpha: 0.5)),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
        thumbVisibility: const WidgetStatePropertyAll(false),
        interactive: true,
      ),
      // Progress indicator theme
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: border,
        circularTrackColor: border,
      ),
      // Slider theme
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: border,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
      ),
      // Switch theme
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return isDark
              ? NeutralColors.darkTextSecondary
              : NeutralColors.lightTextSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.3);
          }
          return border;
        }),
      ),
      visualDensity: VisualDensity.compact,
      // Smooth material animations
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  /// Typography tuned for readability at small sizes (data-dense UIs).
  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    const base = TextStyle(letterSpacing: -0.1, height: 1.35);
    return TextTheme(
      displayLarge: base.copyWith(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      displayMedium: base.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      displaySmall: base.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      headlineLarge: base.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      headlineMedium: base.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      headlineSmall: base.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleLarge: base.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleMedium: base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleSmall: base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: base.copyWith(fontSize: 14, color: primary),
      bodyMedium: base.copyWith(fontSize: 13, color: primary),
      bodySmall: base.copyWith(fontSize: 12, color: secondary),
      labelLarge: base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      labelMedium: base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
      labelSmall: base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
    );
  }
}

/// Custom fade+slide page transition for desktop platforms.
class _FadeSlideTransitionBuilder extends PageTransitionsBuilder {
  const _FadeSlideTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: SlideTransition(
        position:
            Tween<Offset>(
              begin: const Offset(0.0, 0.02),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      ),
    );
  }
}

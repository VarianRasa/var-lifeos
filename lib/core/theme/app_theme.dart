/// Material 3 theme definitions for Var.
///
/// Global blackboard-and-marker look. Dark stays primary, light stays available
/// for accessibility, and typography remains readable while leaning handwritten.
library;

import 'package:flutter/material.dart';

import '../../shared/widgets/doodle_border.dart';
import '../constants/app_constants.dart';
import 'app_colors.dart';
import 'theme_controller.dart';

class AppTheme {
  const AppTheme._();

  /// Default marker accent used for primary actions.
  static const Color seed = NodeColors.task;

  static const String _handwrittenFont = 'PatrickHand';

  static const List<String> _handwrittenFallback = [
    'Comic Sans MS',
    'Segoe Print',
    'Bradley Hand',
    'Chalkboard SE',
    'Marker Felt',
  ];

  static String? _fontFor(AppThemeVariant variant) {
    switch (variant) {
      case AppThemeVariant.blueprint:
        return 'RobotoMono';
      case AppThemeVariant.midnight:
        return 'Roboto';
      default:
        return _handwrittenFont;
    }
  }

  static List<String>? _fallbackFor(AppThemeVariant variant) {
    switch (variant) {
      case AppThemeVariant.blueprint:
        return const ['Courier New', 'Courier', 'monospace'];
      case AppThemeVariant.midnight:
        return const ['Arial', 'sans-serif'];
      default:
        return _handwrittenFallback;
    }
  }

  static DoodleShapeBorder _doodleShape({
    BorderSide side = BorderSide.none,
    double radius = 20,
    double wobble = 2,
  }) {
    return DoodleShapeBorder(side: side, radius: radius, wobble: wobble);
  }

  static DoodleInputBorder _doodleInput({
    required BorderSide side,
    double radius = 18,
    double wobble = 1.8,
  }) {
    return DoodleInputBorder(borderSide: side, radius: radius, wobble: wobble);
  }

  static ThemeData get dark => _base(Brightness.dark, seed, AppThemeVariant.blackboard, AppFontSize.medium);

  static ThemeData get light => _base(Brightness.light, seed, AppThemeVariant.blackboard, AppFontSize.medium);

  static ThemeData darkWithAccent(Color accent, AppThemeVariant variant, AppFontSize fontSize) =>
      _base(Brightness.dark, accent, variant, fontSize);

  static ThemeData lightWithAccent(Color accent, AppThemeVariant variant, AppFontSize fontSize) =>
      _base(Brightness.light, accent, variant, fontSize);

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

  static ThemeData _base(Brightness brightness, Color seedColor, AppThemeVariant variant, AppFontSize fontSize) {
    final scale = fontSize.scaleFactor;
    final isDark = brightness == Brightness.dark;
    final palette = AppThemeVariantColors.of(variant);
    final textPrimary = isDark
        ? palette.darkTextPrimary
        : palette.lightTextPrimary;
    final textSecondary = isDark
        ? palette.darkTextSecondary
        : palette.lightTextSecondary;
    final border = isDark
        ? palette.darkBorder
        : palette.lightBorder;
    final surface = isDark
        ? palette.darkSurface
        : palette.lightSurface;
    final surfaceHigh = isDark
        ? palette.darkSurfaceHigh
        : palette.lightSurfaceHigh;
    final primary = seedColor;
    final secondary = palette.nodeColors[NodeType.kanban] ?? NodeColors.kanban;
    final tertiary = palette.nodeColors[NodeType.plan] ?? NodeColors.plan;
    final scaffoldBg = isDark ? palette.darkBg : palette.lightBg;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: brightness,
          surface: scaffoldBg,
        ).copyWith(
          primary: primary,
          onPrimary: _bestOnColor(primary),
          secondary: secondary,
          onSecondary: _bestOnColor(secondary),
          tertiary: tertiary,
          onTertiary: _bestOnColor(tertiary),
          error: StatusColors.error,
          onError: _bestOnColor(StatusColors.error),
          surface: scaffoldBg,
          onSurface: textPrimary,
          surfaceContainer: surface,
          surfaceContainerHigh: surfaceHigh,
          surfaceContainerHighest: surfaceHigh,
          onSurfaceVariant: textSecondary,
          outline: border,
          outlineVariant: border.withValues(alpha: isDark ? 0.82 : 0.78),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      pageTransitionsTheme: pageTransitionsTheme,
      textTheme: _buildTextTheme(textPrimary, textSecondary, variant, scale),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: _doodleShape(
          side: BorderSide(color: border, width: isDark ? 2 : 1.6),
          radius: 22,
          wobble: 2.4,
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontFamily: _fontFor(variant),
          fontFamilyFallback: _fallbackFor(variant),
          fontSize: 19 * scale,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.15,
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh.withValues(alpha: isDark ? 0.72 : 1),
        border: _doodleInput(side: BorderSide(color: border, width: 1.4)),
        enabledBorder: _doodleInput(
          side: BorderSide(color: border, width: 1.4),
        ),
        focusedBorder: _doodleInput(
          side: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: _doodleInput(
          side: const BorderSide(color: StatusColors.error, width: 1.6),
        ),
        focusedErrorBorder: _doodleInput(
          side: const BorderSide(color: StatusColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        isDense: true,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: scheme.primary,
        labelStyle: TextStyle(color: textPrimary, fontSize: 12 * scale),
        secondaryLabelStyle: TextStyle(color: scheme.onPrimary, fontSize: 12 * scale),
        side: BorderSide(color: border, width: isDark ? 1.8 : 1.4),
        shape: _doodleShape(radius: 16, wobble: 1.7),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: _doodleShape(radius: 18, wobble: 1.9),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          textStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14 * scale,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: _doodleShape(radius: 18, wobble: 1.9),
          side: BorderSide(color: border, width: isDark ? 1.8 : 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          textStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14 * scale,
            letterSpacing: 0.1,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.primary;
            return surfaceHigh.withValues(alpha: isDark ? 0.42 : 1);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.onPrimary;
            return textPrimary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            final color = states.contains(WidgetState.selected)
                ? scheme.primary
                : border;
            return BorderSide(color: color, width: isDark ? 1.8 : 1.4);
          }),
          shape: WidgetStatePropertyAll(_doodleShape(radius: 999, wobble: 1.6)),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800, fontSize: 12 * scale),
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: _doodleShape(radius: 18, wobble: 1.8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: _doodleShape(radius: 16, wobble: 1.6),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        highlightElevation: 8,
        shape: _doodleShape(radius: 24, wobble: 2.1),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark
            ? NeutralColors.darkSurface
            : NeutralColors.lightSurface,
        elevation: 12,
        shape: _doodleShape(
          side: BorderSide(color: border, width: 1.4),
          radius: 28,
          wobble: 2.8,
        ),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontFamily: _fontFor(variant),
          fontFamilyFallback: _fallbackFor(variant),
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
        ),
        contentTextStyle: TextStyle(color: textSecondary, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? NeutralColors.darkSurfaceHigh
            : scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: isDark ? textPrimary : scheme.onInverseSurface,
          fontSize: 13,
        ),
        shape: _doodleShape(
          side: BorderSide(color: border, width: isDark ? 1.8 : 1.4),
          radius: 20,
          wobble: 2.2,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? NeutralColors.darkSurface
            : NeutralColors.lightSurface,
        elevation: 16,
        shape: _doodleShape(
          side: BorderSide(color: border, width: isDark ? 1.8 : 1.4),
          radius: 28,
          wobble: 2.6,
        ),
        dragHandleColor: border,
        dragHandleSize: const Size(40, 4),
        showDragHandle: true,
      ),
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
        indicatorColor: scheme.primary,
        indicatorShape: _doodleShape(radius: 22, wobble: 1.8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface.withValues(alpha: isDark ? 0.96 : 1),
        indicatorColor: scheme.primary,
        indicatorShape: _doodleShape(radius: 24, wobble: 1.9),
        elevation: 0,
        height: 72,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? NeutralColors.darkSurface : NeutralColors.lightSurface,
        elevation: 12,
        shape: _doodleShape(
          side: BorderSide(color: border, width: isDark ? 1.8 : 1.4),
          radius: 18,
          wobble: 2,
        ),
        textStyle: TextStyle(color: textPrimary, fontSize: 13),
      ),
      listTileTheme: ListTileThemeData(
        shape: _doodleShape(radius: 18, wobble: 1.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        dense: true,
      ),
      // Tab bar theme
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: textSecondary,
        indicator: DoodleUnderlineDecoration(
          color: scheme.primary,
          strokeWidth: 2.4,
        ),
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
        decoration: ShapeDecoration(
          color: isDark
              ? NeutralColors.darkSurfaceHigh
              : NeutralColors.lightTextPrimary,
          shape: _doodleShape(radius: 14, wobble: 1.5),
          shadows: [
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
        radius: const Radius.circular(999),
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

  static Color _bestOnColor(Color color) {
    final colorLuminance = color.computeLuminance();
    final darkTextLuminance = NeutralColors.lightTextPrimary.computeLuminance();
    final lightTextLuminance = NeutralColors.darkTextPrimary.computeLuminance();
    final darkTextContrast = _contrastRatio(colorLuminance, darkTextLuminance);
    final lightTextContrast = _contrastRatio(
      colorLuminance,
      lightTextLuminance,
    );
    return darkTextContrast >= lightTextContrast
        ? NeutralColors.lightTextPrimary
        : NeutralColors.darkTextPrimary;
  }

  static double _contrastRatio(double first, double second) {
    final lighter = first > second ? first : second;
    final darker = first > second ? second : first;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static TextTheme _buildTextTheme(
    Color primary,
    Color secondary,
    AppThemeVariant variant,
    double scale,
  ) {
    final font = _fontFor(variant);
    final fallback = _fallbackFor(variant);
    final isMonospace = variant == AppThemeVariant.blueprint;

    final body = TextStyle(
      fontFamily: isMonospace ? 'RobotoMono' : null,
      fontFamilyFallback: isMonospace ? const ['Courier New', 'Courier', 'monospace'] : null,
      letterSpacing: 0,
      height: 1.38,
    );
    final hand = TextStyle(
      fontFamily: font,
      fontFamilyFallback: fallback,
      letterSpacing: 0.18,
      height: 1.22,
    );
    return TextTheme(
      displayLarge: hand.copyWith(
        fontSize: 42 * scale,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      displayMedium: hand.copyWith(
        fontSize: 34 * scale,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      displaySmall: hand.copyWith(
        fontSize: 28 * scale,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      headlineLarge: hand.copyWith(
        fontSize: 24 * scale,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      headlineMedium: hand.copyWith(
        fontSize: 21 * scale,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      headlineSmall: hand.copyWith(
        fontSize: 18 * scale,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      titleLarge: hand.copyWith(
        fontSize: 17 * scale,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      titleMedium: hand.copyWith(
        fontSize: 15 * scale,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      titleSmall: hand.copyWith(
        fontSize: 14 * scale,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      bodyLarge: body.copyWith(fontSize: 14 * scale, color: primary),
      bodyMedium: body.copyWith(fontSize: 13 * scale, color: primary),
      bodySmall: body.copyWith(fontSize: 12 * scale, color: secondary),
      labelLarge: hand.copyWith(
        fontSize: 13 * scale,
        fontWeight: FontWeight.w800,
        color: primary,
      ),
      labelMedium: hand.copyWith(
        fontSize: 12 * scale,
        fontWeight: FontWeight.w700,
        color: secondary,
      ),
      labelSmall: hand.copyWith(
        fontSize: 11 * scale,
        fontWeight: FontWeight.w700,
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

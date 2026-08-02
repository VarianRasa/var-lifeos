/// Material 3 translation of Astryx for Var.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import 'app_colors.dart';
import 'app_design_tokens.dart';
import 'app_theme_icon_set.dart';
import 'theme_controller.dart';

class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF0064E0);

  static const pageTransitionsTheme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: _FadeSlideTransitionBuilder(),
      TargetPlatform.macOS: _FadeSlideTransitionBuilder(),
      TargetPlatform.windows: _FadeSlideTransitionBuilder(),
    },
  );

  static ThemeData get dark => forVariant(
    Brightness.dark,
    AppThemeVariant.astryxNeutral,
    AppFontSize.medium,
  );

  static ThemeData get light => forVariant(
    Brightness.light,
    AppThemeVariant.astryxNeutral,
    AppFontSize.medium,
  );

  static ThemeData forVariant(
    Brightness brightness,
    AppThemeVariant variant,
    AppFontSize fontSize,
  ) {
    final effectiveBrightness = variant.forcesDarkMode
        ? Brightness.dark
        : brightness;
    final scale = fontSize.scaleFactor;
    final palette = AppThemeVariantColors.of(variant);
    final semantic = palette.semanticColors(effectiveBrightness);
    final tokens = AppDesignTokens.forVariant(variant);
    final isDark = effectiveBrightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: semantic.accent,
          brightness: effectiveBrightness,
          surface: semantic.surface,
        ).copyWith(
          primary: semantic.accent,
          onPrimary: semantic.onAccent,
          primaryContainer: semantic.accentMuted,
          onPrimaryContainer: semantic.textPrimary,
          secondary: semantic.nodeColors[NodeType.kanban],
          onSecondary: _bestOnColor(semantic.nodeColors[NodeType.kanban]!),
          tertiary: semantic.nodeColors[NodeType.plan],
          onTertiary: _bestOnColor(semantic.nodeColors[NodeType.plan]!),
          error: semantic.danger,
          onError: semantic.onDanger,
          errorContainer: semantic.dangerMuted,
          onErrorContainer: semantic.textPrimary,
          surface: semantic.surface,
          onSurface: semantic.textPrimary,
          surfaceContainerLowest: semantic.background,
          surfaceContainerLow: semantic.surfaceSunken,
          surfaceContainer: semantic.surface,
          surfaceContainerHigh: semantic.surfaceRaised,
          surfaceContainerHighest: semantic.popover,
          onSurfaceVariant: semantic.textSecondary,
          outline: semantic.borderStrong,
          outlineVariant: semantic.border,
          inverseSurface: semantic.textPrimary,
          onInverseSurface: semantic.background,
          inversePrimary: semantic.onAccent,
          scrim: semantic.scrim,
          shadow: Colors.black,
        );
    final elementShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusElement),
    );
    final borderedElementShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusElement),
      side: BorderSide(color: semantic.border),
    );
    final containerShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusContainer),
      side: BorderSide(color: semantic.border),
    );
    final stateOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (states.contains(WidgetState.pressed)) return semantic.pressedOverlay;
      if (states.contains(WidgetState.hovered)) return semantic.hoverOverlay;
      if (states.contains(WidgetState.focused)) return semantic.accentMuted;
      return null;
    });
    final minimumButtonSize = Size(tokens.minimumTarget, tokens.minimumTarget);

    return ThemeData(
      useMaterial3: true,
      brightness: effectiveBrightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: semantic.background,
      canvasColor: semantic.background,
      disabledColor: semantic.textDisabled,
      dividerColor: semantic.border,
      focusColor: semantic.focusRing,
      hoverColor: semantic.hoverOverlay,
      highlightColor: semantic.pressedOverlay,
      splashColor: semantic.pressedOverlay,
      pageTransitionsTheme: pageTransitionsTheme,
      extensions: <ThemeExtension<dynamic>>[
        tokens,
        semantic,
        AppThemeIconSet.lucideLike,
      ],
      textTheme: _buildTextTheme(semantic, variant, scale),
      appBarTheme: AppBarTheme(
        backgroundColor: semantic.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: semantic.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: _headingStyle(
          variant,
          scale,
          semantic.textPrimary,
          size: 20,
          lineBox: 28,
        ),
      ),
      cardTheme: CardThemeData(
        color: semantic.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.20 : 0.10),
        shape: containerShape,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: semantic.border,
        thickness: 1,
        space: 1,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: semantic.accentMuted,
        textColor: semantic.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: semantic.surface,
        surfaceTintColor: Colors.transparent,
        contentTextStyle: TextStyle(
          color: semantic.textPrimary,
          fontSize: 14 * scale,
          height: 20 / 14,
        ),
        elevation: 0,
        padding: const EdgeInsets.all(16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: semantic.surfaceRaised,
        border: _inputBorder(semantic.border, tokens.radiusElement),
        enabledBorder: _inputBorder(semantic.border, tokens.radiusElement),
        focusedBorder: _inputBorder(
          semantic.focusRing,
          tokens.radiusElement,
          width: 2,
        ),
        errorBorder: _inputBorder(
          semantic.danger,
          tokens.radiusElement,
          width: 1.5,
        ),
        focusedErrorBorder: _inputBorder(
          semantic.danger,
          tokens.radiusElement,
          width: 2,
        ),
        disabledBorder: _inputBorder(
          semantic.border.withValues(alpha: 0.56),
          tokens.radiusElement,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
        hintStyle: TextStyle(color: semantic.textSecondary),
        labelStyle: TextStyle(color: semantic.textSecondary),
        helperStyle: TextStyle(color: semantic.textSecondary),
        errorStyle: TextStyle(color: semantic.danger),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(minimumButtonSize),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          shape: WidgetStatePropertyAll(elementShape),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w600),
          ),
          overlayColor: stateOverlay,
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(minimumButtonSize),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          shape: WidgetStatePropertyAll(elementShape),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: semantic.focusRing, width: 2);
            }
            return BorderSide(color: semantic.borderStrong);
          }),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w600),
          ),
          overlayColor: stateOverlay,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(minimumButtonSize),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          shape: WidgetStatePropertyAll(elementShape),
          overlayColor: stateOverlay,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(minimumButtonSize),
          fixedSize: WidgetStatePropertyAll(minimumButtonSize),
          shape: WidgetStatePropertyAll(elementShape),
          overlayColor: stateOverlay,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return semantic.textDisabled;
          }
          return states.contains(WidgetState.selected)
              ? semantic.accent
              : semantic.surface;
        }),
        checkColor: WidgetStatePropertyAll(semantic.onAccent),
        overlayColor: stateOverlay,
        side: BorderSide(color: semantic.borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusInner),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return semantic.textDisabled;
          }
          return states.contains(WidgetState.selected)
              ? semantic.accent
              : semantic.borderStrong;
        }),
        overlayColor: stateOverlay,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return semantic.textDisabled;
          }
          return states.contains(WidgetState.selected)
              ? semantic.onAccent
              : semantic.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return semantic.border;
          }
          return states.contains(WidgetState.selected)
              ? semantic.accent
              : semantic.track;
        }),
        overlayColor: stateOverlay,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: semantic.surfaceRaised,
        selectedColor: semantic.accentMuted,
        disabledColor: semantic.surfaceRaised.withValues(alpha: 0.56),
        labelStyle: TextStyle(
          color: semantic.textPrimary,
          fontSize: 12 * scale,
        ),
        secondaryLabelStyle: TextStyle(
          color: semantic.textPrimary,
          fontSize: 12 * scale,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(color: semantic.border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(tokens.minimumTarget, tokens.minimumTarget),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return semantic.surface;
            }
            return semantic.surfaceSunken;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? semantic.textDisabled
                : semantic.textPrimary;
          }),
          overlayColor: stateOverlay,
          side: WidgetStateProperty.resolveWith((states) {
            return BorderSide(
              color: states.contains(WidgetState.focused)
                  ? semantic.focusRing
                  : semantic.border,
              width: states.contains(WidgetState.focused) ? 2 : 1,
            );
          }),
          shape: WidgetStatePropertyAll(elementShape),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w600),
          ),
          elevation: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected) ? 1 : 0;
          }),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: semantic.popover,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.30 : 0.18),
        shape: containerShape,
        titleTextStyle: _headingStyle(
          variant,
          scale,
          semantic.textPrimary,
          size: 20,
          lineBox: 28,
        ),
        contentTextStyle: TextStyle(
          color: semantic.textSecondary,
          fontSize: 14 * scale,
          height: 20 / 14,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: semantic.popover,
        modalBackgroundColor: semantic.popover,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.30 : 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(tokens.radiusPage),
          ),
          side: BorderSide(color: semantic.border),
        ),
        dragHandleColor: semantic.borderStrong,
        dragHandleSize: const Size(40, 4),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 14 * scale,
        ),
        actionTextColor: scheme.inversePrimary,
        shape: containerShape,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: ShapeDecoration(
          color: scheme.inverseSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusInner),
          ),
          shadows: tokens.shadowLow,
        ),
        textStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 12 * scale,
          height: 20 / 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        waitDuration: tokens.motionMedium,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(
          color: semantic.textPrimary,
          fontSize: 14 * scale,
          height: 20 / 14,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(semantic.popover),
          elevation: const WidgetStatePropertyAll(3),
          shape: WidgetStatePropertyAll(containerShape),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: semantic.popover,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.24 : 0.14),
        shape: containerShape,
        textStyle: TextStyle(color: semantic.textPrimary, fontSize: 14 * scale),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: semantic.textSecondary,
        textColor: semantic.textPrimary,
        selectedColor: semantic.textPrimary,
        selectedTileColor: semantic.accentMuted,
        shape: elementShape,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        minTileHeight: tokens.minimumTarget,
        dense: true,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: semantic.textPrimary,
        unselectedLabelColor: semantic.textSecondary,
        indicatorColor: semantic.accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: semantic.border,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14 * scale,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14 * scale,
        ),
        overlayColor: stateOverlay,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: semantic.surface,
        elevation: 0,
        indicatorColor: semantic.accentMuted,
        indicatorShape: elementShape,
        selectedIconTheme: IconThemeData(color: semantic.accent, size: 22),
        unselectedIconTheme: IconThemeData(
          color: semantic.textSecondary,
          size: 22,
        ),
        selectedLabelTextStyle: TextStyle(
          color: semantic.textPrimary,
          fontSize: 14 * scale,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: semantic.textSecondary,
          fontSize: 14 * scale,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: semantic.popover,
        surfaceTintColor: Colors.transparent,
        indicatorColor: semantic.accentMuted,
        indicatorShape: elementShape,
        elevation: 6,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: semantic.surface,
        indicatorColor: semantic.accentMuted,
        indicatorShape: elementShape,
        elevation: 0,
        height: 64,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        iconColor: semantic.accent,
        collapsedIconColor: semantic.textSecondary,
        textColor: semantic.textPrimary,
        collapsedTextColor: semantic.textPrimary,
        shape: borderedElementShape,
        collapsedShape: elementShape,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: semantic.accent,
        foregroundColor: semantic.onAccent,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 3,
        highlightElevation: 3,
        shape: elementShape,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: semantic.accent,
        linearTrackColor: semantic.track,
        circularTrackColor: semantic.track,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: semantic.accent,
        inactiveTrackColor: semantic.track,
        thumbColor: semantic.accent,
        overlayColor: semantic.accentMuted,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.hovered)
              ? semantic.borderStrong
              : semantic.border;
        }),
        radius: const Radius.circular(999),
        thickness: const WidgetStatePropertyAll(6),
        thumbVisibility: const WidgetStatePropertyAll(false),
        interactive: true,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  static OutlineInputBorder _inputBorder(
    Color color,
    double radius, {
    double width = 1,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _buildTextTheme(
    AppSemanticColors semantic,
    AppThemeVariant variant,
    double scale,
  ) {
    TextStyle body(double size, double lineBox, Color color, double weight) {
      return TextStyle(
        fontFamily: _bodyFontFor(variant),
        fontFamilyFallback: _fontFallback,
        fontSize: size * scale,
        fontWeight: FontWeight.lerp(FontWeight.w400, FontWeight.w700, weight),
        height: lineBox / size,
        color: color,
      );
    }

    TextStyle heading(double size, double lineBox, {double weight = 0.67}) {
      return body(
        size,
        lineBox,
        semantic.textPrimary,
        weight,
      ).copyWith(fontFamily: _headingFontFor(variant));
    }

    return TextTheme(
      displayLarge: heading(42, 52, weight: 0),
      displayMedium: heading(35, 44, weight: 0),
      displaySmall: heading(29, 36, weight: 0),
      headlineLarge: heading(24, 32),
      headlineMedium: heading(20, 28),
      headlineSmall: heading(17, 24),
      titleLarge: heading(14, 20),
      titleMedium: heading(12, 20),
      titleSmall: heading(10, 16),
      bodyLarge: body(17, 24, semantic.textPrimary, 0.33),
      bodyMedium: body(14, 20, semantic.textPrimary, 0),
      bodySmall: body(12, 20, semantic.textSecondary, 0),
      labelLarge: body(14, 20, semantic.textPrimary, 0.33),
      labelMedium: body(12, 20, semantic.textSecondary, 0.33),
      labelSmall: body(10, 16, semantic.textSecondary, 0.33),
    );
  }

  static TextStyle _headingStyle(
    AppThemeVariant variant,
    double scale,
    Color color, {
    required double size,
    required double lineBox,
  }) {
    return TextStyle(
      color: color,
      fontFamily: _headingFontFor(variant),
      fontFamilyFallback: _fontFallback,
      fontSize: size * scale,
      fontWeight: FontWeight.w600,
      height: lineBox / size,
    );
  }

  static String _bodyFontFor(AppThemeVariant variant) => switch (variant) {
    AppThemeVariant.astryxNeutral || AppThemeVariant.astryxStone => 'Figtree',
    AppThemeVariant.astryxGothic => 'Fustat',
    AppThemeVariant.astryxMatcha => 'DMSans',
    AppThemeVariant.astryxY2k => 'Poppins',
    AppThemeVariant.astryxButter => 'Outfit',
    AppThemeVariant.astryxChocolate => 'AlbertSans',
  };

  static String _headingFontFor(AppThemeVariant variant) => switch (variant) {
    AppThemeVariant.astryxStone => 'Montserrat',
    AppThemeVariant.astryxMatcha => 'PlaywriteUSTrad',
    AppThemeVariant.astryxChocolate => 'Fraunces',
    _ => _bodyFontFor(variant),
  };

  static const _fontFallback = <String>[
    'Segoe UI',
    'Roboto',
    'Arial',
    'sans-serif',
  ];

  static Color _bestOnColor(Color color) {
    final luminance = color.computeLuminance();
    const dark = Color(0xFF0A1317);
    const light = Colors.white;
    final darkContrast = _contrastRatio(luminance, dark.computeLuminance());
    final lightContrast = _contrastRatio(luminance, light.computeLuminance());
    return darkContrast >= lightContrast ? dark : light;
  }

  static double _contrastRatio(double first, double second) {
    final lighter = first > second ? first : second;
    final darker = first > second ? second : first;
    return (lighter + 0.05) / (darker + 0.05);
  }
}

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
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media != null &&
        (media.disableAnimations || media.accessibleNavigation);
    if (reduceMotion) return child;
    final tokens = AppDesignTokens.of(context);
    final curved = CurvedAnimation(
      parent: animation,
      curve: tokens.motionCurve,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

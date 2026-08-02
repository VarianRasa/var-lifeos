/// Semantic color tokens for Var's Astryx themes.
library;

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

enum AppThemeVariant {
  astryxNeutral,
  astryxStone,
  astryxGothic,
  astryxMatcha,
  astryxY2k,
  astryxButter,
  astryxChocolate;

  static const valuesForSettings = <AppThemeVariant>[
    astryxNeutral,
    astryxStone,
    astryxGothic,
    astryxMatcha,
    astryxY2k,
    astryxButter,
    astryxChocolate,
  ];

  String get displayName => switch (this) {
    AppThemeVariant.astryxNeutral => 'Astryx Neutral',
    AppThemeVariant.astryxStone => 'Astryx Stone',
    AppThemeVariant.astryxGothic => 'Astryx Gothic',
    AppThemeVariant.astryxMatcha => 'Astryx Matcha',
    AppThemeVariant.astryxY2k => 'Astryx Y2K',
    AppThemeVariant.astryxButter => 'Astryx Butter',
    AppThemeVariant.astryxChocolate => 'Astryx Chocolate',
  };

  bool get forcesDarkMode => this == AppThemeVariant.astryxGothic;

  ThemeMode effectiveThemeMode(ThemeMode preferred) {
    return forcesDarkMode ? ThemeMode.dark : preferred;
  }
}

@immutable
class AppThemeVariantColors {
  const AppThemeVariantColors({
    required this.darkBg,
    required this.darkSurface,
    required this.darkSurfaceHigh,
    required this.darkBorder,
    required this.darkTextPrimary,
    required this.darkTextSecondary,
    required this.darkTextDisabled,
    required this.lightBg,
    required this.lightSurface,
    required this.lightSurfaceHigh,
    required this.lightBorder,
    required this.lightTextPrimary,
    required this.lightTextSecondary,
    required this.lightTextDisabled,
    required this.nodeColors,
    required this.darkAccent,
    required this.lightAccent,
    required this.darkError,
    required this.lightError,
    required this.darkSuccess,
    required this.lightSuccess,
    required this.darkWarning,
    required this.lightWarning,
    required this.darkCard,
    required this.lightCard,
    required this.darkPopover,
    required this.lightPopover,
  });

  final Color darkBg;
  final Color darkSurface;
  final Color darkSurfaceHigh;
  final Color darkBorder;
  final Color darkTextPrimary;
  final Color darkTextSecondary;
  final Color darkTextDisabled;
  final Color lightBg;
  final Color lightSurface;
  final Color lightSurfaceHigh;
  final Color lightBorder;
  final Color lightTextPrimary;
  final Color lightTextSecondary;
  final Color lightTextDisabled;
  final Map<NodeType, Color> nodeColors;
  final Color darkAccent;
  final Color lightAccent;
  final Color darkError;
  final Color lightError;
  final Color darkSuccess;
  final Color lightSuccess;
  final Color darkWarning;
  final Color lightWarning;
  final Color darkCard;
  final Color lightCard;
  final Color darkPopover;
  final Color lightPopover;

  static AppThemeVariantColors of(AppThemeVariant variant) => switch (variant) {
    AppThemeVariant.astryxNeutral => _neutral,
    AppThemeVariant.astryxStone => _stone,
    AppThemeVariant.astryxGothic => _gothic,
    AppThemeVariant.astryxMatcha => _matcha,
    AppThemeVariant.astryxY2k => _y2k,
    AppThemeVariant.astryxButter => _butter,
    AppThemeVariant.astryxChocolate => _chocolate,
  };

  AppSemanticColors semanticColors(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final accent = isDark ? darkAccent : lightAccent;
    final textPrimary = isDark ? darkTextPrimary : lightTextPrimary;
    final success = isDark ? darkSuccess : lightSuccess;
    final warning = isDark ? darkWarning : lightWarning;
    final danger = isDark ? darkError : lightError;
    final isNeutral = identical(this, _neutral);
    return AppSemanticColors(
      variant: _variantFor(this),
      background: isDark ? darkBg : lightBg,
      surface: isDark ? darkSurface : lightSurface,
      surfaceRaised: isDark ? darkSurfaceHigh : lightSurfaceHigh,
      surfaceSunken: isDark ? darkBg : lightBg,
      card: isDark ? darkCard : lightCard,
      popover: isDark ? darkPopover : lightPopover,
      border: isDark ? darkBorder : lightBorder,
      borderStrong: isNeutral
          ? isDark
                ? const Color(0xFF494D53)
                : const Color(0xFFCCD3DB)
          : (isDark ? darkTextDisabled : lightTextDisabled).withValues(
              alpha: 0.72,
            ),
      textPrimary: textPrimary,
      textSecondary: isDark ? darkTextSecondary : lightTextSecondary,
      textDisabled: isDark ? darkTextDisabled : lightTextDisabled,
      accent: accent,
      onAccent: _bestOnColor(accent),
      accentMuted: isNeutral
          ? isDark
                ? const Color(0x3F0082FB)
                : const Color(0x330082FB)
          : accent.withValues(alpha: isDark ? 0.25 : 0.20),
      hoverOverlay: isNeutral
          ? isDark
                ? const Color(0x0CFFFFFF)
                : const Color(0x0C053659)
          : textPrimary.withValues(alpha: 0.05),
      pressedOverlay: isNeutral
          ? isDark
                ? const Color(0x19FFFFFF)
                : const Color(0x19053659)
          : textPrimary.withValues(alpha: 0.10),
      focusRing: accent,
      scrim: isNeutral
          ? isDark
                ? const Color(0x99111112)
                : const Color(0x66011228)
          : const Color(0xFF011228).withValues(alpha: isDark ? 0.60 : 0.40),
      success: success,
      onSuccess: _bestOnColor(success),
      successMuted: isNeutral
          ? isDark
                ? const Color(0x3F0B991F)
                : const Color(0x330B991F)
          : success.withValues(alpha: isDark ? 0.25 : 0.20),
      warning: warning,
      onWarning: isNeutral ? const Color(0xFF0A1317) : _bestOnColor(warning),
      warningMuted: isNeutral
          ? isDark
                ? const Color(0x3FE2A400)
                : const Color(0x33E2A400)
          : warning.withValues(alpha: isDark ? 0.25 : 0.20),
      info: accent,
      onInfo: _bestOnColor(accent),
      infoMuted: accent.withValues(alpha: isDark ? 0.25 : 0.20),
      danger: danger,
      onDanger: _bestOnColor(danger),
      dangerMuted: isNeutral
          ? isDark
                ? const Color(0x3FF5394F)
                : const Color(0x33E3193B)
          : danger.withValues(alpha: isDark ? 0.25 : 0.20),
      track: isNeutral
          ? isDark
                ? const Color(0xFF5A5E66)
                : const Color(0xFFCCD3DB)
          : (isDark ? darkTextDisabled : lightTextDisabled).withValues(
              alpha: 0.78,
            ),
      nodeColors: nodeColors,
    );
  }

  static AppThemeVariant _variantFor(AppThemeVariantColors colors) {
    for (final variant in AppThemeVariant.values) {
      if (identical(of(variant), colors)) return variant;
    }
    return AppThemeVariant.astryxNeutral;
  }

  static final _neutral = AppThemeVariantColors(
    darkBg: const Color(0xFF111112),
    darkSurface: const Color(0xFF1F1F22),
    darkSurfaceHigh: const Color(0xFF28292C),
    darkBorder: const Color(0x19F2F4F6),
    darkTextPrimary: const Color(0xFFDFE2E5),
    darkTextSecondary: const Color(0xFFAAAFB5),
    darkTextDisabled: const Color(0xFF6F747C),
    lightBg: const Color(0xFFF1F4F7),
    lightSurface: const Color(0xFFFFFFFF),
    lightSurfaceHigh: const Color(0xFFF8FAFC),
    lightBorder: const Color(0x19053659),
    lightTextPrimary: const Color(0xFF0A1317),
    lightTextSecondary: const Color(0xFF4E606F),
    lightTextDisabled: const Color(0xFFA4B0BC),
    darkAccent: const Color(0xFF2694FE),
    lightAccent: const Color(0xFF0064E0),
    darkError: const Color(0xFFF5394F),
    lightError: const Color(0xFFE3193B),
    darkSuccess: const Color(0xFF0D8626),
    lightSuccess: const Color(0xFF0D8626),
    darkWarning: const Color(0xFFF2C00B),
    lightWarning: const Color(0xFFE9AF08),
    darkCard: const Color(0xFF1F1F22),
    lightCard: const Color(0xFFFFFFFF),
    darkPopover: const Color(0xFF28292C),
    lightPopover: const Color(0xFFFFFFFF),
    nodeColors: _astryxNodes(
      blue: 0xFF9EB7FF,
      cyan: 0xFF83C2D4,
      gray: 0xFFA3A3A3,
      green: 0xFF84C980,
      orange: 0xFFFFA258,
      pink: 0xFFFF99C3,
      purple: 0xFFF297FF,
      red: 0xFFFF9E97,
      teal: 0xFF7EC6B8,
      yellow: 0xFFDEB433,
    ),
  );

  static final _stone = AppThemeVariantColors(
    darkBg: const Color(0xFF111015),
    darkSurface: const Color(0xFF1B1B1F),
    darkSurfaceHigh: const Color(0xFF242325),
    darkBorder: const Color(0x1AF3F3F5),
    darkTextPrimary: const Color(0xFFF3F3F5),
    darkTextSecondary: const Color(0xFF9D9DA3),
    darkTextDisabled: const Color(0xFF5E5E61),
    lightBg: const Color(0xFFF3F3F5),
    lightSurface: const Color(0xFFFFFFFF),
    lightSurfaceHigh: const Color(0xFFE2E2E8),
    lightBorder: const Color(0xFFE2E2E8),
    lightTextPrimary: const Color(0xFF25252A),
    lightTextSecondary: const Color(0xFF83838A),
    lightTextDisabled: const Color(0xFFD7D7DA),
    darkAccent: const Color(0xFFF3F3F5),
    lightAccent: const Color(0xFF25252A),
    darkError: const Color(0xFFDCC0BC),
    lightError: const Color(0xFF58413E),
    darkSuccess: const Color(0xFFB4CDB2),
    lightSuccess: const Color(0xFF374C36),
    darkWarning: const Color(0xFFD7C59C),
    lightWarning: const Color(0xFF524622),
    darkCard: const Color(0xFF242325),
    lightCard: const Color(0xFFFFFFFF),
    darkPopover: const Color(0xFF25252A),
    lightPopover: const Color(0xFFFFFFFF),
    nodeColors: _astryxNodes(
      blue: 0xFFA0ACBD,
      cyan: 0xFF95B1AE,
      gray: 0xFFABABB0,
      green: 0xFF99B298,
      orange: 0xFFBEA792,
      pink: 0xFFC2AAB8,
      purple: 0xFFB2A7C1,
      red: 0xFFC7A39D,
      teal: 0xFF94B2A0,
      yellow: 0xFFB6AA90,
    ),
  );

  static final _gothic = AppThemeVariantColors(
    darkBg: const Color(0xFF101314),
    darkSurface: const Color(0xFF101314),
    darkSurfaceHigh: const Color(0xFF1A1D20),
    darkBorder: const Color(0x1AE8F1F6),
    darkTextPrimary: const Color(0xFFE8F1F6),
    darkTextSecondary: const Color(0xFF96A0AB),
    darkTextDisabled: const Color(0xFF495056),
    lightBg: const Color(0xFF101314),
    lightSurface: const Color(0xFF101314),
    lightSurfaceHigh: const Color(0xFF1A1D20),
    lightBorder: const Color(0x1AE8F1F6),
    lightTextPrimary: const Color(0xFFE8F1F6),
    lightTextSecondary: const Color(0xFF96A0AB),
    lightTextDisabled: const Color(0xFF495056),
    darkAccent: const Color(0xFFE8F1F6),
    lightAccent: const Color(0xFFE8F1F6),
    darkError: const Color(0xFFC6A6A2),
    lightError: const Color(0xFFC6A6A2),
    darkSuccess: const Color(0xFFB3C79A),
    lightSuccess: const Color(0xFFB3C79A),
    darkWarning: const Color(0xFFD3C490),
    lightWarning: const Color(0xFFD3C490),
    darkCard: const Color(0xFF1A1D20),
    lightCard: const Color(0xFF1A1D20),
    darkPopover: const Color(0xFF24292D),
    lightPopover: const Color(0xFF24292D),
    nodeColors: _astryxNodes(
      blue: 0xFF2A3B6E,
      cyan: 0xFF2A5E75,
      gray: 0xFFE8F1F6,
      green: 0xFF3A5E2C,
      orange: 0xFF8A4818,
      pink: 0xFF8D2D4C,
      purple: 0xFF5A2370,
      red: 0xFF5E3A35,
      teal: 0xFF1F5E52,
      yellow: 0xFF876515,
    ),
  );

  static final _matcha = AppThemeVariantColors(
    darkBg: const Color(0xFF12140E),
    darkSurface: const Color(0xFF1A1C14),
    darkSurfaceHigh: const Color(0xFF1E2016),
    darkBorder: const Color(0x1AC0CBA9),
    darkTextPrimary: const Color(0xFFC0CBA9),
    darkTextSecondary: const Color(0xFF94A468),
    darkTextDisabled: const Color(0xFF5A6440),
    lightBg: const Color(0xFFF0F0E0),
    lightSurface: const Color(0xFFFFFFFF),
    lightSurfaceHigh: const Color(0xFFF0F0E0),
    lightBorder: const Color(0xFFDCE3CE),
    lightTextPrimary: const Color(0xFF3E481D),
    lightTextSecondary: const Color(0xFF707E46),
    lightTextDisabled: const Color(0xFFC0CBA9),
    darkAccent: const Color(0xFFC0CBA9),
    lightAccent: const Color(0xFF3E481D),
    darkError: const Color(0xFFFF5C5C),
    lightError: const Color(0xFFFD0000),
    darkSuccess: const Color(0xFF6DBF2A),
    lightSuccess: const Color(0xFF4D9900),
    darkWarning: const Color(0xFFFFC940),
    lightWarning: const Color(0xFFFFB600),
    darkCard: const Color(0xFF1E2016),
    lightCard: const Color(0xFFFFFFFF),
    darkPopover: const Color(0xFF3E481D),
    lightPopover: const Color(0xFFFFFFFF),
    nodeColors: _astryxNodes(
      blue: 0xFF7BA8D4,
      cyan: 0xFF70C4C4,
      gray: 0xFF94A468,
      green: 0xFF6DBF2A,
      orange: 0xFFD4903A,
      pink: 0xFFE07A9A,
      purple: 0xFFB08ED4,
      red: 0xFFFF5C5C,
      teal: 0xFF5AB898,
      yellow: 0xFFFFC940,
    ),
  );

  static final _y2k = AppThemeVariantColors(
    darkBg: const Color(0xFF0E0F1A),
    darkSurface: const Color(0xFF16182B),
    darkSurfaceHigh: const Color(0xFF1F2238),
    darkBorder: const Color(0x1AEDEFFC),
    darkTextPrimary: const Color(0xFFEDEFFC),
    darkTextSecondary: const Color(0xFFA6ACD6),
    darkTextDisabled: const Color(0xFF4A4F6B),
    lightBg: const Color(0xFFCCCFFA),
    lightSurface: const Color(0xFFFFFFFF),
    lightSurfaceHigh: const Color(0xFFEDE0D4),
    lightBorder: const Color(0xFF2F292E),
    lightTextPrimary: const Color(0xFF2D241B),
    lightTextSecondary: const Color(0xFF675D52),
    lightTextDisabled: const Color(0xFFD1C5B8),
    darkAccent: const Color(0xFFEDEFFC),
    lightAccent: const Color(0xFF2D241B),
    darkError: const Color(0xFFFFC5C3),
    lightError: const Color(0xFF8D0A19),
    darkSuccess: const Color(0xFFC5E17A),
    lightSuccess: const Color(0xFF315600),
    darkWarning: const Color(0xFFFFE08A),
    lightWarning: const Color(0xFF6B4900),
    darkCard: const Color(0xFF16182B),
    lightCard: const Color(0xFFFFFFFF),
    darkPopover: const Color(0xFF1F2238),
    lightPopover: const Color(0xFFFFFFFF),
    nodeColors: _astryxNodes(
      blue: 0xFF002C4D,
      cyan: 0xFF003028,
      gray: 0xFF2D241B,
      green: 0xFF1E3200,
      orange: 0xFF4A1800,
      pink: 0xFF580030,
      purple: 0xFF201058,
      red: 0xFF5C0008,
      teal: 0xFF003018,
      yellow: 0xFF3F2600,
    ),
  );

  static final _butter = AppThemeVariantColors(
    darkBg: const Color(0xFF261A13),
    darkSurface: const Color(0xFF2E2117),
    darkSurfaceHigh: const Color(0xFF3A2A1F),
    darkBorder: const Color(0x1AF3F2E2),
    darkTextPrimary: const Color(0xFFF3F2E2),
    darkTextSecondary: const Color(0xFFADAC9E),
    darkTextDisabled: const Color(0xFF605F52),
    lightBg: const Color(0xFFFDFBE4),
    lightSurface: const Color(0xFFFFFFFF),
    lightSurfaceHigh: const Color(0xFFF3F2E2),
    lightBorder: const Color(0xFFE5E3D4),
    lightTextPrimary: const Color(0xFF1D1C11),
    lightTextSecondary: const Color(0xFF605F52),
    lightTextDisabled: const Color(0xFFADAC9E),
    darkAccent: const Color(0xFFFDEE8C),
    lightAccent: const Color(0xFF225BFF),
    darkError: const Color(0xFFFFB4A6),
    lightError: const Color(0xFF771210),
    darkSuccess: const Color(0xFF99D94B),
    lightSuccess: const Color(0xFF004700),
    darkWarning: const Color(0xFFF7BE00),
    lightWarning: const Color(0xFF543700),
    darkCard: const Color(0xFF3A2A1F),
    lightCard: const Color(0xFFFFFFFF),
    darkPopover: const Color(0xFF3A2A1F),
    lightPopover: const Color(0xFFFFFFFF),
    nodeColors: _astryxNodes(
      blue: 0xFF203A6C,
      cyan: 0xFF004649,
      gray: 0xFF4A4732,
      green: 0xFF004800,
      orange: 0xFF622E00,
      pink: 0xFF6C0A68,
      purple: 0xFF52237B,
      red: 0xFF6D211C,
      teal: 0xFF00482D,
      yellow: 0xFF413E00,
    ),
  );

  static final _chocolate = AppThemeVariantColors(
    darkBg: const Color(0xFF141010),
    darkSurface: const Color(0xFF1C1610),
    darkSurfaceHigh: const Color(0xFF2A2018),
    darkBorder: const Color(0x1AEDE4D4),
    darkTextPrimary: const Color(0xFFEDE4D4),
    darkTextSecondary: const Color(0xFFC4A882),
    darkTextDisabled: const Color(0xFF6B5540),
    lightBg: const Color(0xFFFFFCF7),
    lightSurface: const Color(0xFFFFFCF7),
    lightSurfaceHigh: const Color(0xFFEDE4D4),
    lightBorder: const Color(0xFFC4AC95),
    lightTextPrimary: const Color(0xFF4A3520),
    lightTextSecondary: const Color(0xFF7A5636),
    lightTextDisabled: const Color(0xFFC4AC95),
    darkAccent: const Color(0xFFD4A06A),
    lightAccent: const Color(0xFF8C5927),
    darkError: const Color(0xFFFF5C5C),
    lightError: const Color(0xFFB00020),
    darkSuccess: const Color(0xFF96BF2A),
    lightSuccess: const Color(0xFF4F6C00),
    darkWarning: const Color(0xFFFFC940),
    lightWarning: const Color(0xFF7A5200),
    darkCard: const Color(0xFF2A2018),
    lightCard: const Color(0xFFEDE4D4),
    darkPopover: const Color(0xFF2A2018),
    lightPopover: const Color(0xFFFFFCF7),
    nodeColors: _astryxNodes(
      blue: 0xFF7BA8D4,
      cyan: 0xFF70C4C4,
      gray: 0xFFC4A882,
      green: 0xFF96BF2A,
      orange: 0xFFD4903A,
      pink: 0xFFE07A9A,
      purple: 0xFFB08ED4,
      red: 0xFFFF5C5C,
      teal: 0xFF5AB898,
      yellow: 0xFFFFC940,
    ),
  );

  static Map<NodeType, Color> _astryxNodes({
    required int blue,
    required int cyan,
    required int gray,
    required int green,
    required int orange,
    required int pink,
    required int purple,
    required int red,
    required int teal,
    required int yellow,
  }) => <NodeType, Color>{
    NodeType.task: Color(blue),
    NodeType.kanban: Color(cyan),
    NodeType.plan: Color(purple),
    NodeType.note: Color(gray),
    NodeType.journal: Color(pink),
    NodeType.habit: Color(green),
    NodeType.goal: Color(yellow),
    NodeType.link: Color(cyan),
    NodeType.event: Color(red),
    NodeType.decision: Color(orange),
    NodeType.resource: Color(gray),
    NodeType.idea: Color(yellow),
    NodeType.question: Color(blue),
    NodeType.contact: Color(teal),
    NodeType.metric: Color(purple),
    NodeType.expense: Color(red),
    NodeType.bookmark: Color(purple),
    NodeType.routine: Color(green),
    NodeType.mood: Color(pink),
    NodeType.timer: Color(orange),
    NodeType.quote: Color(gray),
    NodeType.audio: Color(cyan),
    NodeType.checklist: Color(green),
    NodeType.canvas: Color(blue),
    NodeType.weather: Color(cyan),
    NodeType.fit: Color(green),
    NodeType.empty: Color(gray),
    NodeType.itinerary: Color(orange),
    NodeType.image: Color(blue),
    NodeType.video: Color(purple),
  };
}

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.variant,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.card,
    required this.popover,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.accent,
    required this.onAccent,
    required this.accentMuted,
    required this.hoverOverlay,
    required this.pressedOverlay,
    required this.focusRing,
    required this.scrim,
    required this.success,
    required this.onSuccess,
    required this.successMuted,
    required this.warning,
    required this.onWarning,
    required this.warningMuted,
    required this.info,
    required this.onInfo,
    required this.infoMuted,
    required this.danger,
    required this.onDanger,
    required this.dangerMuted,
    required this.track,
    required this.nodeColors,
  });

  final AppThemeVariant variant;
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color card;
  final Color popover;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color accent;
  final Color onAccent;
  final Color accentMuted;
  final Color hoverOverlay;
  final Color pressedOverlay;
  final Color focusRing;
  final Color scrim;
  final Color success;
  final Color onSuccess;
  final Color successMuted;
  final Color warning;
  final Color onWarning;
  final Color warningMuted;
  final Color info;
  final Color onInfo;
  final Color infoMuted;
  final Color danger;
  final Color onDanger;
  final Color dangerMuted;
  final Color track;
  final Map<NodeType, Color> nodeColors;

  static AppSemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSemanticColors>() ??
        AppThemeVariantColors.of(
          AppThemeVariant.astryxNeutral,
        ).semanticColors(theme.brightness);
  }

  @override
  AppSemanticColors copyWith({
    AppThemeVariant? variant,
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? card,
    Color? popover,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? accent,
    Color? onAccent,
    Color? accentMuted,
    Color? hoverOverlay,
    Color? pressedOverlay,
    Color? focusRing,
    Color? scrim,
    Color? success,
    Color? onSuccess,
    Color? successMuted,
    Color? warning,
    Color? onWarning,
    Color? warningMuted,
    Color? info,
    Color? onInfo,
    Color? infoMuted,
    Color? danger,
    Color? onDanger,
    Color? dangerMuted,
    Color? track,
    Map<NodeType, Color>? nodeColors,
  }) {
    return AppSemanticColors(
      variant: variant ?? this.variant,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      card: card ?? this.card,
      popover: popover ?? this.popover,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentMuted: accentMuted ?? this.accentMuted,
      hoverOverlay: hoverOverlay ?? this.hoverOverlay,
      pressedOverlay: pressedOverlay ?? this.pressedOverlay,
      focusRing: focusRing ?? this.focusRing,
      scrim: scrim ?? this.scrim,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successMuted: successMuted ?? this.successMuted,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningMuted: warningMuted ?? this.warningMuted,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoMuted: infoMuted ?? this.infoMuted,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerMuted: dangerMuted ?? this.dangerMuted,
      track: track ?? this.track,
      nodeColors: nodeColors ?? this.nodeColors,
    );
  }

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) return this;
    return copyWith(
      variant: t < 0.5 ? variant : other.variant,
      background: Color.lerp(background, other.background, t),
      surface: Color.lerp(surface, other.surface, t),
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t),
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t),
      card: Color.lerp(card, other.card, t),
      popover: Color.lerp(popover, other.popover, t),
      border: Color.lerp(border, other.border, t),
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t),
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t),
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t),
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t),
      accent: Color.lerp(accent, other.accent, t),
      onAccent: Color.lerp(onAccent, other.onAccent, t),
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t),
      hoverOverlay: Color.lerp(hoverOverlay, other.hoverOverlay, t),
      pressedOverlay: Color.lerp(pressedOverlay, other.pressedOverlay, t),
      focusRing: Color.lerp(focusRing, other.focusRing, t),
      scrim: Color.lerp(scrim, other.scrim, t),
      success: Color.lerp(success, other.success, t),
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t),
      successMuted: Color.lerp(successMuted, other.successMuted, t),
      warning: Color.lerp(warning, other.warning, t),
      onWarning: Color.lerp(onWarning, other.onWarning, t),
      warningMuted: Color.lerp(warningMuted, other.warningMuted, t),
      info: Color.lerp(info, other.info, t),
      onInfo: Color.lerp(onInfo, other.onInfo, t),
      infoMuted: Color.lerp(infoMuted, other.infoMuted, t),
      danger: Color.lerp(danger, other.danger, t),
      onDanger: Color.lerp(onDanger, other.onDanger, t),
      dangerMuted: Color.lerp(dangerMuted, other.dangerMuted, t),
      track: Color.lerp(track, other.track, t),
      nodeColors: <NodeType, Color>{
        for (final type in NodeType.values)
          type: Color.lerp(nodeColors[type], other.nodeColors[type], t)!,
      },
    );
  }
}

Color _bestOnColor(Color color) {
  final luminance = color.computeLuminance();
  const dark = Color(0xFF0A1317);
  const light = Colors.white;
  final darkContrast = _contrastRatio(luminance, dark.computeLuminance());
  final lightContrast = _contrastRatio(luminance, light.computeLuminance());
  return darkContrast >= lightContrast ? dark : light;
}

double _contrastRatio(double first, double second) {
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

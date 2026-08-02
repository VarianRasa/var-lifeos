import 'package:flutter/material.dart';

import 'app_colors.dart';

@immutable
class AppDesignTokens extends ThemeExtension<AppDesignTokens> {
  const AppDesignTokens({
    required this.spacing,
    required this.radiusInner,
    required this.radiusElement,
    required this.radiusContainer,
    required this.radiusPage,
    required this.shadowLow,
    required this.shadowMedium,
    required this.shadowHigh,
    required this.motionFast,
    required this.motionMedium,
    required this.motionSlow,
    required this.motionCurve,
    required this.controlSmall,
    required this.controlMedium,
    required this.controlLarge,
    required this.minimumTarget,
  });

  static const _spacing = <double>[
    0,
    2,
    4,
    6,
    8,
    12,
    16,
    20,
    24,
    28,
    32,
    36,
    40,
    44,
    48,
  ];

  static const _shadowsLow = <BoxShadow>[
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 1), blurRadius: 1),
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 2), blurRadius: 8),
  ];

  static const _shadowsMedium = <BoxShadow>[
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 2), blurRadius: 12),
  ];

  static const _shadowsHigh = <BoxShadow>[
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 2), blurRadius: 2),
    BoxShadow(color: Color(0x26000000), offset: Offset(0, 8), blurRadius: 24),
  ];

  static const astryx = AppDesignTokens(
    spacing: _spacing,
    radiusInner: 4,
    radiusElement: 8,
    radiusContainer: 12,
    radiusPage: 28,
    shadowLow: _shadowsLow,
    shadowMedium: _shadowsMedium,
    shadowHigh: _shadowsHigh,
    motionFast: Duration(milliseconds: 175),
    motionMedium: Duration(milliseconds: 410),
    motionSlow: Duration(milliseconds: 975),
    motionCurve: Cubic(0.24, 1, 0.4, 1),
    controlSmall: 28,
    controlMedium: 32,
    controlLarge: 36,
    minimumTarget: 44,
  );

  static AppDesignTokens forVariant(AppThemeVariant variant) {
    // Shape and motion remain one system across themes. Theme packages change
    // typography and color, not interaction geometry.
    return astryx;
  }

  static const standard = astryx;

  final List<double> spacing;
  final double radiusInner;
  final double radiusElement;
  final double radiusContainer;
  final double radiusPage;
  final List<BoxShadow> shadowLow;
  final List<BoxShadow> shadowMedium;
  final List<BoxShadow> shadowHigh;
  final Duration motionFast;
  final Duration motionMedium;
  final Duration motionSlow;
  final Curve motionCurve;
  final double controlSmall;
  final double controlMedium;
  final double controlLarge;
  final double minimumTarget;

  static AppDesignTokens of(BuildContext context) {
    return Theme.of(context).extension<AppDesignTokens>() ?? astryx;
  }

  Duration effectiveDuration(BuildContext context, Duration duration) {
    final media = MediaQuery.maybeOf(context);
    return media != null &&
            (media.disableAnimations || media.accessibleNavigation)
        ? Duration.zero
        : duration;
  }

  @override
  AppDesignTokens copyWith({
    List<double>? spacing,
    double? radiusInner,
    double? radiusElement,
    double? radiusContainer,
    double? radiusPage,
    List<BoxShadow>? shadowLow,
    List<BoxShadow>? shadowMedium,
    List<BoxShadow>? shadowHigh,
    Duration? motionFast,
    Duration? motionMedium,
    Duration? motionSlow,
    Curve? motionCurve,
    double? controlSmall,
    double? controlMedium,
    double? controlLarge,
    double? minimumTarget,
  }) {
    return AppDesignTokens(
      spacing: spacing ?? this.spacing,
      radiusInner: radiusInner ?? this.radiusInner,
      radiusElement: radiusElement ?? this.radiusElement,
      radiusContainer: radiusContainer ?? this.radiusContainer,
      radiusPage: radiusPage ?? this.radiusPage,
      shadowLow: shadowLow ?? this.shadowLow,
      shadowMedium: shadowMedium ?? this.shadowMedium,
      shadowHigh: shadowHigh ?? this.shadowHigh,
      motionFast: motionFast ?? this.motionFast,
      motionMedium: motionMedium ?? this.motionMedium,
      motionSlow: motionSlow ?? this.motionSlow,
      motionCurve: motionCurve ?? this.motionCurve,
      controlSmall: controlSmall ?? this.controlSmall,
      controlMedium: controlMedium ?? this.controlMedium,
      controlLarge: controlLarge ?? this.controlLarge,
      minimumTarget: minimumTarget ?? this.minimumTarget,
    );
  }

  @override
  AppDesignTokens lerp(covariant AppDesignTokens? other, double t) {
    return other == null || t < 0.5 ? this : other;
  }
}

/// Astryx Design System Badge component.
/// Supports variants: neutral, info, success, warning, error, blue, purple, pink, teal, orange.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_design_tokens.dart';

enum AstryxBadgeVariant {
  neutral,
  info,
  success,
  warning,
  error,
  blue,
  purple,
  pink,
  teal,
  orange,
}

class AstryxBadge extends StatelessWidget {
  const AstryxBadge({
    required this.label,
    this.variant = AstryxBadgeVariant.neutral,
    this.icon,
    this.onTap,
    super.key,
  });

  final String label;
  final AstryxBadgeVariant variant;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final (bgColor, fgColor) = _getColors(semantic, isDark);

    final badgeChild = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fgColor),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: fgColor,
            height: 1.2,
          ),
        ),
      ],
    );

    final container = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(tokens.radiusInner),
      ),
      child: badgeChild,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusInner),
        child: container,
      );
    }

    return container;
  }

  (Color bg, Color fg) _getColors(AppSemanticColors semantic, bool isDark) {
    switch (variant) {
      case AstryxBadgeVariant.neutral:
        return (semantic.surfaceRaised, semantic.textSecondary);
      case AstryxBadgeVariant.info:
        return (semantic.infoMuted, semantic.info);
      case AstryxBadgeVariant.success:
        return (semantic.successMuted, semantic.success);
      case AstryxBadgeVariant.warning:
        return (semantic.warningMuted, semantic.warning);
      case AstryxBadgeVariant.error:
        return (semantic.dangerMuted, semantic.danger);
      case AstryxBadgeVariant.blue:
        const c = Color(0xFF2694FE);
        return (c.withValues(alpha: isDark ? 0.25 : 0.15), c);
      case AstryxBadgeVariant.purple:
        const c = Color(0xFFB08ED4);
        return (c.withValues(alpha: isDark ? 0.25 : 0.15), c);
      case AstryxBadgeVariant.pink:
        const c = Color(0xFFE07A9A);
        return (c.withValues(alpha: isDark ? 0.25 : 0.15), c);
      case AstryxBadgeVariant.teal:
        const c = Color(0xFF5AB898);
        return (c.withValues(alpha: isDark ? 0.25 : 0.15), c);
      case AstryxBadgeVariant.orange:
        const c = Color(0xFFD4903A);
        return (c.withValues(alpha: isDark ? 0.25 : 0.15), c);
    }
  }
}

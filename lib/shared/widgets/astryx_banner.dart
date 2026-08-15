/// Astryx Design System Banner component.
/// Displays full-width context banner notifications with action buttons.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_design_tokens.dart';

enum AstryxBannerVariant { info, success, warning, error }

class AstryxBanner extends StatelessWidget {
  const AstryxBanner({
    required this.message,
    this.variant = AstryxBannerVariant.info,
    this.title,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    super.key,
  });

  final String message;
  final AstryxBannerVariant variant;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);

    final (bg, fg, border, iconData) = _getStyle(semantic);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(tokens.radiusElement),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: semantic.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    color: semantic.textSecondary,
                    height: 1.3,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onAction,
                    child: Text(
                      actionLabel!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: Icon(Icons.close, size: 16, color: semantic.textSecondary),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
        ],
      ),
    );
  }

  (Color bg, Color fg, Color border, IconData icon) _getStyle(
    AppSemanticColors semantic,
  ) {
    switch (variant) {
      case AstryxBannerVariant.info:
        return (
          semantic.infoMuted.withValues(alpha: 0.15),
          semantic.info,
          semantic.info.withValues(alpha: 0.3),
          Icons.info_outline,
        );
      case AstryxBannerVariant.success:
        return (
          semantic.successMuted.withValues(alpha: 0.15),
          semantic.success,
          semantic.success.withValues(alpha: 0.3),
          Icons.check_circle_outline,
        );
      case AstryxBannerVariant.warning:
        return (
          semantic.warningMuted.withValues(alpha: 0.15),
          semantic.warning,
          semantic.warning.withValues(alpha: 0.3),
          Icons.warning_amber_rounded,
        );
      case AstryxBannerVariant.error:
        return (
          semantic.dangerMuted.withValues(alpha: 0.15),
          semantic.danger,
          semantic.danger.withValues(alpha: 0.3),
          Icons.error_outline,
        );
    }
  }
}

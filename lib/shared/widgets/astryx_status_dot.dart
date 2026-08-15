/// Astryx Design System Status Dot component.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

enum AstryxStatus { active, pending, failed, neutral }

class AstryxStatusDot extends StatelessWidget {
  const AstryxStatusDot({
    this.status = AstryxStatus.active,
    this.size = 8.0,
    super.key,
  });

  final AstryxStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);

    final color = switch (status) {
      AstryxStatus.active => semantic.success,
      AstryxStatus.pending => semantic.warning,
      AstryxStatus.failed => semantic.danger,
      AstryxStatus.neutral => semantic.textDisabled,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Astryx TopNav navigation header component for Web & Desktop shell.
class AstryxTopNavHeader extends StatelessWidget {
  const AstryxTopNavHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox();
  }
}

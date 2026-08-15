/// Astryx Design System Keyboard key (<Kbd>) component.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_design_tokens.dart';

class AstryxKbd extends StatelessWidget {
  const AstryxKbd({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: semantic.surfaceRaised,
        borderRadius: BorderRadius.circular(tokens.radiusInner),
        border: Border.all(color: semantic.borderStrong, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            offset: const Offset(0, 1),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          color: semantic.textPrimary,
        ),
      ),
    );
  }
}

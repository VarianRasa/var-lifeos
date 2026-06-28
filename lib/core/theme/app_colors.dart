/// Centralized color tokens for the Var design language.
///
/// Dark-first palette tuned for a "pro & data-dense" feel (closer to
/// Obsidian/Linear/Things than to playful consumer apps). Colors are exposed
/// both as raw [Color] constants (used by painters and custom widgets) and
/// folded into [AppTheme] for the Material scheme.
library;

import 'package:flutter/material.dart';

/// One accent color per [NodeType] so density dots and chips are scannable.
class NodeColors {
  const NodeColors._();

  static const Color task = Color(0xFF6C8EEF); // indigo-blue
  static const Color kanban = Color(0xFF8B5CF6); // violet
  static const Color plan = Color(0xFF22A06B); // green
  static const Color note = Color(0xFFE2B33C); // amber
  static const Color journal = Color(0xFF4FD1C5); // teal
  static const Color habit = Color(0xFFEC6EAD); // pink-magenta
  static const Color goal = Color(0xFFF27457); // coral-orange
  static const Color link = Color(0xFF7A869A); // slate gray

  /// Ordered list matching a typical toolbar layout.
  static const List<Color> all = [
    task,
    kanban,
    plan,
    note,
    journal,
    habit,
    goal,
    link,
  ];
}

/// Semantic status colors for badges, alerts, and indicators.
class StatusColors {
  const StatusColors._();

  static const Color success = Color(0xFF22A06B);
  static const Color warning = Color(0xFFE2B33C);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF6C8EEF);

  static const Color successBg = Color(0xFF0D3B2E);
  static const Color warningBg = Color(0xFF3B3316);
  static const Color errorBg = Color(0xFF3B1616);
  static const Color infoBg = Color(0xFF1A2742);

  // Light mode backgrounds
  static const Color successBgLight = Color(0xFFE8F5E9);
  static const Color warningBgLight = Color(0xFFFFF8E1);
  static const Color errorBgLight = Color(0xFFFFEBEE);
  static const Color infoBgLight = Color(0xFFE3F2FD);
}

/// Gradient definitions for premium card backgrounds and headers.
class GradientColors {
  const GradientColors._();

  /// Subtle dark card gradient
  static const darkCardGradient = LinearGradient(
    colors: [Color(0xFF161A21), Color(0xFF1A1F28)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Accent header gradient (primary-tinted)
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF4A6CF7), Color(0xFF6C8EEF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Success gradient for completed items
  static const successGradient = LinearGradient(
    colors: [Color(0xFF0D8050), Color(0xFF22A06B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Warm gradient for attention items
  static const warmGradient = LinearGradient(
    colors: [Color(0xFFE2884C), Color(0xFFF27457)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Premium glassmorphic surface gradient (dark)
  static const glassGradientDark = LinearGradient(
    colors: [Color(0x14FFFFFF), Color(0x08FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Premium glassmorphic surface gradient (light)
  static const glassGradientLight = LinearGradient(
    colors: [Color(0x20FFFFFF), Color(0x10FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Neutral surface/ramp tokens shared by light & dark themes.
class NeutralColors {
  const NeutralColors._();

  // Dark ramp (primary experience)
  static const Color darkBg = Color(0xFF0F1115);
  static const Color darkSurface = Color(0xFF161A21);
  static const Color darkSurfaceHigh = Color(0xFF1E232C);
  static const Color darkBorder = Color(0xFF2A313C);
  static const Color darkTextPrimary = Color(0xFFE6E9EF);
  static const Color darkTextSecondary = Color(0xFF9BA3B0);
  static const Color darkTextDisabled = Color(0xFF5C6470);

  // Light ramp (secondary experience)
  static const Color lightBg = Color(0xFFFBFBFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHigh = Color(0xFFF1F3F6);
  static const Color lightBorder = Color(0xFFE1E5EA);
  static const Color lightTextPrimary = Color(0xFF1B1E24);
  static const Color lightTextSecondary = Color(0xFF5C6470);
  static const Color lightTextDisabled = Color(0xFFA0A7B2);
}

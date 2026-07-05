/// Centralized color tokens for the Var design language.
///
/// DoodleCal-inspired blackboard palette: off-white marker outlines, neon lime
/// actions, magenta pins, and small cyan/yellow highlights.
library;

import 'package:flutter/material.dart';

/// One accent color per [NodeType] so density dots and chips are scannable.
class NodeColors {
  const NodeColors._();

  static const Color task = Color(0xFFB6FF00);
  static const Color kanban = Color(0xFFFFEA00);
  static const Color plan = Color(0xFF80ECFF);
  static const Color note = Color(0xFFF8F1E7);
  static const Color journal = Color(0xFFFF4FD8);
  static const Color habit = Color(0xFF7CFF8E);
  static const Color goal = Color(0xFFFF8C1A);
  static const Color link = Color(0xFF73D7FF);
  static const Color event = Color(0xFFFF5ACD);
  static const Color decision = Color(0xFFFFD166);
  static const Color resource = Color(0xFFB6FF00);
  static const Color idea = Color(0xFFFFEA00);
  static const Color question = Color(0xFF80ECFF);
  static const Color contact = Color(0xFF7CFF8E);
  static const Color metric = Color(0xFFFF5ACD);
  static const Color expense = Color(0xFFFF8C1A);
  static const Color bookmark = Color(0xFFCBA6FF);
  static const Color routine = Color(0xFFB6FF00);

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
    event,
    decision,
    resource,
    idea,
    question,
    contact,
    metric,
    expense,
    bookmark,
    routine,
  ];
}

/// Semantic status colors for badges, alerts, and indicators.
class StatusColors {
  const StatusColors._();

  static const Color success = Color(0xFF7CFF8E);
  static const Color warning = Color(0xFFFFEA00);
  static const Color error = Color(0xFFFF6B6B);
  static const Color info = Color(0xFF80ECFF);

  static const Color successBg = Color(0xFF123B1C);
  static const Color warningBg = Color(0xFF3F3600);
  static const Color errorBg = Color(0xFF451718);
  static const Color infoBg = Color(0xFF0D3540);

  static const Color successBgLight = Color(0xFFD7FFDD);
  static const Color warningBgLight = Color(0xFFFFF7B8);
  static const Color errorBgLight = Color(0xFFFFDCDC);
  static const Color infoBgLight = Color(0xFFD9F8FF);
}

/// Gradient definitions for card backgrounds and headers.
class GradientColors {
  const GradientColors._();

  static const darkCardGradient = LinearGradient(
    colors: [Color(0xFF121214), Color(0xFF202024)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const primaryGradient = LinearGradient(
    colors: [Color(0xFFB6FF00), Color(0xFFFFEA00), Color(0xFFFF4FD8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const successGradient = LinearGradient(
    colors: [Color(0xFF123B1C), Color(0xFF7CFF8E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const warmGradient = LinearGradient(
    colors: [Color(0xFF3F3600), Color(0xFFFFEA00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const glassGradientDark = LinearGradient(
    colors: [Color(0x33111111), Color(0x12000000)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const glassGradientLight = LinearGradient(
    colors: [Color(0xE6FFF7DF), Color(0xCCF8F1E7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Neutral surface/ramp tokens shared by light & dark themes.
class NeutralColors {
  const NeutralColors._();

  // Dark blackboard ramp.
  static const Color darkBg = Color(0xFF0B0B0D);
  static const Color darkSurface = Color(0xF2111114);
  static const Color darkSurfaceHigh = Color(0xFF202024);
  static const Color darkBorder = Color(0xFFEDE7F6);
  static const Color darkTextPrimary = Color(0xFFF8F1E7);
  static const Color darkTextSecondary = Color(0xFFC9C3B8);
  static const Color darkTextDisabled = Color(0xFF77736E);

  // Light fallback keeps same doodle language, but on cream.
  static const Color lightBg = Color(0xFFFFF4D7);
  static const Color lightSurface = Color(0xFFFFF9E8);
  static const Color lightSurfaceHigh = Color(0xFFFFEFB8);
  static const Color lightBorder = Color(0xFF1B1B1F);
  static const Color lightTextPrimary = Color(0xFF111114);
  static const Color lightTextSecondary = Color(0xFF4C463D);
  static const Color lightTextDisabled = Color(0xFF8C8273);
}

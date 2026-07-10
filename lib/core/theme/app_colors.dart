/// Centralized color tokens for the Var design language.
///
/// DoodleCal-inspired blackboard palette: off-white marker outlines, neon lime
/// actions, magenta pins, and small cyan/yellow highlights.
library;

import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

enum AppThemeVariant {
  blackboard,
  blueprint,
  schoolboard,
  midnight,
  cardboard,
}

class ThemeVariantConfig {
  const ThemeVariantConfig._();
  static AppThemeVariant active = AppThemeVariant.blackboard;
}

class AppThemeVariantColors {
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
  });

  static AppThemeVariantColors of(AppThemeVariant variant) {
    switch (variant) {
      case AppThemeVariant.blackboard:
        return _blackboard;
      case AppThemeVariant.blueprint:
        return _blueprint;
      case AppThemeVariant.schoolboard:
        return _schoolboard;
      case AppThemeVariant.midnight:
        return _midnight;
      case AppThemeVariant.cardboard:
        return _cardboard;
    }
  }

  static const _blackboard = AppThemeVariantColors(
    darkBg: Color(0xFF0B0B0D),
    darkSurface: Color(0xF2111114),
    darkSurfaceHigh: Color(0xFF202024),
    darkBorder: Color(0xFFEDE7F6),
    darkTextPrimary: Color(0xFFF8F1E7),
    darkTextSecondary: Color(0xFFC9C3B8),
    darkTextDisabled: Color(0xFF77736E),
    lightBg: Color(0xFFFFF4D7),
    lightSurface: Color(0xFFFFF9E8),
    lightSurfaceHigh: Color(0xFFFFEFB8),
    lightBorder: Color(0xFF1B1B1F),
    lightTextPrimary: Color(0xFF111114),
    lightTextSecondary: Color(0xFF4C463D),
    lightTextDisabled: Color(0xFF8C8273),
    nodeColors: {
      NodeType.task: Color(0xFFB6FF00),
      NodeType.kanban: Color(0xFFFFEA00),
      NodeType.plan: Color(0xFF80ECFF),
      NodeType.note: Color(0xFFF8F1E7),
      NodeType.journal: Color(0xFFFF4FD8),
      NodeType.habit: Color(0xFF7CFF8E),
      NodeType.goal: Color(0xFFFF8C1A),
      NodeType.link: Color(0xFF73D7FF),
      NodeType.event: Color(0xFFFF5ACD),
      NodeType.decision: Color(0xFFFFD166),
      NodeType.resource: Color(0xFFB6FF00),
      NodeType.idea: Color(0xFFFFEA00),
      NodeType.question: Color(0xFF80ECFF),
      NodeType.contact: Color(0xFF7CFF8E),
      NodeType.metric: Color(0xFFFF5ACD),
      NodeType.expense: Color(0xFFFF8C1A),
      NodeType.bookmark: Color(0xFFCBA6FF),
      NodeType.routine: Color(0xFFB6FF00),
      NodeType.mood: Color(0xFFFF5ACD),
      NodeType.timer: Color(0xFFFF8C1A),
      NodeType.quote: Color(0xFFFFEA00),
      NodeType.audio: Color(0xFF80ECFF),
      NodeType.checklist: Color(0xFF7CFF8E),
      NodeType.canvas: Color(0xFF73D7FF),
      NodeType.weather: Color(0xFFFFEA00),
      NodeType.fit: Color(0xFF7CFF8E),
    },
  );

  static const _blueprint = AppThemeVariantColors(
    darkBg: Color(0xFF0A111E),
    darkSurface: Color(0xFF121B29),
    darkSurfaceHigh: Color(0xFF1B2A3E),
    darkBorder: Color(0xFFE2F0FD),
    darkTextPrimary: Color(0xFFE2F0FD),
    darkTextSecondary: Color(0xFF9ABCDD),
    darkTextDisabled: Color(0xFF536E8B),
    lightBg: Color(0xFFEBF3FC),
    lightSurface: Color(0xFFF5F9FD),
    lightSurfaceHigh: Color(0xFFD6E7FA),
    lightBorder: Color(0xFF0E1724),
    lightTextPrimary: Color(0xFF0E1724),
    lightTextSecondary: Color(0xFF3F5570),
    lightTextDisabled: Color(0xFF778BA3),
    nodeColors: {
      NodeType.task: Color(0xFF00E5FF),
      NodeType.kanban: Color(0xFF00A9FF),
      NodeType.plan: Color(0xFF73D7FF),
      NodeType.note: Color(0xFFE2F0FD),
      NodeType.journal: Color(0xFFFF5ACD),
      NodeType.habit: Color(0xFF39FF14),
      NodeType.goal: Color(0xFFFF9F0A),
      NodeType.link: Color(0xFF73D7FF),
      NodeType.event: Color(0xFFFF5ACD),
      NodeType.decision: Color(0xFFFFC045),
      NodeType.resource: Color(0xFF00E5FF),
      NodeType.idea: Color(0xFF00A9FF),
      NodeType.question: Color(0xFF73D7FF),
      NodeType.contact: Color(0xFF39FF14),
      NodeType.metric: Color(0xFFFF5ACD),
      NodeType.expense: Color(0xFFFF9F0A),
      NodeType.bookmark: Color(0xFFCBA6FF),
      NodeType.routine: Color(0xFF00E5FF),
      NodeType.mood: Color(0xFFFF5ACD),
      NodeType.timer: Color(0xFFFF9F0A),
      NodeType.quote: Color(0xFF00A9FF),
      NodeType.audio: Color(0xFF73D7FF),
      NodeType.checklist: Color(0xFF39FF14),
      NodeType.canvas: Color(0xFF00E5FF),
      NodeType.weather: Color(0xFF73D7FF),
      NodeType.fit: Color(0xFF39FF14),
    },
  );

  static const _schoolboard = AppThemeVariantColors(
    darkBg: Color(0xFF0A1D17),
    darkSurface: Color(0xFF0D251D),
    darkSurfaceHigh: Color(0xFF143329),
    darkBorder: Color(0xFFFFFDF5),
    darkTextPrimary: Color(0xFFFFFDF5),
    darkTextSecondary: Color(0xFFA3BFB5),
    darkTextDisabled: Color(0xFF5E7D73),
    lightBg: Color(0xFFF3F9F6),
    lightSurface: Color(0xFFFAFCFA),
    lightSurfaceHigh: Color(0xFFE1EFEA),
    lightBorder: Color(0xFF0D251D),
    lightTextPrimary: Color(0xFF0D251D),
    lightTextSecondary: Color(0xFF3B5B50),
    lightTextDisabled: Color(0xFF708D83),
    nodeColors: {
      NodeType.task: Color(0xFF5EFFB2),
      NodeType.kanban: Color(0xFFFFEA00),
      NodeType.plan: Color(0xFF96F0FF),
      NodeType.note: Color(0xFFFFFDF5),
      NodeType.journal: Color(0xFFFF8AE2),
      NodeType.habit: Color(0xFF88FF88),
      NodeType.goal: Color(0xFFFFB366),
      NodeType.link: Color(0xFF96F0FF),
      NodeType.event: Color(0xFFFF8AE2),
      NodeType.decision: Color(0xFFFFEA00),
      NodeType.resource: Color(0xFF5EFFB2),
      NodeType.idea: Color(0xFFFFEA00),
      NodeType.question: Color(0xFF96F0FF),
      NodeType.contact: Color(0xFF88FF88),
      NodeType.metric: Color(0xFFFF8AE2),
      NodeType.expense: Color(0xFFFFB366),
      NodeType.bookmark: Color(0xFFD7B4FF),
      NodeType.routine: Color(0xFF5EFFB2),
      NodeType.mood: Color(0xFFFF8AE2),
      NodeType.timer: Color(0xFFFFB366),
      NodeType.quote: Color(0xFFFFEA00),
      NodeType.audio: Color(0xFF96F0FF),
      NodeType.checklist: Color(0xFF88FF88),
      NodeType.canvas: Color(0xFF96F0FF),
      NodeType.weather: Color(0xFFFFEA00),
      NodeType.fit: Color(0xFF88FF88),
    },
  );

  static const _midnight = AppThemeVariantColors(
    darkBg: Color(0xFF0B0813),
    darkSurface: Color(0xFF140D25),
    darkSurfaceHigh: Color(0xFF21163A),
    darkBorder: Color(0xFFF1EAFF),
    darkTextPrimary: Color(0xFFF1EAFF),
    darkTextSecondary: Color(0xFFB5A7D6),
    darkTextDisabled: Color(0xFF6E6093),
    lightBg: Color(0xFFFAF8FF),
    lightSurface: Color(0xFFFCFAFF),
    lightSurfaceHigh: Color(0xFFECE5FF),
    lightBorder: Color(0xFF140D25),
    lightTextPrimary: Color(0xFF140D25),
    lightTextSecondary: Color(0xFF504170),
    lightTextDisabled: Color(0xFF8577A5),
    nodeColors: {
      NodeType.task: Color(0xFFFF2E93),
      NodeType.kanban: Color(0xFFBF5AF2),
      NodeType.plan: Color(0xFF0A84FF),
      NodeType.note: Color(0xFFF1EAFF),
      NodeType.journal: Color(0xFFFF375F),
      NodeType.habit: Color(0xFF30D158),
      NodeType.goal: Color(0xFFFF9F0A),
      NodeType.link: Color(0xFF0A84FF),
      NodeType.event: Color(0xFFFF375F),
      NodeType.decision: Color(0xFFFFC045),
      NodeType.resource: Color(0xFFFF2E93),
      NodeType.idea: Color(0xFFBF5AF2),
      NodeType.question: Color(0xFF0A84FF),
      NodeType.contact: Color(0xFF30D158),
      NodeType.metric: Color(0xFFFF375F),
      NodeType.expense: Color(0xFFFF9F0A),
      NodeType.bookmark: Color(0xFFBF5AF2),
      NodeType.routine: Color(0xFFFF2E93),
      NodeType.mood: Color(0xFFFF375F),
      NodeType.timer: Color(0xFFFF9F0A),
      NodeType.quote: Color(0xFFBF5AF2),
      NodeType.audio: Color(0xFF0A84FF),
      NodeType.checklist: Color(0xFF30D158),
      NodeType.canvas: Color(0xFF0A84FF),
      NodeType.weather: Color(0xFF0A84FF),
      NodeType.fit: Color(0xFF30D158),
    },
  );

  static const _cardboard = AppThemeVariantColors(
    darkBg: Color(0xFF2B1F16),
    darkSurface: Color(0xFF382A1E),
    darkSurfaceHigh: Color(0xFF463526),
    darkBorder: Color(0xFFFBEFE3),
    darkTextPrimary: Color(0xFFFBEFE3),
    darkTextSecondary: Color(0xFFC7B19C),
    darkTextDisabled: Color(0xFF836F5D),
    lightBg: Color(0xFFE3D4C1),
    lightSurface: Color(0xFFEFE6D9),
    lightSurfaceHigh: Color(0xFFD4C2AB),
    lightBorder: Color(0xFF2E2315),
    lightTextPrimary: Color(0xFF2E2315),
    lightTextSecondary: Color(0xFF6E5640),
    lightTextDisabled: Color(0xFFA58D76),
    nodeColors: {
      NodeType.task: Color(0xFFD32F2F),
      NodeType.kanban: Color(0xFFE65100),
      NodeType.plan: Color(0xFF0D47A1),
      NodeType.note: Color(0xFF2E2315),
      NodeType.journal: Color(0xFF880E4F),
      NodeType.habit: Color(0xFF1B5E20),
      NodeType.goal: Color(0xFF3E2723),
      NodeType.link: Color(0xFF0D47A1),
      NodeType.event: Color(0xFF880E4F),
      NodeType.decision: Color(0xFF5D4037),
      NodeType.resource: Color(0xFFD32F2F),
      NodeType.idea: Color(0xFFE65100),
      NodeType.question: Color(0xFF0D47A1),
      NodeType.contact: Color(0xFF1B5E20),
      NodeType.metric: Color(0xFF880E4F),
      NodeType.expense: Color(0xFF3E2723),
      NodeType.bookmark: Color(0xFF4A148C),
      NodeType.routine: Color(0xFFD32F2F),
      NodeType.mood: Color(0xFF880E4F),
      NodeType.timer: Color(0xFFE65100),
      NodeType.quote: Color(0xFF4A148C),
      NodeType.audio: Color(0xFF0D47A1),
      NodeType.checklist: Color(0xFF1B5E20),
      NodeType.canvas: Color(0xFF0D47A1),
      NodeType.weather: Color(0xFF0D47A1),
      NodeType.fit: Color(0xFF1B5E20),
    },
  );
}

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
  static const Color mood = Color(0xFFFF4FD8);
  static const Color timer = Color(0xFFFF8C1A);
  static const Color quote = Color(0xFFFFEA00);
  static const Color audio = Color(0xFF80ECFF);
  static const Color checklist = Color(0xFF7CFF8E);
  static const Color canvas = Color(0xFF73D7FF);
  static const Color weather = Color(0xFFFFEA00);
  static const Color fit = Color(0xFF7CFF8E);

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
    mood,
    timer,
    quote,
    audio,
    checklist,
    canvas,
    weather,
    fit,
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

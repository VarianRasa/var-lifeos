import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import 'app_colors.dart';

abstract final class NodeVisuals {
  static IconData icon(NodeType type) => switch (type) {
    NodeType.task => Icons.check_circle_outline,
    NodeType.kanban => Icons.view_kanban_outlined,
    NodeType.plan => Icons.route_outlined,
    NodeType.note => Icons.notes_outlined,
    NodeType.journal => Icons.book_outlined,
    NodeType.habit => Icons.repeat_outlined,
    NodeType.goal => Icons.flag_outlined,
    NodeType.link => Icons.link_outlined,
    NodeType.event => Icons.event_outlined,
    NodeType.decision => Icons.rule_outlined,
    NodeType.resource => Icons.inventory_2_outlined,
    NodeType.idea => Icons.lightbulb_outline,
    NodeType.question => Icons.help_outline,
    NodeType.contact => Icons.person_outline,
    NodeType.metric => Icons.query_stats_outlined,
    NodeType.expense => Icons.payments_outlined,
    NodeType.bookmark => Icons.bookmark_border,
    NodeType.routine => Icons.repeat_on_outlined,
    NodeType.mood => Icons.mood,
    NodeType.timer => Icons.timer_outlined,
    NodeType.quote => Icons.format_quote_outlined,
    NodeType.audio => Icons.mic_none_outlined,
    NodeType.checklist => Icons.checklist_rtl_outlined,
    NodeType.canvas => Icons.gesture_outlined,
    NodeType.weather => Icons.wb_sunny_outlined,
    NodeType.fit => Icons.directions_run_outlined,
    NodeType.empty => Icons.circle_outlined,
    NodeType.itinerary => Icons.travel_explore_outlined,
    NodeType.image => Icons.image_outlined,
    NodeType.video => Icons.videocam_outlined,
    NodeType.frame => Icons.crop_free_outlined,
    NodeType.swatch => Icons.palette_outlined,
  };

  static Color color(BuildContext context, NodeType type) {
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    return semantic?.nodeColors[type] ?? Theme.of(context).colorScheme.primary;
  }

  static Color colorForVariant(AppThemeVariant variant, NodeType type) {
    return AppThemeVariantColors.of(variant).nodeColors[type] ??
        AppThemeVariantColors.of(
          AppThemeVariant.astryxNeutral,
        ).nodeColors[NodeType.empty]!;
  }
}

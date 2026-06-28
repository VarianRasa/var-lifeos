/// App-wide constant values and keys.
library;

/// Semantic name + product identity.
class AppInfo {
  const AppInfo._();

  static const String name = 'Var';
  static const String tagline = 'Every day is a variable.';
  static const String description = 'Calendar-centric productivity.';
}

/// Supported node types that can live inside a day's mindmap.
///
/// Each type renders its own widget and editor. Order here is the default
/// ordering used in toolbars and the index menu.
enum NodeType {
  task,
  kanban,
  plan,
  note,
  journal,
  habit,
  goal,
  link,
  empty;

  /// Human-readable label for chips, menus, and dialogs.
  String get label {
    switch (this) {
      case NodeType.task:
        return 'Task';
      case NodeType.kanban:
        return 'Kanban';
      case NodeType.plan:
        return 'Plan';
      case NodeType.note:
        return 'Note';
      case NodeType.journal:
        return 'Journal';
      case NodeType.habit:
        return 'Habit';
      case NodeType.goal:
        return 'Goal';
      case NodeType.link:
        return 'Link';
      case NodeType.empty:
        return 'Empty';
    }
  }
}

/// Layout + canvas tunables kept in one place so they're easy to tune.
class LayoutConstants {
  const LayoutConstants._();

  /// Breakpoint (in logical pixels) above which we use a desktop layout
  /// (sidebar nav) instead of mobile (bottom nav).
  static const double desktopBreakpoint = 840;

  /// Compact target density for data-dense UI.
  static const double denseSpacing = 4;
  static const double comfortableSpacing = 8;
  static const double looseSpacing = 16;
}

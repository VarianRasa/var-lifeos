/// Astryx window chrome for Windows desktop.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_design_tokens.dart';

/// Small native-window boundary kept injectable for widget tests.
enum DesktopMenuAction {
  quickCapture,
  today,
  calendar,
  focus,
  goalsHabits,
  notesJournal,
  workspaces,
  insights,
  graph,
  collab,
  settings,
  commandPalette,
  toggleTopHeader,
  toggleRibbonToolbar,
  toggleBoardTabs,
  toggleAllCanvasControls,
  closePanel,
  resetPanelWidth,
  recoveryCenter,
  about,
}

class DesktopMenuController extends ChangeNotifier {
  DesktopMenuAction? _action;

  DesktopMenuAction? get action => _action;

  void invoke(DesktopMenuAction action) {
    _action = action;
    notifyListeners();
  }
}

final desktopMenuController = DesktopMenuController();

bool isWindowsDesktop({bool? override}) =>
    override ??
    (!kIsWeb &&
        !const bool.fromEnvironment('FLUTTER_TEST') &&
        defaultTargetPlatform == TargetPlatform.windows);

abstract interface class DesktopWindowController {
  void addListener(WindowListener listener);

  void removeListener(WindowListener listener);

  Future<bool> isMaximized();

  Future<void> minimize();

  Future<void> maximize();

  Future<void> unmaximize();

  Future<void> close();

  Future<void> startDragging();

  Future<void> popUpWindowMenu();
}

/// Adds custom window controls only on native Windows builds.
class DesktopWindowChrome extends StatefulWidget {
  const DesktopWindowChrome({
    required this.child,
    this.controller,
    this.enabled,
    super.key,
  });

  final Widget child;

  /// Override for tests. Production uses [windowManager].
  final DesktopWindowController? controller;

  /// Override for tests. Production follows current platform.
  final bool? enabled;

  @override
  State<DesktopWindowChrome> createState() => _DesktopWindowChromeState();
}

class _DesktopWindowChromeState extends State<DesktopWindowChrome>
    with WindowListener {
  late final bool _enabled = isWindowsDesktop(override: widget.enabled);
  late final DesktopWindowController _controller =
      widget.controller ?? const _WindowManagerController();
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    _controller.addListener(this);
    unawaited(_loadWindowState());
  }

  Future<void> _loadWindowState() async {
    final isMaximized = await _controller.isMaximized();
    if (mounted) setState(() => _isMaximized = isMaximized);
  }

  Future<void> _toggleMaximized() async {
    final isMaximized = await _controller.isMaximized();
    if (isMaximized) {
      await _controller.unmaximize();
    } else {
      await _controller.maximize();
    }
    if (mounted) setState(() => _isMaximized = !isMaximized);
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void dispose() {
    if (_enabled) _controller.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;

    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    return ColoredBox(
      color: semantic.background,
      child: Column(
        children: [
          DecoratedBox(
            key: const ValueKey('windows-title-bar'),
            decoration: BoxDecoration(
              color: semantic.surface,
              border: Border(bottom: BorderSide(color: semantic.border)),
            ),
            child: SizedBox(
              height: tokens.minimumTarget,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            tokens.radiusInner,
                          ),
                          child: Image.asset(
                            'assets/branding/app_icon.png',
                            width: 20,
                            height: 20,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppInfo.name,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: semantic.textPrimary),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  const _DesktopMenuBar(),
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('windows-drag-region'),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => unawaited(_controller.startDragging()),
                      onDoubleTap: () => unawaited(_toggleMaximized()),
                      onSecondaryTapDown: (_) =>
                          unawaited(_controller.popUpWindowMenu()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: semantic.surfaceRaised,
                        borderRadius: BorderRadius.circular(tokens.radiusInner),
                        border: Border.all(color: semantic.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _WindowControlButton(
                            controlKey: const ValueKey('windows-minimize'),
                            tooltip: 'Minimize',
                            icon: Icons.remove_rounded,
                            onPressed: () => unawaited(_controller.minimize()),
                          ),
                          _WindowControlButton(
                            controlKey: ValueKey(
                              _isMaximized
                                  ? 'windows-restore'
                                  : 'windows-maximize',
                            ),
                            tooltip: _isMaximized ? 'Restore' : 'Maximize',
                            icon: _isMaximized
                                ? Icons.filter_none_rounded
                                : Icons.crop_square_rounded,
                            onPressed: () => unawaited(_toggleMaximized()),
                          ),
                          _WindowControlButton(
                            controlKey: const ValueKey('windows-close'),
                            tooltip: 'Close',
                            icon: Icons.close_rounded,
                            danger: true,
                            onPressed: () => unawaited(_controller.close()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _DesktopMenuBar extends StatelessWidget {
  const _DesktopMenuBar();

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final theme = Theme.of(context);
    final menuButtonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 11),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? semantic.textPrimary
            : semantic.textSecondary,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)
            ? semantic.surfaceRaised
            : Colors.transparent,
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      textStyle: WidgetStatePropertyAll(
        theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
    final popupStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(semantic.surfaceRaised),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(10),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: semantic.border),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      child: MenuBar(
        style: const MenuStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
          elevation: WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
        children: [
          _menu(
            'File',
            {'Quick Capture': DesktopMenuAction.quickCapture},
            menuButtonStyle,
            popupStyle,
          ),
          _menu(
            'Navigate',
            {
              'Today': DesktopMenuAction.today,
              'Calendar': DesktopMenuAction.calendar,
              'Focus': DesktopMenuAction.focus,
              'Goals & Habits': DesktopMenuAction.goalsHabits,
              'Notes & Journal': DesktopMenuAction.notesJournal,
              'Workspaces': DesktopMenuAction.workspaces,
              'Insights': DesktopMenuAction.insights,
              'Graph': DesktopMenuAction.graph,
              'Collab': DesktopMenuAction.collab,
              'Settings': DesktopMenuAction.settings,
            },
            menuButtonStyle,
            popupStyle,
          ),
          _menu(
            'View',
            {
              'Toggle Top Header Bar': DesktopMenuAction.toggleTopHeader,
              'Toggle Board Tabs': DesktopMenuAction.toggleBoardTabs,
              'Hide/Show All Controls':
                  DesktopMenuAction.toggleAllCanvasControls,
              'Close panel': DesktopMenuAction.closePanel,
              'Reset panel width': DesktopMenuAction.resetPanelWidth,
            },
            menuButtonStyle,
            popupStyle,
          ),
          _menu(
            'Tools',
            {
              'Command Palette': DesktopMenuAction.commandPalette,
              'Recovery Center': DesktopMenuAction.recoveryCenter,
            },
            menuButtonStyle,
            popupStyle,
          ),
          _menu(
            'Help',
            {'About Var': DesktopMenuAction.about},
            menuButtonStyle,
            popupStyle,
          ),
        ],
      ),
    );
  }

  SubmenuButton _menu(
    String label,
    Map<String, DesktopMenuAction> actions,
    ButtonStyle buttonStyle,
    MenuStyle menuStyle,
  ) {
    return SubmenuButton(
      key: ValueKey('windows-menu-${label.toLowerCase()}'),
      style: buttonStyle,
      menuStyle: menuStyle,
      menuChildren: [
        for (final entry in actions.entries)
          MenuItemButton(
            key: ValueKey('windows-menu-${entry.value.name}'),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(210, 38)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 12),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              ),
            ),
            leadingIcon: Icon(entry.value.icon, size: 17),
            trailingIcon: entry.value.shortcut == null
                ? null
                : Text(
                    entry.value.shortcut!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
            onPressed: () => desktopMenuController.invoke(entry.value),
            child: Text(entry.key),
          ),
      ],
      child: Text(label),
    );
  }
}

extension on DesktopMenuAction {
  IconData get icon => switch (this) {
    DesktopMenuAction.quickCapture => Icons.bolt_rounded,
    DesktopMenuAction.today => Icons.today_rounded,
    DesktopMenuAction.calendar => Icons.calendar_month_rounded,
    DesktopMenuAction.focus => Icons.timer_rounded,
    DesktopMenuAction.goalsHabits => Icons.track_changes_rounded,
    DesktopMenuAction.notesJournal => Icons.auto_stories_rounded,
    DesktopMenuAction.workspaces => Icons.workspaces_rounded,
    DesktopMenuAction.insights => Icons.insights_rounded,
    DesktopMenuAction.graph => Icons.account_tree_rounded,
    DesktopMenuAction.collab => Icons.people_rounded,
    DesktopMenuAction.settings => Icons.settings_rounded,
    DesktopMenuAction.commandPalette => Icons.manage_search_rounded,
    DesktopMenuAction.toggleTopHeader => Icons.vertical_align_top_rounded,
    DesktopMenuAction.toggleRibbonToolbar => Icons.view_headline_rounded,
    DesktopMenuAction.toggleBoardTabs => Icons.tab_rounded,
    DesktopMenuAction.toggleAllCanvasControls => Icons.visibility_off_rounded,
    DesktopMenuAction.closePanel => Icons.close_fullscreen_rounded,
    DesktopMenuAction.resetPanelWidth => Icons.width_normal_rounded,
    DesktopMenuAction.recoveryCenter => Icons.restore_rounded,
    DesktopMenuAction.about => Icons.info_outline_rounded,
  };

  String? get shortcut => switch (this) {
    DesktopMenuAction.quickCapture => 'Ctrl+Q',
    DesktopMenuAction.today => 'Ctrl+T',
    DesktopMenuAction.commandPalette => 'Ctrl+K',
    DesktopMenuAction.toggleTopHeader => 'Ctrl+Alt+1',
    DesktopMenuAction.toggleBoardTabs => 'Ctrl+Alt+2',
    DesktopMenuAction.toggleAllCanvasControls => 'Ctrl+Shift+H',
    DesktopMenuAction.closePanel => 'Esc',
    _ => null,
  };
}

class _WindowControlButton extends StatelessWidget {
  const _WindowControlButton({
    required this.controlKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final Key controlKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    return Semantics(
      key: controlKey,
      label: tooltip,
      button: true,
      enabled: true,
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton(
        onPressed: onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          fixedSize: const WidgetStatePropertyAll(Size(44, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (danger &&
                (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed))) {
              return semantic.onDanger;
            }
            return semantic.textSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (danger && states.contains(WidgetState.hovered)) {
              return semantic.danger;
            }
            if (danger && states.contains(WidgetState.pressed)) {
              return semantic.danger.withValues(alpha: 0.88);
            }
            if (states.contains(WidgetState.pressed)) {
              return semantic.pressedOverlay;
            }
            if (states.contains(WidgetState.hovered)) {
              return semantic.hoverOverlay;
            }
            return Colors.transparent;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.focused)
                ? BorderSide(color: semantic.focusRing, width: 2)
                : BorderSide.none;
          }),
        ),
        icon: Icon(icon, size: 16),
      ),
    );
  }
}

class _WindowManagerController implements DesktopWindowController {
  const _WindowManagerController();

  @override
  void addListener(WindowListener listener) =>
      windowManager.addListener(listener);

  @override
  void removeListener(WindowListener listener) =>
      windowManager.removeListener(listener);

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> unmaximize() => windowManager.unmaximize();

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<void> popUpWindowMenu() => windowManager.popUpWindowMenu();
}

/// App shell with adaptive Astryx navigation.
///
/// Mobile (<=768px) uses a drawer. Larger non-Windows layouts use TopNav;
/// Windows uses native-style title menus. Feature pages keep their own content
/// scaffolds while this shell manages navigation and global shortcuts.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_design_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../features/command/global_command_palette.dart';
import '../../features/command/presentation/quick_capture_dock.dart';
import '../../features/focus/widgets/top_bar_focus_timer_pill.dart';
import '../widgets/astryx_kbd.dart';
import 'desktop_window_chrome.dart';

final navigationSidebarCollapsedProvider = StateProvider<bool>((ref) => false);
final routePanelResetController = ValueNotifier<int>(0);

class AdaptiveScaffold extends ConsumerStatefulWidget {
  const AdaptiveScaffold({required this.body, this.windowsDesktop, super.key});

  final Widget body;
  final bool? windowsDesktop;

  @override
  ConsumerState<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends ConsumerState<AdaptiveScaffold> {
  @override
  void initState() {
    super.initState();
    desktopMenuController.addListener(_handleDesktopMenu);
  }

  @override
  void dispose() {
    desktopMenuController.removeListener(_handleDesktopMenu);
    super.dispose();
  }

  void _handleDesktopMenu() {
    final action = desktopMenuController.takeAction();
    if (action == null || !mounted) return;
    switch (action) {
      case DesktopMenuAction.quickCapture:
        final visible = ref.read(quickCaptureVisibleProvider);
        ref.read(quickCaptureVisibleProvider.notifier).state = !visible;
      case DesktopMenuAction.today:
        context.go('/calendar/${dayKey(DateTime.now())}');
      case DesktopMenuAction.commandPalette:
        showGlobalCommandPalette(context);
      case DesktopMenuAction.toggleTopHeader:
      case DesktopMenuAction.toggleRibbonToolbar:
      case DesktopMenuAction.toggleBoardTabs:
      case DesktopMenuAction.toggleAllCanvasControls:
        break;
      case DesktopMenuAction.closePanel:
        final date = GoRouterState.of(context).pathParameters['date'];
        context.go('/calendar/${date ?? dayKey(DateTime.now())}');
      case DesktopMenuAction.resetPanelWidth:
        routePanelResetController.value++;
      case DesktopMenuAction.recoveryCenter:
        context.go('/recovery');
      case DesktopMenuAction.about:
        showAboutDialog(
          context: context,
          applicationName: AppInfo.name,
          applicationVersion: '1.0.1',
        );
      case DesktopMenuAction.calendar:
      case DesktopMenuAction.search:
      case DesktopMenuAction.focus:
      case DesktopMenuAction.goalsHabits:
      case DesktopMenuAction.notesJournal:
      case DesktopMenuAction.workspaces:
      case DesktopMenuAction.insights:
      case DesktopMenuAction.graph:
      case DesktopMenuAction.collab:
      case DesktopMenuAction.settings:
        final route = AppRoute.values.byName(action.name);
        context.go(appRouteLocation(context, route));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final uri = GoRouterState.of(context).uri;
    final route =
        AppRoute.fromPanel(uri.queryParameters['panel']) ??
        _routeFromLocation(uri.path);
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width <= LayoutConstants.mobileBreakpoint;
    final isSidebarCollapsed = ref.watch(navigationSidebarCollapsedProvider);
    final theme = Theme.of(context);
    final pageTheme = theme.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
    );
    final isQuickCaptureVisible = ref.watch(quickCaptureVisibleProvider);
    final windowsDesktop = isWindowsDesktop(override: widget.windowsDesktop);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            showGlobalCommandPalette(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            showGlobalCommandPalette(context),
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          control: true,
          shift: true,
        ): () => ref.read(quickCaptureVisibleProvider.notifier).state =
            !isQuickCaptureVisible,
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () =>
            ref.read(quickCaptureVisibleProvider.notifier).state =
                !isQuickCaptureVisible,
        const SingleActivator(LogicalKeyboardKey.keyQ, meta: true): () =>
            ref.read(quickCaptureVisibleProvider.notifier).state =
                !isQuickCaptureVisible,
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
            context.go('/calendar/${dayKey(DateTime.now())}'),
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () =>
            context.go('/calendar/${dayKey(DateTime.now())}'),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
          if (windowsDesktop) {
            desktopMenuController.openNavigateMenu();
          } else {
            ref.read(navigationSidebarCollapsedProvider.notifier).state =
                !isSidebarCollapsed;
          }
        },
        if (!windowsDesktop)
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
              ref.read(navigationSidebarCollapsedProvider.notifier).state =
                  !isSidebarCollapsed,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          drawer: !windowsDesktop && isMobile
              ? _AstryxNavigationDrawer(route: route)
              : null,
          body: Stack(
            children: [
              Positioned.fill(
                child: windowsDesktop
                    ? Theme(data: pageTheme, child: widget.body)
                    : isMobile
                    ? Column(
                        children: [
                          _MobileShellHeader(route: route),
                          Expanded(
                            child: Theme(data: pageTheme, child: widget.body),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          AstryxTopNav(
                            route: route,
                            navigationCollapsed: isSidebarCollapsed,
                          ),
                          Expanded(
                            child: Theme(data: pageTheme, child: widget.body),
                          ),
                        ],
                      ),
              ),
              if (isQuickCaptureVisible)
                const Positioned.fill(child: QuickCaptureDock()),
            ],
          ),
        ),
      ),
    );
  }
}

const _primaryRoutes = <AppRoute>[
  AppRoute.calendar,
  AppRoute.search,
  AppRoute.focus,
  AppRoute.workspaces,
];

const _analysisRoutes = <AppRoute>[AppRoute.insights, AppRoute.graph];

const _systemRoutes = <AppRoute>[AppRoute.collab, AppRoute.settings];

const _navigationRoutes = <AppRoute>[
  ..._primaryRoutes,
  ..._analysisRoutes,
  ..._systemRoutes,
];

class _MobileShellHeader extends ConsumerWidget {
  const _MobileShellHeader({required this.route});

  final AppRoute route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Builder(
                builder: (context) => IconButton(
                  key: const ValueKey('astryx-mobile-menu'),
                  tooltip: 'Open navigation',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
              ),
              Expanded(
                child: Text(
                  route.label,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Flexible(
                child: TopBarFocusTimerPill(
                  compact: true,
                  onTap: () =>
                      context.go(appRouteLocation(context, AppRoute.focus)),
                ),
              ),
              IconButton(
                key: const ValueKey('astryx-mobile-quick-capture'),
                tooltip: 'Quick capture',
                onPressed: () {
                  final visible = ref.read(quickCaptureVisibleProvider);
                  ref.read(quickCaptureVisibleProvider.notifier).state =
                      !visible;
                },
                icon: const Icon(Icons.bolt_outlined),
              ),
              IconButton(
                tooltip: 'Command palette',
                onPressed: () => showGlobalCommandPalette(context),
                icon: const Icon(Icons.manage_search_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AstryxNavigationDrawer extends StatelessWidget {
  const _AstryxNavigationDrawer({required this.route});

  final AppRoute route;

  @override
  Widget build(BuildContext context) {
    return NavigationDrawer(
      key: const ValueKey('astryx-mobile-drawer'),
      selectedIndex: _navigationRoutes.indexOf(route),
      onDestinationSelected: (index) {
        Navigator.of(context).pop();
        context.go(appRouteLocation(context, _navigationRoutes[index]));
      },
      children: [
        const SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [_BrandMark(), SizedBox(width: 12), Text('Var LifeOS')],
            ),
          ),
        ),
        ..._drawerSection('Main', _primaryRoutes),
        ..._drawerSection('Analyze', _analysisRoutes),
        ..._drawerSection('System', _systemRoutes),
      ],
    );
  }

  static List<Widget> _drawerSection(String label, List<AppRoute> routes) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 6),
      child: Text(label),
    ),
    for (final route in routes)
      NavigationDrawerDestination(
        key: ValueKey('astryx-drawer-${route.name}'),
        icon: Icon(route.icon),
        selectedIcon: Icon(route.selectedIcon),
        label: Text(route.label),
      ),
  ];
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset(
        'assets/branding/app_icon.png',
        width: 24,
        height: 24,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// Maps a router location to the active top-level route.
AppRoute _routeFromLocation(String location) {
  if (location.startsWith('/calendar')) return AppRoute.calendar;
  if (location.startsWith('/search')) return AppRoute.search;
  if (location.startsWith('/focus')) return AppRoute.focus;
  if (location.startsWith('/workspaces')) return AppRoute.workspaces;
  if (location.startsWith('/insights')) return AppRoute.insights;
  if (location.startsWith('/graph')) return AppRoute.graph;
  if (location.startsWith('/collab')) return AppRoute.collab;
  if (location.startsWith('/settings') || location.startsWith('/recovery')) {
    return AppRoute.settings;
  }
  return AppRoute.calendar;
}

/// Astryx TopNav navigation header component for Web & Desktop shell.
class AstryxTopNav extends ConsumerWidget {
  const AstryxTopNav({
    required this.route,
    this.navigationCollapsed = false,
    super.key,
  });

  final AppRoute route;
  final bool navigationCollapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final showMenu =
            width >= 900 &&
            !navigationCollapsed &&
            (textScale < 2 || width >= 1440);
        final showSearchText = width >= 720 && textScale < 2;
        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: semantic.surface,
            border: Border(bottom: BorderSide(color: semantic.border)),
          ),
          child: Row(
            children: [
              // Brand
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(tokens.radiusInner),
                    child: Image.asset(
                      'assets/branding/app_icon.png',
                      width: 22,
                      height: 22,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (showSearchText) ...[
                    const SizedBox(width: 10),
                    Text('Var LifeOS', style: theme.textTheme.labelLarge),
                  ],
                ],
              ),
              const SizedBox(width: 20),

              // Menu Dropdowns (File, Navigate, Tools)
              if (showMenu) ...[
                const _TopNavMenuBar(),
                const SizedBox(width: 20),
              ],

              // Search / Command Trigger Bar
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: InkWell(
                      key: const ValueKey('astryx-topnav-search'),
                      onTap: () => showGlobalCommandPalette(context),
                      borderRadius: BorderRadius.circular(tokens.radiusElement),
                      child: Container(
                        constraints: BoxConstraints(
                          minHeight: tokens.minimumTarget,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: semantic.surfaceRaised,
                          borderRadius: BorderRadius.circular(
                            tokens.radiusElement,
                          ),
                          border: Border.all(color: semantic.border),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              size: 16,
                              color: semantic.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Search nodes...',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: semantic.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const AstryxKbd(label: 'Ctrl K'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Right Controls (Timer, Capture, Settings)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TopBarFocusTimerPill(
                    compact: !showSearchText,
                    onTap: () =>
                        context.go(appRouteLocation(context, AppRoute.focus)),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const ValueKey('astryx-topnav-quick-capture'),
                    tooltip: 'Quick capture (Ctrl+Q)',
                    onPressed: () {
                      final visible = ref.read(quickCaptureVisibleProvider);
                      ref.read(quickCaptureVisibleProvider.notifier).state =
                          !visible;
                    },
                    icon: const Icon(Icons.bolt_outlined, size: 20),
                  ),
                  IconButton(
                    key: const ValueKey('astryx-topnav-settings'),
                    tooltip: 'Settings',
                    onPressed: () => context.go(
                      appRouteLocation(context, AppRoute.settings),
                    ),
                    icon: const Icon(Icons.settings_outlined, size: 20),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopNavMenuBar extends StatelessWidget {
  const _TopNavMenuBar();

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final theme = Theme.of(context);
    final tokens = AppDesignTokens.of(context);

    final menuButtonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(tokens.minimumTarget, tokens.minimumTarget),
      ),
      visualDensity: VisualDensity.standard,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? semantic.textPrimary
            : semantic.textSecondary,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? semantic.surfaceRaised
            : Colors.transparent,
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusInner),
        ),
      ),
      textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
    );

    final popupStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(semantic.surfaceRaised),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(8),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusElement),
          side: BorderSide(color: semantic.border),
        ),
      ),
    );

    return MenuBar(
      style: const MenuStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        elevation: WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      children: [
        _menu(
          context,
          'File',
          {'Quick Capture': DesktopMenuAction.quickCapture},
          menuButtonStyle,
          popupStyle,
        ),
        _menu(
          context,
          'Navigate',
          {
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
          includeSearch: true,
        ),
        _menu(
          context,
          'Tools',
          {
            'Command Palette': DesktopMenuAction.commandPalette,
            'Recovery Center': DesktopMenuAction.recoveryCenter,
          },
          menuButtonStyle,
          popupStyle,
        ),
      ],
    );
  }

  Widget _menu(
    BuildContext context,
    String label,
    Map<String, DesktopMenuAction> items,
    ButtonStyle style,
    MenuStyle popupStyle, {
    bool includeSearch = false,
  }) {
    return SubmenuButton(
      key: ValueKey('astryx-topnav-menu-${label.toLowerCase()}'),
      style: style,
      menuStyle: popupStyle,
      menuChildren: [
        if (includeSearch)
          MenuItemButton(
            onPressed: () => context.go('/search'),
            child: const Text('Search'),
          ),
        for (final entry in items.entries)
          MenuItemButton(
            onPressed: () => desktopMenuController.invoke(entry.value),
            child: Text(entry.key),
          ),
      ],
      child: Text(label),
    );
  }
}

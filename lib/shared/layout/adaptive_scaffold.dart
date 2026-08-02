/// App shell with adaptive Astryx navigation.
///
/// Mobile (<=768px) uses a drawer, medium widths use a compact rail, and
/// desktop (>1024px) uses an extended rail. Feature pages keep their own
/// content scaffolds while this shell manages navigation and global shortcuts.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/date_utils.dart';
import '../../features/command/global_command_palette.dart';
import '../../features/command/presentation/quick_capture_dock.dart';
import '../../features/focus/widgets/top_bar_focus_timer_pill.dart';
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
    final action = desktopMenuController.action;
    if (action == null || !mounted) return;
    switch (action) {
      case DesktopMenuAction.quickCapture:
        final visible = ref.read(quickCaptureVisibleProvider);
        ref.read(quickCaptureVisibleProvider.notifier).state = !visible;
      case DesktopMenuAction.today:
        context.go('/calendar/${dayKey(DateTime.now())}');
      case DesktopMenuAction.commandPalette:
        showGlobalCommandPalette(context);
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
    final canExtend = size.width > LayoutConstants.mediumBreakpoint;
    final isSidebarCollapsed = ref.watch(navigationSidebarCollapsedProvider);
    final isExtended = canExtend && !isSidebarCollapsed;
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
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            ref.read(navigationSidebarCollapsedProvider.notifier).state =
                !isSidebarCollapsed,
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
                    : Row(
                        children: [
                          _AstryxNavigationRail(
                            route: route,
                            extended: isExtended,
                          ),
                          VerticalDivider(
                            width: 1,
                            color: theme.colorScheme.outlineVariant,
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
  AppRoute.focus,
  AppRoute.goalsHabits,
  AppRoute.notesJournal,
  AppRoute.workspaces,
];

const _analysisRoutes = <AppRoute>[AppRoute.insights, AppRoute.graph];

const _systemRoutes = <AppRoute>[AppRoute.collab, AppRoute.settings];

class _AstryxNavigationRail extends ConsumerWidget {
  const _AstryxNavigationRail({required this.route, required this.extended});

  final AppRoute route;
  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    const destinations = AppRoute.values;
    final selectedIndex = destinations.indexOf(route);
    return SizedBox(
      key: ValueKey(extended ? 'astryx-extended-rail' : 'astryx-compact-rail'),
      width: extended
          ? LayoutConstants.extendedNavigationWidth
          : LayoutConstants.compactNavigationWidth,
      child: NavigationRail(
        extended: extended,
        minWidth: LayoutConstants.compactNavigationWidth,
        minExtendedWidth: LayoutConstants.extendedNavigationWidth,
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        onDestinationSelected: (index) =>
            context.go(appRouteLocation(context, destinations[index])),
        leading: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BrandMark(),
              const SizedBox(height: 8),
              IconButton(
                key: const ValueKey('astryx-rail-collapse'),
                tooltip: extended ? 'Collapse navigation' : 'Expand navigation',
                onPressed: () {
                  final collapsed = ref.read(
                    navigationSidebarCollapsedProvider,
                  );
                  ref.read(navigationSidebarCollapsedProvider.notifier).state =
                      !collapsed;
                },
                icon: Icon(
                  extended
                      ? Icons.keyboard_double_arrow_left
                      : Icons.keyboard_double_arrow_right,
                ),
              ),
            ],
          ),
        ),
        scrollable: true,
        trailing: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TopBarFocusTimerPill(
                compact: !extended,
                onTap: () =>
                    context.go(appRouteLocation(context, AppRoute.focus)),
              ),
              const SizedBox(height: 4),
              IconButton(
                key: const ValueKey('astryx-command-button'),
                tooltip: 'Command palette (Ctrl/⌘+K)',
                onPressed: () => showGlobalCommandPalette(context),
                icon: const Icon(Icons.manage_search_outlined),
              ),
              IconButton(
                key: const ValueKey('astryx-quick-capture-button'),
                tooltip: 'Quick capture (Ctrl/⌘+Q)',
                onPressed: () {
                  final visible = ref.read(quickCaptureVisibleProvider);
                  ref.read(quickCaptureVisibleProvider.notifier).state =
                      !visible;
                },
                icon: const Icon(Icons.bolt_outlined),
              ),
              if (extended)
                Text(
                  'Var LifeOS',
                  style: theme.textTheme.labelMedium,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
        destinations: [
          for (final destination in destinations)
            NavigationRailDestination(
              icon: Tooltip(
                key: ValueKey('astryx-rail-${destination.name}'),
                message: destination.label,
                child: Icon(destination.icon),
              ),
              selectedIcon: Icon(destination.selectedIcon),
              label: Text(destination.label),
            ),
        ],
      ),
    );
  }
}

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
                  style: Theme.of(context).textTheme.headlineMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TopBarFocusTimerPill(
                compact: true,
                onTap: () =>
                    context.go(appRouteLocation(context, AppRoute.focus)),
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
      selectedIndex: AppRoute.values.indexOf(route),
      onDestinationSelected: (index) {
        Navigator.of(context).pop();
        context.go(appRouteLocation(context, AppRoute.values[index]));
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
  if (location.startsWith('/focus')) return AppRoute.focus;
  if (location.startsWith('/goals-habits')) return AppRoute.goalsHabits;
  if (location.startsWith('/notes-journal')) return AppRoute.notesJournal;
  if (location.startsWith('/workspaces')) return AppRoute.workspaces;
  if (location.startsWith('/insights')) return AppRoute.insights;
  if (location.startsWith('/graph')) return AppRoute.graph;
  if (location.startsWith('/collab')) return AppRoute.collab;
  if (location.startsWith('/settings') || location.startsWith('/recovery')) {
    return AppRoute.settings;
  }
  return AppRoute.calendar;
}

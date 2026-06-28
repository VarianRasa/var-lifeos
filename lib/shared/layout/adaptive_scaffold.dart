/// App shell with adaptive navigation.
///
/// Desktop (>840px): Compact floating nav + command button.
/// Mobile (<840px): Bottom navigation bar.
/// All feature pages keep their own content scaffolds, while this shell manages
/// route navigation and the global command palette button.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/date_utils.dart';
import '../../features/command/global_command_palette.dart';
import '../../features/mindmap/application/focus_timer_provider.dart';
import '../../features/mindmap/application/mindmap_providers.dart';

class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({required this.body, super.key});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final route = _routeFromLocation(location);
    final isDesktop =
        MediaQuery.sizeOf(context).width >= LayoutConstants.desktopBreakpoint;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            showGlobalCommandPalette(context),
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): () {
          final todayStr = dayKey(DateTime.now());
          context.go('/calendar/$todayStr');
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            children: [
              // Main content fills the entire viewport
              Positioned.fill(child: body),

              // Desktop: floating nav + command button
              if (isDesktop) ...[
                const Positioned(
                  top: 10,
                  right: 310,
                  child: _FocusTimerButton(),
                ),
                const Positioned(
                  top: 10,
                  right: 260,
                  child: _GlobalCommandButton(),
                ),
                Positioned(
                  top: 10,
                  right: 64,
                  child: _FloatingNavigationMenu(route: route),
                ),
              ],
            ],
          ),

          // Mobile: bottom navigation bar
          bottomNavigationBar: isDesktop
              ? null
              : _MobileBottomNav(route: route),
        ),
      ),
    );
  }
}

/// Mobile bottom navigation bar with smooth animated indicator.
class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({required this.route});

  final AppRoute route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
      ),
      child: NavigationBar(
        selectedIndex: route.index,
        onDestinationSelected: (index) => _go(context, AppRoute.values[index]),
        destinations: [
          for (final destination in AppRoute.values)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

class _GlobalCommandButton extends StatefulWidget {
  const _GlobalCommandButton();

  @override
  State<_GlobalCommandButton> createState() => _GlobalCommandButtonState();
}

class _GlobalCommandButtonState extends State<_GlobalCommandButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.diagonal3Values(
          _isHovered ? 1.05 : 1.0,
          _isHovered ? 1.05 : 1.0,
          1.0,
        ),
        transformAlignment: Alignment.center,
        child: Material(
          elevation: 0,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.4,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _isHovered
                    ? theme.colorScheme.primary.withValues(alpha: 0.5)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: SizedBox.square(
              dimension: 36,
              child: IconButton(
                key: const ValueKey('global-command-button'),
                tooltip: 'Open command palette (Ctrl+K)',
                onPressed: () => showGlobalCommandPalette(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.manage_search,
                  size: 20,
                  color: _isHovered ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingNavigationMenu extends StatefulWidget {
  const _FloatingNavigationMenu({required this.route});

  final AppRoute route;

  @override
  State<_FloatingNavigationMenu> createState() =>
      _FloatingNavigationMenuState();
}

class _FloatingNavigationMenuState extends State<_FloatingNavigationMenu> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: PopupMenuButton<AppRoute>(
        key: const ValueKey('floating-nav-menu-button'),
        tooltip: 'Navigation',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        constraints: const BoxConstraints(minWidth: 200),
        color: theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onSelected: (destination) => _go(context, destination),
        itemBuilder: (context) => [
          for (final destination in AppRoute.values)
            PopupMenuItem<AppRoute>(
              key: ValueKey('floating-nav-item-${destination.name}'),
              value: destination,
              height: 44,
              child: _FloatingNavigationItem(
                route: destination,
                isSelected: destination == widget.route,
              ),
            ),
        ],
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.diagonal3Values(
            _isHovered ? 1.03 : 1.0,
            _isHovered ? 1.03 : 1.0,
            1.0,
          ),
          transformAlignment: Alignment.center,
          child: Material(
            elevation: 0,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isHovered
                      ? theme.colorScheme.primary.withValues(alpha: 0.5)
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _BrandMark(),
                    const SizedBox(width: 8),
                    Icon(widget.route.selectedIcon, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      widget.route.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_up_rounded,
                      size: 18,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingNavigationItem extends StatelessWidget {
  const _FloatingNavigationItem({
    required this.route,
    required this.isSelected,
  });

  final AppRoute route;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: isSelected
              ? BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Icon(
            isSelected ? route.selectedIcon : route.icon,
            size: 18,
            color: isSelected ? theme.colorScheme.primary : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            route.label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? theme.colorScheme.primary : null,
            ),
          ),
        ),
        if (isSelected)
          Icon(Icons.check_rounded, size: 16, color: theme.colorScheme.primary),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A6CF7), Color(0xFF6C8EEF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        'V',
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

void _go(BuildContext context, AppRoute route) {
  context.go(route.path);
}

/// Maps a router location to the active top-level route.
AppRoute _routeFromLocation(String location) {
  if (location.startsWith('/calendar')) return AppRoute.calendar;
  if (location.startsWith('/insights')) return AppRoute.insights;
  if (location.startsWith('/graph')) return AppRoute.graph;
  if (location.startsWith('/workspaces')) return AppRoute.workspaces;
  if (location.startsWith('/settings')) return AppRoute.settings;
  return AppRoute.calendar;
}

class _FocusTimerButton extends ConsumerStatefulWidget {
  const _FocusTimerButton();

  @override
  ConsumerState<_FocusTimerButton> createState() => _FocusTimerButtonState();
}

class _FocusTimerButtonState extends ConsumerState<_FocusTimerButton> {
  bool _isHovered = false;

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timerState = ref.watch(focusTimerProvider);
    final timerNotifier = ref.read(focusTimerProvider.notifier);

    final allNodesAsync = ref.watch(allMindmapNodesProvider);
    final activeTasks =
        allNodesAsync.valueOrNull
            ?.where(
              (n) => n.type == NodeType.task && !n.isDone && !n.isArchived,
            )
            .toList() ??
        [];

    final progressColor = timerState.phase == FocusTimerPhase.focus
        ? theme.colorScheme.primary
        : Colors.green;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: PopupMenuButton<void>(
        tooltip: 'Focus Timer',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 300),
        color: theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        itemBuilder: (context) => [
          PopupMenuItem<void>(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      timerState.phase.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: progressColor,
                      ),
                    ),
                    Text(
                      _formatDuration(timerState.remainingSeconds),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: timerState.isRunning ? 'Pause' : 'Start',
                      icon: Icon(
                        timerState.isRunning
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 32,
                        color: progressColor,
                      ),
                      onPressed: () {
                        if (timerState.isRunning) {
                          timerNotifier.pause();
                        } else {
                          timerNotifier.start();
                        }
                        setState(() {});
                      },
                    ),
                    IconButton(
                      tooltip: 'Skip Phase',
                      icon: const Icon(Icons.skip_next, size: 24),
                      onPressed: () {
                        timerNotifier.skip();
                        setState(() {});
                      },
                    ),
                    IconButton(
                      tooltip: 'Reset',
                      icon: const Icon(Icons.replay, size: 24),
                      onPressed: () {
                        timerNotifier.reset();
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _DurationPresetButton(
                      label: '25m',
                      value: 25,
                      notifier: timerNotifier,
                    ),
                    _DurationPresetButton(
                      label: '50m',
                      value: 50,
                      notifier: timerNotifier,
                    ),
                    _DurationPresetButton(
                      label: '5m Break',
                      value: 5,
                      notifier: timerNotifier,
                    ),
                    _DurationPresetButton(
                      label: '15m Break',
                      value: 15,
                      notifier: timerNotifier,
                    ),
                  ],
                ),
                const Divider(height: 20),
                Text(
                  timerState.selectedNodeId == null
                      ? 'Select Task to Focus On:'
                      : 'Focusing on:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                if (timerState.selectedNodeId != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.2,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.assignment,
                          size: 14,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            timerState.selectedNodeTitle ?? 'Untitled Task',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 14),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            timerNotifier.selectNode(null, null);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (activeTasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No active tasks today',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else ...[
                  for (final t in activeTasks.take(4)) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        Icons.assignment_outlined,
                        size: 14,
                        color: timerState.selectedNodeId == t.id
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        t.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: timerState.selectedNodeId == t.id
                              ? FontWeight.bold
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: timerState.selectedNodeId == t.id,
                      onTap: () {
                        timerNotifier.selectNode(t.id, t.title);
                        setState(() {});
                      },
                    ),
                  ],
                  if (activeTasks.length > 4)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '+ ${activeTasks.length - 4} more tasks',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.diagonal3Values(
            _isHovered ? 1.03 : 1.0,
            _isHovered ? 1.03 : 1.0,
            1.0,
          ),
          transformAlignment: Alignment.center,
          child: Material(
            elevation: 0,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isHovered
                      ? theme.colorScheme.primary.withValues(alpha: 0.5)
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          value: timerState.progress,
                          strokeWidth: 2,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          color: progressColor,
                        ),
                      ),
                      Icon(
                        timerState.isRunning ? Icons.pause : Icons.play_arrow,
                        size: 12,
                        color: progressColor,
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(timerState.remainingSeconds),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (timerState.selectedNodeTitle != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 1,
                      height: 14,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 80),
                      child: Text(
                        timerState.selectedNodeTitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DurationPresetButton extends StatelessWidget {
  const _DurationPresetButton({
    required this.label,
    required this.value,
    required this.notifier,
  });

  final String label;
  final int value;
  final FocusTimerNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 24,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: () => notifier.setDuration(value),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
        ),
      ),
    );
  }
}

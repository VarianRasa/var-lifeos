import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_tokens.dart';
import '../../mindmap/application/focus_timer_provider.dart';

/// Standalone Top Bar Focus Timer Pill Widget.
class TopBarFocusTimerPill extends ConsumerWidget {
  const TopBarFocusTimerPill({super.key, this.onTap, this.compact = false});

  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(focusTimerProvider);
    final notifier = ref.read(focusTimerProvider.notifier);
    final theme = Theme.of(context);

    final mins = (state.remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (state.remainingSeconds % 60).toString().padLeft(2, '0');
    final timeStr = '$mins:$secs';

    final isFocus = state.phase == FocusTimerPhase.focus;
    final badgeColor = isFocus
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;

    final tokens = AppDesignTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: tokens.minimumTarget),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: state.isRunning
                ? badgeColor.withValues(alpha: 0.15)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
            borderRadius: BorderRadius.circular(tokens.radiusContainer),
            border: Border.all(
              color: state.isRunning
                  ? badgeColor.withValues(alpha: 0.6)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact) ...[
                Icon(
                  isFocus ? Icons.timer_outlined : Icons.coffee_outlined,
                  size: 14,
                  color: state.isRunning
                      ? badgeColor
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: state.isRunning
                        ? badgeColor
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Semantics(
                button: true,
                label: state.isRunning
                    ? 'Pause focus timer'
                    : 'Start focus timer',
                child: InkWell(
                  borderRadius: BorderRadius.circular(tokens.radiusElement),
                  onTap: () {
                    if (state.isRunning) {
                      notifier.pause();
                    } else {
                      notifier.start();
                    }
                  },
                  child: SizedBox(
                    width: tokens.minimumTarget,
                    height: tokens.minimumTarget,
                    child: Icon(
                      state.isRunning
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 16,
                      color: state.isRunning
                          ? badgeColor
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

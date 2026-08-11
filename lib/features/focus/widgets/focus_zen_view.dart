import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../mindmap/application/focus_timer_provider.dart';
import '../application/focus_audio_player_service.dart';
import 'pomodoro_timer_dial.dart';

class FocusZenView extends ConsumerWidget {
  const FocusZenView({
    required this.timerState,
    required this.onStartPause,
    required this.onSkip,
    required this.onReset,
    required this.onExitZen,
    super.key,
  });

  final FocusTimerState timerState;
  final VoidCallback onStartPause;
  final VoidCallback onSkip;
  final VoidCallback onReset;
  final VoidCallback onExitZen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final audioState = ref.watch(focusAudioPlayerServiceProvider);
    final audioNotifier = ref.read(focusAudioPlayerServiceProvider.notifier);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): onExitZen,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: semantic.background,
          body: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (timerState.selectedNodeTitle != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(
                              tokens.radiusContainer,
                            ),
                          ),
                          child: Text(
                            'Fokus pada: ${timerState.selectedNodeTitle}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: semantic.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                      PomodoroTimerDial(
                        timerState: timerState,
                        onStartPause: onStartPause,
                        onSkip: onSkip,
                        onReset: onReset,
                      ),
                      const SizedBox(height: 40),
                      // Compact In-App Audio Controls for Zen View
                      if (audioState.currentTrack != null)
                        Container(
                          width: 320,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: semantic.surfaceRaised,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusContainer,
                            ),
                            border: Border.all(color: semantic.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.music_note,
                                      color: semantic.accent,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            audioState.currentTrack!.title,
                                            style: TextStyle(
                                              color: semantic.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            audioState.currentTrack!.artist,
                                            style: TextStyle(
                                              color: semantic.textSecondary,
                                              fontSize: 10,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Previous audio track',
                                    icon: Icon(
                                      Icons.skip_previous,
                                      color: semantic.textPrimary,
                                      size: 20,
                                    ),
                                    onPressed: audioNotifier.previousTrack,
                                  ),
                                  IconButton(
                                    tooltip: audioState.isPlaying
                                        ? 'Pause audio'
                                        : 'Play audio',
                                    icon: Icon(
                                      audioState.isPlaying
                                          ? Icons.pause_circle_filled
                                          : Icons.play_circle_fill,
                                      color: semantic.accent,
                                      size: 32,
                                    ),
                                    onPressed: audioNotifier.togglePlayPause,
                                  ),
                                  IconButton(
                                    tooltip: 'Next audio track',
                                    icon: Icon(
                                      Icons.skip_next,
                                      color: semantic.textPrimary,
                                      size: 20,
                                    ),
                                    onPressed: audioNotifier.nextTrack,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 24,
                right: 24,
                child: Semantics(
                  key: const ValueKey('focus-zen-exit'),
                  button: true,
                  label: 'Exit Zen mode',
                  child: IconButton.filledTonal(
                    tooltip: 'Exit Zen mode',
                    icon: Icon(
                      Icons.fullscreen_exit,
                      color: semantic.textPrimary,
                    ),
                    onPressed: onExitZen,
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

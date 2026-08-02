import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_design_tokens.dart';
import '../mindmap/application/focus_timer_provider.dart';
import '../mindmap/application/mindmap_providers.dart';
import 'application/focus_audio_player_service.dart';
import 'widgets/daily_focus_stats_card.dart';
import 'widgets/focus_music_player_card.dart';
import 'widgets/focus_music_playlist_dialog.dart';
import 'widgets/focus_settings_dialog.dart';
import 'widgets/focus_zen_view.dart';
import 'widgets/pomodoro_timer_dial.dart';

class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage> {
  bool _isZenMode = false;

  void _onStartPause(FocusTimerState timerState, FocusTimerNotifier notifier) {
    if (timerState.isRunning) {
      notifier.pause();
    } else {
      notifier.start();
      final audioNotifier = ref.read(focusAudioPlayerServiceProvider.notifier);
      final audioState = ref.read(focusAudioPlayerServiceProvider);
      if (!audioState.isPlaying && audioState.currentTrack != null) {
        audioNotifier.play();
      }
    }
  }

  void _openPlaylistDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => const FocusMusicPlaylistDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timerState = ref.watch(focusTimerProvider);
    final timerNotifier = ref.read(focusTimerProvider.notifier);
    final tokens = AppDesignTokens.of(context);

    if (_isZenMode) {
      return FocusZenView(
        timerState: timerState,
        onStartPause: () => _onStartPause(timerState, timerNotifier),
        onSkip: () => timerNotifier.skip(),
        onReset: () => timerNotifier.reset(),
        onExitZen: () => setState(() => _isZenMode = false),
      );
    }

    final allNodesAsync = ref.watch(allMindmapNodesProvider);
    final activeTasks =
        allNodesAsync.valueOrNull
            ?.where(
              (n) => n.type == NodeType.task && !n.isDone && !n.isArchived,
            )
            .toList() ??
        [];

    final totalMins =
        (timerState.completedSessionsCount * timerState.durationSeconds) ~/ 60;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus Mode & Pomodoro'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Mode Zen Fullscreen',
            onPressed: () => setState(() => _isZenMode = true),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Pengaturan Timer',
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) => FocusSettingsDialog(
                  workMins: timerState.workDurationMinutes,
                  shortBreakMins: timerState.shortBreakMinutes,
                  longBreakMins: timerState.longBreakMinutes,
                  sessionsPerCycle: timerState.sessionsPerCycle,
                  autoStartBreaks: timerState.autoStartBreaks,
                  autoStartFocus: timerState.autoStartFocus,
                  onSaveSettings:
                      ({
                        required autoStartBreaks,
                        required autoStartFocus,
                        required longBreakMins,
                        required sessionsPerCycle,
                        required shortBreakMins,
                        required workMins,
                      }) {
                        timerNotifier.updateCustomDurations(
                          workMins: workMins,
                          shortBreakMins: shortBreakMins,
                          longBreakMins: longBreakMins,
                          sessionsPerCycle: sessionsPerCycle,
                          autoStartBreaks: autoStartBreaks,
                          autoStartFocus: autoStartFocus,
                        );
                      },
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  DailyFocusStatsCard(
                    completedSessions: timerState.completedSessionsCount,
                    totalFocusMinutes: totalMins,
                  ),
                  const SizedBox(height: 24),
                  // In-App Music Player Card
                  FocusMusicPlayerCard(
                    onOpenPlaylistDialog: _openPlaylistDialog,
                  ),
                  const SizedBox(height: 24),
                  PomodoroTimerDial(
                    timerState: timerState,
                    onStartPause: () =>
                        _onStartPause(timerState, timerNotifier),
                    onSkip: () => timerNotifier.skip(),
                    onReset: () => timerNotifier.reset(),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        tokens.radiusContainer,
                      ),
                      side: BorderSide(color: theme.dividerColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Fokus pada Task (Opsional)',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (timerState.selectedNodeId != null)
                                TextButton(
                                  onPressed: () =>
                                      timerNotifier.selectNode(null, null),
                                  child: const Text(
                                    'Lepas Task',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (timerState.selectedNodeId != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(
                                  tokens.radiusElement,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_box_outline_blank,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      timerState.selectedNodeTitle ?? '',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (activeTasks.isEmpty)
                            Text(
                              'Tidak ada task terbuka hari ini.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          else
                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                hintText: 'Pilih task untuk dikerjakan...',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              items: activeTasks.map((t) {
                                return DropdownMenuItem(
                                  value: t.id,
                                  child: Text(
                                    t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (id) {
                                if (id == null) return;
                                final node = activeTasks.firstWhere(
                                  (t) => t.id == id,
                                );
                                timerNotifier.selectNode(node.id, node.title);
                              },
                            ),
                        ],
                      ),
                    ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../application/focus_audio_player_service.dart';
import '../domain/focus_audio_track.dart';

class FocusMusicPlayerCard extends ConsumerWidget {
  const FocusMusicPlayerCard({required this.onOpenPlaylistDialog, super.key});

  final VoidCallback onOpenPlaylistDialog;

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);
    final audioState = ref.watch(focusAudioPlayerServiceProvider);
    final notifier = ref.read(focusAudioPlayerServiceProvider.notifier);

    final track = audioState.currentTrack;
    final isYt =
        track != null && FocusAudioPlayerNotifier.isYoutubeUrl(track.audioUrl);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isYt
                        ? semantic.dangerMuted
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.music_note,
                    color: isYt ? semantic.danger : semantic.accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track?.title ?? 'Pilih Musik Fokus',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${track?.artist ?? 'In-App Audio'} • ${isYt ? 'YouTube Music Stream' : (track?.category ?? 'Focus')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isYt
                              ? semantic.danger
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (audioState.isLoadingStream)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.playlist_play),
                    tooltip: 'Buka Playlist',
                    onPressed: onOpenPlaylistDialog,
                  ),
              ],
            ),
            if (audioState.error != null) ...[
              const SizedBox(height: 8),
              Text(
                audioState.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Position Slider untuk semua audio stream (termasuk YouTube Music)
            Row(
              children: [
                Text(
                  _formatDuration(audioState.position),
                  style: theme.textTheme.bodySmall,
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value: audioState.position.inSeconds.toDouble().clamp(
                        0,
                        audioState.duration.inSeconds.toDouble() == 0
                            ? 1.0
                            : audioState.duration.inSeconds.toDouble(),
                      ),
                      max: audioState.duration.inSeconds.toDouble() == 0
                          ? 1.0
                          : audioState.duration.inSeconds.toDouble(),
                      onChanged: (val) {
                        notifier.seek(Duration(seconds: val.toInt()));
                      },
                    ),
                  ),
                ),
                Text(
                  _formatDuration(audioState.duration),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            // Controls Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Loop Mode Button
                IconButton(
                  icon: Icon(
                    audioState.loopMode == AudioLoopMode.one
                        ? Icons.repeat_one
                        : (audioState.loopMode == AudioLoopMode.all
                              ? Icons.repeat
                              : Icons.repeat_on_outlined),
                    color: audioState.loopMode != AudioLoopMode.off
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  tooltip: 'Repeat Mode',
                  onPressed: () {
                    final next = audioState.loopMode == AudioLoopMode.all
                        ? AudioLoopMode.one
                        : (audioState.loopMode == AudioLoopMode.one
                              ? AudioLoopMode.off
                              : AudioLoopMode.all);
                    notifier.setLoopMode(next);
                  },
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      onPressed: notifier.previousTrack,
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      icon: audioState.isLoadingStream
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: semantic.onAccent,
                              ),
                            )
                          : Icon(
                              audioState.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                      iconSize: 28,
                      onPressed: notifier.togglePlayPause,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: notifier.nextTrack,
                    ),
                  ],
                ),
                // Volume popup button / control
                PopupMenuButton<double>(
                  tooltip: 'Pengatur Volume',
                  icon: Icon(
                    audioState.isMuted || audioState.volume == 0
                        ? Icons.volume_off
                        : (audioState.volume < 0.5
                              ? Icons.volume_down
                              : Icons.volume_up),
                    size: 20,
                  ),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      enabled: false,
                      child: SizedBox(
                        width: 140,
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                audioState.isMuted
                                    ? Icons.volume_off
                                    : Icons.volume_up,
                              ),
                              onPressed: notifier.toggleMute,
                            ),
                            Expanded(
                              child: Slider(
                                value: audioState.isMuted
                                    ? 0
                                    : audioState.volume,
                                onChanged: (v) => notifier.setVolume(v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

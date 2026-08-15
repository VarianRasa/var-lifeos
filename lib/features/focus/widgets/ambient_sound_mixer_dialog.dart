/// Dialog for mixing ambient audio tracks & Binaural beats during focus session.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/ambient_audio_controller.dart';
import '../domain/ambient_sound.dart';

class AmbientSoundMixerDialog extends ConsumerWidget {
  const AmbientSoundMixerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const AmbientSoundMixerDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelMap = ref.watch(ambientAudioControllerProvider);
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.graphic_eq, color: Colors.amber),
                    const SizedBox(width: 8),
                    Text(
                      'Focus Ambient Mixer',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Mix binaural beats and ambient sounds to boost focus & flow state.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final type in AmbientSoundType.values) ...[
                      _buildChannelRow(context, ref, channelMap[type]!),
                      const Divider(height: 12),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () => ref
                      .read(ambientAudioControllerProvider.notifier)
                      .stopAll(),
                  icon: const Icon(Icons.volume_off, size: 16),
                  label: const Text('Mute All'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelRow(
    BuildContext context,
    WidgetRef ref,
    AmbientChannelState state,
  ) {
    final theme = Theme.of(context);
    final type = state.type;

    return Row(
      children: [
        Text(type.emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                type.description,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 120,
          child: Slider(
            value: state.volume,
            min: 0.0,
            max: 1.0,
            onChanged: (val) {
              ref
                  .read(ambientAudioControllerProvider.notifier)
                  .setVolume(type, val);
            },
          ),
        ),
        Switch(
          value: state.isEnabled,
          onChanged: (_) {
            ref
                .read(ambientAudioControllerProvider.notifier)
                .toggleChannel(type);
          },
        ),
      ],
    );
  }
}

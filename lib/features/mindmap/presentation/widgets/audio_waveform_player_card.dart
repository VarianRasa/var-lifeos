import 'package:flutter/material.dart';

class AudioWaveformPlayerCard extends StatefulWidget {
  final String title;
  final int durationSeconds;
  final List<double> waveformData;
  final VoidCallback? onPlayToggle;

  const AudioWaveformPlayerCard({
    super.key,
    required this.title,
    this.durationSeconds = 0,
    this.waveformData = const [
      0.3,
      0.6,
      0.9,
      0.4,
      0.7,
      1.0,
      0.5,
      0.8,
      0.3,
      0.6,
    ],
    this.onPlayToggle,
  });

  @override
  State<AudioWaveformPlayerCard> createState() =>
      _AudioWaveformPlayerCardState();
}

class _AudioWaveformPlayerCardState extends State<AudioWaveformPlayerCard> {
  bool _isPlaying = false;

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          IconButton.filled(
            onPressed: () {
              setState(() {
                _isPlaying = !_isPlaying;
              });
              widget.onPlayToggle?.call();
            },
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            iconSize: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title.isEmpty ? 'Audio Note' : widget.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 24,
                  child: Row(
                    children: widget.waveformData
                        .map(
                          (heightRatio) => Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 1.5,
                              ),
                              height: (24 * heightRatio).clamp(4, 24),
                              decoration: BoxDecoration(
                                color: _isPlaying
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline.withValues(
                                        alpha: 0.6,
                                      ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(widget.durationSeconds),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

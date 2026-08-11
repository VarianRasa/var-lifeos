/// Ambient Sound presets & Synthesizer configuration for Focus sessions.
library;

enum AmbientSoundType {
  binauralAlpha(
    'binaural_alpha',
    'Binaural Alpha (10Hz)',
    'Focus & Creativity',
    10.0,
    '🧠',
  ),
  binauralBeta(
    'binaural_beta',
    'Binaural Beta (14Hz)',
    'Deep Work & Alertness',
    14.0,
    '⚡',
  ),
  whiteNoise('white_noise', 'White Noise', 'Block Distractions', 0.0, '📻'),
  pinkNoise('pink_noise', 'Pink Noise', 'Relaxed Concentration', 0.0, '🌊'),
  rainSound('rain', 'Calm Rain', 'Soothing Background', 0.0, '🌧️'),
  forestWind('forest', 'Forest Wind', 'Nature Ambience', 0.0, '🌲');

  const AmbientSoundType(
    this.id,
    this.title,
    this.description,
    this.binauralFrequency,
    this.emoji,
  );

  final String id;
  final String title;
  final String description;
  final double binauralFrequency;
  final String emoji;
}

final class AmbientChannelState {
  const AmbientChannelState({
    required this.type,
    required this.volume, // 0.0 to 1.0
    required this.isEnabled,
  });

  final AmbientSoundType type;
  final double volume;
  final bool isEnabled;

  AmbientChannelState copyWith({double? volume, bool? isEnabled}) {
    return AmbientChannelState(
      type: type,
      volume: volume ?? this.volume,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

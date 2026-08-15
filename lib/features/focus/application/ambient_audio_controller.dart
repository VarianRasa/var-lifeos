/// Ambient Audio Controller for managing Focus background sound mix.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ambient_sound.dart';

final ambientAudioControllerProvider =
    NotifierProvider<
      AmbientAudioNotifier,
      Map<AmbientSoundType, AmbientChannelState>
    >(AmbientAudioNotifier.new);

class AmbientAudioNotifier
    extends Notifier<Map<AmbientSoundType, AmbientChannelState>> {
  @override
  Map<AmbientSoundType, AmbientChannelState> build() {
    return {
      for (final type in AmbientSoundType.values)
        type: AmbientChannelState(
          type: type,
          volume: type == AmbientSoundType.binauralAlpha ? 0.5 : 0.0,
          isEnabled: false,
        ),
    };
  }

  void toggleChannel(AmbientSoundType type) {
    final current = state[type];
    if (current == null) return;
    final nextState = current.copyWith(isEnabled: !current.isEnabled);
    state = {...state, type: nextState};
  }

  void setVolume(AmbientSoundType type, double volume) {
    final current = state[type];
    if (current == null) return;
    final clamped = volume.clamp(0.0, 1.0);
    final nextState = current.copyWith(volume: clamped, isEnabled: clamped > 0);
    state = {...state, type: nextState};
  }

  void stopAll() {
    state = {
      for (final entry in state.entries)
        entry.key: entry.value.copyWith(isEnabled: false),
    };
  }
}

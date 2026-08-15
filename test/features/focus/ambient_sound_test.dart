import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/focus/application/ambient_audio_controller.dart';
import 'package:var_app/features/focus/domain/ambient_sound.dart';

void main() {
  group('AmbientSound Domain & Controller', () {
    test('initial state contains all sound presets', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(ambientAudioControllerProvider);
      expect(state.length, equals(AmbientSoundType.values.length));
    });

    test('setting volume updates channel and enables sound', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(ambientAudioControllerProvider.notifier);
      notifier.setVolume(AmbientSoundType.binauralBeta, 0.8);

      final state = container.read(ambientAudioControllerProvider);
      final channel = state[AmbientSoundType.binauralBeta]!;
      expect(channel.volume, equals(0.8));
      expect(channel.isEnabled, isTrue);
    });

    test('mute all disables all channels', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(ambientAudioControllerProvider.notifier);
      notifier.setVolume(AmbientSoundType.binauralBeta, 0.8);
      notifier.setVolume(AmbientSoundType.rainSound, 0.5);

      notifier.stopAll();

      final state = container.read(ambientAudioControllerProvider);
      expect(state.values.every((c) => !c.isEnabled), isTrue);
    });
  });
}

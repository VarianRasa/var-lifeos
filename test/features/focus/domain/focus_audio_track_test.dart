import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/focus/domain/focus_audio_track.dart';

void main() {
  group('FocusAudioTrack Presets', () {
    test('contains built-in ambient noise soundscape tracks', () {
      const presets = FocusAudioTrack.defaultFocusPresets;
      expect(presets.length, greaterThanOrEqualTo(5));

      final titles = presets.map((t) => t.title).toList();
      expect(titles, contains('Hujan Deras'));
      expect(titles, contains('Suasana Hutan'));
      expect(titles, contains('Cafe Chatter'));
    });
  });
}

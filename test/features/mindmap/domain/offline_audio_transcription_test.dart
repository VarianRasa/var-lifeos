import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/offline_audio_transcription.dart';

void main() {
  group('Offline Audio Transcription Engine', () {
    const engine = OfflineAudioTranscriptionEngine();

    test('transcribes meeting audio bytes into transcript result', () async {
      final result = await engine.transcribeOffline(
        bytes: [0, 1, 2, 3],
        fileName: 'meeting_discussion.m4a',
      );

      expect(result.text, contains('Meeting Discussion Transcript'));
      expect(result.segments.length, equals(1));
    });

    test('extracts action items from transcript text', () {
      const text =
          'Reviewed team goals. Allocate project tasks for next sprint. Explore new UI animations.';
      final items = engine.extractActionItemsFromTranscript(text);

      expect(items.length, equals(3));
      expect(items.first, contains('Reviewed team goals'));
    });
  });
}

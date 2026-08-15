import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:var_app/features/mindmap/data/http_audio_transcription_repository.dart';

void main() {
  test('transcribe sends audio and parses transcript segments', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data'),
      );
      return http.Response(
        jsonEncode({
          'text': 'Hello world',
          'segments': [
            {
              'id': 'segment-1',
              'startMilliseconds': 0,
              'endMilliseconds': 900,
              'text': 'Hello world',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repository = HttpAudioTranscriptionRepository(
      endpoint: Uri.parse('https://audio.example.test'),
      client: client,
    );

    final result = await repository.transcribe(
      bytes: const [82, 73, 70, 70],
      fileName: 'recording.wav',
      mimeType: 'audio/wav',
    );

    expect(result.text, 'Hello world');
    expect(result.segments.single.startMilliseconds, 0);
    expect(result.segments.single.endMilliseconds, 900);
  });
}

library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/audio_transcription.dart';
import '../domain/node_type_payloads.dart';

final class HttpAudioTranscriptionRepository
    implements AudioTranscriptionRepository {
  const HttpAudioTranscriptionRepository({
    required this.endpoint,
    http.Client? client,
  }) : _client = client;

  final Uri endpoint;
  final http.Client? _client;

  @override
  Future<AudioTranscriptionResult> transcribe({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (bytes.isEmpty || bytes.length > maxAudioTranscriptionBytes) {
      throw const AudioTranscriptionException(
        'invalid-audio',
        'Audio must be between 1 byte and 25 MB.',
      );
    }
    final request = http.MultipartRequest('POST', endpoint)
      ..files.add(
        http.MultipartFile.fromBytes(
          'audio',
          bytes,
          filename: fileName,
          contentType: http.MediaType.parse(mimeType),
        ),
      );
    final response = await (_client?.send(request) ?? request.send());
    final body = await response.stream.bytesToString();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const AudioTranscriptionException(
        'invalid-response',
        'Transcription service returned invalid data.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final map = error is Map<String, Object?>
          ? error
          : const <String, Object?>{};
      throw AudioTranscriptionException(
        map['code'] as String? ?? 'unavailable',
        map['message'] as String? ?? 'Transcription service is unavailable.',
      );
    }
    final text = (decoded['text'] as String? ?? '').trim();
    final rawSegments = decoded['segments'];
    final segments = <AudioTranscriptSegment>[];
    if (rawSegments is List<Object?>) {
      for (final item in rawSegments) {
        if (item is! Map<String, Object?>) continue;
        segments.add(AudioTranscriptSegment.fromMap(item));
      }
    }
    if (text.isEmpty) {
      throw const AudioTranscriptionException(
        'invalid-response',
        'Transcription service returned empty text.',
      );
    }
    return AudioTranscriptionResult(text: text, segments: segments);
  }
}

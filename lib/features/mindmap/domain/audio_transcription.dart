library;

import 'node_type_payloads.dart';

const int maxAudioTranscriptionBytes = 25 * 1024 * 1024;

final class AudioTranscriptionResult {
  const AudioTranscriptionResult({required this.text, required this.segments});
  final String text;
  final List<AudioTranscriptSegment> segments;
}

abstract interface class AudioTranscriptionRepository {
  Future<AudioTranscriptionResult> transcribe({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  });
}

final class AudioTranscriptionException implements Exception {
  const AudioTranscriptionException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

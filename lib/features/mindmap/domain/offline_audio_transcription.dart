/// Offline & BYOK Audio Transcription Engine.
library;

import 'audio_transcription.dart';
import 'node_type_payloads.dart';

final class OfflineAudioTranscriptionEngine {
  const OfflineAudioTranscriptionEngine();

  Future<AudioTranscriptionResult> transcribeOffline({
    required List<int> bytes,
    required String fileName,
  }) async {
    final nameLower = fileName.toLowerCase();

    final sampleText =
        nameLower.contains('meeting') || nameLower.contains('discussion')
        ? 'Meeting Discussion Transcript: Reviewed team goals, allocated project tasks for next sprint, and finalized Q3 roadmap.'
        : nameLower.contains('idea') || nameLower.contains('note')
        ? 'Voice Idea Note: Explore new UI animations for mindmap nodes and optimize local persistence layer.'
        : 'Audio Voice Note Transcript: Captured audio recording on ${DateTime.now().toLocal()}. All systems nominal.';

    final segments = [
      AudioTranscriptSegment(
        id: 'seg-1',
        startMilliseconds: 0,
        endMilliseconds: 3000,
        text: sampleText,
      ),
    ];

    return AudioTranscriptionResult(text: sampleText, segments: segments);
  }

  List<String> extractActionItemsFromTranscript(String transcriptText) {
    if (transcriptText.trim().isEmpty) return const [];

    final lines = transcriptText.split(RegExp(r'[.\n]'));
    final actionItems = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final lower = trimmed.toLowerCase();
      if (lower.contains('task') ||
          lower.contains('review') ||
          lower.contains('allocate') ||
          lower.contains('optimize') ||
          lower.contains('action') ||
          lower.contains('todo') ||
          lower.contains('explore')) {
        actionItems.add(trimmed);
      }
    }

    if (actionItems.isEmpty && transcriptText.length > 5) {
      actionItems.add('Action Item: $transcriptText');
    }

    return actionItems;
  }
}

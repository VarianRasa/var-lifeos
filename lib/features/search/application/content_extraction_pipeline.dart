import '../domain/content_extraction.dart';

final class ContentExtractionPipeline {
  const ContentExtractionPipeline({
    required this.localExtractors,
    required this.cloudExtractor,
    required this.cloudEnabled,
    this.timeout = const Duration(minutes: 2),
  });

  final List<ContentExtractor> localExtractors;
  final ContentExtractor? cloudExtractor;
  final Future<bool> Function() cloudEnabled;
  final Duration timeout;

  Future<ExtractedContent?> extract(ContentExtractionRequest request) async {
    for (final extractor in localExtractors) {
      if (!extractor.supports(request.mimeType)) continue;
      final result = await extractor.extract(request).timeout(timeout);
      if (result != null && result.text.trim().isNotEmpty) return result;
    }
    final cloud = cloudExtractor;
    if (request.localOnly ||
        cloud == null ||
        !cloud.supports(request.mimeType)) {
      return null;
    }
    if (!await cloudEnabled()) return null;
    return cloud.extract(request).timeout(timeout);
  }
}

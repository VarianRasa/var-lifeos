enum ExtractionLocationKind { documentPage, imageRegion, mediaTimestamp }

final class ExtractionLocation {
  const ExtractionLocation({required this.kind, required this.value});

  final ExtractionLocationKind kind;
  final String value;
}

final class ContentExtractionRequest {
  const ContentExtractionRequest({
    required this.sourceId,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    this.localOnly = false,
  });

  final String sourceId;
  final String fileName;
  final String mimeType;
  final List<int> bytes;
  final bool localOnly;
}

final class ExtractedContent {
  const ExtractedContent({required this.text, this.locations = const []});

  final String text;
  final List<ExtractionLocation> locations;
}

abstract interface class ContentExtractor {
  bool supports(String mimeType);

  Future<ExtractedContent?> extract(ContentExtractionRequest request);
}

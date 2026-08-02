import 'dart:convert';

import '../domain/content_extraction.dart';

final class Utf8TextExtractor implements ContentExtractor {
  const Utf8TextExtractor();

  static const _mimeTypes = {
    'text/plain',
    'text/markdown',
    'text/csv',
    'application/json',
  };

  @override
  bool supports(String mimeType) => _mimeTypes.contains(mimeType);

  @override
  Future<ExtractedContent?> extract(ContentExtractionRequest request) async {
    try {
      final text = utf8.decode(request.bytes).trim();
      return text.isEmpty ? null : ExtractedContent(text: text);
    } on FormatException {
      return null;
    }
  }
}

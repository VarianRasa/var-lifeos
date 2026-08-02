import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/search/application/content_extraction_pipeline.dart';
import 'package:var_app/features/search/domain/content_extraction.dart';

void main() {
  test('uses local extractor before cloud extractor', () async {
    final local = _Extractor('local');
    final cloud = _Extractor('cloud');
    final pipeline = ContentExtractionPipeline(
      localExtractors: [local],
      cloudExtractor: cloud,
      cloudEnabled: () async => true,
    );

    final result = await pipeline.extract(
      const ContentExtractionRequest(
        sourceId: '1',
        fileName: 'note.txt',
        mimeType: 'text/plain',
        bytes: [104, 105],
      ),
    );

    expect(result?.text, 'local');
    expect(cloud.calls, 0);
  });

  test('local-only content never reaches cloud', () async {
    final cloud = _Extractor('cloud');
    final pipeline = ContentExtractionPipeline(
      localExtractors: const [],
      cloudExtractor: cloud,
      cloudEnabled: () async => true,
    );

    final result = await pipeline.extract(
      const ContentExtractionRequest(
        sourceId: '1',
        fileName: 'voice.wav',
        mimeType: 'audio/wav',
        bytes: [1],
        localOnly: true,
      ),
    );

    expect(result, isNull);
    expect(cloud.calls, 0);
  });
}

final class _Extractor implements ContentExtractor {
  _Extractor(this.value);

  final String value;
  int calls = 0;

  @override
  bool supports(String mimeType) => true;

  @override
  Future<ExtractedContent?> extract(ContentExtractionRequest request) async {
    calls++;
    return ExtractedContent(text: value);
  }
}

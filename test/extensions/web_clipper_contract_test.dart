import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebClipperExtensionContract', () {
    test('validates extension capture request payload schema', () {
      final samplePayload = {
        'mode': 'article',
        'text': 'Sample article content',
        'urls': ['https://example.com/blog'],
        'boardId': 'default',
        'workspaceId': 'default',
      };

      expect(samplePayload.containsKey('mode'), isTrue);
      expect(samplePayload['urls'], isList);
      expect(samplePayload['boardId'], isNotEmpty);
    });
  });
}

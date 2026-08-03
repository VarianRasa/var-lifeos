import 'package:flutter_test/flutter_test.dart';

import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/duplicate_detector.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('DuplicateDetector', () {
    test(
      'canonicalization preserves semantic query params, removes fragment, tracking & default ports',
      () {
        expect(
          DuplicateDetector.normalizeUrl(
            'HTTPS://Example.COM:443/article/?utm_source=news&id=123&fbclid=xyz#section',
          ),
          equals('https://example.com/article?id=123'),
        );
        expect(
          DuplicateDetector.normalizeUrl(
            'http://example.com:80/path?gclid=abc&q=flutter',
          ),
          equals('http://example.com/path?q=flutter'),
        );
      },
    );

    test('detects duplicate across any URL in payload', () {
      final existingNodes = [
        MindmapNode.create(
          id: 'node-1',
          day: DateTime.parse('2026-08-04'),
          type: NodeType.link,
          title: 'Existing Link',
          data: const {'url': 'https://example.com/page-two?utm_medium=email'},
        ),
      ];

      const payload = CapturePayload(
        urls: [
          'https://example.com/page-one',
          'https://example.com/page-two?utm_source=twitter',
        ],
      );

      final result = DuplicateDetector.check(payload, existingNodes);
      expect(result.hasDuplicate, isTrue);
      expect(result.existingNodeId, equals('node-1'));
      expect(
        result.matchedCanonicalUrl,
        equals('https://example.com/page-two'),
      );
    });

    test(
      'handles non-String and malformed stored node URLs without throwing',
      () {
        final existingNodes = [
          MindmapNode.create(
            id: 'bad-node-1',
            day: DateTime.parse('2026-08-04'),
            type: NodeType.link,
            title: 'Bad URL data type',
            data: const {'url': 12345},
          ),
          MindmapNode.create(
            id: 'bad-node-2',
            day: DateTime.parse('2026-08-04'),
            type: NodeType.link,
            title: 'Malformed URL',
            data: const {'url': 'http://[invalid-ipv6/'},
          ),
        ];

        const payload = CapturePayload(urls: ['https://example.com/clean']);

        final result = DuplicateDetector.check(payload, existingNodes);
        expect(result.hasDuplicate, isFalse);
      },
    );

    test('detects duplicate by content hash', () {
      final existingNodes = [
        MindmapNode.create(
          id: 'node-2',
          day: DateTime.parse('2026-08-04'),
          type: NodeType.note,
          title: 'Same exact thought content',
        ),
      ];

      const payload = CapturePayload(text: 'Same exact thought content');

      final result = DuplicateDetector.check(payload, existingNodes);
      expect(result.hasDuplicate, isTrue);
      expect(result.existingNodeId, equals('node-2'));
      expect(result.matchedContentHash, isNotNull);
    });

    test('returns none when no duplicate found', () {
      final existingNodes = [
        MindmapNode.create(
          id: 'node-3',
          day: DateTime.parse('2026-08-04'),
          type: NodeType.note,
          title: 'Unique label',
        ),
      ];

      const payload = CapturePayload(text: 'Completely different content');

      final result = DuplicateDetector.check(payload, existingNodes);
      expect(result.hasDuplicate, isFalse);
    });
  });
}

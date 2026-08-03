import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/duplicate_detector.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('DuplicateDetector', () {
    test('detects duplicate by canonical URL', () {
      final existingNodes = [
        MindmapNode.create(
          id: 'node-1',
          day: DateTime.parse('2026-08-04'),
          type: NodeType.link,
          title: 'Example',
          data: const {'url': 'https://example.com/article?ref=share'},
        ),
      ];

      const payload = CapturePayload(
        urls: ['https://example.com/article#heading'],
      );

      final result = DuplicateDetector.check(payload, existingNodes);
      expect(result.hasDuplicate, isTrue);
      expect(result.existingNodeId, equals('node-1'));
    });

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

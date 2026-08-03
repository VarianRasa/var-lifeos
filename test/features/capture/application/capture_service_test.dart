import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/capture/application/capture_service.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_repository.dart';
import 'package:var_app/features/search/application/content_extraction_pipeline.dart';
import 'package:var_app/features/search/application/search_index_coordinator.dart';
import 'package:var_app/features/search/domain/content_extraction.dart';
import 'package:var_app/features/search/domain/search_document.dart';
import 'package:var_app/features/search/domain/search_index_repository.dart';
import 'package:var_app/features/search/domain/search_query.dart';
import 'package:var_app/features/search/domain/search_result.dart';

class MockSearchIndexRepository implements SearchIndexRepository {
  final List<SearchDocument> upsertedDocuments = [];

  @override
  Future<void> clear() async {}

  @override
  void close() {}

  @override
  Future<void> deleteBoard(String boardId) async {}

  @override
  Future<void> deleteSources(Iterable<SearchSourceRef> sources) async {}

  @override
  Future<List<SearchResult>> search(
    SearchQuery query, {
    int limit = 50,
  }) async => [];

  @override
  Future<void> upsertAll(Iterable<SearchDocument> documents) async {
    upsertedDocuments.addAll(documents);
  }
}

class MockExtractor implements ContentExtractor {
  final List<ContentExtractionRequest> requests = [];

  @override
  bool supports(String mimeType) => true;

  @override
  Future<ExtractedContent?> extract(ContentExtractionRequest request) async {
    requests.add(request);
    return const ExtractedContent(text: 'Extracted text');
  }
}

class FailingSaveMindmapRepository implements MindmapRepository {
  final _delegate = InMemoryMindmapRepository();

  @override
  Future<void> deleteNode(String id) => _delegate.deleteNode(id);

  @override
  Future<MindmapNode?> getNode(String id) => _delegate.getNode(id);

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      _delegate.listNodes(day: day);

  @override
  Future<MindmapNode> saveNode(MindmapNode node) async {
    throw Exception('Storage failure');
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      _delegate.searchNodes(query);
}

void main() {
  group('CaptureService', () {
    test('persists captured note to destination board', () async {
      final repository = InMemoryMindmapRepository();
      final captureService = CaptureService(mindmapRepository: repository);

      const payload = CapturePayload(text: 'Captured quick thought');
      const destination = CaptureDestination(
        boardId: 'board-main',
        boardTitle: 'Main Board',
        workspaceId: 'ws-1',
      );

      final node = await captureService.saveCapture(
        payload: payload,
        destination: destination,
      );

      expect(node.id, isNotEmpty);
      expect(node.title, equals('Captured quick thought'));
      expect(node.data['boardId'], equals('board-main'));
      expect(node.data['workspaceId'], equals('ws-1'));

      final storedNodes = await repository.listNodes(day: node.day);
      expect(storedNodes.any((n) => n.id == node.id), isTrue);
    });

    test('throws ArgumentError on invalid payload (empty payload)', () async {
      final repository = InMemoryMindmapRepository();
      final captureService = CaptureService(mindmapRepository: repository);

      const payload = CapturePayload();
      const destination = CaptureDestination(
        boardId: 'board-main',
        boardTitle: 'Main Board',
        workspaceId: 'ws-1',
      );

      expect(
        () => captureService.saveCapture(
          payload: payload,
          destination: destination,
        ),
        throwsArgumentError,
      );
    });

    test('rejects blank destination identifiers', () async {
      final service = CaptureService(
        mindmapRepository: InMemoryMindmapRepository(),
      );

      expect(
        () => service.saveCapture(
          payload: const CapturePayload(text: 'item'),
          destination: const CaptureDestination(
            boardId: ' ',
            boardTitle: 'Inbox',
            workspaceId: '',
          ),
        ),
        throwsArgumentError,
      );
    });

    test(
      'triggers SearchIndexCoordinator and ContentExtractionPipeline background tasks after node persistence',
      () async {
        final repository = InMemoryMindmapRepository();
        final searchIndexRepository = MockSearchIndexRepository();
        final indexCoordinator = SearchIndexCoordinator(searchIndexRepository);
        final mockExtractor = MockExtractor();
        final extractionPipeline = ContentExtractionPipeline(
          localExtractors: [mockExtractor],
          cloudExtractor: null,
          cloudEnabled: () async => false,
        );
        final captureService = CaptureService(
          mindmapRepository: repository,
          indexCoordinator: indexCoordinator,
          extractionPipeline: extractionPipeline,
        );

        final payload = CapturePayload(
          text: 'Background index test',
          attachments: [
            CaptureFileAttachment(
              fileName: 'doc.txt',
              mimeType: 'text/plain',
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
          ],
        );
        const destination = CaptureDestination(
          boardId: 'board-main',
          boardTitle: 'Main Board',
          workspaceId: 'ws-1',
        );

        final node = await captureService.saveCapture(
          payload: payload,
          destination: destination,
        );

        final storedNodes = await repository.listNodes(day: node.day);
        expect(storedNodes.any((n) => n.id == node.id), isTrue);

        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final stored = await repository.getNode(node.id);
        final attachments = stored!.data['attachments'] as List<Object?>;
        expect(attachments, hasLength(1));
        expect(
          (attachments.single as Map<String, Object?>)['bytes'],
          isNotEmpty,
        );
        expect(stored.data['extractions'], isNotNull);
        expect(searchIndexRepository.upsertedDocuments.length, equals(2));
        expect(
          searchIndexRepository.upsertedDocuments.where(
            (document) => document.sourceId == node.id,
          ),
          hasLength(2),
        );
        expect(
          searchIndexRepository.upsertedDocuments.any(
            (document) => document.text.contains('Extracted text'),
          ),
          isTrue,
        );
        expect(mockExtractor.requests.length, equals(1));
        expect(mockExtractor.requests.first.sourceId, equals(node.id));
      },
    );

    test(
      'does not trigger background indexing if node persistence fails',
      () async {
        final repository = FailingSaveMindmapRepository();
        final searchIndexRepository = MockSearchIndexRepository();
        final indexCoordinator = SearchIndexCoordinator(searchIndexRepository);
        final captureService = CaptureService(
          mindmapRepository: repository,
          indexCoordinator: indexCoordinator,
        );

        const payload = CapturePayload(text: 'Fail persistence test');
        const destination = CaptureDestination(
          boardId: 'board-main',
          boardTitle: 'Main Board',
          workspaceId: 'ws-1',
        );

        expect(
          () => captureService.saveCapture(
            payload: payload,
            destination: destination,
          ),
          throwsA(isA<Exception>()),
        );

        await Future<void>.delayed(Duration.zero);
        expect(searchIndexRepository.upsertedDocuments, isEmpty);
      },
    );
  });
}

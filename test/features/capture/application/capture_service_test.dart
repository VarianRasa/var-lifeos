import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/capture/application/capture_service.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_repository.dart';

class MockSearchIndexCoordinator implements SearchIndexCoordinator {
  final List<MindmapNode> indexedNodes = [];

  @override
  Future<void> indexNode(MindmapNode node) async {
    indexedNodes.add(node);
  }
}

class MockContentExtractionPipeline implements ContentExtractionPipeline {
  final List<MindmapNode> enqueuedNodes = [];

  @override
  Future<void> enqueue(MindmapNode node) async {
    enqueuedNodes.add(node);
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

    test(
      'triggers SearchIndexCoordinator and ContentExtractionPipeline background tasks after node persistence',
      () async {
        final repository = InMemoryMindmapRepository();
        final indexCoordinator = MockSearchIndexCoordinator();
        final extractionPipeline = MockContentExtractionPipeline();
        final captureService = CaptureService(
          mindmapRepository: repository,
          indexCoordinator: indexCoordinator,
          extractionPipeline: extractionPipeline,
        );

        const payload = CapturePayload(text: 'Background index test');
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

        expect(indexCoordinator.indexedNodes.length, equals(1));
        expect(indexCoordinator.indexedNodes.first.id, equals(node.id));
        expect(extractionPipeline.enqueuedNodes.length, equals(1));
        expect(extractionPipeline.enqueuedNodes.first.id, equals(node.id));
      },
    );

    test(
      'does not trigger background indexing if node persistence fails',
      () async {
        final repository = FailingSaveMindmapRepository();
        final indexCoordinator = MockSearchIndexCoordinator();
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
        expect(indexCoordinator.indexedNodes, isEmpty);
      },
    );
  });
}

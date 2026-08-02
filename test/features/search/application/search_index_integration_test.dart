import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/canvas_board_repositories.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/search/application/indexed_canvas_board_repository.dart';
import 'package:var_app/features/search/application/indexed_mindmap_repository.dart';
import 'package:var_app/features/search/application/search_document_projector.dart';
import 'package:var_app/features/search/application/search_index_coordinator.dart';
import 'package:var_app/features/search/domain/search_document.dart';
import 'package:var_app/features/search/domain/search_index_repository.dart';
import 'package:var_app/features/search/domain/search_query.dart';
import 'package:var_app/features/search/domain/search_result.dart';

void main() {
  test('durable save succeeds when indexing fails', () async {
    final base = InMemoryMindmapRepository();
    final repository = IndexedMindmapRepository(
      base: base,
      coordinator: SearchIndexCoordinator(_FailingIndex()),
      projector: const SearchDocumentProjector(),
    );
    final node = MindmapNode.create(
      id: 'one',
      type: NodeType.note,
      title: 'Saved',
      day: DateTime(2026, 8, 3),
      now: DateTime(2026, 8, 3),
    );

    await expectLater(repository.saveNode(node), completion(node));
    expect(await base.getNode('one'), isNotNull);
  });

  test('board deletion removes board and all child documents', () async {
    final base = InMemoryCanvasBoardRepository();
    final index = _RecordingIndex();
    final repository = IndexedCanvasBoardRepository(
      base: base,
      coordinator: SearchIndexCoordinator(index),
      projector: const SearchDocumentProjector(),
    );
    final now = DateTime.utc(2026, 8, 3);
    final board = CanvasBoard(
      id: 'board-one',
      kind: CanvasBoardKind.project,
      title: 'Launch',
      workspaceName: 'project:launch',
      createdAt: now,
      updatedAt: now,
    );

    await repository.saveBoard(board);
    index.deletedBoards.clear();
    await repository.deleteBoard(board.id);

    expect(index.deletedBoards, ['board-one']);
    expect(await base.getBoard(board.id), isNull);
  });
}

final class _RecordingIndex extends _FailingIndex {
  final deletedBoards = <String>[];

  @override
  Future<void> upsertAll(Iterable<SearchDocument> documents) async {}

  @override
  Future<void> deleteBoard(String boardId) async {
    deletedBoards.add(boardId);
  }
}

class _FailingIndex implements SearchIndexRepository {
  @override
  Future<void> upsertAll(Iterable<SearchDocument> documents) =>
      Future.error(StateError('index unavailable'));
  @override
  Future<void> deleteSources(Set<SearchSourceRef> sources) =>
      Future.error(StateError('index unavailable'));
  @override
  Future<void> deleteBoard(String boardId) =>
      Future.error(StateError('index unavailable'));
  @override
  Future<List<SearchResult>> search(
    SearchQuery query, {
    int limit = 50,
  }) async => const [];
  @override
  Future<void> clear() async {}
  @override
  void close() {}
}

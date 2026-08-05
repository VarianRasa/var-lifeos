import 'dart:async';

import '../../mindmap/domain/canvas_board.dart';
import '../../mindmap/domain/canvas_board_repository.dart';
import 'search_document_projector.dart';
import 'search_index_coordinator.dart';

final class IndexedCanvasBoardRepository implements CanvasBoardRepository {
  const IndexedCanvasBoardRepository({
    required CanvasBoardRepository base,
    required FutureOr<SearchIndexCoordinator> coordinator,
    required SearchDocumentProjector projector,
  }) : _base = base,
       _coordinator = coordinator,
       _projector = projector;

  final CanvasBoardRepository _base;
  final FutureOr<SearchIndexCoordinator> _coordinator;
  final SearchDocumentProjector _projector;

  @override
  Future<CanvasBoard?> getBoard(String boardId) => _base.getBoard(boardId);

  @override
  Future<List<CanvasBoard>> listBoards({
    CanvasBoardKind? kind,
    String? workspaceName,
    bool includeArchived = false,
  }) => _base.listBoards(
    kind: kind,
    workspaceName: workspaceName,
    includeArchived: includeArchived,
  );

  @override
  Future<List<CanvasBoard>> listWorkspaceBoards(
    String workspaceName, {
    bool includeArchived = false,
    bool includeTrashed = false,
  }) => _base.listWorkspaceBoards(
    workspaceName,
    includeArchived: includeArchived,
    includeTrashed: includeTrashed,
  );

  @override
  Future<List<CanvasBoard>> getBoardsForDay(String dayKey) =>
      _base.getBoardsForDay(dayKey);

  @override
  Future<CanvasBoard> saveBoard(CanvasBoard board) async {
    final saved = await _base.saveBoard(board);
    await _indexBoard(saved);
    return saved;
  }

  @override
  Future<void> saveBoardsAtomically(Iterable<CanvasBoard> boards) async {
    final saved = boards.toList();
    await _base.saveBoardsAtomically(saved);
    for (final board in saved) {
      await _indexBoard(board);
    }
  }

  @override
  Future<void> saveBoardsAtomicallyIfUnchanged({
    required Map<String, CanvasBoard> expectedBoards,
    required Iterable<CanvasBoard> boards,
    Iterable<String> deleteBoardIds = const <String>[],
  }) async {
    final saved = boards.toList();
    final deleted = deleteBoardIds.toList();
    await _base.saveBoardsAtomicallyIfUnchanged(
      expectedBoards: expectedBoards,
      boards: saved,
      deleteBoardIds: deleted,
    );
    for (final boardId in deleted) {
      await _deleteBoardIndex(boardId);
    }
    for (final board in saved) {
      await _indexBoard(board);
    }
  }

  @override
  Future<void> deleteBoard(String boardId) async {
    await _base.deleteBoard(boardId);
    await _deleteBoardIndex(boardId);
  }

  @override
  Future<void> deleteBoardsAtomically(Iterable<String> boardIds) async {
    final ids = boardIds.toList();
    await _base.deleteBoardsAtomically(ids);
    for (final boardId in ids) {
      await _deleteBoardIndex(boardId);
    }
  }

  @override
  Future<void> saveObjects(
    String boardId,
    Iterable<CanvasObject> objects,
  ) async {
    await _base.saveObjects(boardId, objects);
    await _reindexBoard(boardId);
  }

  @override
  Future<void> deleteObjects(String boardId, Iterable<String> objectIds) async {
    await _base.deleteObjects(boardId, objectIds);
    await _reindexBoard(boardId);
  }

  Future<void> _reindexBoard(String boardId) async {
    final board = await _base.getBoard(boardId);
    if (board == null) {
      await _deleteBoardIndex(boardId);
    } else {
      await _indexBoard(board);
    }
  }

  Future<void> _indexBoard(CanvasBoard board) async {
    try {
      final coordinator = await Future.value(_coordinator);
      await coordinator.removeBoard(board.id);
      await coordinator.indexDocuments(_projector.projectBoard(board));
    } on Object {
      return;
    }
  }

  Future<void> _deleteBoardIndex(String boardId) async {
    try {
      await (await Future.value(_coordinator)).removeBoard(boardId);
    } on Object {
      return;
    }
  }
}

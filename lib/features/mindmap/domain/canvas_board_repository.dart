import 'canvas_board.dart';

abstract interface class CanvasBoardRepository {
  Future<CanvasBoard?> getBoard(String boardId);

  Future<List<CanvasBoard>> listBoards({
    CanvasBoardKind? kind,
    String? workspaceName,
    bool includeArchived = false,
  });

  Future<List<CanvasBoard>> listWorkspaceBoards(
    String workspaceName, {
    bool includeArchived = false,
    bool includeTrashed = false,
  });

  Future<List<CanvasBoard>> getBoardsForDay(String dayKey);

  Future<CanvasBoard> saveBoard(CanvasBoard board);

  Future<void> saveBoardsAtomically(Iterable<CanvasBoard> boards);

  Future<void> saveBoardsAtomicallyIfUnchanged({
    required Map<String, CanvasBoard> expectedBoards,
    required Iterable<CanvasBoard> boards,
    Iterable<String> deleteBoardIds = const <String>[],
  });

  Future<void> deleteBoard(String boardId);

  Future<void> deleteBoardsAtomically(Iterable<String> boardIds);

  Future<void> saveObjects(String boardId, Iterable<CanvasObject> objects);

  Future<void> deleteObjects(String boardId, Iterable<String> objectIds);
}

import 'canvas_board.dart';

final class CanvasBoardGraph {
  CanvasBoardGraph(Iterable<CanvasBoard> boards)
    : _boardsById = <String, CanvasBoard>{
        for (final board in boards) board.id: board,
      } {
    for (final board in _boardsById.values) {
      final parentId = board.parentBoardId;
      if (parentId != null && !_boardsById.containsKey(parentId)) {
        throw const FormatException('Missing parent board.');
      }
      for (final object in board.objects) {
        final targetId = object.referencedBoardId;
        if (object.type == CanvasObjectType.boardReference &&
            targetId != null) {
          (_referenceObjectIdsByBoardId[targetId] ??= <String>[]).add(
            object.id,
          );
        }
      }
    }
    for (final board in _boardsById.values) {
      ancestorsOf(board.id);
    }
  }

  final Map<String, CanvasBoard> _boardsById;
  final Map<String, List<String>> _referenceObjectIdsByBoardId =
      <String, List<String>>{};

  List<CanvasBoard> ancestorsOf(String boardId) {
    final board = _boardsById[boardId];
    if (board == null) throw StateError('Board not found.');
    final ancestors = <CanvasBoard>[];
    final visited = <String>{boardId};
    var parentId = board.parentBoardId;
    while (parentId != null) {
      if (!visited.add(parentId)) {
        throw const FormatException('Cyclic board ancestry.');
      }
      final parent = _boardsById[parentId];
      if (parent == null) throw const FormatException('Missing parent board.');
      ancestors.add(parent);
      parentId = parent.parentBoardId;
    }
    return List<CanvasBoard>.unmodifiable(ancestors);
  }

  bool canReference({
    required String sourceBoardId,
    required String targetBoardId,
  }) {
    try {
      validateReference(
        sourceBoardId: sourceBoardId,
        targetBoardId: targetBoardId,
      );
      return true;
    } on StateError {
      return false;
    }
  }

  void validateReference({
    required String sourceBoardId,
    required String targetBoardId,
  }) {
    final source = _boardsById[sourceBoardId];
    final target = _boardsById[targetBoardId];
    if (source == null || target == null) throw StateError('Board not found.');
    if (source.id == target.id) {
      throw StateError('Board cannot reference itself.');
    }
    if (source.workspaceName != target.workspaceName) {
      throw StateError('Board reference must stay in workspace.');
    }
    if (target.isTrashed) throw StateError('Trashed board must be restored.');
    if (ancestorsOf(source.id).any((board) => board.id == target.id)) {
      throw StateError('Board cannot reference an ancestor.');
    }
  }

  List<String> referencingObjectIds(String boardId) =>
      List<String>.unmodifiable(
        _referenceObjectIdsByBoardId[boardId] ?? const <String>[],
      );
}

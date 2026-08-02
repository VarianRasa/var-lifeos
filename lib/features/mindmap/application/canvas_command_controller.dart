import '../domain/canvas_board.dart';

abstract interface class CanvasCommand {
  CanvasBoard apply(CanvasBoard board);

  CanvasBoard revert(CanvasBoard board);
}

final class ReplaceCanvasObjectCommand implements CanvasCommand {
  const ReplaceCanvasObjectCommand({required this.before, required this.after});

  final CanvasObject before;
  final CanvasObject after;

  @override
  CanvasBoard apply(CanvasBoard board) => board.replaceObject(after);

  @override
  CanvasBoard revert(CanvasBoard board) => board.replaceObject(before);
}

final class ReplaceCanvasBoardCommand implements CanvasCommand {
  const ReplaceCanvasBoardCommand({required this.before, required this.after});

  final CanvasBoard before;
  final CanvasBoard after;

  @override
  CanvasBoard apply(CanvasBoard board) => after;

  @override
  CanvasBoard revert(CanvasBoard board) => before;
}

final class CanvasCommandStack {
  CanvasCommandStack({this.limit = 100}) : assert(limit > 0);

  final int limit;
  final List<CanvasCommand> _undo = <CanvasCommand>[];
  final List<CanvasCommand> _redo = <CanvasCommand>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoCount => _undo.length;
  int get redoCount => _redo.length;

  CanvasBoard execute(CanvasBoard board, CanvasCommand command) {
    final next = command.apply(board);
    _undo.add(command);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
    return next;
  }

  CanvasBoard undo(CanvasBoard board) {
    if (_undo.isEmpty) return board;
    final command = _undo.removeLast();
    _redo.add(command);
    return command.revert(board);
  }

  CanvasBoard redo(CanvasBoard board) {
    if (_redo.isEmpty) return board;
    final command = _redo.removeLast();
    _undo.add(command);
    return command.apply(board);
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}

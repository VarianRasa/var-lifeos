import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/canvas_command_controller.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';

void main() {
  test('execute undo redo replaces one object', () {
    final now = DateTime(2026, 7, 28);
    final before = CanvasObject(
      id: 'object-1',
      type: CanvasObjectType.stickyNote,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final after = before.copyWith(
      geometry: before.geometry.copyWith(x: 50, y: 30),
      updatedAt: now.add(const Duration(seconds: 1)),
    );
    final board = CanvasBoard(
      id: 'board-1',
      kind: CanvasBoardKind.project,
      title: 'Board',
      objects: <CanvasObject>[before],
      createdAt: now,
      updatedAt: now,
    );
    final stack = CanvasCommandStack();
    final command = ReplaceCanvasObjectCommand(before: before, after: after);

    final moved = stack.execute(board, command);
    final undone = stack.undo(moved);
    final redone = stack.redo(undone);

    expect(moved.objectById(before.id), after);
    expect(undone.objectById(before.id), before);
    expect(redone.objectById(before.id), after);
    expect(stack.canUndo, isTrue);
    expect(stack.canRedo, isFalse);
  });

  test('new command clears redo and history respects limit', () {
    final now = DateTime(2026, 7, 28);
    final object = CanvasObject(
      id: 'object-1',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 10, height: 10),
      createdAt: now,
      updatedAt: now,
    );
    var board = CanvasBoard(
      id: 'board-1',
      kind: CanvasBoardKind.project,
      title: 'Board',
      objects: <CanvasObject>[object],
      createdAt: now,
      updatedAt: now,
    );
    final stack = CanvasCommandStack(limit: 2);

    for (var x = 1; x <= 3; x++) {
      final before = board.objects.single;
      final after = before.copyWith(
        geometry: before.geometry.copyWith(x: x.toDouble()),
      );
      board = stack.execute(
        board,
        ReplaceCanvasObjectCommand(before: before, after: after),
      );
    }
    board = stack.undo(board);
    expect(stack.canRedo, isTrue);
    final before = board.objects.single;
    final after = before.copyWith(geometry: before.geometry.copyWith(y: 9));
    stack.execute(
      board,
      ReplaceCanvasObjectCommand(before: before, after: after),
    );

    expect(stack.undoCount, 2);
    expect(stack.canRedo, isFalse);
  });

  test('replace board command restores batch create and delete', () {
    final now = DateTime(2026, 7, 28);
    final first = CanvasObject(
      id: 'first',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final second = CanvasObject(
      id: 'second',
      type: CanvasObjectType.stickyNote,
      geometry: const CanvasGeometry(x: 120, y: 0, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final before = CanvasBoard(
      id: 'board',
      kind: CanvasBoardKind.project,
      title: 'Board',
      objects: <CanvasObject>[first],
      createdAt: now,
      updatedAt: now,
    );
    final after = before.copyWith(objects: <CanvasObject>[first, second]);
    final stack = CanvasCommandStack();

    final applied = stack.execute(
      before,
      ReplaceCanvasBoardCommand(before: before, after: after),
    );

    expect(applied.objects, hasLength(2));
    expect(stack.undo(applied).objects, <CanvasObject>[first]);
    expect(stack.redo(before).objects, <CanvasObject>[first, second]);
  });
}

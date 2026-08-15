import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/mindmap/application/collaboration_session.dart';
import 'package:var_app/features/mindmap/data/canvas_board_repositories.dart';
import 'package:var_app/features/mindmap/data/collaboration_canvas_board_repository.dart';
import 'package:var_app/features/mindmap/data/sembast_collaboration_board_sync_store.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/collaboration_room.dart';

void main() {
  test('editor saves locally and queues matching project board', () async {
    final db = await databaseFactoryMemory.openDatabase('board-repository.db');
    final store = SembastCollaborationBoardSyncStore(database: db);
    final session = ActiveCollaborationSessionState()
      ..set(
        const ActiveCollaborationSession(
          roomId: 'room',
          target: CollaborationTarget(
            kind: CollaborationTargetKind.projectBoard,
            id: 'board',
            label: 'Board',
          ),
          uid: 'editor',
          role: CollaborationRole.editor,
        ),
      );
    final base = InMemoryCanvasBoardRepository();
    final repository = CollaborationCanvasBoardRepository(
      base: base,
      store: store,
      sessionReader: session,
    );
    final board = CanvasBoard(
      id: 'board',
      kind: CanvasBoardKind.project,
      title: 'Board',
      workspaceName: 'project:test',
      createdAt: DateTime.utc(2026, 7, 28),
      updatedAt: DateTime.utc(2026, 7, 28),
    );
    await repository.saveBoard(board);
    expect(await base.getBoard('board'), board);
    final payload = (await store.pendingForRoom('room')).single.payload;
    expect(payload['id'], 'board');
    expect(
      (payload['votingSession']! as Map<Object?, Object?>).containsKey(
        'allocations',
      ),
      isFalse,
    );
    await db.close();
  });

  test('atomic save persists all boards then queues active board', () async {
    final db = await databaseFactoryMemory.openDatabase('board-atomic.db');
    final store = SembastCollaborationBoardSyncStore(database: db);
    final session = ActiveCollaborationSessionState()
      ..set(
        const ActiveCollaborationSession(
          roomId: 'room',
          target: CollaborationTarget(
            kind: CollaborationTargetKind.projectBoard,
            id: 'parent',
            label: 'Parent',
          ),
          uid: 'editor',
          role: CollaborationRole.editor,
        ),
      );
    final base = InMemoryCanvasBoardRepository();
    final repository = CollaborationCanvasBoardRepository(
      base: base,
      store: store,
      sessionReader: session,
    );
    final now = DateTime.utc(2026, 8, 2, 12);
    final parent = CanvasBoard(
      id: 'parent',
      kind: CanvasBoardKind.project,
      title: 'Parent',
      workspaceName: 'Work',
      createdAt: now,
      updatedAt: now,
    );
    final child = CanvasBoard(
      id: 'child',
      kind: CanvasBoardKind.project,
      title: 'Child',
      workspaceName: 'Work',
      parentBoardId: 'parent',
      createdAt: now,
      updatedAt: now,
    );

    await repository.saveBoardsAtomically(<CanvasBoard>[parent, child]);

    expect(await base.getBoard('parent'), parent);
    expect(await base.getBoard('child'), child);
    expect(
      (await store.pendingForRoom('room')).map((item) => item.boardId),
      <String>['parent'],
    );
    await db.close();
  });

  test(
    'enqueue failure rolls back compare-and-save without partial board',
    () async {
      final db = await databaseFactoryMemory.openDatabase(
        'board-cas-rollback.db',
      );
      addTearDown(db.close);
      final store = SembastCollaborationBoardSyncStore(database: db);
      final session = ActiveCollaborationSessionState()
        ..set(
          const ActiveCollaborationSession(
            roomId: 'room',
            target: CollaborationTarget(
              kind: CollaborationTargetKind.projectBoard,
              id: 'parent',
              label: 'Parent',
            ),
            uid: 'editor',
            role: CollaborationRole.editor,
          ),
        );
      final base = InMemoryCanvasBoardRepository();
      final now = DateTime.utc(2026, 8, 2, 12);
      final parent = CanvasBoard(
        id: 'parent',
        kind: CanvasBoardKind.project,
        title: 'Before',
        workspaceName: 'Work',
        createdAt: now,
        updatedAt: now,
      );
      final changedParent = parent.copyWith(
        title: 'After',
        updatedAt: now.add(const Duration(minutes: 1)),
      );
      final child = CanvasBoard(
        id: 'child',
        kind: CanvasBoardKind.project,
        title: 'Child',
        workspaceName: 'Work',
        parentBoardId: parent.id,
        createdAt: now,
        updatedAt: now,
      );
      await base.saveBoard(parent);
      final repository = CollaborationCanvasBoardRepository(
        base: base,
        store: store,
        sessionReader: session,
        enqueueMutation: (_) => throw StateError('enqueue failed'),
      );

      await expectLater(
        repository.saveBoardsAtomicallyIfUnchanged(
          expectedBoards: <String, CanvasBoard>{parent.id: parent},
          boards: <CanvasBoard>[changedParent, child],
        ),
        throwsStateError,
      );

      expect(await base.getBoard(parent.id), parent);
      expect(await base.getBoard(child.id), isNull);
      expect(await store.pendingForRoom('room'), isEmpty);
    },
  );

  test('commenter cannot mutate shared project board locally', () async {
    final db = await databaseFactoryMemory.openDatabase('board-readonly.db');
    final session = ActiveCollaborationSessionState()
      ..set(
        const ActiveCollaborationSession(
          roomId: 'room',
          target: CollaborationTarget(
            kind: CollaborationTargetKind.projectBoard,
            id: 'board',
            label: 'Board',
          ),
          uid: 'commenter',
          role: CollaborationRole.commenter,
        ),
      );
    final repository = CollaborationCanvasBoardRepository(
      base: InMemoryCanvasBoardRepository(),
      store: SembastCollaborationBoardSyncStore(database: db),
      sessionReader: session,
    );
    final board = CanvasBoard(
      id: 'board',
      kind: CanvasBoardKind.project,
      title: 'Board',
      workspaceName: 'project:test',
      createdAt: DateTime.utc(2026, 7, 28),
      updatedAt: DateTime.utc(2026, 7, 28),
    );
    expect(
      () => repository.saveBoard(board),
      throwsA(
        isA<CollaborationException>().having(
          (error) => error.code,
          'code',
          CollaborationErrorCode.permissionDenied,
        ),
      ),
    );
    await db.close();
  });
}

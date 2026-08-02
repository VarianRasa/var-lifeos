import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/mindmap/data/canvas_board_repositories.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_repository.dart';
import 'package:var_app/features/mindmap/domain/canvas_workshop.dart';
import 'package:var_app/features/mindmap/domain/workshop_ai.dart';

void main() {
  final now = DateTime.utc(2026, 8, 2, 12);

  CanvasBoard board(
    String id, {
    String workspaceName = 'Work',
    bool isArchived = false,
    DateTime? trashedAt,
  }) => CanvasBoard(
    id: id,
    kind: CanvasBoardKind.project,
    title: id,
    workspaceName: workspaceName,
    isArchived: isArchived,
    trashedAt: trashedAt,
    createdAt: now,
    updatedAt: now,
  );

  Future<void> verifyGraphContract(CanvasBoardRepository repository) async {
    final active = board('active');
    final archived = board('archived', isArchived: true);
    final trashed = board('trashed', trashedAt: now);
    final other = board('other', workspaceName: 'Other');
    await repository.saveBoardsAtomically(<CanvasBoard>[
      active,
      archived,
      trashed,
      other,
    ]);

    expect(
      (await repository.listWorkspaceBoards('Work')).map((item) => item.id),
      <String>['active'],
    );
    expect(
      (await repository.listWorkspaceBoards(
        'Work',
        includeArchived: true,
        includeTrashed: true,
      )).map((item) => item.id).toSet(),
      <String>{'active', 'archived', 'trashed'},
    );

    await repository.deleteBoardsAtomically(<String>['active', 'archived']);
    expect(await repository.getBoard('active'), isNull);
    expect(await repository.getBoard('archived'), isNull);
    expect(await repository.getBoard('trashed'), trashed);
  }

  test('in-memory repository supports workspace graph transactions', () async {
    await verifyGraphContract(InMemoryCanvasBoardRepository());
  });

  test('Sembast repository supports workspace graph transactions', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'canvas-graph-contract.db',
    );
    await verifyGraphContract(SembastCanvasBoardRepository(database: database));
    await database.close();
  });

  Future<void> verifyCompareAndSaveContract(
    CanvasBoardRepository repository,
  ) async {
    final original = board('parent');
    await repository.saveBoard(original);
    final concurrent = original.copyWith(
      title: 'Concurrent edit',
      updatedAt: now.add(const Duration(minutes: 1)),
    );
    await repository.saveBoard(concurrent);

    await expectLater(
      repository.saveBoardsAtomicallyIfUnchanged(
        expectedBoards: <String, CanvasBoard>{original.id: original},
        boards: <CanvasBoard>[
          original.copyWith(title: 'Stale overwrite'),
          board('child'),
        ],
      ),
      throwsStateError,
    );

    expect(await repository.getBoard(original.id), concurrent);
    expect(await repository.getBoard('child'), isNull);
  }

  test('in-memory compare-and-save rejects stale parent atomically', () async {
    await verifyCompareAndSaveContract(InMemoryCanvasBoardRepository());
  });

  test('Sembast compare-and-save rejects stale parent atomically', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'canvas-compare-save.db',
    );
    addTearDown(database.close);
    await verifyCompareAndSaveContract(
      SembastCanvasBoardRepository(database: database),
    );
  });

  test('in-memory atomic save consumes input before changing boards', () async {
    final repository = InMemoryCanvasBoardRepository();
    final original = board('original');
    await repository.saveBoard(original);

    Iterable<CanvasBoard> failingBoards() sync* {
      yield board('new');
      throw StateError('input failed');
    }

    await expectLater(
      repository.saveBoardsAtomically(failingBoards()),
      throwsStateError,
    );
    expect(await repository.getBoard('original'), original);
    expect(await repository.getBoard('new'), isNull);
  });

  test('Sembast repository saves updates and deletes objects', () async {
    final database = await databaseFactoryMemory.openDatabase('canvas-test.db');
    final repository = SembastCanvasBoardRepository(database: database);
    final now = DateTime(2026, 7, 28);
    final object = CanvasObject(
      id: 'object-1',
      type: CanvasObjectType.stickyNote,
      geometry: const CanvasGeometry(x: 1, y: 2, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'board-1',
      kind: CanvasBoardKind.project,
      title: 'Board',
      objects: <CanvasObject>[object],
      createdAt: now,
      updatedAt: now,
    );

    await repository.saveBoard(board);
    final moved = object.copyWith(geometry: object.geometry.copyWith(x: 40));
    await repository.saveObjects(board.id, <CanvasObject>[moved]);
    expect((await repository.getBoard(board.id))!.objects.single, moved);

    await repository.deleteObjects(board.id, <String>[object.id]);
    expect((await repository.getBoard(board.id))!.objects, isEmpty);
    await database.close();
  });

  test('Sembast repository persists workshop semantic snapshot', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'canvas-summary-test.db',
    );
    final repository = SembastCanvasBoardRepository(database: database);
    const snapshot = WorkshopAiSummarySnapshot(
      summary: 'Outcome',
      themes: <String>['Theme'],
      decisions: <String>['Decision'],
      actionItems: <String>['Action'],
      risks: <String>['Risk'],
      model: 'model',
      version: '1',
    );
    final now = DateTime(2026, 7, 29);
    final board = CanvasBoard(
      id: 'board-summary',
      kind: CanvasBoardKind.project,
      title: 'Summary',
      workshopSession: CanvasWorkshopSession(
        summary: const CanvasWorkshopSummary(
          activeDurationSeconds: 60,
          participantCount: 1,
          objectsAdded: 1,
          objectsUpdated: 0,
          objectsDeleted: 0,
          aiSummarySnapshot: snapshot,
        ),
      ),
      createdAt: now,
      updatedAt: now,
    );

    await repository.saveBoard(board);

    expect(
      (await repository.getBoard(
        board.id,
      ))!.workshopSession.summary!.aiSummarySnapshot,
      snapshot,
    );
    await database.close();
  });

  test('Sembast repository lists recent boards and filters archives', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'canvas-list-test.db',
    );
    final repository = SembastCanvasBoardRepository(database: database);
    final older = CanvasBoard(
      id: 'project:alpha:older',
      kind: CanvasBoardKind.project,
      title: 'Older',
      workspaceName: 'project:Alpha',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
    );
    final recent = CanvasBoard(
      id: 'project:alpha:recent',
      kind: CanvasBoardKind.project,
      title: 'Recent',
      workspaceName: 'project:Alpha',
      createdAt: DateTime(2026, 7, 21),
      updatedAt: DateTime(2026, 7, 28),
    );
    final archived = CanvasBoard(
      id: 'project:alpha:archived',
      kind: CanvasBoardKind.project,
      title: 'Archived',
      workspaceName: 'project:Alpha',
      isArchived: true,
      createdAt: DateTime(2026, 7, 22),
      updatedAt: DateTime(2026, 7, 27),
    );
    await repository.saveBoard(older);
    await repository.saveBoard(recent);
    await repository.saveBoard(archived);

    final active = await repository.listBoards(
      kind: CanvasBoardKind.project,
      workspaceName: 'project:Alpha',
    );
    expect(active.map((board) => board.id), <String>[recent.id, older.id]);

    final all = await repository.listBoards(
      workspaceName: 'project:Alpha',
      includeArchived: true,
    );
    expect(all.map((board) => board.id), <String>[
      recent.id,
      archived.id,
      older.id,
    ]);

    await repository.deleteBoard(recent.id);
    expect(await repository.getBoard(recent.id), isNull);
    await database.close();
  });
}

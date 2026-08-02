import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/mindmap/application/nested_board_service.dart';
import 'package:var_app/features/mindmap/data/canvas_board_repositories.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_repository.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_template.dart';

void main() {
  final now = DateTime.utc(2026, 8, 2, 12);
  var id = 0;

  CanvasObject object(
    String objectId,
    CanvasObjectType type, {
    String? parentFrameId,
    String? parentColumnId,
    String? referencedBoardId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) => CanvasObject(
    id: objectId,
    type: type,
    geometry: const CanvasGeometry(x: 0, y: 0, width: 200, height: 100),
    parentFrameId: parentFrameId,
    parentColumnId: parentColumnId,
    referencedBoardId: referencedBoardId,
    payload: payload,
    createdAt: now,
    updatedAt: now,
  );

  CanvasBoard board(
    String boardId, {
    String? parentBoardId,
    DateTime? trashedAt,
    List<CanvasObject> objects = const <CanvasObject>[],
  }) => CanvasBoard(
    id: boardId,
    kind: CanvasBoardKind.project,
    title: boardId,
    workspaceName: 'Work',
    parentBoardId: parentBoardId,
    trashedAt: trashedAt,
    objects: objects,
    createdAt: now,
    updatedAt: now,
  );

  NestedBoardService service(CanvasBoardRepository repository) =>
      NestedBoardService(
        repository: repository,
        idFactory: () => 'generated-${id++}',
      );

  setUp(() => id = 0);

  test('creates child and parent reference atomically', () async {
    final repository = InMemoryCanvasBoardRepository();
    await repository.saveBoard(board('parent'));

    final mutation = await service(
      repository,
    ).createNestedBoard(parentBoardId: 'parent', title: 'Child', now: now);

    final parent = await repository.getBoard('parent');
    final child = await repository.getBoard('generated-0');
    expect(child!.parentBoardId, 'parent');
    expect(child.title, 'Child');
    expect(parent!.objects.single.type, CanvasObjectType.boardReference);
    expect(parent.objects.single.referencedBoardId, child.id);
    expect(mutation.before.map((item) => item.id), <String>['parent']);
    expect(mutation.after.map((item) => item.id), <String>['parent', child.id]);
  });

  test(
    'copy selection remaps frame column and connector relationships',
    () async {
      final repository = InMemoryCanvasBoardRepository();
      final source = board(
        'parent',
        objects: <CanvasObject>[
          object('frame', CanvasObjectType.frame),
          object('shape-a', CanvasObjectType.shape, parentFrameId: 'frame'),
          object(
            'column',
            CanvasObjectType.column,
            payload: const <String, Object?>{
              'title': 'Column',
              'isCollapsed': false,
              'orderedChildIds': <String>['shape-b'],
            },
          ),
          object('shape-b', CanvasObjectType.shape, parentColumnId: 'column'),
          object(
            'connector',
            CanvasObjectType.connector,
            payload: const <String, Object?>{
              'sourceObjectId': 'shape-a',
              'targetObjectId': 'shape-b',
            },
          ),
        ],
      );
      await repository.saveBoard(source);

      await service(repository).createNestedBoard(
        parentBoardId: 'parent',
        title: 'Copied',
        selectedObjectIds: source.objects.map((item) => item.id).toSet(),
        now: now,
      );

      final child = await repository.getBoard('generated-0');
      final copiedFrame = child!.objects.singleWhere(
        (item) => item.type == CanvasObjectType.frame,
      );
      final copiedColumn = child.objects.singleWhere(
        (item) => item.type == CanvasObjectType.column,
      );
      final frameChild = child.objects.singleWhere(
        (item) => item.parentFrameId != null,
      );
      final columnChild = child.objects.singleWhere(
        (item) => item.parentColumnId != null,
      );
      final connector = child.objects.singleWhere(
        (item) => item.type == CanvasObjectType.connector,
      );

      expect(frameChild.parentFrameId, copiedFrame.id);
      expect(columnChild.parentColumnId, copiedColumn.id);
      expect(copiedColumn.orderedColumnChildIds, <String>[columnChild.id]);
      expect(connector.payload['sourceObjectId'], frameChild.id);
      expect(connector.payload['targetObjectId'], columnChild.id);
      final updatedSource = await repository.getBoard('parent');
      expect(
        updatedSource!.objects.where(
          (item) => item.type != CanvasObjectType.boardReference,
        ),
        source.objects,
      );
    },
  );

  test('copy selection excludes board references', () async {
    final repository = InMemoryCanvasBoardRepository();
    final reference = object(
      'reference',
      CanvasObjectType.boardReference,
      referencedBoardId: 'target',
    );
    await repository.saveBoard(
      board('parent', objects: <CanvasObject>[reference]),
    );

    await service(repository).createNestedBoard(
      parentBoardId: 'parent',
      title: 'Copied',
      selectedObjectIds: <String>{reference.id},
      now: now,
    );

    expect((await repository.getBoard('generated-0'))!.objects, isEmpty);
  });

  test(
    'creates nested board from prebuilt template objects atomically',
    () async {
      final repository = InMemoryCanvasBoardRepository();
      await repository.saveBoard(board('parent'));
      final templateObjects = <CanvasObject>[
        object('template-shape', CanvasObjectType.shape),
      ];

      final mutation = await service(repository).createNestedBoard(
        parentBoardId: 'parent',
        title: 'Template child',
        templateObjects: templateObjects,
        now: now,
      );

      final child = await repository.getBoard('generated-0');
      final parent = await repository.getBoard('parent');
      expect(child!.objects.single.id, 'generated-1');
      expect(parent!.objects.single.referencedBoardId, child.id);
      expect(mutation.after.map((item) => item.id), <String>[
        'parent',
        child.id,
      ]);
    },
  );

  test(
    'live source trashed at write boundary leaves no partial state',
    () async {
      final delegate = InMemoryCanvasBoardRepository();
      final parent = board('parent');
      final source = board(
        'source',
        objects: <CanvasObject>[object('source-shape', CanvasObjectType.shape)],
      );
      await delegate.saveBoardsAtomically(<CanvasBoard>[parent, source]);
      final repository = _BeforeCompareSaveRepository(
        delegate,
        () => delegate.saveBoard(source.copyWith(trashedAt: now)),
      );

      await expectLater(
        service(repository).createNestedBoard(
          parentBoardId: parent.id,
          title: 'Child',
          sourceBoardId: source.id,
          now: now,
        ),
        throwsStateError,
      );

      expect((await delegate.getBoard(parent.id))!.objects, isEmpty);
      expect(await delegate.getBoard('generated-0'), isNull);
    },
  );

  test(
    'concurrent parent edit is preserved and child is not created',
    () async {
      final delegate = InMemoryCanvasBoardRepository();
      final parent = board('parent');
      await delegate.saveBoard(parent);
      final edited = parent.copyWith(
        title: 'Concurrent title',
        updatedAt: now.add(const Duration(minutes: 1)),
      );
      final repository = _BeforeCompareSaveRepository(
        delegate,
        () => delegate.saveBoard(edited),
      );

      await expectLater(
        service(
          repository,
        ).createNestedBoard(parentBoardId: parent.id, title: 'Child', now: now),
        throwsStateError,
      );

      expect(await delegate.getBoard(parent.id), edited);
      expect(await delegate.getBoard('generated-0'), isNull);
    },
  );

  test('focused template input preserves existing callers', () async {
    final repository = InMemoryCanvasBoardRepository();
    await repository.saveBoard(board('parent'));

    await service(repository).createNestedBoard(
      parentBoardId: 'parent',
      title: 'Focused',
      template: CanvasProjectTemplate.kanban,
      now: now,
    );

    expect((await repository.getBoard('generated-0'))!.objects, isNotEmpty);
  });

  test('rejects conflicting template inputs before atomic write', () async {
    final repository = InMemoryCanvasBoardRepository();
    await repository.saveBoard(board('parent'));

    await expectLater(
      service(repository).createNestedBoard(
        parentBoardId: 'parent',
        title: 'Invalid',
        template: CanvasProjectTemplate.kanban,
        templateObjects: builtInCanvasBoardTemplates.first.objects,
        now: now,
      ),
      throwsArgumentError,
    );

    expect((await repository.getBoard('parent'))!.objects, isEmpty);
    expect(await repository.getBoard('generated-0'), isNull);
  });

  test('Sembast transaction failure rolls back parent and child', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'nested-board-atomic-failure.db',
    );
    addTearDown(database.close);
    final repository = SembastCanvasBoardRepository(database: database);
    final parent = board('parent');
    await repository.saveBoard(parent);
    final invalidPayload = <String, Object?>{'unsupported': Object()};

    await expectLater(
      service(repository).createNestedBoard(
        parentBoardId: 'parent',
        title: 'Child',
        templateObjects: <CanvasObject>[
          object('invalid', CanvasObjectType.shape, payload: invalidPayload),
        ],
        now: now,
      ),
      throwsA(anything),
    );

    expect(await repository.getBoard('parent'), parent);
    expect(await repository.getBoard('generated-0'), isNull);
  });

  test('links existing eligible board', () async {
    final repository = InMemoryCanvasBoardRepository();
    await repository.saveBoardsAtomically(<CanvasBoard>[
      board('source'),
      board('target'),
    ]);

    await service(repository).linkExistingBoard(
      sourceBoardId: 'source',
      targetBoardId: 'target',
      now: now,
    );

    expect(
      (await repository.getBoard('source'))!.objects.single.referencedBoardId,
      'target',
    );
  });

  test('deletes reference only or trashes board and all references', () async {
    final repository = InMemoryCanvasBoardRepository();
    final target = board('target');
    final first = board(
      'first',
      objects: <CanvasObject>[
        object(
          'first-ref',
          CanvasObjectType.boardReference,
          referencedBoardId: 'target',
        ),
      ],
    );
    final second = board(
      'second',
      objects: <CanvasObject>[
        object(
          'second-ref',
          CanvasObjectType.boardReference,
          referencedBoardId: 'target',
        ),
      ],
    );
    await repository.saveBoardsAtomically(<CanvasBoard>[target, first, second]);
    final nested = service(repository);

    await nested.deleteBoardReference(
      sourceBoardId: 'first',
      referenceObjectId: 'first-ref',
      choice: BoardReferenceDeleteChoice.referenceOnly,
      now: now,
    );
    expect((await repository.getBoard('first'))!.objects, isEmpty);
    expect((await repository.getBoard('target'))!.isTrashed, isFalse);

    await nested.deleteBoardReference(
      sourceBoardId: 'second',
      referenceObjectId: 'second-ref',
      choice: BoardReferenceDeleteChoice.boardAndAllReferences,
      now: now,
    );
    expect((await repository.getBoard('target'))!.trashedAt, now);
    expect((await repository.getBoard('second'))!.objects, isEmpty);
  });

  test('restores board and purges expired board plus references', () async {
    final repository = InMemoryCanvasBoardRepository();
    final old = now.subtract(const Duration(days: 30));
    await repository.saveBoardsAtomically(<CanvasBoard>[
      board('target', trashedAt: old),
      board(
        'source',
        objects: <CanvasObject>[
          object(
            'ref',
            CanvasObjectType.boardReference,
            referencedBoardId: 'target',
          ),
        ],
      ),
    ]);
    final nested = service(repository);

    final restore = await nested.restoreBoard(boardId: 'target', now: now);
    expect((await repository.getBoard('target'))!.isTrashed, isFalse);
    await nested.revertMutation(restore);
    expect((await repository.getBoard('target'))!.isTrashed, isTrue);
    await nested.reapplyMutation(restore);
    expect((await repository.getBoard('target'))!.isTrashed, isFalse);

    await repository.saveBoard(board('target', trashedAt: old));
    await nested.purgeExpiredTrash(now);
    expect(await repository.getBoard('target'), isNull);
    expect((await repository.getBoard('source'))!.objects, isEmpty);
  });
}

final class _BeforeCompareSaveRepository implements CanvasBoardRepository {
  _BeforeCompareSaveRepository(this._delegate, this._beforeSave);

  final CanvasBoardRepository _delegate;
  final Future<void> Function() _beforeSave;
  bool _didRun = false;

  @override
  Future<CanvasBoard?> getBoard(String boardId) => _delegate.getBoard(boardId);

  @override
  Future<List<CanvasBoard>> listBoards({
    CanvasBoardKind? kind,
    String? workspaceName,
    bool includeArchived = false,
  }) => _delegate.listBoards(
    kind: kind,
    workspaceName: workspaceName,
    includeArchived: includeArchived,
  );

  @override
  Future<List<CanvasBoard>> listWorkspaceBoards(
    String workspaceName, {
    bool includeArchived = false,
    bool includeTrashed = false,
  }) => _delegate.listWorkspaceBoards(
    workspaceName,
    includeArchived: includeArchived,
    includeTrashed: includeTrashed,
  );

  @override
  Future<CanvasBoard> saveBoard(CanvasBoard board) =>
      _delegate.saveBoard(board);

  @override
  Future<void> saveBoardsAtomically(Iterable<CanvasBoard> boards) =>
      _delegate.saveBoardsAtomically(boards);

  @override
  Future<void> saveBoardsAtomicallyIfUnchanged({
    required Map<String, CanvasBoard> expectedBoards,
    required Iterable<CanvasBoard> boards,
    Iterable<String> deleteBoardIds = const <String>[],
  }) async {
    if (!_didRun) {
      _didRun = true;
      await _beforeSave();
    }
    await _delegate.saveBoardsAtomicallyIfUnchanged(
      expectedBoards: expectedBoards,
      boards: boards,
      deleteBoardIds: deleteBoardIds,
    );
  }

  @override
  Future<void> deleteBoard(String boardId) => _delegate.deleteBoard(boardId);

  @override
  Future<void> deleteBoardsAtomically(Iterable<String> boardIds) =>
      _delegate.deleteBoardsAtomically(boardIds);

  @override
  Future<void> saveObjects(String boardId, Iterable<CanvasObject> objects) =>
      _delegate.saveObjects(boardId, objects);

  @override
  Future<void> deleteObjects(String boardId, Iterable<String> objectIds) =>
      _delegate.deleteObjects(boardId, objectIds);
}

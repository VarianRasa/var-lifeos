import 'package:uuid/uuid.dart';

import '../domain/canvas_board.dart';
import '../domain/canvas_board_graph.dart';
import '../domain/canvas_board_repository.dart';
import '../domain/canvas_object_clone.dart';

enum NestedBoardCreationKind { empty, template, copySelection, existing }

enum BoardReferenceDeleteChoice { referenceOnly, boardAndAllReferences }

final class NestedBoardMutation {
  const NestedBoardMutation({required this.before, required this.after});

  final List<CanvasBoard> before;
  final List<CanvasBoard> after;
}

final class NestedBoardService {
  NestedBoardService({
    required CanvasBoardRepository repository,
    String Function()? idFactory,
  }) : _repository = repository,
       _idFactory = idFactory ?? const Uuid().v4;

  final CanvasBoardRepository _repository;
  final String Function() _idFactory;

  Future<NestedBoardMutation> createNestedBoard({
    required String parentBoardId,
    required String title,
    required DateTime now,
    CanvasProjectTemplate? template,
    Iterable<CanvasObject>? templateObjects,
    String? sourceBoardId,
    Set<String> selectedObjectIds = const <String>{},
  }) async {
    if (template != null && templateObjects != null ||
        sourceBoardId != null &&
            (template != null || templateObjects != null)) {
      throw ArgumentError('Provide one template source only.');
    }
    final parent = await _requiredBoard(parentBoardId);
    final workspaceName = parent.workspaceName;
    if (parent.kind != CanvasBoardKind.project || workspaceName == null) {
      throw StateError('Nested boards require a project workspace.');
    }
    final source = sourceBoardId == null
        ? null
        : await _requiredActiveSource(sourceBoardId, workspaceName);
    final childId = _idFactory();
    var child = CanvasBoard(
      id: childId,
      kind: CanvasBoardKind.project,
      title: title.trim(),
      workspaceName: workspaceName,
      parentBoardId: parent.id,
      createdAt: now,
      updatedAt: now,
      objects: cloneCanvasObjects(
        templateObjects ??
            source?.objects ??
            parent.objects.where(
              (object) => selectedObjectIds.contains(object.id),
            ),
        idFactory: _idFactory,
        now: now,
        excludeBoardReferences: true,
      ),
    );
    if (template != null) {
      child = child.addProjectTemplate(template, now: now);
    }
    final reference = _boardReference(child.id, parent.objects.length, now);
    final updatedParent = parent.copyWith(
      objects: <CanvasObject>[...parent.objects, reference],
      updatedAt: now,
    );
    final mutation = NestedBoardMutation(
      before: <CanvasBoard>[parent],
      after: <CanvasBoard>[updatedParent, child],
    );
    await _repository.saveBoardsAtomicallyIfUnchanged(
      expectedBoards: <String, CanvasBoard>{
        parent.id: parent,
        ..._expectedBoard(source),
      },
      boards: mutation.after,
    );
    return mutation;
  }

  Future<CanvasBoard> createTopLevelBoard({
    required String workspaceName,
    required String title,
    required DateTime now,
    Iterable<CanvasObject>? templateObjects,
    String? sourceBoardId,
  }) async {
    if (templateObjects != null && sourceBoardId != null) {
      throw ArgumentError('Provide one template source only.');
    }
    final source = sourceBoardId == null
        ? null
        : await _requiredActiveSource(sourceBoardId, workspaceName);
    final board = CanvasBoard(
      id: _idFactory(),
      kind: CanvasBoardKind.project,
      title: title.trim(),
      workspaceName: workspaceName,
      createdAt: now,
      updatedAt: now,
      objects: cloneCanvasObjects(
        templateObjects ?? source?.objects ?? const <CanvasObject>[],
        idFactory: _idFactory,
        now: now,
        excludeBoardReferences: true,
      ),
    );
    await _repository.saveBoardsAtomicallyIfUnchanged(
      expectedBoards: _expectedBoard(source),
      boards: <CanvasBoard>[board],
    );
    return board;
  }

  Future<NestedBoardMutation> linkExistingBoard({
    required String sourceBoardId,
    required String targetBoardId,
    required DateTime now,
  }) async {
    final source = await _requiredBoard(sourceBoardId);
    final boards = await _workspaceBoards(source);
    CanvasBoardGraph(boards).validateReference(
      sourceBoardId: sourceBoardId,
      targetBoardId: targetBoardId,
    );
    final updated = source.copyWith(
      objects: <CanvasObject>[
        ...source.objects,
        _boardReference(targetBoardId, source.objects.length, now),
      ],
      updatedAt: now,
    );
    final mutation = NestedBoardMutation(
      before: <CanvasBoard>[source],
      after: <CanvasBoard>[updated],
    );
    await _apply(mutation);
    return mutation;
  }

  Future<NestedBoardMutation> deleteBoardReference({
    required String sourceBoardId,
    required String referenceObjectId,
    required BoardReferenceDeleteChoice choice,
    required DateTime now,
  }) async {
    final source = await _requiredBoard(sourceBoardId);
    final reference = source.objectById(referenceObjectId);
    if (reference == null ||
        reference.type != CanvasObjectType.boardReference) {
      throw StateError('Board reference not found.');
    }
    final targetId = reference.referencedBoardId!;
    final boards = await _workspaceBoards(source);
    if (choice == BoardReferenceDeleteChoice.referenceOnly) {
      final updated = _withoutReferences(source, <String>{reference.id}, now);
      final mutation = NestedBoardMutation(
        before: <CanvasBoard>[source],
        after: <CanvasBoard>[updated],
      );
      await _apply(mutation);
      return mutation;
    }
    final target = boards.where((board) => board.id == targetId).firstOrNull;
    if (target == null) throw StateError('Board not found.');
    final affected = boards
        .where(
          (board) => board.objects.any(
            (object) => object.referencedBoardId == targetId,
          ),
        )
        .toList();
    final after = <CanvasBoard>[
      target.copyWith(trashedAt: now, updatedAt: now),
      for (final board in affected)
        _withoutTargetReferences(board, targetId, now),
    ];
    final beforeById = <String, CanvasBoard>{
      target.id: target,
      for (final board in affected) board.id: board,
    };
    final mutation = NestedBoardMutation(
      before: beforeById.values.toList(growable: false),
      after: after,
    );
    await _apply(mutation);
    return mutation;
  }

  Future<NestedBoardMutation> restoreBoard({
    required String boardId,
    required DateTime now,
  }) async {
    final board = await _requiredBoard(boardId);
    if (!board.isTrashed) throw StateError('Board is not in Trash.');
    final mutation = NestedBoardMutation(
      before: <CanvasBoard>[board],
      after: <CanvasBoard>[
        board.copyWith(clearTrashedAt: true, updatedAt: now),
      ],
    );
    await _apply(mutation);
    return mutation;
  }

  Future<NestedBoardMutation> purgeExpiredTrash(
    DateTime now, {
    String? workspaceName,
  }) async {
    final all = await _repository.listBoards(includeArchived: true);
    final workspaceNames = <String>{
      ?workspaceName,
      ...all.map((board) => board.workspaceName).whereType<String>(),
    };
    final graphBoards = <CanvasBoard>[];
    for (final workspaceName in workspaceNames) {
      graphBoards.addAll(
        await _repository.listWorkspaceBoards(
          workspaceName,
          includeArchived: true,
          includeTrashed: true,
        ),
      );
    }
    final expiredIds = graphBoards
        .where((board) => board.isTrashExpired(now))
        .map((board) => board.id)
        .toSet();
    final changed = <CanvasBoard>[];
    for (final board in graphBoards) {
      if (expiredIds.contains(board.id)) continue;
      final updated = _withoutTargetReferences(board, expiredIds, now);
      if (updated != board) changed.add(updated);
    }
    final before = <CanvasBoard>[
      ...graphBoards.where((board) => expiredIds.contains(board.id)),
      ...graphBoards.where(
        (board) => changed.any((updated) => updated.id == board.id),
      ),
    ];
    final mutation = NestedBoardMutation(before: before, after: changed);
    await _apply(mutation);
    return mutation;
  }

  Future<void> revertMutation(NestedBoardMutation mutation) =>
      _replace(mutation.after, mutation.before);

  Future<void> reapplyMutation(NestedBoardMutation mutation) =>
      _replace(mutation.before, mutation.after);

  Future<CanvasBoard> _requiredBoard(String boardId) async {
    final board = await _repository.getBoard(boardId);
    if (board == null) throw StateError('Board not found.');
    return board;
  }

  Future<CanvasBoard> _requiredActiveSource(
    String boardId,
    String workspaceName,
  ) async {
    final board = await _repository.getBoard(boardId);
    if (board == null ||
        board.kind != CanvasBoardKind.project ||
        board.workspaceName != workspaceName ||
        board.isArchived ||
        board.isTrashed) {
      throw StateError('Template source is unavailable.');
    }
    return board;
  }

  Future<List<CanvasBoard>> _workspaceBoards(CanvasBoard board) {
    final workspaceName = board.workspaceName;
    if (workspaceName == null) throw StateError('Board has no workspace.');
    return _repository.listWorkspaceBoards(
      workspaceName,
      includeArchived: true,
      includeTrashed: true,
    );
  }

  CanvasObject _boardReference(String targetId, int zIndex, DateTime now) =>
      CanvasObject(
        id: _idFactory(),
        type: CanvasObjectType.boardReference,
        geometry: const CanvasGeometry(x: 0, y: 0, width: 280, height: 180),
        zIndex: zIndex,
        referencedBoardId: targetId,
        createdAt: now,
        updatedAt: now,
      );

  CanvasBoard _withoutReferences(
    CanvasBoard board,
    Set<String> objectIds,
    DateTime now,
  ) => board.copyWith(
    objects: board.objects
        .where((object) => !objectIds.contains(object.id))
        .toList(),
    updatedAt: now,
  );

  CanvasBoard _withoutTargetReferences(
    CanvasBoard board,
    Object targetIds,
    DateTime now,
  ) {
    final ids = targetIds is String
        ? <String>{targetIds}
        : targetIds as Set<String>;
    final objects = board.objects
        .where((object) => !ids.contains(object.referencedBoardId))
        .toList();
    return objects.length == board.objects.length
        ? board
        : board.copyWith(objects: objects, updatedAt: now);
  }

  Future<void> _apply(NestedBoardMutation mutation) =>
      _replace(mutation.before, mutation.after);

  Future<void> _replace(
    List<CanvasBoard> oldBoards,
    List<CanvasBoard> newBoards,
  ) async {
    final oldIds = oldBoards.map((board) => board.id).toSet();
    final newIds = newBoards.map((board) => board.id).toSet();
    await _repository.saveBoardsAtomically(newBoards);
    await _repository.deleteBoardsAtomically(oldIds.difference(newIds));
  }
}

Map<String, CanvasBoard> _expectedBoard(CanvasBoard? board) => board == null
    ? const <String, CanvasBoard>{}
    : <String, CanvasBoard>{board.id: board};

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

import 'dart:async';

import 'package:sembast/sembast.dart';

import '../../../core/utils/date_utils.dart';
import '../domain/canvas_board.dart';
import '../domain/canvas_board_repository.dart';

final class InMemoryCanvasBoardRepository implements CanvasBoardRepository {
  final Map<String, CanvasBoard> _boards = <String, CanvasBoard>{};

  @override
  Future<CanvasBoard?> getBoard(String boardId) async => _boards[boardId];

  @override
  Future<List<CanvasBoard>> listBoards({
    CanvasBoardKind? kind,
    String? workspaceName,
    bool includeArchived = false,
  }) async {
    final boards =
        _boards.values
            .where((board) => kind == null || board.kind == kind)
            .where(
              (board) =>
                  workspaceName == null || board.workspaceName == workspaceName,
            )
            .where((board) => includeArchived || !board.isArchived)
            .where((board) => !board.isTrashed)
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return boards;
  }

  @override
  Future<List<CanvasBoard>> listWorkspaceBoards(
    String workspaceName, {
    bool includeArchived = false,
    bool includeTrashed = false,
  }) async {
    final boards =
        _boards.values
            .where((board) => board.workspaceName == workspaceName)
            .where((board) => includeArchived || !board.isArchived)
            .where((board) => includeTrashed || !board.isTrashed)
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return boards;
  }

  @override
  Future<List<CanvasBoard>> getBoardsForDay(String dayKeyString) async {
    final boards =
        _boards.values
            .where(
              (board) =>
                  board.day != null && dayKey(board.day!) == dayKeyString,
            )
            .where((board) => !board.isTrashed)
            .toList()
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return boards;
  }

  @override
  Future<CanvasBoard> saveBoard(CanvasBoard board) async {
    _boards[board.id] = board;
    return board;
  }

  @override
  Future<void> saveBoardsAtomically(Iterable<CanvasBoard> boards) async {
    final replacements = <String, CanvasBoard>{
      for (final board in boards) board.id: board,
    };
    _boards.addAll(replacements);
  }

  @override
  Future<void> saveBoardsAtomicallyIfUnchanged({
    required Map<String, CanvasBoard> expectedBoards,
    required Iterable<CanvasBoard> boards,
    Iterable<String> deleteBoardIds = const <String>[],
  }) async {
    final replacements = <String, CanvasBoard>{
      for (final board in boards) board.id: board,
    };
    for (final entry in expectedBoards.entries) {
      if (_boards[entry.key] != entry.value) {
        throw StateError('Canvas board changed concurrently.');
      }
    }
    _boards.addAll(replacements);
    for (final boardId in deleteBoardIds) {
      _boards.remove(boardId);
    }
  }

  @override
  Future<void> deleteBoard(String boardId) async {
    _boards.remove(boardId);
  }

  @override
  Future<void> deleteBoardsAtomically(Iterable<String> boardIds) async {
    final ids = boardIds.toSet();
    for (final id in ids) {
      _boards.remove(id);
    }
  }

  @override
  Future<void> saveObjects(
    String boardId,
    Iterable<CanvasObject> objects,
  ) async {
    var board = _boards[boardId];
    if (board == null) {
      if (boardId.startsWith('daily:')) {
        final dayString = boardId.substring(6);
        final date = DateTime.tryParse(dayString);
        if (date != null) {
          board = CanvasBoard.daily(
            day: date,
            nodes: const [],
            now: DateTime.now(),
          );
          _boards[boardId] = board;
        } else {
          throw StateError('Canvas board not found: $boardId');
        }
      } else {
        throw StateError('Canvas board not found: $boardId');
      }
    }
    final replacements = <String, CanvasObject>{
      for (final object in objects) object.id: object,
    };
    final existingIds = board.objects.map((object) => object.id).toSet();
    _boards[boardId] = board.copyWith(
      objects: <CanvasObject>[
        for (final object in board.objects) replacements[object.id] ?? object,
        for (final object in replacements.values)
          if (!existingIds.contains(object.id)) object,
      ],
    );
  }

  @override
  Future<void> deleteObjects(String boardId, Iterable<String> objectIds) async {
    final board = _boards[boardId];
    if (board == null) return;
    final ids = objectIds.toSet();
    _boards[boardId] = board.copyWith(
      objects: board.objects
          .where((object) => !ids.contains(object.id))
          .toList(),
    );
  }
}

final class SembastCanvasBoardRepository implements CanvasBoardRepository {
  SembastCanvasBoardRepository({required FutureOr<Database> database})
    : _databaseSource = database;

  final FutureOr<Database> _databaseSource;
  final StoreRef<String, Map<String, Object?>> _boardStore =
      stringMapStoreFactory.store('canvas_boards');
  final StoreRef<String, Map<String, Object?>> _objectStore =
      stringMapStoreFactory.store('canvas_objects');
  Database? _database;

  Future<Database> get _db async =>
      _database ??= await Future<Database>.value(_databaseSource);

  @override
  Future<CanvasBoard?> getBoard(String boardId) async =>
      _getBoard(await _db, boardId);

  Future<CanvasBoard?> _getBoard(DatabaseClient client, String boardId) async {
    final boardJson = await _boardStore.record(boardId).get(client);
    if (boardJson == null) return null;
    final records = await _objectStore.find(
      client,
      finder: Finder(
        filter: Filter.equals('boardId', boardId),
        sortOrders: <SortOrder>[SortOrder('zIndex'), SortOrder('objectId')],
      ),
    );
    return CanvasBoard.fromJson(<String, Object?>{
      ...boardJson,
      'objects': <Map<String, Object?>>[
        for (final record in records) _objectJson(record.value),
      ],
    });
  }

  @override
  Future<List<CanvasBoard>> listBoards({
    CanvasBoardKind? kind,
    String? workspaceName,
    bool includeArchived = false,
  }) async {
    final db = await _db;
    final records = await _boardStore.find(
      db,
      finder: Finder(sortOrders: <SortOrder>[SortOrder('updatedAt', false)]),
    );
    final boards = <CanvasBoard>[];
    for (final record in records) {
      final board = await getBoard(record.key);
      if (board == null ||
          (kind != null && board.kind != kind) ||
          (workspaceName != null && board.workspaceName != workspaceName) ||
          (!includeArchived && board.isArchived) ||
          board.isTrashed) {
        continue;
      }
      boards.add(board);
    }
    return boards;
  }

  @override
  Future<List<CanvasBoard>> listWorkspaceBoards(
    String workspaceName, {
    bool includeArchived = false,
    bool includeTrashed = false,
  }) async {
    final db = await _db;
    final records = await _boardStore.find(
      db,
      finder: Finder(
        filter: Filter.equals('workspaceName', workspaceName),
        sortOrders: <SortOrder>[SortOrder('updatedAt', false)],
      ),
    );
    final boards = <CanvasBoard>[];
    for (final record in records) {
      final board = await getBoard(record.key);
      if (board == null ||
          (!includeArchived && board.isArchived) ||
          (!includeTrashed && board.isTrashed)) {
        continue;
      }
      boards.add(board);
    }
    return boards;
  }

  @override
  Future<List<CanvasBoard>> getBoardsForDay(String dayKey) async {
    final db = await _db;
    final records = await _boardStore.find(
      db,
      finder: Finder(
        filter: Filter.equals('day', dayKey),
        sortOrders: <SortOrder>[SortOrder('updatedAt', false)],
      ),
    );
    final boards = <CanvasBoard>[];
    for (final record in records) {
      final board = await getBoard(record.key);
      if (board == null || board.isTrashed) {
        continue;
      }
      boards.add(board);
    }
    return boards;
  }

  @override
  Future<CanvasBoard> saveBoard(CanvasBoard board) async {
    await saveBoardsAtomically(<CanvasBoard>[board]);
    return board;
  }

  @override
  Future<void> saveBoardsAtomically(Iterable<CanvasBoard> boards) async {
    final values = boards.toList(growable: false);
    final db = await _db;
    await db.transaction((transaction) async {
      for (final board in values) {
        await _saveBoard(transaction, board);
      }
    });
  }

  @override
  Future<void> saveBoardsAtomicallyIfUnchanged({
    required Map<String, CanvasBoard> expectedBoards,
    required Iterable<CanvasBoard> boards,
    Iterable<String> deleteBoardIds = const <String>[],
  }) async {
    final values = boards.toList(growable: false);
    final db = await _db;
    await db.transaction((transaction) async {
      for (final entry in expectedBoards.entries) {
        final current = await _getBoard(transaction, entry.key);
        if (current != entry.value) {
          throw StateError('Canvas board changed concurrently.');
        }
      }
      for (final board in values) {
        await _saveBoard(transaction, board);
      }
      for (final boardId in deleteBoardIds) {
        await _deleteBoard(transaction, boardId);
      }
    });
  }

  @override
  Future<void> deleteBoard(String boardId) async {
    await deleteBoardsAtomically(<String>[boardId]);
  }

  @override
  Future<void> deleteBoardsAtomically(Iterable<String> boardIds) async {
    final ids = boardIds.toSet();
    final db = await _db;
    await db.transaction((transaction) async {
      for (final boardId in ids) {
        await _deleteBoard(transaction, boardId);
      }
    });
  }

  @override
  Future<void> saveObjects(
    String boardId,
    Iterable<CanvasObject> objects,
  ) async {
    final db = await _db;
    if (!await _boardStore.record(boardId).exists(db)) {
      if (boardId.startsWith('daily:')) {
        final dayString = boardId.substring(6);
        final date = DateTime.tryParse(dayString);
        if (date != null) {
          final board = CanvasBoard.daily(
            day: date,
            nodes: const [],
            now: DateTime.now(),
          );
          await _saveBoard(db, board);
        } else {
          throw StateError('Canvas board not found: $boardId');
        }
      } else {
        throw StateError('Canvas board not found: $boardId');
      }
    }
    await db.transaction((transaction) async {
      for (final object in objects) {
        await _objectStore
            .record(_objectKey(boardId, object.id))
            .put(transaction, _objectRecord(boardId, object));
      }
    });
  }

  @override
  Future<void> deleteObjects(String boardId, Iterable<String> objectIds) async {
    final db = await _db;
    await db.transaction((transaction) async {
      for (final objectId in objectIds) {
        await _objectStore
            .record(_objectKey(boardId, objectId))
            .delete(transaction);
      }
    });
  }

  Future<void> _saveBoard(DatabaseClient transaction, CanvasBoard board) async {
    await _boardStore.record(board.id).put(transaction, _boardJson(board));
    final staleKeys = await _objectStore.findKeys(
      transaction,
      finder: Finder(filter: Filter.equals('boardId', board.id)),
    );
    for (final key in staleKeys) {
      await _objectStore.record(key).delete(transaction);
    }
    for (final object in board.objects) {
      await _objectStore
          .record(_objectKey(board.id, object.id))
          .put(transaction, _objectRecord(board.id, object));
    }
  }

  Future<void> _deleteBoard(DatabaseClient transaction, String boardId) async {
    await _boardStore.record(boardId).delete(transaction);
    final keys = await _objectStore.findKeys(
      transaction,
      finder: Finder(filter: Filter.equals('boardId', boardId)),
    );
    for (final key in keys) {
      await _objectStore.record(key).delete(transaction);
    }
  }
}

String _objectKey(String boardId, String objectId) => '$boardId::$objectId';

Map<String, Object?> _boardJson(CanvasBoard board) =>
    board.toJson()..remove('objects');

Map<String, Object?> _objectRecord(String boardId, CanvasObject object) =>
    <String, Object?>{
      'boardId': boardId,
      'objectId': object.id,
      'zIndex': object.zIndex,
      'object': object.toJson(),
    };

Map<String, Object?> _objectJson(Map<String, Object?> record) {
  final object = record['object'];
  if (object is! Map) {
    throw const FormatException('Canvas object record is missing object.');
  }
  return Map<String, Object?>.from(object);
}

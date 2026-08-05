import 'package:uuid/uuid.dart';

import '../application/collaboration_session.dart';
import '../domain/canvas_board.dart';
import '../domain/canvas_board_graph.dart';
import '../domain/canvas_board_repository.dart';
import '../domain/collaboration_board_sync.dart';
import '../domain/collaboration_room.dart';
import 'sembast_collaboration_board_sync_store.dart';

typedef CollaborationMutationEnqueuer =
    Future<void> Function(CollaborationPendingBoardMutation mutation);

final class CollaborationCanvasBoardRepository
    implements CanvasBoardRepository {
  CollaborationCanvasBoardRepository({
    required CanvasBoardRepository base,
    required SembastCollaborationBoardSyncStore store,
    required ActiveCollaborationSessionReader sessionReader,
    CollaborationMutationEnqueuer? enqueueMutation,
    Uuid uuid = const Uuid(),
  }) : _base = base,
       _store = store,
       _sessionReader = sessionReader,
       _enqueueMutation = enqueueMutation ?? store.enqueue,
       _uuid = uuid;

  final CanvasBoardRepository _base;
  final SembastCollaborationBoardSyncStore _store;
  final ActiveCollaborationSessionReader _sessionReader;
  final CollaborationMutationEnqueuer _enqueueMutation;
  final Uuid _uuid;
  var _applyingRemote = false;

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
    _ensureCanMutate(board.id);
    final saved = await _base.saveBoard(board);
    await _enqueue(saved);
    return saved;
  }

  @override
  Future<void> saveBoardsAtomically(Iterable<CanvasBoard> boards) async {
    final values = boards.toList(growable: false);
    for (final board in values) {
      _ensureCanMutate(board.id);
    }
    await _base.saveBoardsAtomically(values);
    for (final board in values) {
      await _enqueue(board);
    }
  }

  @override
  Future<void> saveBoardsAtomicallyIfUnchanged({
    required Map<String, CanvasBoard> expectedBoards,
    required Iterable<CanvasBoard> boards,
    Iterable<String> deleteBoardIds = const <String>[],
  }) async {
    final values = boards.toList(growable: false);
    for (final board in values) {
      _ensureCanMutate(board.id);
    }
    await _base.saveBoardsAtomicallyIfUnchanged(
      expectedBoards: expectedBoards,
      boards: values,
      deleteBoardIds: deleteBoardIds,
    );
    try {
      for (final board in values) {
        await _enqueue(board);
      }
    } on Object {
      await _base.saveBoardsAtomicallyIfUnchanged(
        expectedBoards: <String, CanvasBoard>{
          for (final board in values) board.id: board,
        },
        boards: expectedBoards.values,
        deleteBoardIds: values
            .where((board) => !expectedBoards.containsKey(board.id))
            .map((board) => board.id),
      );
      rethrow;
    }
  }

  @override
  Future<void> deleteBoard(String boardId) => _base.deleteBoard(boardId);

  @override
  Future<void> deleteBoardsAtomically(Iterable<String> boardIds) async {
    final ids = boardIds.toSet();
    for (final boardId in ids) {
      _ensureCanMutate(boardId);
    }
    await _base.deleteBoardsAtomically(ids);
  }

  @override
  Future<void> saveObjects(
    String boardId,
    Iterable<CanvasObject> objects,
  ) async {
    _ensureCanMutate(boardId);
    await _base.saveObjects(boardId, objects);
    final board = await _base.getBoard(boardId);
    if (board != null) await _enqueue(board);
  }

  @override
  Future<void> deleteObjects(String boardId, Iterable<String> objectIds) async {
    _ensureCanMutate(boardId);
    await _base.deleteObjects(boardId, objectIds);
    final board = await _base.getBoard(boardId);
    if (board != null) await _enqueue(board);
  }

  Future<void> applyRemoteBoard(
    CanvasBoard board, {
    required String roomId,
    required int revision,
  }) async {
    if (board.kind != CanvasBoardKind.project) {
      throw StateError('Collaboration remote board must be a project board.');
    }
    if (!await _store.applyRemoteRevision(roomId, board.id, revision)) return;
    _applyingRemote = true;
    try {
      final local = await _base.getBoard(board.id);
      final workspaceName = board.workspaceName;
      if (workspaceName != null) {
        final workspaceBoards = await _base.listWorkspaceBoards(
          workspaceName,
          includeArchived: true,
          includeTrashed: true,
        );
        CanvasBoardGraph(<CanvasBoard>[
          ...workspaceBoards.where((candidate) => candidate.id != board.id),
          board,
        ]);
      }
      final voting = board.votingSession;

      await _base.saveBoard(
        local == null
            ? board
            : board.copyWith(
                votingSession: CanvasVotingSession(
                  sessionId: voting.sessionId,
                  ballotStorageVersion: voting.ballotStorageVersion,
                  status: voting.status,
                  isAnonymous: voting.isAnonymous,
                  resultsRevealed: voting.resultsRevealed,
                  maxVotesPerParticipant: voting.maxVotesPerParticipant,
                  allocations: local.votingSession.sessionId == voting.sessionId
                      ? local.votingSession.allocations
                      : const <String, Set<String>>{},
                ),
              ),
      );
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> applyLocalBallot(
    String boardId, {
    required String uid,
    required String sessionId,
    required Iterable<String> objectIds,
  }) async {
    final board = await _base.getBoard(boardId);
    if (board == null || board.votingSession.sessionId != sessionId) return;
    final allocations = <String, Set<String>>{
      ...board.votingSession.allocations,
      uid: objectIds.where((id) => id.isNotEmpty).toSet(),
    };
    _applyingRemote = true;
    try {
      await _base.saveBoard(
        board.copyWith(
          votingSession: CanvasVotingSession(
            sessionId: sessionId,
            ballotStorageVersion: board.votingSession.ballotStorageVersion,
            status: board.votingSession.status,
            isAnonymous: board.votingSession.isAnonymous,
            resultsRevealed: board.votingSession.resultsRevealed,
            maxVotesPerParticipant: board.votingSession.maxVotesPerParticipant,
            allocations: allocations,
          ),
        ),
      );
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> _enqueue(CanvasBoard board) async {
    if (_applyingRemote || board.kind != CanvasBoardKind.project) return;
    final session = _sessionReader.current;
    if (session == null ||
        session.target.kind != CollaborationTargetKind.projectBoard ||
        session.target.id != board.id ||
        !session.role.canWriteNodes) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _enqueueMutation(
      CollaborationPendingBoardMutation(
        mutationId: _uuid.v4(),
        roomId: session.roomId,
        boardId: board.id,
        baseRevision: await _store.revision(session.roomId, board.id),
        payload: collaborationBoardPayload(board.toJson()),
        updatedByUid: session.uid,
        attemptCount: 0,
        createdAt: now,
        updatedAt: now,
        nextAttemptAt: now,
        lastAttemptAt: null,
        lastErrorCode: null,
        deliveryState: CollaborationBoardDeliveryState.pending,
      ),
    );
  }

  void _ensureCanMutate(String boardId) {
    if (_applyingRemote) return;
    final session = _sessionReader.current;
    if (session == null ||
        session.target.kind != CollaborationTargetKind.projectBoard ||
        session.target.id != boardId) {
      return;
    }
    if (!session.role.canWriteNodes) {
      throw const CollaborationException(
        CollaborationErrorCode.permissionDenied,
        'Your collaboration role cannot edit this board.',
      );
    }
  }
}

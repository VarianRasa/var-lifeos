import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/canvas_workshop.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('voting codec preserves ballot metadata and local allocations', () {
    final session = CanvasVotingSession(
      sessionId: 'session',
      ballotStorageVersion: 1,
      status: CanvasVotingStatus.active,
      allocations: const <String, Set<String>>{
        'participant': <String>{'object'},
      },
    );

    expect(CanvasVotingSession.fromJson(session.toJson()), session);
    final metadata = session.toJson(includeAllocations: false);
    expect(metadata['sessionId'], 'session');
    expect(metadata.containsKey('allocations'), isFalse);
  });

  test('round trip preserves canvas object rotation radians', () {
    const geometry = CanvasGeometry(
      x: 10,
      y: 20,
      width: 100,
      height: 80,
      rotation: 0.2617993877991494,
    );

    expect(CanvasGeometry.fromJson(geometry.toJson()), geometry);
  });

  test('round trip preserves unknown canvas object payload', () {
    final json = <String, Object?>{
      'id': 'board-1',
      'kind': 'project',
      'title': 'Roadmap',
      'schemaVersion': 1,
      'viewport': <String, Object?>{'x': 1, 'y': 2, 'scale': 0.8},
      'settings': <String, Object?>{'background': 'grid'},
      'createdAt': '2026-07-28T00:00:00.000Z',
      'updatedAt': '2026-07-28T00:00:00.000Z',
      'objects': <Object?>[
        <String, Object?>{
          'id': 'future-1',
          'type': 'futureWidget',
          'geometry': <String, Object?>{
            'x': 10,
            'y': 20,
            'width': 100,
            'height': 80,
          },
          'payload': <String, Object?>{
            'nested': <String, Object?>{'keep': true},
          },
          'createdAt': '2026-07-28T00:00:00.000Z',
          'updatedAt': '2026-07-28T00:00:00.000Z',
        },
      ],
    };

    final board = CanvasBoard.fromJson(json);

    expect(board.objects.single.type, CanvasObjectType.unknown);
    expect(board.objects.single.rawType, 'futureWidget');
    expect(CanvasBoard.fromJson(board.toJson()), board);
  });

  test('workshop view excludes private objects until reveal', () {
    final now = DateTime.utc(2026, 7, 29, 9);
    final stage = CanvasWorkshopStage(
      id: 'ideas',
      title: 'Ideas',
      type: CanvasWorkshopStageType.brainstorm,
      durationSeconds: 300,
    );
    var session = CanvasWorkshopSession().startAgenda(
      sessionId: 'session',
      hostUid: 'owner',
      now: now,
      agenda: <CanvasWorkshopStage>[stage],
      baselineObjectVersions: const <String, String>{},
    );
    CanvasBoard boardWithSession(
      CanvasWorkshopSession currentSession,
    ) => CanvasBoard(
      id: 'board',
      kind: CanvasBoardKind.project,
      title: 'Workshop',
      workshopSession: currentSession,
      objects: <CanvasObject>[
        CanvasObject(
          id: 'public',
          type: CanvasObjectType.stickyNote,
          geometry: const CanvasGeometry(x: 0, y: 0, width: 120, height: 80),
          createdAt: now,
          updatedAt: now,
        ),
        CanvasObject(
          id: 'private-a',
          type: CanvasObjectType.stickyNote,
          geometry: const CanvasGeometry(x: 140, y: 0, width: 120, height: 80),
          payload: const <String, Object?>{
            'workshopPrivate': true,
            'workshopStageId': 'ideas',
            'workshopAuthorUid': 'editor-a',
          },
          createdAt: now,
          updatedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    var board = boardWithSession(session);
    expect(
      board
          .visibleForWorkshop(
            session: session,
            viewerUid: 'editor-b',
            isHost: false,
          )
          .objects
          .map((object) => object.id),
      <String>['public'],
    );
    expect(
      board
          .visibleForWorkshop(
            session: session,
            viewerUid: 'editor-a',
            isHost: false,
          )
          .objects
          .map((object) => object.id),
      <String>['public', 'private-a'],
    );
    expect(
      board
          .visibleForWorkshop(
            session: session,
            viewerUid: 'owner',
            isHost: true,
          )
          .objects
          .map((object) => object.id),
      <String>['public', 'private-a'],
    );

    session = session.revealActiveStage();
    board = boardWithSession(session);
    expect(
      board
          .visibleForWorkshop(
            session: session,
            viewerUid: 'editor-b',
            isHost: false,
          )
          .objects
          .map((object) => object.id),
      <String>['public', 'private-a'],
    );
  });

  test('daily adapter uses legacy node geometry and stable id', () {
    final day = DateTime(2026, 7, 28);
    final node = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Task',
      day: day,
      position: const CanvasPosition(40, 60),
      data: const <String, Object?>{
        'uiSizePreset': 'custom',
        'uiWidth': 420.0,
        'uiHeight': 260.0,
        'groupId': 'frame-1',
        'groupLocked': true,
      },
      now: day,
    );

    final board = CanvasBoard.daily(
      day: day,
      nodes: <MindmapNode>[node],
      now: day,
    );
    final object = board.objects.single;

    expect(board.id, 'daily:2026-07-28');
    expect(object.mindmapNodeId, node.id);
    expect(
      object.geometry,
      const CanvasGeometry(x: 40, y: 60, width: 420, height: 260),
    );
    expect(object.parentFrameId, 'frame-1');
    expect(object.isLocked, isTrue);
  });

  test(
    'project adapter creates stable workspace board and node references',
    () {
      final now = DateTime(2026, 7, 28);
      final node = MindmapNode.create(
        id: 'task-1',
        type: NodeType.task,
        title: 'Task',
        day: now,
        position: const CanvasPosition(20, 30),
        now: now,
      );

      final board = CanvasBoard.project(
        workspaceName: 'project:Alpha Launch',
        nodes: <MindmapNode>[node],
        now: now,
      );

      expect(board.id, 'project:project%3Aalpha%20launch');
      expect(board.kind, CanvasBoardKind.project);
      expect(board.workspaceName, 'project:Alpha Launch');
      expect(board.objects.single.mindmapNodeId, node.id);
      expect(board.objects.single.geometry.x, 20);
      expect(board.objects.single.geometry.y, 30);
    },
  );

  test('project reconciliation preserves layout and native objects', () {
    final now = DateTime(2026, 7, 28);
    final retained = MindmapNode.create(
      id: 'retained',
      type: NodeType.task,
      title: 'Retained',
      day: now,
      position: const CanvasPosition(10, 20),
      now: now,
    );
    final added = MindmapNode.create(
      id: 'added',
      type: NodeType.note,
      title: 'Added',
      day: now,
      position: const CanvasPosition(70, 90),
      now: now,
    );
    final stale = MindmapNode.create(
      id: 'stale',
      type: NodeType.task,
      title: 'Stale',
      day: now,
      now: now,
    );
    final native = CanvasObject(
      id: 'sticky',
      type: CanvasObjectType.stickyNote,
      geometry: const CanvasGeometry(x: 200, y: 100, width: 240, height: 180),
      createdAt: now,
      updatedAt: now,
    );
    final initial = CanvasBoard.project(
      workspaceName: 'project:Alpha',
      nodes: <MindmapNode>[retained, stale],
      now: now,
    );
    final movedReference = initial
        .objectById('node:retained')!
        .copyWith(
          geometry: const CanvasGeometry(
            x: 500,
            y: 600,
            width: 340,
            height: 320,
          ),
        );
    final board = initial.copyWith(
      objects: <CanvasObject>[
        movedReference,
        initial.objectById('node:stale')!,
        native,
      ],
    );

    final reconciled = board.reconcileNodeReferences(<MindmapNode>[
      retained,
      added,
    ], now: now.add(const Duration(minutes: 1)));

    expect(reconciled.objectById('node:retained')!.geometry.x, 500);
    expect(reconciled.objectById('node:retained')!.geometry.y, 600);
    expect(reconciled.objectById('node:added')!.geometry.x, 70);
    expect(reconciled.objectById('node:added')!.geometry.y, 90);
    expect(reconciled.objectById('node:stale'), isNull);
    expect(reconciled.objectById(native.id), native);
  });

  test('project planning template creates grouped workflow columns', () {
    final now = DateTime(2026, 7, 28);
    final board = CanvasBoard.project(
      workspaceName: 'project:Alpha',
      nodes: const <MindmapNode>[],
      now: now,
    ).addProjectTemplate(CanvasProjectTemplate.projectPlan, now: now);

    final frames = board.objects
        .where((object) => object.type == CanvasObjectType.frame)
        .toList();
    final stickies = board.objects
        .where((object) => object.type == CanvasObjectType.stickyNote)
        .toList();

    expect(frames, hasLength(3));
    expect(stickies, hasLength(3));
    expect(
      frames.map((frame) => frame.payload['text']),
      containsAll(<String>['Backlog', 'In progress', 'Done']),
    );
    expect(
      stickies.every(
        (sticky) => frames.any((frame) => frame.id == sticky.parentFrameId),
      ),
      isTrue,
    );
  });

  test('every project template adds canvas objects', () {
    final now = DateTime(2026, 7, 28);

    for (final template in CanvasProjectTemplate.values) {
      final board = CanvasBoard.project(
        workspaceName: 'project:Alpha',
        nodes: const <MindmapNode>[],
        now: now,
      ).addProjectTemplate(template, now: now);

      expect(board.objects, isNotEmpty, reason: template.name);
    }
  });

  test('canvas object vote count is normalized and persisted', () {
    final now = DateTime(2026, 7, 28);
    final object = CanvasObject(
      id: 'shape',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 100, height: 80),
      payload: const <String, Object?>{'voteCount': -4},
      createdAt: now,
      updatedAt: now,
    );

    expect(object.voteCount, 0);
    final voted = object.withVoteCount(3, updatedAt: now);
    expect(voted.voteCount, 3);
    expect(CanvasObject.fromJson(voted.toJson()).voteCount, 3);
    expect(voted.withVoteCount(-1, updatedAt: now).voteCount, 0);
  });

  test('canvas comments preserve threads and resolved state', () {
    final now = DateTime(2026, 7, 28);
    final root = CanvasObjectComment(
      id: 'root',
      body: 'Review this section',
      authorName: 'Ari',
      createdAt: now,
    );
    final reply = CanvasObjectComment(
      id: 'reply',
      body: 'Looks good',
      authorName: 'Bima',
      createdAt: now,
      parentId: root.id,
    );
    final object = CanvasObject(
      id: 'shape',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 100, height: 80),
      createdAt: now,
      updatedAt: now,
    ).withComments(<CanvasObjectComment>[root, reply], updatedAt: now);

    expect(object.comments, hasLength(2));
    expect(object.comments.last.parentId, root.id);
    expect(object.openCommentCount, 1);
    final resolved = object.withComments(<CanvasObjectComment>[
      root.copyWith(isResolved: true),
      reply,
    ], updatedAt: now);
    expect(resolved.openCommentCount, 0);
    expect(CanvasObject.fromJson(resolved.toJson()).comments, hasLength(2));
  });

  test('canvas voting session enforces participant limits and lifecycle', () {
    var session = CanvasVotingSession().start(maxVotes: 2, anonymous: true);
    expect(session.isAnonymous, isTrue);
    expect(session.resultsRevealed, isFalse);

    session = session.changeVote(
      participantId: 'ari',
      objectId: 'idea-a',
      add: true,
    );
    session = session.changeVote(
      participantId: 'ari',
      objectId: 'idea-b',
      add: true,
    );
    final limited = session.changeVote(
      participantId: 'ari',
      objectId: 'idea-c',
      add: true,
    );
    final duplicate = session.changeVote(
      participantId: 'ari',
      objectId: 'idea-a',
      add: true,
    );
    session = session.changeVote(
      participantId: 'bima',
      objectId: 'idea-a',
      add: true,
    );

    expect(limited.votesUsedBy('ari'), 2);
    expect(limited.votesForObject('idea-c'), 0);
    expect(duplicate.votesUsedBy('ari'), 2);
    expect(session.remainingVotesFor('ari'), 0);
    expect(session.votesForObject('idea-a'), 2);
    expect(session.votesForObject('idea-b'), 1);

    final ended = session.end();
    expect(ended.isActive, isFalse);
    expect(ended.resultsConcealed, isTrue);
    final revealed = ended.revealResults();
    expect(revealed.resultsRevealed, isTrue);
    expect(revealed.allocations, ended.allocations);
    expect(
      ended.changeVote(participantId: 'bima', objectId: 'idea-b', add: true),
      ended,
    );

    final restored = CanvasVotingSession.fromJson(ended.toJson());
    expect(restored, ended);
    expect(restored.reset().allocations, isEmpty);
    expect(restored.reset().status, CanvasVotingStatus.inactive);
  });

  test('canvas board persists voting session', () {
    final now = DateTime(2026, 7, 28);
    final session = CanvasVotingSession()
        .start(maxVotes: 4)
        .changeVote(participantId: 'local', objectId: 'shape', add: true);
    final board = CanvasBoard(
      id: 'project:voting',
      kind: CanvasBoardKind.project,
      title: 'Voting',
      votingSession: session,
      createdAt: now,
      updatedAt: now,
    );

    expect(CanvasBoard.fromJson(board.toJson()), board);
  });

  test('column codec validates payload and preserves membership', () {
    final now = DateTime(2026, 8, 2);
    final column = CanvasObject(
      id: 'column',
      type: CanvasObjectType.column,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 320, height: 600),
      payload: const <String, Object?>{
        'title': '  Doing  ',
        'isCollapsed': false,
        'orderedChildIds': <String>['task'],
      },
      createdAt: now,
      updatedAt: now,
    );
    final child = CanvasObject(
      id: 'task',
      type: CanvasObjectType.nodeReference,
      geometry: const CanvasGeometry(x: 20, y: 80, width: 240, height: 120),
      parentColumnId: column.id,
      createdAt: now,
      updatedAt: now,
    );

    expect(column.columnTitle, 'Doing');
    expect(column.isColumnCollapsed, isFalse);
    expect(column.orderedColumnChildIds, <String>['task']);
    expect(CanvasObject.fromJson(column.toJson()), column);
    expect(CanvasObject.fromJson(child.toJson()).parentColumnId, column.id);
    expect(
      () => CanvasObject(
        id: 'invalid',
        type: CanvasObjectType.column,
        geometry: const CanvasGeometry(x: 0, y: 0, width: 1, height: 1),
        payload: const <String, Object?>{
          'title': '',
          'isCollapsed': 'no',
          'orderedChildIds': <String>['duplicate', 'duplicate'],
        },
        createdAt: now,
        updatedAt: now,
      ),
      throwsFormatException,
    );
  });

  test('column membership reconciles eligible children and order', () {
    final now = DateTime(2026, 8, 2);
    CanvasObject object(
      String id,
      CanvasObjectType type, {
      bool locked = false,
      String? parentColumnId,
      Map<String, Object?> payload = const <String, Object?>{},
    }) => CanvasObject(
      id: id,
      type: type,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 100, height: 80),
      isLocked: locked,
      parentColumnId: parentColumnId,
      payload: payload,
      createdAt: now,
      updatedAt: now,
    );
    final column = object(
      'column',
      CanvasObjectType.column,
      payload: const {
        'title': 'Todo',
        'isCollapsed': false,
        'orderedChildIds': <String>['stale'],
      },
    );
    final board = CanvasBoard(
      id: 'board',
      kind: CanvasBoardKind.project,
      title: 'Board',
      objects: <CanvasObject>[
        column,
        object('node', CanvasObjectType.nodeReference),
        object('sticky', CanvasObjectType.stickyNote),
        object('locked', CanvasObjectType.text, locked: true),
        object('connector', CanvasObjectType.connector),
        object('frame', CanvasObjectType.frame),
        object(
          'other-column',
          CanvasObjectType.column,
          payload: const {
            'title': 'Other',
            'isCollapsed': false,
            'orderedChildIds': <String>[],
          },
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    final reconciled = board.reconcileColumnMembership(
      columnId: 'column',
      orderedChildIds: const <String>['sticky', 'node'],
      now: now.add(const Duration(minutes: 1)),
    );

    expect(reconciled.objectById('sticky')!.parentColumnId, 'column');
    expect(reconciled.objectById('node')!.parentColumnId, 'column');
    expect(reconciled.objectById('column')!.orderedColumnChildIds, <String>[
      'sticky',
      'node',
    ]);
    for (final id in <String>['locked', 'connector', 'frame', 'other-column']) {
      expect(reconciled.objectById(id)!.parentColumnId, isNull);
    }
  });

  test(
    'column membership rejects duplicate, stale, multiple, self and cycle',
    () {
      final now = DateTime(2026, 8, 2);
      CanvasObject object(
        String id,
        CanvasObjectType type, {
        String? parentColumnId,
        Map<String, Object?> payload = const <String, Object?>{},
      }) => CanvasObject(
        id: id,
        type: type,
        geometry: const CanvasGeometry(x: 0, y: 0, width: 100, height: 80),
        parentColumnId: parentColumnId,
        payload: payload,
        createdAt: now,
        updatedAt: now,
      );
      final board = CanvasBoard(
        id: 'board',
        kind: CanvasBoardKind.project,
        title: 'Board',
        objects: <CanvasObject>[
          object(
            'column',
            CanvasObjectType.column,
            payload: const {
              'title': 'Column',
              'isCollapsed': false,
              'orderedChildIds': <String>[],
            },
          ),
          object(
            'other',
            CanvasObjectType.column,
            payload: const {
              'title': 'Other',
              'isCollapsed': false,
              'orderedChildIds': <String>['child'],
            },
          ),
          object('child', CanvasObjectType.shape, parentColumnId: 'other'),
        ],
        createdAt: now,
        updatedAt: now,
      );

      for (final ids in <List<String>>[
        <String>['child', 'child'],
        <String>['missing'],
        <String>['child'],
        <String>['column'],
        <String>['other'],
      ]) {
        expect(
          () => board.reconcileColumnMembership(
            columnId: 'column',
            orderedChildIds: ids,
            now: now,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('detaching column children preserves objects and clears membership', () {
    final now = DateTime(2026, 8, 2);
    final column = CanvasObject(
      id: 'column',
      type: CanvasObjectType.column,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 320, height: 600),
      payload: const <String, Object?>{
        'title': 'Done',
        'isCollapsed': false,
        'orderedChildIds': <String>['child'],
      },
      createdAt: now,
      updatedAt: now,
    );
    final child = CanvasObject(
      id: 'child',
      type: CanvasObjectType.image,
      geometry: const CanvasGeometry(x: 0, y: 0, width: 100, height: 80),
      parentColumnId: 'column',
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'board',
      kind: CanvasBoardKind.project,
      title: 'Board',
      objects: <CanvasObject>[column, child],
      createdAt: now,
      updatedAt: now,
    );

    final detached = board.detachColumnChildren('column', now: now);

    expect(detached.objects, hasLength(2));
    expect(detached.objectById('child')!.parentColumnId, isNull);
    expect(detached.objectById('column')!.orderedColumnChildIds, isEmpty);
  });

  test(
    'fromJson normalizes inconsistent column membership deterministically',
    () {
      final now = DateTime(2026, 8, 2).toIso8601String();
      Map<String, Object?> object(
        String id,
        String type, {
        String? parentColumnId,
        Map<String, Object?> payload = const <String, Object?>{},
        bool locked = false,
      }) => <String, Object?>{
        'id': id,
        'type': type,
        'geometry': <String, Object?>{
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 80,
        },
        'parentColumnId': ?parentColumnId,
        'isLocked': locked,
        'payload': payload,
        'createdAt': now,
        'updatedAt': now,
      };
      final board = CanvasBoard.fromJson(<String, Object?>{
        'id': 'broken',
        'kind': 'project',
        'title': 'Broken',
        'createdAt': now,
        'updatedAt': now,
        'objects': <Object?>[
          object(
            'a',
            'column',
            payload: <String, Object?>{
              'title': 'A',
              'isCollapsed': false,
              'orderedChildIds': <String>[
                'child',
                'missing',
                'child',
                'locked',
              ],
            },
          ),
          object(
            'b',
            'column',
            payload: <String, Object?>{
              'title': 'B',
              'isCollapsed': false,
              'orderedChildIds': <String>['child'],
            },
          ),
          object('child', 'shape', parentColumnId: 'b'),
          object('locked', 'shape', parentColumnId: 'a', locked: true),
          object('stale', 'shape', parentColumnId: 'missing'),
        ],
      });

      expect(board.objectById('a')!.orderedColumnChildIds, <String>['child']);
      expect(board.objectById('b')!.orderedColumnChildIds, isEmpty);
      expect(board.objectById('child')!.parentColumnId, 'a');
      expect(board.objectById('locked')!.parentColumnId, isNull);
      expect(board.objectById('stale')!.parentColumnId, isNull);
      expect(CanvasBoard.fromJson(board.toJson()), board);
    },
  );

  test('board reference and trash metadata survive round trip', () {
    final now = DateTime.utc(2026, 8, 2, 12);
    final trashedAt = DateTime.utc(2026, 8, 3, 12);
    final reference = CanvasObject(
      id: 'board-reference',
      type: CanvasObjectType.boardReference,
      geometry: const CanvasGeometry(x: 10, y: 20, width: 280, height: 180),
      referencedBoardId: 'child-board',
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'parent-board',
      kind: CanvasBoardKind.project,
      title: 'Parent',
      workspaceName: 'Work',
      parentBoardId: 'root-board',
      trashedAt: trashedAt,
      objects: <CanvasObject>[reference],
      createdAt: now,
      updatedAt: now,
    );

    final decoded = CanvasBoard.fromJson(board.toJson());

    expect(decoded, board);
    expect(decoded.parentBoardId, 'root-board');
    expect(decoded.trashedAt, trashedAt);
    expect(decoded.isTrashed, isTrue);
    expect(decoded.objects.single.referencedBoardId, 'child-board');
  });

  test('legacy board defaults nested metadata to null', () {
    final board = CanvasBoard.fromJson(<String, Object?>{
      'id': 'legacy',
      'kind': 'project',
      'title': 'Legacy',
      'createdAt': '2026-08-02T12:00:00.000Z',
      'updatedAt': '2026-08-02T12:00:00.000Z',
    });

    expect(board.parentBoardId, isNull);
    expect(board.trashedAt, isNull);
    expect(board.isTrashed, isFalse);
  });

  test('board reference rejects blank target id', () {
    final now = DateTime.utc(2026, 8, 2, 12);

    expect(
      () => CanvasObject(
        id: 'board-reference',
        type: CanvasObjectType.boardReference,
        geometry: const CanvasGeometry(x: 0, y: 0, width: 280, height: 180),
        referencedBoardId: '   ',
        createdAt: now,
        updatedAt: now,
      ),
      throwsFormatException,
    );
  });

  test('daily board rejects parent board relation', () {
    final now = DateTime.utc(2026, 8, 2, 12);

    expect(
      () => CanvasBoard(
        id: 'daily',
        kind: CanvasBoardKind.daily,
        title: 'Daily',
        parentBoardId: 'parent',
        createdAt: now,
        updatedAt: now,
      ),
      throwsFormatException,
    );
  });

  test('trash expires at exact thirty day boundary', () {
    final trashedAt = DateTime.utc(2026, 8, 2, 12);
    final board = CanvasBoard(
      id: 'board',
      kind: CanvasBoardKind.project,
      title: 'Board',
      trashedAt: trashedAt,
      createdAt: trashedAt,
      updatedAt: trashedAt,
    );

    expect(
      board.isTrashExpired(trashedAt.add(const Duration(days: 30))),
      isTrue,
    );
    expect(
      board.isTrashExpired(
        trashedAt
            .add(const Duration(days: 30))
            .subtract(const Duration(microseconds: 1)),
      ),
      isFalse,
    );
  });

  test('canvas board persists bounded activity history', () {
    final now = DateTime(2026, 7, 28, 12);
    var board = CanvasBoard(
      id: 'project:activity',
      kind: CanvasBoardKind.project,
      title: 'Activity',
      createdAt: now,
      updatedAt: now,
    );
    for (var index = 0; index < 505; index++) {
      board = board.recordActivity(
        type: CanvasActivityType.objectsUpdated,
        summary: 'Updated object $index',
        now: now.add(Duration(seconds: index)),
        objectIds: <String>['object-$index'],
      );
    }

    expect(board.activity, hasLength(500));
    expect(board.activity.first.summary, 'Updated object 504');
    expect(board.activity.last.summary, 'Updated object 5');
    expect(CanvasBoard.fromJson(board.toJson()), board);
  });
}

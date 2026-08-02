import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_assistant.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';

void main() {
  final now = DateTime(2026, 7, 28, 12);

  CanvasObject sticky(
    String id,
    String text,
    double x, {
    bool locked = false,
  }) => CanvasObject(
    id: id,
    type: CanvasObjectType.stickyNote,
    geometry: CanvasGeometry(x: x, y: 0, width: 240, height: 160),
    isLocked: locked,
    payload: <String, Object?>{'text': text},
    createdAt: now,
    updatedAt: now,
  );

  test('analyzes themes actions duplicates and layout deterministically', () {
    final locked = sticky(
      'locked',
      'Research customer onboarding',
      500,
      locked: true,
    );
    final board = CanvasBoard(
      id: 'project:alpha',
      kind: CanvasBoardKind.project,
      title: 'Alpha',
      objects: <CanvasObject>[
        sticky('research-1', 'Research customer onboarding', 0),
        sticky('research-copy', 'Research customer onboarding', 130),
        sticky('research-2', 'Research customer onboarding flow', 260),
        sticky('action', 'TODO: Interview five customers', 520),
        locked,
      ],
      createdAt: now,
      updatedAt: now,
    );

    final analysis = const CanvasAssistantAnalyzer().analyze(
      board: board,
      nodes: const [],
      now: now.add(const Duration(minutes: 1)),
    );

    expect(analysis.summary, contains('5 analyzed objects'));
    expect(analysis.actionItems, contains('Interview five customers'));
    expect(analysis.duplicates, isNotEmpty);
    expect(
      analysis.proposals.map((proposal) => proposal.kind),
      containsAll(<CanvasAssistantProposalKind>[
        CanvasAssistantProposalKind.cluster,
        CanvasAssistantProposalKind.actionItem,
        CanvasAssistantProposalKind.duplicate,
        CanvasAssistantProposalKind.layout,
      ]),
    );
    final layout = analysis.proposals.singleWhere(
      (proposal) => proposal.kind == CanvasAssistantProposalKind.layout,
    );
    expect(
      layout.updatedObjects.map((object) => object.id),
      isNot(contains(locked.id)),
    );
  });

  test('selection scope and preview apply preserve source until accepted', () {
    final board = CanvasBoard(
      id: 'project:selection',
      kind: CanvasBoardKind.project,
      title: 'Selection',
      objects: <CanvasObject>[
        sticky('selected', 'TODO: Ship release', 0),
        sticky('ignored', 'Unrelated note', 300),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final analysis = const CanvasAssistantAnalyzer().analyze(
      board: board,
      nodes: const [],
      now: now.add(const Duration(minutes: 1)),
      objectIds: const <String>{'selected'},
    );
    final action = analysis.proposals.singleWhere(
      (proposal) => proposal.kind == CanvasAssistantProposalKind.actionItem,
    );

    expect(analysis.analyzedObjectIds, <String>['selected']);
    expect(board.objects, hasLength(2));
    final applied = analysis.apply(<String>[
      action.id,
    ], now: now.add(const Duration(minutes: 2)));
    expect(applied.objects, hasLength(3));
    expect(board.objects, hasLength(2));
    expect(analysis.isCurrent(board), isTrue);
    expect(analysis.isCurrent(applied), isFalse);
  });

  test(
    'remote clusters replace only cluster proposals and retain snapshot',
    () {
      final board = CanvasBoard(
        id: 'project:remote-clusters',
        kind: CanvasBoardKind.project,
        title: 'Remote clusters',
        objects: <CanvasObject>[
          sticky('first', 'TODO: Research launch', 0),
          sticky('second', 'Research launch plan', 260),
        ],
        createdAt: now,
        updatedAt: now,
      );
      const analyzer = CanvasAssistantAnalyzer();
      final local = analyzer.analyze(board: board, nodes: const [], now: now);
      final replaced = analyzer.replaceClusters(
        analysis: local,
        clusters: const <CanvasAssistantCluster>[
          CanvasAssistantCluster(
            id: 'remote-1',
            label: 'Remote theme',
            objectIds: <String>['first', 'second', 'unknown'],
          ),
        ],
        now: now.add(const Duration(minutes: 1)),
      );

      expect(replaced.clusters.single.objectIds, <String>['first', 'second']);
      expect(
        replaced.proposals
            .where(
              (proposal) =>
                  proposal.kind == CanvasAssistantProposalKind.cluster,
            )
            .single
            .title,
        'Group Remote theme',
      );
      expect(
        replaced.proposals.where(
          (proposal) => proposal.kind == CanvasAssistantProposalKind.actionItem,
        ),
        isNotEmpty,
      );
      expect(replaced.isCurrent(board), isTrue);
      expect(replaced.apply(const <String>[], now: now).objects, board.objects);
    },
  );

  test('layout requires at least two movable objects', () {
    final board = CanvasBoard(
      id: 'project:locked-layout',
      kind: CanvasBoardKind.project,
      title: 'Locked layout',
      objects: <CanvasObject>[
        sticky('movable', 'Research launch', 0),
        sticky('locked', 'Research plan', 260, locked: true),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final analysis = const CanvasAssistantAnalyzer().analyze(
      board: board,
      nodes: const [],
      now: now,
    );

    expect(
      analysis.proposals.where(
        (proposal) => proposal.kind == CanvasAssistantProposalKind.layout,
      ),
      isEmpty,
    );
  });

  test('empty board returns safe empty analysis', () {
    final board = CanvasBoard(
      id: 'project:empty',
      kind: CanvasBoardKind.project,
      title: 'Empty',
      createdAt: now,
      updatedAt: now,
    );
    final analysis = const CanvasAssistantAnalyzer().analyze(
      board: board,
      nodes: const [],
      now: now,
    );
    expect(analysis.analyzedObjectIds, isEmpty);
    expect(analysis.proposals, isEmpty);
    expect(analysis.summary, contains('0 analyzed objects'));
  });

  test('extracts checklist and imperative action items', () {
    final board = CanvasBoard(
      id: 'project:actions',
      kind: CanvasBoardKind.project,
      title: 'Actions',
      objects: <CanvasObject>[
        sticky('actions', '- [ ] Prepare release notes\nSend launch email', 0),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final analysis = const CanvasAssistantAnalyzer().analyze(
      board: board,
      nodes: const [],
      now: now,
    );

    expect(
      analysis.actionItems,
      containsAll(<String>['Prepare release notes', 'Send launch email']),
    );
  });

  test('duplicate merge preserves comments and remaps voting allocation', () {
    final first = sticky('first', 'Launch customer survey', 0)
        .withComments(<CanvasObjectComment>[
          CanvasObjectComment(
            id: 'comment',
            body: 'Keep this',
            authorName: 'Ari',
            createdAt: now,
          ),
        ], updatedAt: now);
    final second = sticky('second', 'Launch customer survey', 260);
    final board = CanvasBoard(
      id: 'project:duplicate',
      kind: CanvasBoardKind.project,
      title: 'Duplicate',
      objects: <CanvasObject>[first, second],
      votingSession: CanvasVotingSession(
        status: CanvasVotingStatus.active,
        allocations: const <String, Set<String>>{
          'ari': <String>{'second'},
        },
      ),
      createdAt: now,
      updatedAt: now,
    );
    final analysis = const CanvasAssistantAnalyzer().analyze(
      board: board,
      nodes: const [],
      now: now.add(const Duration(minutes: 1)),
    );
    final merge = analysis.proposals.singleWhere(
      (proposal) => proposal.kind == CanvasAssistantProposalKind.duplicate,
    );
    final applied = analysis.apply(<String>[
      merge.id,
    ], now: now.add(const Duration(minutes: 2)));

    expect(applied.objectById('second'), isNull);
    expect(applied.objectById('first')!.comments, hasLength(1));
    expect(applied.votingSession.hasVote('ari', 'first'), isTrue);
    expect(applied.votingSession.hasVote('ari', 'second'), isFalse);
  });

  test('combined cluster and layout preserve connectors and grouping', () {
    final first = sticky('first', 'Customer launch research', 500);
    final second = sticky('second', 'Customer launch plan', 900);
    final connector = CanvasObject(
      id: 'connector',
      type: CanvasObjectType.connector,
      geometry: const CanvasGeometry(x: 700, y: 40, width: 200, height: 40),
      payload: const <String, Object?>{
        'startX': 0.0,
        'startY': 20.0,
        'endX': 200.0,
        'endY': 20.0,
      },
      createdAt: now,
      updatedAt: now,
    );
    final board = CanvasBoard(
      id: 'project:combined',
      kind: CanvasBoardKind.project,
      title: 'Combined',
      objects: <CanvasObject>[first, second, connector],
      createdAt: now,
      updatedAt: now,
    );
    final analysis = const CanvasAssistantAnalyzer().analyze(
      board: board,
      nodes: const [],
      now: now.add(const Duration(minutes: 1)),
    );
    final cluster = analysis.proposals.singleWhere(
      (proposal) => proposal.kind == CanvasAssistantProposalKind.cluster,
    );
    final layout = analysis.proposals.singleWhere(
      (proposal) => proposal.kind == CanvasAssistantProposalKind.layout,
    );
    final applied = analysis.apply(<String>[
      cluster.id,
      layout.id,
    ], now: now.add(const Duration(minutes: 2)));

    expect(applied.objectById('first')!.parentFrameId, isNotNull);
    expect(applied.objectById('first')!.geometry.x, isNot(first.geometry.x));
    expect(applied.objectById('connector'), connector);
    final moved = applied.objectById('first')!;
    final frame = applied.objectById(moved.parentFrameId!)!;
    expect(
      Rect.fromLTWH(
        frame.geometry.x,
        frame.geometry.y,
        frame.geometry.width,
        frame.geometry.height,
      ).contains(
        Offset(
          moved.geometry.x + moved.geometry.width / 2,
          moved.geometry.y + moved.geometry.height / 2,
        ),
      ),
      isTrue,
    );
    final movedSecond = applied.objectById('second')!;
    expect(
      moved.geometry.y + moved.geometry.height <= movedSecond.geometry.y ||
          movedSecond.geometry.y + movedSecond.geometry.height <=
              moved.geometry.y,
      isTrue,
    );
  });
}

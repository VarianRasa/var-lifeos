import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/canvas_command_controller.dart';
import 'package:var_app/features/mindmap/application/canvas_workshop_controller.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_workshop.dart';

void main() {
  test('workshop controller records lifecycle and summary', () {
    const controller = CanvasWorkshopController();
    final start = DateTime.utc(2026, 7, 28, 10);
    var board = CanvasBoard.project(
      workspaceName: 'project:test',
      nodes: const [],
      now: start,
    );
    board = controller.start(
      board: board,
      sessionId: 'session',
      hostUid: 'owner',
      durationMinutes: 15,
      now: start,
    );
    board = controller.join(board, 'editor', start);
    board = controller.react(board, '👍', start);
    board = controller.pause(board, start.add(const Duration(minutes: 2)));
    board = controller.resume(board, start.add(const Duration(minutes: 3)));
    board = controller.extend(board, 5, start.add(const Duration(minutes: 3)));
    board = controller.end(board, start.add(const Duration(minutes: 8)));

    expect(board.workshopSession.summary!.activeDurationSeconds, 420);
    expect(board.workshopSession.summary!.participantCount, 2);
    expect(board.workshopSession.summary!.reactionTotals, {'👍': 1});
    expect(board.activity.first.type, CanvasActivityType.workshopEnded);
    expect(
      board.activity.map((item) => item.type),
      containsAll(<CanvasActivityType>[
        CanvasActivityType.workshopStarted,
        CanvasActivityType.workshopPaused,
        CanvasActivityType.workshopResumed,
        CanvasActivityType.workshopEnded,
      ]),
    );
  });

  test('facilitated agenda waits then advances into voting', () {
    const controller = CanvasWorkshopController();
    final start = DateTime.utc(2026, 7, 29, 10);
    var board = CanvasBoard.project(
      workspaceName: 'project:agenda',
      nodes: const [],
      now: start,
    );
    final agenda = <CanvasWorkshopStage>[
      CanvasWorkshopStage(
        id: 'ideas',
        title: 'Ideas',
        type: CanvasWorkshopStageType.brainstorm,
        durationSeconds: 60,
      ),
      CanvasWorkshopStage(
        id: 'vote',
        title: 'Vote',
        type: CanvasWorkshopStageType.vote,
        durationSeconds: 60,
        maxVotesPerParticipant: 4,
      ),
    ];
    board = controller.startAgenda(
      board: board,
      sessionId: 'session',
      hostUid: 'owner',
      agenda: agenda,
      now: start,
    );
    final activityCount = board.activity.length;

    board = controller.maintain(board, start.add(const Duration(seconds: 61)));
    expect(board.workshopSession.awaitingAdvance, isTrue);
    expect(board.activity, hasLength(activityCount));

    board = controller.advanceStage(
      board,
      start.add(const Duration(seconds: 70)),
    );
    expect(board.workshopSession.activeStage?.id, 'vote');
    expect(board.votingSession.status, CanvasVotingStatus.active);
    expect(board.votingSession.maxVotesPerParticipant, 4);
    expect(board.activity.first.type, CanvasActivityType.workshopStageChanged);
  });

  test('reveal and contribution metadata remain local-first', () {
    const controller = CanvasWorkshopController();
    final start = DateTime.utc(2026, 7, 29, 10);
    var board = CanvasBoard.project(
      workspaceName: 'project:agenda',
      nodes: const [],
      now: start,
    );
    board = controller.startAgenda(
      board: board,
      sessionId: 'session',
      hostUid: 'owner',
      agenda: controller.agendaTemplate('brainstorm'),
      now: start,
    );
    board = controller.advanceStage(board, start);
    final object = controller.tagContribution(
      object: CanvasObject(
        id: 'idea',
        type: CanvasObjectType.stickyNote,
        geometry: const CanvasGeometry(x: 0, y: 0, width: 160, height: 100),
        createdAt: start,
        updatedAt: start,
      ),
      session: board.workshopSession,
      authorUid: 'editor',
      now: start,
    );
    expect(object.payload['workshopPrivate'], isTrue);
    expect(object.payload['workshopAuthorUid'], 'editor');

    board = controller.revealStage(board, start);
    expect(board.workshopSession.revealedStageIds, contains('ideas'));
    expect(board.activity.first.type, CanvasActivityType.workshopStageRevealed);
  });

  test(
    'late joiner stays isolated from private contributions until reveal',
    () {
      const controller = CanvasWorkshopController();
      final start = DateTime.utc(2026, 7, 29, 10);
      var board = CanvasBoard.project(
        workspaceName: 'project:agenda',
        nodes: const [],
        now: start,
      );
      board = controller.startAgenda(
        board: board,
        sessionId: 'session',
        hostUid: 'owner',
        agenda: controller.agendaTemplate('brainstorm'),
        now: start,
      );
      board = controller.advanceStage(board, start);
      final privateIdea = controller.tagContribution(
        object: CanvasObject(
          id: 'idea',
          type: CanvasObjectType.stickyNote,
          geometry: const CanvasGeometry(x: 0, y: 0, width: 160, height: 100),
          createdAt: start,
          updatedAt: start,
        ),
        session: board.workshopSession,
        authorUid: 'editor-a',
        now: start,
      );
      board = board.copyWith(objects: <CanvasObject>[privateIdea]);
      board = controller.join(
        board,
        'editor-late',
        start.add(const Duration(seconds: 30)),
      );

      expect(board.workshopSession.participantIds, contains('editor-late'));
      expect(
        board
            .visibleForWorkshop(
              session: board.workshopSession,
              viewerUid: 'editor-late',
              isHost: false,
            )
            .objects,
        isEmpty,
      );

      board = controller.revealStage(
        board,
        start.add(const Duration(seconds: 40)),
      );
      expect(
        board
            .visibleForWorkshop(
              session: board.workshopSession,
              viewerUid: 'editor-late',
              isHost: false,
            )
            .objects
            .single
            .id,
        'idea',
      );
    },
  );

  test('host reveal supports undo and redo through canvas command stack', () {
    const controller = CanvasWorkshopController();
    final start = DateTime.utc(2026, 7, 29, 10);
    var before = CanvasBoard.project(
      workspaceName: 'project:agenda',
      nodes: const [],
      now: start,
    );
    before = controller.startAgenda(
      board: before,
      sessionId: 'session',
      hostUid: 'owner',
      agenda: controller.agendaTemplate('brainstorm'),
      now: start,
    );
    before = controller.advanceStage(before, start);
    final after = controller.revealStage(before, start);
    final stack = CanvasCommandStack();

    final revealed = stack.execute(
      before,
      ReplaceCanvasBoardCommand(before: before, after: after),
    );
    expect(revealed.workshopSession.revealedStageIds, contains('ideas'));

    final hidden = stack.undo(revealed);
    expect(hidden.workshopSession.revealedStageIds, isEmpty);

    final restored = stack.redo(hidden);
    expect(restored.workshopSession.revealedStageIds, contains('ideas'));
  });

  test('agenda templates are deterministic and bounded', () {
    const controller = CanvasWorkshopController();
    for (final template in <String>[
      'brainstorm',
      'retrospective',
      'decision',
    ]) {
      final agenda = controller.agendaTemplate(template);
      expect(agenda, isNotEmpty);
      expect(agenda.length, lessThanOrEqualTo(12));
      expect(agenda.map((stage) => stage.id).toSet(), hasLength(agenda.length));
      expect(agenda.last.type, CanvasWorkshopStageType.review);
    }
  });

  test('facilitated summary reports stages authors ranking and clusters', () {
    const controller = CanvasWorkshopController();
    final start = DateTime.utc(2026, 7, 29, 10);
    final agenda = <CanvasWorkshopStage>[
      CanvasWorkshopStage(
        id: 'ideas',
        title: 'Ideas',
        type: CanvasWorkshopStageType.brainstorm,
        durationSeconds: 60,
      ),
    ];
    var board = CanvasBoard.project(
      workspaceName: 'project:summary',
      nodes: const [],
      now: start,
    );
    board = controller.startAgenda(
      board: board,
      sessionId: 'session',
      hostUid: 'owner',
      agenda: agenda,
      now: start,
    );
    final idea = controller.tagContribution(
      object: CanvasObject(
        id: 'idea',
        type: CanvasObjectType.stickyNote,
        geometry: const CanvasGeometry(x: 0, y: 0, width: 160, height: 100),
        createdAt: start,
        updatedAt: start,
      ),
      session: board.workshopSession,
      authorUid: 'editor',
      now: start,
    );
    final frame = CanvasObject(
      id: 'cluster',
      type: CanvasObjectType.frame,
      geometry: const CanvasGeometry(x: -20, y: -20, width: 240, height: 180),
      createdAt: start,
      updatedAt: start,
    );
    board = board.copyWith(
      objects: <CanvasObject>[idea, frame],
      votingSession: board.votingSession
          .start(maxVotes: 3)
          .changeVote(participantId: 'owner', objectId: idea.id, add: true),
    );
    board = controller.end(board, start.add(const Duration(seconds: 45)));

    final summary = board.workshopSession.summary!;
    expect(summary.stageContributionCounts, <String, int>{'ideas': 1});
    expect(summary.participantContributionCounts, <String, int>{'editor': 1});
    expect(summary.votingRanking, <String, int>{'idea': 1});
    expect(summary.clusterCount, 1);
    expect(summary.stageDurationSeconds['ideas'], 45);
  });
}

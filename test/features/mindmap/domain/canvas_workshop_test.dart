import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_workshop.dart';
import 'package:var_app/features/mindmap/domain/workshop_ai.dart';

void main() {
  final agenda = <CanvasWorkshopStage>[
    CanvasWorkshopStage(
      id: 'intro',
      title: 'Welcome',
      type: CanvasWorkshopStageType.intro,
      durationSeconds: 60,
    ),
    CanvasWorkshopStage(
      id: 'ideas',
      title: 'Silent ideas',
      type: CanvasWorkshopStageType.brainstorm,
      durationSeconds: 300,
    ),
    CanvasWorkshopStage(
      id: 'reveal',
      title: 'Reveal',
      type: CanvasWorkshopStageType.reveal,
      durationSeconds: 60,
    ),
    CanvasWorkshopStage(
      id: 'vote',
      title: 'Vote',
      type: CanvasWorkshopStageType.vote,
      durationSeconds: 120,
      maxVotesPerParticipant: 4,
    ),
  ];

  test('workshop timer survives pause resume extend and round trip', () {
    final start = DateTime(2026, 7, 28, 9);
    var session = CanvasWorkshopSession().start(
      sessionId: 'session-1',
      hostUid: 'owner',
      now: start,
      durationMinutes: 30,
      baselineObjectVersions: const <String, String>{'one': 'v1'},
    );

    expect(
      session.remainingSeconds(start.add(const Duration(minutes: 10))),
      1200,
    );
    session = session.pause(start.add(const Duration(minutes: 10)));
    expect(
      session.remainingSeconds(start.add(const Duration(minutes: 20))),
      1200,
    );
    session = session.resume(start.add(const Duration(minutes: 20))).extend(5);
    expect(
      session.remainingSeconds(start.add(const Duration(minutes: 25))),
      1200,
    );
    expect(CanvasWorkshopSession.fromJson(session.toJson()), session);
  });

  test('AI snapshot survives JSON and workshop session round trip', () {
    const snapshot = WorkshopAiSummarySnapshot(
      summary: 'Launch plan',
      themes: <String>['Scope'],
      decisions: <String>['Ship Friday'],
      actionItems: <String>['Run checks'],
      risks: <String>['Delay'],
      model: 'model',
      version: '1',
    );
    const summary = CanvasWorkshopSummary(
      activeDurationSeconds: 60,
      participantCount: 2,
      objectsAdded: 1,
      objectsUpdated: 0,
      objectsDeleted: 0,
      aiSummarySnapshot: snapshot,
    );
    final session = CanvasWorkshopSession(summary: summary);

    expect(WorkshopAiSummarySnapshot.fromJson(snapshot.toJson()), snapshot);
    expect(CanvasWorkshopSession.fromJson(session.toJson()), session);
  });

  test('workshop tracks participants reactions presenter and summary', () {
    final start = DateTime(2026, 7, 28, 9);
    var session = CanvasWorkshopSession().start(
      sessionId: 'session-1',
      hostUid: 'owner',
      now: start,
      durationMinutes: 15,
      baselineObjectVersions: const <String, String>{},
    );
    session = session
        .addParticipant('editor')
        .setPresenter('editor')
        .recordReaction('👍')
        .recordReaction('👍');
    const summary = CanvasWorkshopSummary(
      activeDurationSeconds: 600,
      participantCount: 2,
      objectsAdded: 3,
      objectsUpdated: 1,
      objectsDeleted: 1,
      reactionTotals: <String, int>{'👍': 2},
      votingWinnerObjectId: 'idea-1',
      votingWinnerVotes: 4,
      lastPresenterUid: 'editor',
    );
    session = session.end(
      now: start.add(const Duration(minutes: 10)),
      summary: summary,
    );

    expect(session.status, CanvasWorkshopStatus.ended);
    expect(session.participantIds, <String>{'owner', 'editor'});
    expect(session.reactionTotals['👍'], 2);
    expect(session.summary, summary);
    expect(CanvasWorkshopSession.fromJson(session.toJson()), session);
  });

  test('agenda waits for host confirmation and survives round trip', () {
    final start = DateTime.utc(2026, 7, 29, 9);
    var session = CanvasWorkshopSession().startAgenda(
      sessionId: 'agenda-1',
      hostUid: 'owner',
      now: start,
      agenda: agenda,
      baselineObjectVersions: const <String, String>{},
    );

    session = session.maintain(start.add(const Duration(seconds: 61)));
    expect(session.awaitingAdvance, isTrue);
    expect(session.activeStage?.id, 'intro');

    session = session.advanceStage(start.add(const Duration(seconds: 70)));
    expect(session.activeStage?.id, 'ideas');
    expect(session.completedStageIds, contains('intro'));
    expect(session.stageElapsedSeconds['intro'], 70);
    expect(CanvasWorkshopSession.fromJson(session.toJson()), session);
  });

  test('private contributions stay author-only until reveal', () {
    final start = DateTime.utc(2026, 7, 29, 9);
    var session = CanvasWorkshopSession().startAgenda(
      sessionId: 'agenda-1',
      hostUid: 'owner',
      now: start,
      agenda: agenda,
      baselineObjectVersions: const <String, String>{},
    );
    session = session.advanceStage(start);
    const payload = <String, Object?>{
      'workshopPrivate': true,
      'workshopStageId': 'ideas',
      'workshopAuthorUid': 'editor-a',
    };

    expect(
      isWorkshopObjectVisible(
        payload,
        session,
        viewerUid: 'editor-a',
        isHost: false,
      ),
      isTrue,
    );
    expect(
      isWorkshopObjectVisible(
        payload,
        session,
        viewerUid: 'editor-b',
        isHost: false,
      ),
      isFalse,
    );
    expect(
      isWorkshopObjectVisible(
        payload,
        session,
        viewerUid: 'owner',
        isHost: true,
      ),
      isTrue,
    );

    session = session.revealActiveStage();
    expect(
      isWorkshopObjectVisible(
        payload,
        session,
        viewerUid: 'editor-b',
        isHost: false,
      ),
      isTrue,
    );
  });

  test('stage policy gates tools deterministically', () {
    final start = DateTime.utc(2026, 7, 29, 9);
    var session = CanvasWorkshopSession().startAgenda(
      sessionId: 'agenda-1',
      hostUid: 'owner',
      now: start,
      agenda: agenda,
      baselineObjectVersions: const <String, String>{},
    );
    expect(canvasWorkshopPolicyFor(session, isHost: false).canCreate, isFalse);

    session = session.advanceStage(start);
    final brainstorm = canvasWorkshopPolicyFor(session, isHost: false);
    expect(brainstorm.canCreate, isTrue);
    expect(brainstorm.canEditOthers, isFalse);
    expect(brainstorm.contributionsPrivate, isTrue);

    session = session.advanceStage(start).advanceStage(start);
    final vote = canvasWorkshopPolicyFor(session, isHost: false);
    expect(vote.canVote, isTrue);
    expect(vote.canCreate, isFalse);
  });

  test('host and participant permissions follow every agenda stage', () {
    final start = DateTime.utc(2026, 7, 29, 9);
    var session = CanvasWorkshopSession().startAgenda(
      sessionId: 'agenda-1',
      hostUid: 'owner',
      now: start,
      agenda: agenda,
      baselineObjectVersions: const <String, String>{},
    );

    final introHost = canvasWorkshopPolicyFor(session, isHost: true);
    final introParticipant = canvasWorkshopPolicyFor(session, isHost: false);
    expect(introHost.canCreate, isFalse);
    expect(introHost.canEditOthers, isTrue);
    expect(introParticipant.canCreate, isFalse);
    expect(introParticipant.canVote, isFalse);

    session = session.advanceStage(start);
    final brainstormHost = canvasWorkshopPolicyFor(session, isHost: true);
    final brainstormParticipant = canvasWorkshopPolicyFor(
      session,
      isHost: false,
    );
    expect(brainstormHost.canCreate, isTrue);
    expect(brainstormHost.canEditOthers, isTrue);
    expect(brainstormParticipant.canCreate, isTrue);
    expect(brainstormParticipant.canEditOwn, isTrue);
    expect(brainstormParticipant.canEditOthers, isFalse);
    expect(brainstormParticipant.canVote, isFalse);

    session = session.advanceStage(start).advanceStage(start);
    final voteHost = canvasWorkshopPolicyFor(session, isHost: true);
    final voteParticipant = canvasWorkshopPolicyFor(session, isHost: false);
    expect(voteHost.canVote, isTrue);
    expect(voteParticipant.canVote, isTrue);
    expect(voteHost.canCreate, isFalse);
    expect(voteParticipant.canEditOwn, isFalse);
  });

  test('legacy workshop JSON remains agenda-free', () {
    final session = CanvasWorkshopSession.fromJson(const <String, Object?>{
      'status': 'running',
      'sessionId': 'legacy',
      'hostUid': 'owner',
      'targetDurationSeconds': 900,
    });
    expect(session.agenda, isEmpty);
    expect(session.activeStage, isNull);
    expect(canvasWorkshopPolicyFor(session, isHost: false).canCreate, isTrue);
  });
}

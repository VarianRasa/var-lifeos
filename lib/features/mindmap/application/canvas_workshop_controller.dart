import '../domain/canvas_board.dart';
import '../domain/canvas_workshop.dart';

final class CanvasWorkshopController {
  const CanvasWorkshopController();

  List<CanvasWorkshopStage> agendaTemplate(String template) =>
      switch (template) {
        'retrospective' => _retrospectiveAgenda(),
        'decision' => _decisionAgenda(),
        _ => _brainstormAgenda(),
      };

  CanvasBoard startAgenda({
    required CanvasBoard board,
    required String sessionId,
    required String hostUid,
    required List<CanvasWorkshopStage> agenda,
    required DateTime now,
  }) {
    final session = board.workshopSession.startAgenda(
      sessionId: sessionId,
      hostUid: hostUid,
      now: now,
      agenda: agenda,
      baselineObjectVersions: <String, String>{
        for (final object in board.objects)
          object.id: object.updatedAt.toUtc().toIso8601String(),
      },
    );
    return board
        .copyWith(workshopSession: session, updatedAt: now)
        .recordActivity(
          type: CanvasActivityType.workshopStarted,
          summary: 'Started ${agenda.length}-stage workshop',
          now: now,
        );
  }

  CanvasBoard maintain(CanvasBoard board, DateTime now) {
    final maintained = board.workshopSession.maintain(now);
    return identical(maintained, board.workshopSession)
        ? board
        : board.copyWith(workshopSession: maintained, updatedAt: now);
  }

  CanvasBoard advanceStage(CanvasBoard board, DateTime now) {
    final previous = board.workshopSession.activeStage;
    final session = board.workshopSession.advanceStage(now);
    if (identical(session, board.workshopSession)) return board;
    var next = board.copyWith(workshopSession: session, updatedAt: now);
    final active = session.activeStage;
    if (active?.type == CanvasWorkshopStageType.vote) {
      next = next.copyWith(
        votingSession: next.votingSession.start(
          maxVotes: active!.maxVotesPerParticipant,
        ),
      );
    } else if (board.votingSession.isActive) {
      next = next.copyWith(votingSession: board.votingSession.end());
    }
    return next.recordActivity(
      type: CanvasActivityType.workshopStageChanged,
      summary:
          'Advanced from ${previous?.title ?? 'workshop'} to ${active?.title ?? 'complete'}',
      now: now,
    );
  }

  CanvasBoard restartStage(CanvasBoard board, DateTime now) => board
      .copyWith(
        workshopSession: board.workshopSession.restartStage(now),
        updatedAt: now,
      )
      .recordActivity(
        type: CanvasActivityType.workshopStageChanged,
        summary:
            'Restarted ${board.workshopSession.activeStage?.title ?? 'stage'}',
        now: now,
      );

  CanvasBoard skipStage(CanvasBoard board, DateTime now) =>
      advanceStage(board, now);

  CanvasBoard revealStage(CanvasBoard board, DateTime now) {
    final stage = board.workshopSession.activeStage;
    if (stage == null) return board;
    return board
        .copyWith(
          workshopSession: board.workshopSession.revealActiveStage(),
          updatedAt: now,
        )
        .recordActivity(
          type: CanvasActivityType.workshopStageRevealed,
          summary: 'Revealed ${stage.title}',
          now: now,
        );
  }

  CanvasObject tagContribution({
    required CanvasObject object,
    required CanvasWorkshopSession session,
    required String authorUid,
    required DateTime now,
  }) {
    final stage = session.activeStage;
    if (!session.isActive || stage == null) return object;
    return object.copyWith(
      payload: <String, Object?>{
        ...object.payload,
        'workshopSessionId': session.sessionId,
        'workshopStageId': stage.id,
        'workshopAuthorUid': authorUid,
        'workshopPrivate': stage.contributionsPrivate,
      },
      updatedAt: now,
    );
  }

  CanvasBoard start({
    required CanvasBoard board,
    required String sessionId,
    required String hostUid,
    required int durationMinutes,
    required DateTime now,
  }) {
    final session = board.workshopSession.start(
      sessionId: sessionId,
      hostUid: hostUid,
      now: now,
      durationMinutes: durationMinutes,
      baselineObjectVersions: <String, String>{
        for (final object in board.objects)
          object.id: object.updatedAt.toUtc().toIso8601String(),
      },
    );
    return board
        .copyWith(workshopSession: session, updatedAt: now)
        .recordActivity(
          type: CanvasActivityType.workshopStarted,
          summary: 'Started $durationMinutes minute workshop',
          now: now,
        );
  }

  CanvasBoard pause(CanvasBoard board, DateTime now) => board
      .copyWith(
        workshopSession: board.workshopSession.pause(now),
        updatedAt: now,
      )
      .recordActivity(
        type: CanvasActivityType.workshopPaused,
        summary: 'Paused workshop',
        now: now,
      );

  CanvasBoard resume(CanvasBoard board, DateTime now) => board
      .copyWith(
        workshopSession: board.workshopSession.resume(now),
        updatedAt: now,
      )
      .recordActivity(
        type: CanvasActivityType.workshopResumed,
        summary: 'Resumed workshop',
        now: now,
      );

  CanvasBoard extend(CanvasBoard board, int minutes, DateTime now) =>
      board.copyWith(
        workshopSession: board.workshopSession.extend(minutes),
        updatedAt: now,
      );

  CanvasBoard join(CanvasBoard board, String uid, DateTime now) =>
      board.copyWith(
        workshopSession: board.workshopSession.addParticipant(uid),
        updatedAt: now,
      );

  CanvasBoard setPresenter(CanvasBoard board, String? uid, DateTime now) =>
      board
          .copyWith(
            workshopSession: board.workshopSession.setPresenter(uid),
            updatedAt: now,
          )
          .recordActivity(
            type: CanvasActivityType.presenterChanged,
            summary: uid == null ? 'Cleared presenter' : 'Changed presenter',
            now: now,
          );

  CanvasBoard react(CanvasBoard board, String emoji, DateTime now) =>
      board.copyWith(
        workshopSession: board.workshopSession.recordReaction(emoji),
        updatedAt: now,
      );

  CanvasBoard end(CanvasBoard board, DateTime now) {
    final session = board.workshopSession;
    final current = <String, CanvasObject>{
      for (final object in board.objects) object.id: object,
    };
    final added = current.keys
        .where((id) => !session.baselineObjectVersions.containsKey(id))
        .length;
    final deleted = session.baselineObjectVersions.keys
        .where((id) => !current.containsKey(id))
        .length;
    final updated = current.entries
        .where(
          (entry) =>
              session.baselineObjectVersions[entry.key] != null &&
              session.baselineObjectVersions[entry.key] !=
                  entry.value.updatedAt.toUtc().toIso8601String(),
        )
        .length;
    final ranked = board.objects.toList()
      ..sort(
        (left, right) => board.votingSession
            .votesForObject(right.id)
            .compareTo(board.votingSession.votesForObject(left.id)),
      );
    final winner = ranked.isEmpty ? null : ranked.first;
    final winnerVotes = winner == null
        ? 0
        : board.votingSession.votesForObject(winner.id);
    final summary = CanvasWorkshopSummary(
      activeDurationSeconds: session.activeElapsedSeconds(now),
      participantCount: session.participantIds.length,
      objectsAdded: added,
      objectsUpdated: updated,
      objectsDeleted: deleted,
      reactionTotals: session.reactionTotals,
      votingWinnerObjectId: winnerVotes > 0 ? winner?.id : null,
      votingWinnerVotes: winnerVotes,
      lastPresenterUid: session.presenterUid,
      stageDurationSeconds: <String, int>{
        ...session.stageElapsedSeconds,
        if (session.activeStage case final stage?)
          stage.id: session.activeStageElapsedSeconds(now),
      },
      stageContributionCounts: _contributionCounts(
        board.objects,
        'workshopStageId',
      ),
      participantContributionCounts: _contributionCounts(
        board.objects,
        'workshopAuthorUid',
      ),
      completedStageIds: session.completedStageIds,
      votingRanking: <String, int>{
        for (final object in ranked)
          if (board.votingSession.votesForObject(object.id) > 0)
            object.id: board.votingSession.votesForObject(object.id),
      },
      clusterCount: board.objects
          .where((object) => object.type == CanvasObjectType.frame)
          .length,
    );
    return board
        .copyWith(
          workshopSession: session.end(now: now, summary: summary),
          updatedAt: now,
        )
        .recordActivity(
          type: CanvasActivityType.workshopEnded,
          summary:
              'Ended workshop with ${session.participantIds.length} participants',
          now: now,
        );
  }

  Map<String, int> _contributionCounts(
    Iterable<CanvasObject> objects,
    String payloadKey,
  ) {
    final counts = <String, int>{};
    for (final object in objects) {
      final value = object.payload[payloadKey];
      if (value is String && value.isNotEmpty) {
        counts[value] = (counts[value] ?? 0) + 1;
      }
    }
    return counts;
  }
}

List<CanvasWorkshopStage> _brainstormAgenda() => <CanvasWorkshopStage>[
  _stage('intro', 'Welcome', CanvasWorkshopStageType.intro, 60),
  _stage('ideas', 'Silent brainstorm', CanvasWorkshopStageType.brainstorm, 300),
  _stage('reveal', 'Reveal ideas', CanvasWorkshopStageType.reveal, 120),
  _stage('cluster', 'Cluster ideas', CanvasWorkshopStageType.cluster, 300),
  _stage('vote', 'Vote', CanvasWorkshopStageType.vote, 180),
  _stage('review', 'Review outcomes', CanvasWorkshopStageType.review, 180),
];

List<CanvasWorkshopStage> _retrospectiveAgenda() => <CanvasWorkshopStage>[
  _stage('intro', 'Set the context', CanvasWorkshopStageType.intro, 120),
  _stage('ideas', 'Silent reflection', CanvasWorkshopStageType.brainstorm, 300),
  _stage('reveal', 'Reveal reflections', CanvasWorkshopStageType.reveal, 120),
  _stage('cluster', 'Group themes', CanvasWorkshopStageType.cluster, 300),
  _stage('vote', 'Vote priorities', CanvasWorkshopStageType.vote, 180),
  _stage('review', 'Agree next actions', CanvasWorkshopStageType.review, 180),
];

List<CanvasWorkshopStage> _decisionAgenda() => <CanvasWorkshopStage>[
  _stage('intro', 'Decision brief', CanvasWorkshopStageType.intro, 120),
  _stage(
    'options',
    'Generate options',
    CanvasWorkshopStageType.brainstorm,
    300,
  ),
  _stage('reveal', 'Reveal options', CanvasWorkshopStageType.reveal, 120),
  CanvasWorkshopStage(
    id: 'vote',
    title: 'Vote options',
    type: CanvasWorkshopStageType.vote,
    durationSeconds: 180,
    maxVotesPerParticipant: 3,
  ),
  _stage('review', 'Confirm decision', CanvasWorkshopStageType.review, 180),
];

CanvasWorkshopStage _stage(
  String id,
  String title,
  CanvasWorkshopStageType type,
  int durationSeconds,
) => CanvasWorkshopStage(
  id: id,
  title: title,
  type: type,
  durationSeconds: durationSeconds,
);

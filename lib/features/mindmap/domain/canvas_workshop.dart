import 'package:collection/collection.dart';

import 'workshop_ai.dart';

enum CanvasWorkshopStatus { inactive, running, paused, ended }

enum CanvasWorkshopStageType {
  intro,
  brainstorm,
  reveal,
  cluster,
  vote,
  review,
}

final class CanvasWorkshopStage {
  CanvasWorkshopStage({
    required this.id,
    required this.title,
    required this.type,
    required int durationSeconds,
    this.instructions = '',
    int maxVotesPerParticipant = 3,
  }) : durationSeconds = durationSeconds.clamp(0, 7200),
       maxVotesPerParticipant = maxVotesPerParticipant.clamp(1, 10) {
    if (id.trim().isEmpty || title.trim().isEmpty) {
      throw const FormatException('Invalid workshop stage.');
    }
  }

  factory CanvasWorkshopStage.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    return CanvasWorkshopStage(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: CanvasWorkshopStageType.values.firstWhere(
        (candidate) => candidate.name == json['type'],
        orElse: () => CanvasWorkshopStageType.intro,
      ),
      durationSeconds: _nonNegativeInt(json['durationSeconds']),
      instructions: json['instructions'] as String? ?? '',
      maxVotesPerParticipant: _nonNegativeInt(
        json['maxVotesPerParticipant'],
      ).clamp(1, 10),
    );
  }

  final String id;
  final String title;
  final CanvasWorkshopStageType type;
  final int durationSeconds;
  final String instructions;
  final int maxVotesPerParticipant;

  bool get contributionsPrivate => type == CanvasWorkshopStageType.brainstorm;
  bool get boardReadOnly => switch (type) {
    CanvasWorkshopStageType.intro ||
    CanvasWorkshopStageType.reveal ||
    CanvasWorkshopStageType.vote ||
    CanvasWorkshopStageType.review => true,
    CanvasWorkshopStageType.brainstorm ||
    CanvasWorkshopStageType.cluster => false,
  };
  bool get votingEnabled => type == CanvasWorkshopStageType.vote;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'type': type.name,
    'durationSeconds': durationSeconds,
    'instructions': instructions,
    'maxVotesPerParticipant': maxVotesPerParticipant,
  };

  @override
  bool operator ==(Object other) =>
      other is CanvasWorkshopStage &&
      other.id == id &&
      other.title == title &&
      other.type == type &&
      other.durationSeconds == durationSeconds &&
      other.instructions == instructions &&
      other.maxVotesPerParticipant == maxVotesPerParticipant;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    type,
    durationSeconds,
    instructions,
    maxVotesPerParticipant,
  );
}

final class CanvasWorkshopPolicy {
  const CanvasWorkshopPolicy({
    required this.canCreate,
    required this.canEditOwn,
    required this.canEditOthers,
    required this.canMoveAndGroup,
    required this.canVote,
    required this.contributionsPrivate,
  });

  const CanvasWorkshopPolicy.open()
    : canCreate = true,
      canEditOwn = true,
      canEditOthers = true,
      canMoveAndGroup = true,
      canVote = true,
      contributionsPrivate = false;

  final bool canCreate;
  final bool canEditOwn;
  final bool canEditOthers;
  final bool canMoveAndGroup;
  final bool canVote;
  final bool contributionsPrivate;
}

CanvasWorkshopPolicy canvasWorkshopPolicyFor(
  CanvasWorkshopSession session, {
  required bool isHost,
}) {
  final stage = session.activeStage;
  if (!session.isActive || stage == null) {
    return const CanvasWorkshopPolicy.open();
  }
  if (isHost) {
    return CanvasWorkshopPolicy(
      canCreate: !stage.boardReadOnly,
      canEditOwn: true,
      canEditOthers: true,
      canMoveAndGroup: stage.type == CanvasWorkshopStageType.cluster,
      canVote: stage.votingEnabled,
      contributionsPrivate: stage.contributionsPrivate,
    );
  }
  return switch (stage.type) {
    CanvasWorkshopStageType.brainstorm => const CanvasWorkshopPolicy(
      canCreate: true,
      canEditOwn: true,
      canEditOthers: false,
      canMoveAndGroup: false,
      canVote: false,
      contributionsPrivate: true,
    ),
    CanvasWorkshopStageType.cluster => const CanvasWorkshopPolicy(
      canCreate: false,
      canEditOwn: false,
      canEditOthers: false,
      canMoveAndGroup: true,
      canVote: false,
      contributionsPrivate: false,
    ),
    CanvasWorkshopStageType.vote => const CanvasWorkshopPolicy(
      canCreate: false,
      canEditOwn: false,
      canEditOthers: false,
      canMoveAndGroup: false,
      canVote: true,
      contributionsPrivate: false,
    ),
    _ => const CanvasWorkshopPolicy(
      canCreate: false,
      canEditOwn: false,
      canEditOthers: false,
      canMoveAndGroup: false,
      canVote: false,
      contributionsPrivate: false,
    ),
  };
}

bool isWorkshopObjectVisible(
  Map<String, Object?> payload,
  CanvasWorkshopSession session, {
  required String viewerUid,
  required bool isHost,
}) {
  if (payload['workshopPrivate'] != true) return true;
  final stageId = payload['workshopStageId'];
  if (stageId is String && session.revealedStageIds.contains(stageId)) {
    return true;
  }
  return isHost || payload['workshopAuthorUid'] == viewerUid;
}

final class CanvasWorkshopSummary {
  const CanvasWorkshopSummary({
    required this.activeDurationSeconds,
    required this.participantCount,
    required this.objectsAdded,
    required this.objectsUpdated,
    required this.objectsDeleted,
    this.reactionTotals = const <String, int>{},
    this.votingWinnerObjectId,
    this.votingWinnerVotes = 0,
    this.lastPresenterUid,
    this.stageDurationSeconds = const <String, int>{},
    this.stageContributionCounts = const <String, int>{},
    this.participantContributionCounts = const <String, int>{},
    this.completedStageIds = const <String>{},
    this.votingRanking = const <String, int>{},
    this.clusterCount = 0,
    this.aiSummarySnapshot,
  });

  factory CanvasWorkshopSummary.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    final reactions = json['reactionTotals'];
    final stageDurations = json['stageDurationSeconds'];
    final stageContributions = json['stageContributionCounts'];
    final participantContributions = json['participantContributionCounts'];
    final completedStages = json['completedStageIds'];
    final votingRanking = json['votingRanking'];
    return CanvasWorkshopSummary(
      activeDurationSeconds: _nonNegativeInt(json['activeDurationSeconds']),
      participantCount: _nonNegativeInt(json['participantCount']),
      objectsAdded: _nonNegativeInt(json['objectsAdded']),
      objectsUpdated: _nonNegativeInt(json['objectsUpdated']),
      objectsDeleted: _nonNegativeInt(json['objectsDeleted']),
      reactionTotals: reactions is Map
          ? <String, int>{
              for (final entry in reactions.entries)
                if (entry.key is String && entry.value is num)
                  entry.key as String: (entry.value! as num).toInt().clamp(
                    0,
                    999999,
                  ),
            }
          : const <String, int>{},
      votingWinnerObjectId: json['votingWinnerObjectId'] as String?,
      votingWinnerVotes: _nonNegativeInt(json['votingWinnerVotes']),
      lastPresenterUid: json['lastPresenterUid'] as String?,
      stageDurationSeconds: _intMap(stageDurations),
      stageContributionCounts: _intMap(stageContributions),
      participantContributionCounts: _intMap(participantContributions),
      completedStageIds: completedStages is List
          ? completedStages.whereType<String>().toSet()
          : const <String>{},
      votingRanking: _intMap(votingRanking),
      clusterCount: _nonNegativeInt(json['clusterCount']),
      aiSummarySnapshot: json['aiSummarySnapshot'] == null
          ? null
          : WorkshopAiSummarySnapshot.fromJson(json['aiSummarySnapshot']),
    );
  }

  final int activeDurationSeconds;
  final int participantCount;
  final int objectsAdded;
  final int objectsUpdated;
  final int objectsDeleted;
  final Map<String, int> reactionTotals;
  final String? votingWinnerObjectId;
  final int votingWinnerVotes;
  final String? lastPresenterUid;
  final Map<String, int> stageDurationSeconds;
  final Map<String, int> stageContributionCounts;
  final Map<String, int> participantContributionCounts;
  final Set<String> completedStageIds;
  final Map<String, int> votingRanking;
  final int clusterCount;
  final WorkshopAiSummarySnapshot? aiSummarySnapshot;

  CanvasWorkshopSummary withAiSummary(WorkshopAiSummarySnapshot snapshot) =>
      CanvasWorkshopSummary(
        activeDurationSeconds: activeDurationSeconds,
        participantCount: participantCount,
        objectsAdded: objectsAdded,
        objectsUpdated: objectsUpdated,
        objectsDeleted: objectsDeleted,
        reactionTotals: reactionTotals,
        votingWinnerObjectId: votingWinnerObjectId,
        votingWinnerVotes: votingWinnerVotes,
        lastPresenterUid: lastPresenterUid,
        stageDurationSeconds: stageDurationSeconds,
        stageContributionCounts: stageContributionCounts,
        participantContributionCounts: participantContributionCounts,
        completedStageIds: completedStageIds,
        votingRanking: votingRanking,
        clusterCount: clusterCount,
        aiSummarySnapshot: snapshot,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'activeDurationSeconds': activeDurationSeconds,
    'participantCount': participantCount,
    'objectsAdded': objectsAdded,
    'objectsUpdated': objectsUpdated,
    'objectsDeleted': objectsDeleted,
    'reactionTotals': reactionTotals,
    if (votingWinnerObjectId != null)
      'votingWinnerObjectId': votingWinnerObjectId,
    'votingWinnerVotes': votingWinnerVotes,
    if (lastPresenterUid != null) 'lastPresenterUid': lastPresenterUid,
    'stageDurationSeconds': stageDurationSeconds,
    'stageContributionCounts': stageContributionCounts,
    'participantContributionCounts': participantContributionCounts,
    'completedStageIds': completedStageIds.toList()..sort(),
    'votingRanking': votingRanking,
    'clusterCount': clusterCount,
    if (aiSummarySnapshot != null)
      'aiSummarySnapshot': aiSummarySnapshot!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is CanvasWorkshopSummary &&
      other.activeDurationSeconds == activeDurationSeconds &&
      other.participantCount == participantCount &&
      other.objectsAdded == objectsAdded &&
      other.objectsUpdated == objectsUpdated &&
      other.objectsDeleted == objectsDeleted &&
      const MapEquality<String, int>().equals(
        other.reactionTotals,
        reactionTotals,
      ) &&
      other.votingWinnerObjectId == votingWinnerObjectId &&
      other.votingWinnerVotes == votingWinnerVotes &&
      other.lastPresenterUid == lastPresenterUid &&
      const MapEquality<String, int>().equals(
        other.stageDurationSeconds,
        stageDurationSeconds,
      ) &&
      const MapEquality<String, int>().equals(
        other.stageContributionCounts,
        stageContributionCounts,
      ) &&
      const MapEquality<String, int>().equals(
        other.participantContributionCounts,
        participantContributionCounts,
      ) &&
      const SetEquality<String>().equals(
        other.completedStageIds,
        completedStageIds,
      ) &&
      const MapEquality<String, int>().equals(
        other.votingRanking,
        votingRanking,
      ) &&
      other.clusterCount == clusterCount &&
      other.aiSummarySnapshot == aiSummarySnapshot;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    activeDurationSeconds,
    participantCount,
    objectsAdded,
    objectsUpdated,
    objectsDeleted,
    const MapEquality<String, int>().hash(reactionTotals),
    votingWinnerObjectId,
    votingWinnerVotes,
    lastPresenterUid,
    const MapEquality<String, int>().hash(stageDurationSeconds),
    const MapEquality<String, int>().hash(stageContributionCounts),
    const MapEquality<String, int>().hash(participantContributionCounts),
    const SetEquality<String>().hash(completedStageIds),
    const MapEquality<String, int>().hash(votingRanking),
    clusterCount,
    aiSummarySnapshot,
  ]);
}

final class CanvasWorkshopSession {
  CanvasWorkshopSession({
    this.status = CanvasWorkshopStatus.inactive,
    this.sessionId,
    this.hostUid,
    this.presenterUid,
    this.startedAt,
    this.pausedAt,
    this.endedAt,
    int targetDurationSeconds = 0,
    int accumulatedPauseSeconds = 0,
    Set<String> participantIds = const <String>{},
    Map<String, String> baselineObjectVersions = const <String, String>{},
    Map<String, int> reactionTotals = const <String, int>{},
    List<CanvasWorkshopStage> agenda = const <CanvasWorkshopStage>[],
    this.activeStageIndex = 0,
    this.stageStartedAt,
    int stageAccumulatedPauseSeconds = 0,
    this.awaitingAdvance = false,
    Set<String> revealedStageIds = const <String>{},
    Set<String> completedStageIds = const <String>{},
    Map<String, int> stageElapsedSeconds = const <String, int>{},
    this.summary,
  }) : targetDurationSeconds = targetDurationSeconds.clamp(0, 43200),
       accumulatedPauseSeconds = accumulatedPauseSeconds.clamp(0, 43200),
       participantIds = Set<String>.unmodifiable(
         participantIds.where((id) => id.isNotEmpty),
       ),
       baselineObjectVersions = Map<String, String>.unmodifiable(
         baselineObjectVersions,
       ),
       reactionTotals = Map<String, int>.unmodifiable(
         reactionTotals.map(
           (emoji, count) => MapEntry(emoji, count.clamp(0, 999999)),
         ),
       ),
       agenda = List<CanvasWorkshopStage>.unmodifiable(agenda),
       stageAccumulatedPauseSeconds = stageAccumulatedPauseSeconds.clamp(
         0,
         7200,
       ),
       revealedStageIds = Set<String>.unmodifiable(revealedStageIds),
       completedStageIds = Set<String>.unmodifiable(completedStageIds),
       stageElapsedSeconds = Map<String, int>.unmodifiable(
         stageElapsedSeconds.map(
           (id, seconds) => MapEntry(id, seconds.clamp(0, 7200)),
         ),
       ) {
    if (agenda.length > 12 ||
        agenda.map((stage) => stage.id).toSet().length != agenda.length) {
      throw const FormatException('Invalid workshop agenda.');
    }
  }

  factory CanvasWorkshopSession.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    final participants = json['participantIds'];
    final baseline = json['baselineObjectVersions'];
    final reactions = json['reactionTotals'];
    final rawAgenda = json['agenda'];
    final revealedStages = json['revealedStageIds'];
    final completedStages = json['completedStageIds'];
    final elapsedStages = json['stageElapsedSeconds'];
    return CanvasWorkshopSession(
      status: CanvasWorkshopStatus.values.firstWhere(
        (candidate) => candidate.name == json['status'],
        orElse: () => CanvasWorkshopStatus.inactive,
      ),
      sessionId: json['sessionId'] as String?,
      hostUid: json['hostUid'] as String?,
      presenterUid: json['presenterUid'] as String?,
      startedAt: _optionalDateTime(json['startedAt']),
      pausedAt: _optionalDateTime(json['pausedAt']),
      endedAt: _optionalDateTime(json['endedAt']),
      targetDurationSeconds: _nonNegativeInt(json['targetDurationSeconds']),
      accumulatedPauseSeconds: _nonNegativeInt(json['accumulatedPauseSeconds']),
      participantIds: participants is List
          ? participants.whereType<String>().toSet()
          : const <String>{},
      baselineObjectVersions: baseline is Map
          ? <String, String>{
              for (final entry in baseline.entries)
                if (entry.key is String && entry.value is String)
                  entry.key as String: entry.value! as String,
            }
          : const <String, String>{},
      reactionTotals: reactions is Map
          ? <String, int>{
              for (final entry in reactions.entries)
                if (entry.key is String && entry.value is num)
                  entry.key as String: (entry.value! as num).toInt(),
            }
          : const <String, int>{},
      agenda: rawAgenda is List
          ? <CanvasWorkshopStage>[
              for (final value in rawAgenda)
                if (value is Map)
                  CanvasWorkshopStage.fromJson(
                    Map<String, Object?>.from(value),
                  ),
            ]
          : const <CanvasWorkshopStage>[],
      activeStageIndex: _nonNegativeInt(json['activeStageIndex']),
      stageStartedAt: _optionalDateTime(json['stageStartedAt']),
      stageAccumulatedPauseSeconds: _nonNegativeInt(
        json['stageAccumulatedPauseSeconds'],
      ),
      awaitingAdvance: json['awaitingAdvance'] as bool? ?? false,
      revealedStageIds: revealedStages is List
          ? revealedStages.whereType<String>().toSet()
          : const <String>{},
      completedStageIds: completedStages is List
          ? completedStages.whereType<String>().toSet()
          : const <String>{},
      stageElapsedSeconds: _intMap(elapsedStages),
      summary: json['summary'] == null
          ? null
          : CanvasWorkshopSummary.fromJson(json['summary']),
    );
  }

  final CanvasWorkshopStatus status;
  final String? sessionId;
  final String? hostUid;
  final String? presenterUid;
  final DateTime? startedAt;
  final DateTime? pausedAt;
  final DateTime? endedAt;
  final int targetDurationSeconds;
  final int accumulatedPauseSeconds;
  final Set<String> participantIds;
  final Map<String, String> baselineObjectVersions;
  final Map<String, int> reactionTotals;
  final List<CanvasWorkshopStage> agenda;
  final int activeStageIndex;
  final DateTime? stageStartedAt;
  final int stageAccumulatedPauseSeconds;
  final bool awaitingAdvance;
  final Set<String> revealedStageIds;
  final Set<String> completedStageIds;
  final Map<String, int> stageElapsedSeconds;
  final CanvasWorkshopSummary? summary;

  bool get isActive =>
      status == CanvasWorkshopStatus.running ||
      status == CanvasWorkshopStatus.paused;

  CanvasWorkshopStage? get activeStage =>
      activeStageIndex < agenda.length ? agenda[activeStageIndex] : null;

  bool get hasAgenda => agenda.isNotEmpty;

  bool get isLastStage =>
      agenda.isNotEmpty && activeStageIndex == agenda.length - 1;

  int activeElapsedSeconds(DateTime now) {
    final start = startedAt;
    if (start == null) return 0;
    final endpoint = endedAt ?? pausedAt ?? now;
    return (endpoint.difference(start).inSeconds - accumulatedPauseSeconds)
        .clamp(0, 43200);
  }

  int remainingSeconds(DateTime now) =>
      (targetDurationSeconds - activeElapsedSeconds(now)).clamp(
        0,
        targetDurationSeconds,
      );

  int activeStageElapsedSeconds(DateTime now) {
    final stage = activeStage;
    final start = stageStartedAt;
    if (stage == null || start == null) return 0;
    final endpoint = pausedAt ?? now;
    return (endpoint.difference(start).inSeconds - stageAccumulatedPauseSeconds)
        .clamp(0, 7200);
  }

  int activeStageRemainingSeconds(DateTime now) {
    final stage = activeStage;
    if (stage == null) return remainingSeconds(now);
    return (stage.durationSeconds - activeStageElapsedSeconds(now)).clamp(
      0,
      stage.durationSeconds,
    );
  }

  CanvasWorkshopSession maintain(DateTime now) {
    final stage = activeStage;
    if (status != CanvasWorkshopStatus.running ||
        stage == null ||
        stage.durationSeconds == 0 ||
        activeStageRemainingSeconds(now) > 0 ||
        awaitingAdvance) {
      return this;
    }
    return _copy(awaitingAdvance: true);
  }

  CanvasWorkshopSession start({
    required String sessionId,
    required String hostUid,
    required DateTime now,
    required int durationMinutes,
    required Map<String, String> baselineObjectVersions,
  }) {
    if (sessionId.isEmpty ||
        hostUid.isEmpty ||
        durationMinutes < 5 ||
        durationMinutes > 120) {
      throw const FormatException('Invalid workshop session.');
    }
    return CanvasWorkshopSession(
      status: CanvasWorkshopStatus.running,
      sessionId: sessionId,
      hostUid: hostUid,
      presenterUid: hostUid,
      startedAt: now,
      targetDurationSeconds: durationMinutes * 60,
      participantIds: <String>{hostUid},
      baselineObjectVersions: baselineObjectVersions,
    );
  }

  CanvasWorkshopSession startAgenda({
    required String sessionId,
    required String hostUid,
    required DateTime now,
    required List<CanvasWorkshopStage> agenda,
    required Map<String, String> baselineObjectVersions,
  }) {
    if (sessionId.isEmpty ||
        hostUid.isEmpty ||
        agenda.isEmpty ||
        agenda.length > 12) {
      throw const FormatException('Invalid workshop agenda.');
    }
    final totalSeconds = agenda.fold<int>(
      0,
      (total, stage) => total + stage.durationSeconds,
    );
    return CanvasWorkshopSession(
      status: CanvasWorkshopStatus.running,
      sessionId: sessionId,
      hostUid: hostUid,
      presenterUid: hostUid,
      startedAt: now,
      targetDurationSeconds: totalSeconds,
      participantIds: <String>{hostUid},
      baselineObjectVersions: baselineObjectVersions,
      agenda: agenda,
      stageStartedAt: now,
    );
  }

  CanvasWorkshopSession pause(DateTime now) =>
      status != CanvasWorkshopStatus.running
      ? this
      : _copy(status: CanvasWorkshopStatus.paused, pausedAt: now);

  CanvasWorkshopSession resume(DateTime now) {
    if (status != CanvasWorkshopStatus.paused || pausedAt == null) return this;
    return _copy(
      status: CanvasWorkshopStatus.running,
      accumulatedPauseSeconds:
          accumulatedPauseSeconds + now.difference(pausedAt!).inSeconds,
      stageAccumulatedPauseSeconds:
          stageAccumulatedPauseSeconds + now.difference(pausedAt!).inSeconds,
      clearPausedAt: true,
    );
  }

  CanvasWorkshopSession extend(int minutes) {
    if (!isActive || !const <int>{1, 5, 10}.contains(minutes)) return this;
    return _copy(
      targetDurationSeconds: (targetDurationSeconds + minutes * 60).clamp(
        0,
        43200,
      ),
    );
  }

  CanvasWorkshopSession addParticipant(String uid) => uid.isEmpty
      ? this
      : _copy(participantIds: <String>{...participantIds, uid});

  CanvasWorkshopSession setPresenter(String? uid) =>
      !isActive ? this : _copy(presenterUid: uid, clearPresenter: uid == null);

  CanvasWorkshopSession recordReaction(String emoji) {
    if (!isActive || emoji.isEmpty || emoji.length > 16) return this;
    return _copy(
      reactionTotals: <String, int>{
        ...reactionTotals,
        emoji: (reactionTotals[emoji] ?? 0) + 1,
      },
    );
  }

  CanvasWorkshopSession revealActiveStage() {
    final stage = activeStage;
    if (!isActive || stage == null) return this;
    return _copy(revealedStageIds: <String>{...revealedStageIds, stage.id});
  }

  CanvasWorkshopSession advanceStage(DateTime now) {
    final stage = activeStage;
    if (!isActive || stage == null || isLastStage) return this;
    final elapsed = activeStageElapsedSeconds(now);
    return _copy(
      activeStageIndex: activeStageIndex + 1,
      stageStartedAt: now,
      stageAccumulatedPauseSeconds: 0,
      awaitingAdvance: false,
      completedStageIds: <String>{...completedStageIds, stage.id},
      stageElapsedSeconds: <String, int>{
        ...stageElapsedSeconds,
        stage.id: elapsed,
      },
      clearPausedAt: true,
      status: CanvasWorkshopStatus.running,
    );
  }

  CanvasWorkshopSession restartStage(DateTime now) {
    final stage = activeStage;
    if (!isActive || stage == null) return this;
    return _copy(
      stageStartedAt: now,
      stageAccumulatedPauseSeconds: 0,
      awaitingAdvance: false,
      clearPausedAt: true,
      status: CanvasWorkshopStatus.running,
    );
  }

  CanvasWorkshopSession skipStage(DateTime now) => advanceStage(now);

  CanvasWorkshopSession saveAiSummary(WorkshopAiSummarySnapshot snapshot) =>
      summary == null ? this : _copy(summary: summary!.withAiSummary(snapshot));

  CanvasWorkshopSession end({
    required DateTime now,
    required CanvasWorkshopSummary summary,
  }) => !isActive
      ? this
      : _copy(
          status: CanvasWorkshopStatus.ended,
          endedAt: now,
          summary: summary,
          clearPausedAt: true,
        );

  CanvasWorkshopSession _copy({
    CanvasWorkshopStatus? status,
    String? presenterUid,
    bool clearPresenter = false,
    DateTime? pausedAt,
    bool clearPausedAt = false,
    DateTime? endedAt,
    int? targetDurationSeconds,
    int? accumulatedPauseSeconds,
    Set<String>? participantIds,
    Map<String, int>? reactionTotals,
    int? activeStageIndex,
    DateTime? stageStartedAt,
    int? stageAccumulatedPauseSeconds,
    bool? awaitingAdvance,
    Set<String>? revealedStageIds,
    Set<String>? completedStageIds,
    Map<String, int>? stageElapsedSeconds,
    CanvasWorkshopSummary? summary,
  }) => CanvasWorkshopSession(
    status: status ?? this.status,
    sessionId: sessionId,
    hostUid: hostUid,
    presenterUid: clearPresenter ? null : presenterUid ?? this.presenterUid,
    startedAt: startedAt,
    pausedAt: clearPausedAt ? null : pausedAt ?? this.pausedAt,
    endedAt: endedAt ?? this.endedAt,
    targetDurationSeconds: targetDurationSeconds ?? this.targetDurationSeconds,
    accumulatedPauseSeconds:
        accumulatedPauseSeconds ?? this.accumulatedPauseSeconds,
    participantIds: participantIds ?? this.participantIds,
    baselineObjectVersions: baselineObjectVersions,
    reactionTotals: reactionTotals ?? this.reactionTotals,
    agenda: agenda,
    activeStageIndex: activeStageIndex ?? this.activeStageIndex,
    stageStartedAt: stageStartedAt ?? this.stageStartedAt,
    stageAccumulatedPauseSeconds:
        stageAccumulatedPauseSeconds ?? this.stageAccumulatedPauseSeconds,
    awaitingAdvance: awaitingAdvance ?? this.awaitingAdvance,
    revealedStageIds: revealedStageIds ?? this.revealedStageIds,
    completedStageIds: completedStageIds ?? this.completedStageIds,
    stageElapsedSeconds: stageElapsedSeconds ?? this.stageElapsedSeconds,
    summary: summary ?? this.summary,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    if (sessionId != null) 'sessionId': sessionId,
    if (hostUid != null) 'hostUid': hostUid,
    if (presenterUid != null) 'presenterUid': presenterUid,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (pausedAt != null) 'pausedAt': pausedAt!.toIso8601String(),
    if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
    'targetDurationSeconds': targetDurationSeconds,
    'accumulatedPauseSeconds': accumulatedPauseSeconds,
    'participantIds': participantIds.toList()..sort(),
    'baselineObjectVersions': baselineObjectVersions,
    'reactionTotals': reactionTotals,
    'agenda': <Map<String, Object?>>[
      for (final stage in agenda) stage.toJson(),
    ],
    'activeStageIndex': activeStageIndex,
    if (stageStartedAt != null)
      'stageStartedAt': stageStartedAt!.toIso8601String(),
    'stageAccumulatedPauseSeconds': stageAccumulatedPauseSeconds,
    'awaitingAdvance': awaitingAdvance,
    'revealedStageIds': revealedStageIds.toList()..sort(),
    'completedStageIds': completedStageIds.toList()..sort(),
    'stageElapsedSeconds': stageElapsedSeconds,
    if (summary != null) 'summary': summary!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is CanvasWorkshopSession &&
      other.status == status &&
      other.sessionId == sessionId &&
      other.hostUid == hostUid &&
      other.presenterUid == presenterUid &&
      other.startedAt == startedAt &&
      other.pausedAt == pausedAt &&
      other.endedAt == endedAt &&
      other.targetDurationSeconds == targetDurationSeconds &&
      other.accumulatedPauseSeconds == accumulatedPauseSeconds &&
      const SetEquality<String>().equals(
        other.participantIds,
        participantIds,
      ) &&
      const MapEquality<String, String>().equals(
        other.baselineObjectVersions,
        baselineObjectVersions,
      ) &&
      const MapEquality<String, int>().equals(
        other.reactionTotals,
        reactionTotals,
      ) &&
      const ListEquality<CanvasWorkshopStage>().equals(other.agenda, agenda) &&
      other.activeStageIndex == activeStageIndex &&
      other.stageStartedAt == stageStartedAt &&
      other.stageAccumulatedPauseSeconds == stageAccumulatedPauseSeconds &&
      other.awaitingAdvance == awaitingAdvance &&
      const SetEquality<String>().equals(
        other.revealedStageIds,
        revealedStageIds,
      ) &&
      const SetEquality<String>().equals(
        other.completedStageIds,
        completedStageIds,
      ) &&
      const MapEquality<String, int>().equals(
        other.stageElapsedSeconds,
        stageElapsedSeconds,
      ) &&
      other.summary == summary;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    status,
    sessionId,
    hostUid,
    presenterUid,
    startedAt,
    pausedAt,
    endedAt,
    targetDurationSeconds,
    accumulatedPauseSeconds,
    const SetEquality<String>().hash(participantIds),
    const MapEquality<String, String>().hash(baselineObjectVersions),
    const MapEquality<String, int>().hash(reactionTotals),
    const ListEquality<CanvasWorkshopStage>().hash(agenda),
    activeStageIndex,
    stageStartedAt,
    stageAccumulatedPauseSeconds,
    awaitingAdvance,
    const SetEquality<String>().hash(revealedStageIds),
    const SetEquality<String>().hash(completedStageIds),
    const MapEquality<String, int>().hash(stageElapsedSeconds),
    summary,
  ]);
}

DateTime? _optionalDateTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

int _nonNegativeInt(Object? value) =>
    value is num ? value.toInt().clamp(0, 999999999) : 0;

Map<String, int> _intMap(Object? value) => value is Map
    ? <String, int>{
        for (final entry in value.entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value! as num).toInt().clamp(
              0,
              999999999,
            ),
      }
    : const <String, int>{};

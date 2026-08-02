enum VotingDeliveryStatus { queued, syncing, accepted, rejected }

final class VotingBallotMutation {
  const VotingBallotMutation({
    required this.mutationId,
    required this.roomId,
    required this.boardId,
    required this.sessionId,
    required this.uid,
    required this.choices,
    required this.status,
    required this.attemptCount,
    required this.nextAttemptAt,
    this.error,
  });

  factory VotingBallotMutation.fromJson(Map<String, Object?> json) =>
      VotingBallotMutation(
        mutationId: json['mutationId']! as String,
        roomId: json['roomId']! as String,
        boardId: json['boardId']! as String,
        sessionId: json['sessionId']! as String,
        uid: json['uid']! as String,
        choices: (json['choices']! as List).cast<String>().toSet(),
        status: VotingDeliveryStatus.values.byName(json['status']! as String),
        attemptCount: json['attemptCount']! as int,
        nextAttemptAt: DateTime.parse(json['nextAttemptAt']! as String),
        error: json['error'] as String?,
      );

  final String mutationId;
  final String roomId;
  final String boardId;
  final String sessionId;
  final String uid;
  final Set<String> choices;
  final VotingDeliveryStatus status;
  final int attemptCount;
  final DateTime nextAttemptAt;
  final String? error;

  String get key => '$roomId|$boardId|$sessionId|$uid';

  VotingBallotMutation copyWith({
    VotingDeliveryStatus? status,
    int? attemptCount,
    DateTime? nextAttemptAt,
    String? error,
  }) => VotingBallotMutation(
    mutationId: mutationId,
    roomId: roomId,
    boardId: boardId,
    sessionId: sessionId,
    uid: uid,
    choices: choices,
    status: status ?? this.status,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    error: error,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'mutationId': mutationId,
    'roomId': roomId,
    'boardId': boardId,
    'sessionId': sessionId,
    'uid': uid,
    'choices': choices.toList()..sort(),
    'status': status.name,
    'attemptCount': attemptCount,
    'nextAttemptAt': nextAttemptAt.toUtc().toIso8601String(),
    if (error != null) 'error': error,
  };
}

final class VotingAggregate {
  const VotingAggregate({required this.sessionId, required this.totals});

  final String sessionId;
  final Map<String, int> totals;
}

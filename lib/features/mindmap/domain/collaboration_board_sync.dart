import 'dart:convert';

Map<String, Object?> collaborationBoardPayload(Map<String, Object?> payload) {
  final result = Map<String, Object?>.from(payload);
  final voting = result['votingSession'];
  if (voting is Map) {
    result['votingSession'] = Map<String, Object?>.from(voting)
      ..remove('allocations');
  }
  final objects = result['objects'];
  if (objects is List) {
    result['objects'] = <Object?>[
      for (final object in objects)
        if (object is Map)
          Map<String, Object?>.from(object)..update(
            'payload',
            (payload) => payload is Map
                ? (Map<String, Object?>.from(payload)..remove('voteCount'))
                : payload,
          )
        else
          object,
    ];
  }
  return result;
}

final class CollaborationBoardEnvelope {
  CollaborationBoardEnvelope({
    required this.boardId,
    required this.revision,
    required Map<String, Object?> payload,
    required this.createdByUid,
    required this.updatedByUid,
    required this.lastMutationId,
  }) : payload = Map<String, Object?>.unmodifiable(payload) {
    if (boardId.isEmpty ||
        revision < 1 ||
        payload['id'] != boardId ||
        payload['kind'] != 'project' ||
        createdByUid.isEmpty ||
        updatedByUid.isEmpty ||
        lastMutationId.isEmpty ||
        lastMutationId.length > 128) {
      throw const FormatException('Invalid collaboration board envelope.');
    }
    _ensureJson(payload);
  }

  factory CollaborationBoardEnvelope.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const <String>{
      'schemaVersion',
      'boardId',
      'revision',
      'payload',
      'createdByUid',
      'updatedByUid',
      'lastMutationId',
    });
    if (json['schemaVersion'] != schemaVersion ||
        json['boardId'] is! String ||
        json['revision'] is! int ||
        json['payload'] is! Map ||
        json['createdByUid'] is! String ||
        json['updatedByUid'] is! String ||
        json['lastMutationId'] is! String) {
      throw const FormatException('Invalid collaboration board envelope JSON.');
    }
    return CollaborationBoardEnvelope(
      boardId: json['boardId']! as String,
      revision: json['revision']! as int,
      payload: Map<String, Object?>.from(json['payload']! as Map),
      createdByUid: json['createdByUid']! as String,
      updatedByUid: json['updatedByUid']! as String,
      lastMutationId: json['lastMutationId']! as String,
    );
  }

  static const int schemaVersion = 1;
  final String boardId;
  final int revision;
  final Map<String, Object?> payload;
  final String createdByUid;
  final String updatedByUid;
  final String lastMutationId;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'boardId': boardId,
    'revision': revision,
    'payload': payload,
    'createdByUid': createdByUid,
    'updatedByUid': updatedByUid,
    'lastMutationId': lastMutationId,
  };
}

enum CollaborationBoardDeliveryState {
  pending,
  retryWaiting,
  blocked,
  failed,
  conflict,
}

final class CollaborationPendingBoardMutation {
  CollaborationPendingBoardMutation({
    required this.mutationId,
    required this.roomId,
    required this.boardId,
    required this.baseRevision,
    required Map<String, Object?> payload,
    required this.updatedByUid,
    required this.attemptCount,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime nextAttemptAt,
    required DateTime? lastAttemptAt,
    required this.lastErrorCode,
    required this.deliveryState,
  }) : payload = Map<String, Object?>.unmodifiable(payload),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       nextAttemptAt = nextAttemptAt.toUtc(),
       lastAttemptAt = lastAttemptAt?.toUtc() {
    if (mutationId.isEmpty ||
        mutationId.length > 128 ||
        roomId.isEmpty ||
        boardId.isEmpty ||
        baseRevision < 0 ||
        payload['id'] != boardId ||
        payload['kind'] != 'project' ||
        updatedByUid.isEmpty ||
        attemptCount < 0) {
      throw const FormatException('Invalid pending board mutation.');
    }
    _ensureJson(payload);
  }

  final String mutationId;
  final String roomId;
  final String boardId;
  final int baseRevision;
  final Map<String, Object?> payload;
  final String updatedByUid;
  final int attemptCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime nextAttemptAt;
  final DateTime? lastAttemptAt;
  final String? lastErrorCode;
  final CollaborationBoardDeliveryState deliveryState;

  factory CollaborationPendingBoardMutation.fromJson(
    Map<String, Object?> json,
  ) {
    final payload = json['payload'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    final nextAttemptAt = DateTime.tryParse(
      json['nextAttemptAt'] as String? ?? '',
    );
    final lastAttemptValue = json['lastAttemptAt'] as String?;
    final lastAttemptAt = lastAttemptValue == null
        ? null
        : DateTime.tryParse(lastAttemptValue);
    CollaborationBoardDeliveryState? state;
    for (final value in CollaborationBoardDeliveryState.values) {
      if (value.name == json['deliveryState']) state = value;
    }
    if (json['mutationId'] is! String ||
        json['roomId'] is! String ||
        json['boardId'] is! String ||
        json['baseRevision'] is! int ||
        payload is! Map ||
        json['updatedByUid'] is! String ||
        json['attemptCount'] is! int ||
        createdAt == null ||
        updatedAt == null ||
        nextAttemptAt == null ||
        (lastAttemptValue != null && lastAttemptAt == null) ||
        state == null) {
      throw const FormatException('Invalid pending board mutation JSON.');
    }
    return CollaborationPendingBoardMutation(
      mutationId: json['mutationId']! as String,
      roomId: json['roomId']! as String,
      boardId: json['boardId']! as String,
      baseRevision: json['baseRevision']! as int,
      payload: Map<String, Object?>.from(payload),
      updatedByUid: json['updatedByUid']! as String,
      attemptCount: json['attemptCount']! as int,
      createdAt: createdAt,
      updatedAt: updatedAt,
      nextAttemptAt: nextAttemptAt,
      lastAttemptAt: lastAttemptAt,
      lastErrorCode: json['lastErrorCode'] as String?,
      deliveryState: state,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'mutationId': mutationId,
    'roomId': roomId,
    'boardId': boardId,
    'baseRevision': baseRevision,
    'payload': payload,
    'updatedByUid': updatedByUid,
    'attemptCount': attemptCount,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'nextAttemptAt': nextAttemptAt.toIso8601String(),
    'lastAttemptAt': lastAttemptAt?.toIso8601String(),
    'lastErrorCode': lastErrorCode,
    'deliveryState': deliveryState.name,
  };

  CollaborationPendingBoardMutation copyWith({
    int? baseRevision,
    int? attemptCount,
    DateTime? updatedAt,
    DateTime? nextAttemptAt,
    DateTime? lastAttemptAt,
    String? lastErrorCode,
    bool clearError = false,
    CollaborationBoardDeliveryState? deliveryState,
  }) => CollaborationPendingBoardMutation(
    mutationId: mutationId,
    roomId: roomId,
    boardId: boardId,
    baseRevision: baseRevision ?? this.baseRevision,
    payload: payload,
    updatedByUid: updatedByUid,
    attemptCount: attemptCount ?? this.attemptCount,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    lastErrorCode: clearError ? null : lastErrorCode ?? this.lastErrorCode,
    deliveryState: deliveryState ?? this.deliveryState,
  );
}

final class CollaborationBoardConflict {
  const CollaborationBoardConflict({
    required this.roomId,
    required this.boardId,
    required this.localBaseRevision,
    required this.remoteRevision,
    required this.remoteEnvelope,
  });

  factory CollaborationBoardConflict.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const <String>{
      'roomId',
      'boardId',
      'localBaseRevision',
      'remoteRevision',
      'remoteEnvelope',
    });
    final envelope = json['remoteEnvelope'];
    if (json['roomId'] is! String ||
        json['boardId'] is! String ||
        json['localBaseRevision'] is! int ||
        json['remoteRevision'] is! int ||
        envelope is! Map) {
      throw const FormatException('Invalid collaboration board conflict.');
    }
    return CollaborationBoardConflict(
      roomId: json['roomId']! as String,
      boardId: json['boardId']! as String,
      localBaseRevision: json['localBaseRevision']! as int,
      remoteRevision: json['remoteRevision']! as int,
      remoteEnvelope: CollaborationBoardEnvelope.fromJson(
        Map<String, Object?>.from(envelope),
      ),
    );
  }

  final String roomId;
  final String boardId;
  final int localBaseRevision;
  final int remoteRevision;
  final CollaborationBoardEnvelope remoteEnvelope;

  Map<String, Object?> toJson() => <String, Object?>{
    'roomId': roomId,
    'boardId': boardId,
    'localBaseRevision': localBaseRevision,
    'remoteRevision': remoteRevision,
    'remoteEnvelope': remoteEnvelope.toJson(),
  };
}

void _requireKeys(Map<String, Object?> json, Set<String> keys) {
  final actual = json.keys.toSet();
  if (actual.difference(keys).isNotEmpty ||
      keys.difference(actual).isNotEmpty) {
    throw const FormatException('Unexpected collaboration board keys.');
  }
}

void _ensureJson(Object? value) {
  try {
    jsonEncode(value);
  } on Object {
    throw const FormatException('Collaboration board payload is not JSON.');
  }
}

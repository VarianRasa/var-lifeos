import 'dart:convert';

final class CollaborationNodeEnvelope {
  CollaborationNodeEnvelope({
    required this.remoteNodeId,
    required this.dayKey,
    required this.revision,
    required this.deleted,
    required Map<String, Object?>? payload,
    required this.createdByUid,
    required this.updatedByUid,
    required this.lastMutationId,
  }) : payload = payload == null ? null : Map.unmodifiable(payload) {
    if (remoteNodeId.isEmpty ||
        dayKey.isEmpty ||
        DateTime.tryParse(dayKey) == null ||
        revision < 1 ||
        createdByUid.isEmpty ||
        updatedByUid.isEmpty ||
        lastMutationId.isEmpty ||
        lastMutationId.length > 128 ||
        (deleted ? payload != null : payload == null)) {
      throw const FormatException('Invalid collaboration node envelope.');
    }
    if (!deleted &&
        (payload?['id'] != remoteNodeId || payload?['day'] != dayKey)) {
      throw const FormatException('Envelope payload identity mismatch.');
    }
  }

  factory CollaborationNodeEnvelope.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != 1 && version != 2) {
      throw const FormatException('Invalid collaboration node envelope JSON.');
    }
    _requireKeys(json, {
      'schemaVersion',
      'remoteNodeId',
      'dayKey',
      'revision',
      'deleted',
      'payload',
      'createdByUid',
      'updatedByUid',
      if (version == 2) 'lastMutationId',
    });
    if (json['remoteNodeId'] is! String ||
        json['dayKey'] is! String ||
        json['revision'] is! int ||
        json['deleted'] is! bool ||
        json['createdByUid'] is! String ||
        json['updatedByUid'] is! String ||
        (version == 2 && json['lastMutationId'] is! String)) {
      throw const FormatException('Invalid collaboration node envelope JSON.');
    }
    final rawPayload = json['payload'];
    if (rawPayload != null && rawPayload is! Map) {
      throw const FormatException('Invalid collaboration node payload.');
    }
    return CollaborationNodeEnvelope(
      remoteNodeId: json['remoteNodeId']! as String,
      dayKey: json['dayKey']! as String,
      revision: json['revision']! as int,
      deleted: json['deleted']! as bool,
      payload: rawPayload == null
          ? null
          : Map<String, Object?>.from(rawPayload as Map),
      createdByUid: json['createdByUid']! as String,
      updatedByUid: json['updatedByUid']! as String,
      lastMutationId: version == 2
          ? json['lastMutationId']! as String
          : 'legacy:${json['revision']}',
    );
  }

  static const int schemaVersion = 2;
  final String remoteNodeId;
  final String dayKey;
  final int revision;
  final bool deleted;
  final Map<String, Object?>? payload;
  final String createdByUid;
  final String updatedByUid;
  final String lastMutationId;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'remoteNodeId': remoteNodeId,
    'dayKey': dayKey,
    'revision': revision,
    'deleted': deleted,
    'payload': payload,
    'createdByUid': createdByUid,
    'updatedByUid': updatedByUid,
    'lastMutationId': lastMutationId,
  };
}

final class CollaborationNodeBinding {
  const CollaborationNodeBinding({
    required this.roomId,
    required this.localNodeId,
    required this.remoteNodeId,
    required this.dayKey,
    required this.revision,
  });
  final String roomId;
  final String localNodeId;
  final String remoteNodeId;
  final String dayKey;
  final int revision;
}

enum CollaborationMutationKind { upsert, delete }

enum CollaborationDeliveryState {
  pending,
  retryWaiting,
  blocked,
  failed,
  conflict,
}

final class CollaborationPendingMutation {
  CollaborationPendingMutation({
    required this.mutationId,
    required this.roomId,
    required this.localNodeId,
    required this.remoteNodeId,
    required this.dayKey,
    required this.baseRevision,
    required this.kind,
    required Map<String, Object?>? payload,
    required this.updatedByUid,
    required this.attemptCount,
    required DateTime createdAt,
    required DateTime updatedAt,
    required DateTime nextAttemptAt,
    required DateTime? lastAttemptAt,
    required this.lastErrorCode,
    required this.deliveryState,
  }) : payload = payload == null ? null : Map.unmodifiable(payload),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       nextAttemptAt = nextAttemptAt.toUtc(),
       lastAttemptAt = lastAttemptAt?.toUtc() {
    if (mutationId.isEmpty ||
        mutationId.length > 128 ||
        attemptCount < 0 ||
        baseRevision < 0 ||
        roomId.isEmpty ||
        localNodeId.isEmpty ||
        remoteNodeId.isEmpty ||
        dayKey.isEmpty ||
        DateTime.tryParse(dayKey) == null ||
        updatedByUid.isEmpty ||
        (kind == CollaborationMutationKind.upsert
            ? payload == null
            : payload != null)) {
      throw const FormatException('Invalid collaboration pending mutation.');
    }
  }

  final String mutationId;
  final String roomId;
  final String localNodeId;
  final String remoteNodeId;
  final String dayKey;
  final int baseRevision;
  final CollaborationMutationKind kind;
  final Map<String, Object?>? payload;
  final String updatedByUid;
  final int attemptCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime nextAttemptAt;
  final DateTime? lastAttemptAt;
  final String? lastErrorCode;
  final CollaborationDeliveryState deliveryState;

  CollaborationPendingMutation copyWith({
    int? baseRevision,
    int? attemptCount,
    DateTime? updatedAt,
    DateTime? nextAttemptAt,
    DateTime? lastAttemptAt,
    String? lastErrorCode,
    bool clearError = false,
    CollaborationDeliveryState? deliveryState,
  }) => CollaborationPendingMutation(
    mutationId: mutationId,
    roomId: roomId,
    localNodeId: localNodeId,
    remoteNodeId: remoteNodeId,
    dayKey: dayKey,
    baseRevision: baseRevision ?? this.baseRevision,
    kind: kind,
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

final class CollaborationOutboxSummary {
  const CollaborationOutboxSummary({
    required this.pending,
    required this.retrying,
    required this.blocked,
    required this.failed,
    required this.conflict,
    required this.nextRetryAt,
  });
  final int pending;
  final int retrying;
  final int blocked;
  final int failed;
  final int conflict;
  final DateTime? nextRetryAt;
  int get total => pending + retrying + blocked + failed + conflict;
}

final class CollaborationNodeConflict {
  const CollaborationNodeConflict({
    required this.roomId,
    required this.localNodeId,
    required this.remoteNodeId,
    required this.localBaseRevision,
    required this.remoteRevision,
    required this.remoteEnvelope,
  });
  factory CollaborationNodeConflict.fromJson(Map<String, Object?> json) {
    const keys = {
      'roomId',
      'localNodeId',
      'remoteNodeId',
      'localBaseRevision',
      'remoteRevision',
      'remoteEnvelope',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        json['roomId'] is! String ||
        json['localNodeId'] is! String ||
        json['remoteNodeId'] is! String ||
        json['localBaseRevision'] is! int ||
        json['remoteRevision'] is! int) {
      throw const FormatException('Invalid collaboration conflict JSON.');
    }
    final raw = json['remoteEnvelope'];
    if (raw != null && raw is! Map) {
      throw const FormatException('Invalid collaboration conflict envelope.');
    }
    return CollaborationNodeConflict(
      roomId: json['roomId']! as String,
      localNodeId: json['localNodeId']! as String,
      remoteNodeId: json['remoteNodeId']! as String,
      localBaseRevision: json['localBaseRevision']! as int,
      remoteRevision: json['remoteRevision']! as int,
      remoteEnvelope: raw == null
          ? null
          : CollaborationNodeEnvelope.fromJson(
              Map<String, Object?>.from(raw as Map),
            ),
    );
  }
  final String roomId;
  final String localNodeId;
  final String remoteNodeId;
  final int localBaseRevision;
  final int remoteRevision;
  final CollaborationNodeEnvelope? remoteEnvelope;
  Map<String, Object?> toJson() => {
    'roomId': roomId,
    'localNodeId': localNodeId,
    'remoteNodeId': remoteNodeId,
    'localBaseRevision': localBaseRevision,
    'remoteRevision': remoteRevision,
    'remoteEnvelope': remoteEnvelope?.toJson(),
  };
}

void _requireKeys(Map<String, Object?> json, Set<String> keys) {
  if (json.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(json.keys.toSet()).isNotEmpty) {
    throw const FormatException('Unexpected collaboration node envelope keys.');
  }
  try {
    jsonEncode(json);
  } on Object {
    throw const FormatException('Envelope is not JSON encodable.');
  }
}

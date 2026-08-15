enum CollaborationRole { owner, editor, commenter, viewer }

enum CollaborationInviteStatus { active, redeemed, revoked }

enum CollaborationTargetKind { day, projectBoard }

final class CollaborationTarget {
  const CollaborationTarget({
    required this.kind,
    required this.id,
    required this.label,
  });

  factory CollaborationTarget.day(String dayKey) => CollaborationTarget(
    kind: CollaborationTargetKind.day,
    id: dayKey,
    label: dayKey,
  );

  factory CollaborationTarget.projectBoard({
    required String boardId,
    required String label,
  }) => CollaborationTarget(
    kind: CollaborationTargetKind.projectBoard,
    id: boardId,
    label: label.trim(),
  );

  factory CollaborationTarget.fromRoomJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'] as int? ?? 2;
    if (schemaVersion == 2) {
      final dayKey = json['dayKey'] as String? ?? '';
      if (DateTime.tryParse(dayKey) == null) {
        throw const CollaborationException(
          CollaborationErrorCode.invalidInput,
          'Invalid collaboration day target.',
        );
      }
      return CollaborationTarget.day(dayKey);
    }
    final kindName = json['targetKind'] as String? ?? '';
    final kind = CollaborationTargetKind.values.firstWhere(
      (candidate) => candidate.name == kindName,
      orElse: () => throw const CollaborationException(
        CollaborationErrorCode.invalidInput,
        'Invalid collaboration target kind.',
      ),
    );
    final id = json['targetId'] as String? ?? '';
    final label = json['targetLabel'] as String? ?? '';
    final target = CollaborationTarget(kind: kind, id: id, label: label);
    if (!target.isValid) {
      throw const CollaborationException(
        CollaborationErrorCode.invalidInput,
        'Invalid collaboration target.',
      );
    }
    return target;
  }

  final CollaborationTargetKind kind;
  final String id;
  final String label;

  bool get isValid =>
      id.trim().isNotEmpty &&
      label.trim().isNotEmpty &&
      (kind != CollaborationTargetKind.day || DateTime.tryParse(id) != null);

  String? get dayKey => kind == CollaborationTargetKind.day ? id : null;

  Map<String, Object?> toRoomJson() => <String, Object?>{
    'targetKind': kind.name,
    'targetId': id,
    'targetLabel': label,
  };

  @override
  bool operator ==(Object other) =>
      other is CollaborationTarget &&
      other.kind == kind &&
      other.id == id &&
      other.label == label;

  @override
  int get hashCode => Object.hash(kind, id, label);
}

enum CollaborationErrorCode {
  unauthenticated,
  emailNotVerified,
  invalidInput,
  permissionDenied,
  notFound,
  inviteExpired,
  inviteUsed,
  unavailable,
  unknown,
}

class CollaborationException implements Exception {
  const CollaborationException(this.code, this.message);

  final CollaborationErrorCode code;
  final String message;

  @override
  String toString() => message;
}

class CollaborationIdentity {
  const CollaborationIdentity({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.isAnonymous,
    required this.emailVerified,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final bool isAnonymous;
  final bool emailVerified;

  bool get isEligible =>
      uid.isNotEmpty &&
      !isAnonymous &&
      emailVerified &&
      normalizeCollaborationEmail(email ?? '').isNotEmpty;
}

extension CollaborationRoleCapabilities on CollaborationRole {
  bool get canRead => true;
  bool get canWriteNodes =>
      this == CollaborationRole.owner || this == CollaborationRole.editor;
  bool get canComment => this != CollaborationRole.viewer;
  bool get canManageMembers => this == CollaborationRole.owner;
  bool get canControlWorkshop =>
      this == CollaborationRole.owner || this == CollaborationRole.editor;
  bool get canPresent => canControlWorkshop;
  bool get canVote => this != CollaborationRole.viewer;
  bool get canReact => this != CollaborationRole.viewer;
  bool get canPing => this != CollaborationRole.viewer;
  bool get canFollowPresenter => true;
}

CollaborationRole collaborationRoleFromString(String value) {
  return CollaborationRole.values.firstWhere(
    (role) => role.name == value,
    orElse: () => throw const CollaborationException(
      CollaborationErrorCode.invalidInput,
      'Invalid collaboration role.',
    ),
  );
}

String normalizeCollaborationEmail(String value) => value.trim().toLowerCase();

class CollaborationRoom {
  const CollaborationRoom({
    required this.id,
    required this.ownerUid,
    required this.target,
    required this.createdAt,
  });

  factory CollaborationRoom.fromJson(Map<String, Object?> json) =>
      CollaborationRoom(
        id: json['id'] as String? ?? '',
        ownerUid: json['ownerUid'] as String? ?? '',
        target: CollaborationTarget.fromRoomJson(json),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  static const int currentSchemaVersion = 3;

  final String id;
  final String ownerUid;
  final CollaborationTarget target;
  final DateTime createdAt;
  int get schemaVersion => currentSchemaVersion;
  String? get dayKey => target.dayKey;

  String get link => 'var-collab://var.app/room/$id';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'schemaVersion': currentSchemaVersion,
    'ownerUid': ownerUid,
    ...target.toRoomJson(),
    'createdAt': createdAt.toIso8601String(),
  };
}

class CollaborationRoomLink {
  const CollaborationRoomLink({required this.roomId});

  final String roomId;

  static CollaborationRoomLink? tryParse(String value) {
    final input = value.trim();
    if (_uuid.hasMatch(input)) return CollaborationRoomLink(roomId: input);
    final uri = Uri.tryParse(input);
    if (uri == null ||
        uri.scheme != 'var-collab' ||
        uri.host != 'var.app' ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 'room' ||
        !_uuid.hasMatch(uri.pathSegments.last)) {
      return null;
    }
    return CollaborationRoomLink(roomId: uri.pathSegments.last);
  }
}

class CollaborationMember {
  const CollaborationMember({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.joinedAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final CollaborationRole role;
  final DateTime joinedAt;
}

class CollaborationInvite {
  const CollaborationInvite({
    required this.id,
    required this.roomId,
    required this.email,
    required this.role,
    this.status = CollaborationInviteStatus.active,
    required this.createdByUid,
    required this.createdAt,
    required this.expiresAt,
    this.redeemedByUid,
    this.redeemedAt,
  });

  final String id;
  final String roomId;
  final String email;
  final CollaborationRole role;
  final CollaborationInviteStatus status;
  final String createdByUid;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? redeemedByUid;
  final DateTime? redeemedAt;

  String get link => 'var-collab://var.app/invite/$roomId/$id';

  bool get isValid =>
      id.isNotEmpty &&
      roomId.isNotEmpty &&
      createdByUid.isNotEmpty &&
      normalizeCollaborationEmail(email).contains('@') &&
      role != CollaborationRole.owner &&
      expiresAt.isAfter(createdAt);
}

class CollaborationInviteLink {
  const CollaborationInviteLink({required this.roomId, required this.inviteId});

  final String roomId;
  final String inviteId;

  static CollaborationInviteLink? tryParse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'var-collab' ||
        uri.host != 'var.app' ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.pathSegments.length != 3 ||
        uri.pathSegments.first != 'invite' ||
        !_uuid.hasMatch(uri.pathSegments[1]) ||
        !_uuid.hasMatch(uri.pathSegments[2])) {
      return null;
    }
    return CollaborationInviteLink(
      roomId: uri.pathSegments[1],
      inviteId: uri.pathSegments[2],
    );
  }
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

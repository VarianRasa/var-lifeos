import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/collaboration_room.dart';

void main() {
  test('identity eligibility requires verified non-anonymous email', () {
    const eligible = CollaborationIdentity(
      uid: 'uid',
      email: 'user@example.com',
      displayName: null,
      isAnonymous: false,
      emailVerified: true,
    );
    expect(eligible.isEligible, isTrue);
    expect(
      const CollaborationIdentity(
        uid: 'uid',
        email: 'user@example.com',
        displayName: null,
        isAnonymous: true,
        emailVerified: true,
      ).isEligible,
      isFalse,
    );
  });

  test('roles expose minimum capabilities', () {
    expect(CollaborationRole.owner.canManageMembers, isTrue);
    expect(CollaborationRole.editor.canWriteNodes, isTrue);
    expect(CollaborationRole.commenter.canComment, isTrue);
    expect(CollaborationRole.viewer.canComment, isFalse);
    expect(CollaborationRole.owner.canControlWorkshop, isTrue);
    expect(CollaborationRole.editor.canPresent, isTrue);
    expect(CollaborationRole.commenter.canReact, isTrue);
    expect(CollaborationRole.viewer.canReact, isFalse);
    expect(CollaborationRole.viewer.canFollowPresenter, isTrue);
  });

  test('schema v2 room maps to day target', () {
    final target = CollaborationTarget.fromRoomJson(<String, Object?>{
      'schemaVersion': 2,
      'dayKey': '2026-07-28',
    });

    expect(target.kind, CollaborationTargetKind.day);
    expect(target.dayKey, '2026-07-28');
  });

  test('schema v3 project target round trips', () {
    final room = CollaborationRoom(
      id: 'room',
      ownerUid: 'owner',
      target: CollaborationTarget.projectBoard(
        boardId: 'project:alpha',
        label: 'Alpha board',
      ),
      createdAt: DateTime(2026, 7, 28),
    );

    final restored = CollaborationRoom.fromJson(room.toJson());
    expect(restored.target, room.target);
    expect(restored.dayKey, isNull);
    expect(restored.schemaVersion, 3);
  });

  test('room and invite links require full UUIDs', () {
    const roomId = '123e4567-e89b-42d3-a456-426614174000';
    const inviteId = '123e4567-e89b-42d3-a456-426614174001';
    expect(CollaborationRoomLink.tryParse(roomId)?.roomId, roomId);
    expect(
      CollaborationRoomLink.tryParse(
        'var-collab://var.app/room/$roomId',
      )?.roomId,
      roomId,
    );
    expect(CollaborationRoomLink.tryParse('123e4567'), isNull);
    expect(
      CollaborationInviteLink.tryParse(
        'var-collab://var.app/invite/$roomId/$inviteId',
      )?.inviteId,
      inviteId,
    );
    expect(
      CollaborationInviteLink.tryParse(
        'var-collab://var.app/invite/$roomId/$inviteId?key=fake',
      ),
      isNull,
    );
  });

  test('invite validates email, role, and expiry', () {
    final invite = CollaborationInvite(
      id: 'invite',
      roomId: 'room',
      email: 'member@example.com',
      role: CollaborationRole.editor,
      createdByUid: 'owner',
      createdAt: DateTime(2026),
      expiresAt: DateTime(2026, 1, 2),
    );
    expect(invite.isValid, isTrue);
  });
}

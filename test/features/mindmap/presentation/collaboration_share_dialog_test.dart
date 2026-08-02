import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/collaboration_controller.dart';
import 'package:var_app/features/mindmap/domain/collaboration_room.dart';
import 'package:var_app/features/mindmap/presentation/collaboration_share_dialog.dart';

void main() {
  testWidgets('owner sees invite and member management controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildDialog(
        role: CollaborationRole.owner,
        members: <CollaborationMember>[
          _member('owner', CollaborationRole.owner),
          _member('editor', CollaborationRole.editor),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('collaboration-open-invite-dialog')),
      findsOneWidget,
    );
    expect(find.byTooltip('Remove editor'), findsOneWidget);
    expect(find.byType(DropdownButton<CollaborationRole>), findsOneWidget);
  });

  testWidgets('non-owner cannot invite or manage members', (tester) async {
    await tester.pumpWidget(
      _buildDialog(
        role: CollaborationRole.editor,
        members: <CollaborationMember>[
          _member('owner', CollaborationRole.owner),
          _member('editor', CollaborationRole.editor),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('collaboration-open-invite-dialog')),
      findsNothing,
    );
    expect(find.byTooltip('Remove editor'), findsNothing);
    expect(find.byType(DropdownButton<CollaborationRole>), findsNothing);
    expect(find.text('editor'), findsWidgets);
  });
}

Widget _buildDialog({
  required CollaborationRole role,
  required List<CollaborationMember> members,
}) => ProviderScope(
  overrides: [
    collaborationProvider.overrideWith(
      (ref) => _FakeCollaborationNotifier(
        CollaborationState(
          collaborators: const {},
          isDemoMode: false,
          isConnected: true,
          roomId: '123e4567-e89b-42d3-a456-426614174000',
          roomTarget: CollaborationTarget.projectBoard(
            boardId: 'board',
            label: 'Board',
          ),
          currentRole: role,
          members: members,
          localUserId: role == CollaborationRole.owner ? 'owner' : 'editor',
          localName: role.name,
          localColor: Colors.blue,
        ),
      ),
    ),
    collaborationActionsProvider.overrideWithValue(_FakeActions()),
  ],
  child: const MaterialApp(
    home: Scaffold(body: CollaborationShareDialog(targetLabel: 'Board')),
  ),
);

CollaborationMember _member(String uid, CollaborationRole role) =>
    CollaborationMember(
      uid: uid,
      email: '$uid@example.com',
      displayName: uid,
      role: role,
      joinedAt: DateTime(2026, 7, 30),
    );

final class _FakeCollaborationNotifier extends CollaborationNotifier {
  _FakeCollaborationNotifier(CollaborationState initialState) : super(_ref) {
    state = initialState;
  }

  static final _ref = _UnsupportedRef();
}

final class _UnsupportedRef implements Ref {
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Provider access is not expected in this widget test.',
  );
}

final class _FakeActions implements CollaborationActions {
  @override
  Future<void> acceptInvite(String link) async {}

  @override
  Future<CollaborationInvite> createInvite(
    String email,
    CollaborationRole role,
    Duration validity,
  ) => throw UnimplementedError();

  @override
  Future<String> createProjectRoom({
    required String boardId,
    required String label,
  }) async => 'room';

  @override
  Future<void> leaveRoom() async {}

  @override
  Future<void> openRoomChecked(
    String urlOrId, {
    CollaborationTarget? expectedTarget,
    bool navigate = true,
  }) async {}

  @override
  Future<void> removeMember(String uid) async {}

  @override
  Future<void> retryOutboxNow() async {}

  @override
  Future<void> updateMemberRole(String uid, CollaborationRole role) async {}
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/collaboration_controller.dart';
import 'package:var_app/features/mindmap/domain/collaboration_room.dart';
import 'package:var_app/features/mindmap/presentation/collab_page.dart';

void main() {
  testWidgets('generic room join does not inject a day target', (tester) async {
    final actions = _FakeCollaborationActions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collaborationActionsProvider.overrideWithValue(actions)],
        child: const MaterialApp(home: CollabPage()),
      ),
    );

    await tester.enterText(
      find.byType(TextField).last,
      '123e4567-e89b-42d3-a456-426614174000',
    );
    await tester.tap(find.text('Join Room'));
    await tester.pump();

    expect(actions.openedRoomId, '123e4567-e89b-42d3-a456-426614174000');
    expect(actions.expectedTarget, isNull);
  });

  testWidgets('explicit day join keeps expected day target', (tester) async {
    final actions = _FakeCollaborationActions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collaborationActionsProvider.overrideWithValue(actions)],
        child: const MaterialApp(home: CollabPage(initialDayKey: '2026-07-30')),
      ),
    );

    await tester.enterText(
      find.byType(TextField).last,
      '123e4567-e89b-42d3-a456-426614174000',
    );
    await tester.tap(find.text('Join Room'));
    await tester.pump();

    expect(actions.expectedTarget, CollaborationTarget.day('2026-07-30'));
  });
}

final class _FakeCollaborationActions implements CollaborationActions {
  String? openedRoomId;
  CollaborationTarget? expectedTarget;

  @override
  Future<void> openRoomChecked(
    String urlOrId, {
    CollaborationTarget? expectedTarget,
    bool navigate = true,
  }) async {
    openedRoomId = urlOrId;
    this.expectedTarget = expectedTarget;
  }

  @override
  Future<void> acceptInvite(String link) async {}

  @override
  Future<String> createProjectRoom({
    required String boardId,
    required String label,
  }) async => 'room';

  @override
  Future<CollaborationInvite> createInvite(
    String email,
    CollaborationRole role,
    Duration validity,
  ) => throw UnimplementedError();

  @override
  Future<void> leaveRoom() async {}

  @override
  Future<void> removeMember(String uid) async {}

  @override
  Future<void> retryOutboxNow() async {}

  @override
  Future<void> updateMemberRole(String uid, CollaborationRole role) async {}
}

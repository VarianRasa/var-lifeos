import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/collaboration_room.dart';

final class ActiveCollaborationSession {
  const ActiveCollaborationSession({
    required this.roomId,
    required this.target,
    required this.uid,
    required this.role,
  });

  final String roomId;
  final CollaborationTarget target;
  final String uid;
  final CollaborationRole role;
  String? get dayKey => target.dayKey;
  bool get canWriteNodes => role.canWriteNodes;
}

abstract interface class ActiveCollaborationSessionReader {
  ActiveCollaborationSession? get current;
}

final class ActiveCollaborationSessionState
    extends StateNotifier<ActiveCollaborationSession?>
    implements ActiveCollaborationSessionReader {
  ActiveCollaborationSessionState() : super(null);

  @override
  ActiveCollaborationSession? get current => state;

  void set(ActiveCollaborationSession? value) => state = value;
}

final activeCollaborationSessionProvider =
    StateNotifierProvider<
      ActiveCollaborationSessionState,
      ActiveCollaborationSession?
    >((ref) => ActiveCollaborationSessionState());

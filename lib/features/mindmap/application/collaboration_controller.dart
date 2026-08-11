import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:var_app/core/router/app_router.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/mindmap/application/collaboration_board_sync_service.dart';
import 'package:var_app/features/mindmap/application/collaboration_node_sync_service.dart';
import 'package:var_app/features/mindmap/application/collaboration_session.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/application/node_comment_controller.dart';
import 'package:var_app/features/mindmap/data/collaboration_canvas_board_repository.dart';
import 'package:var_app/features/mindmap/data/collaboration_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/collaboration_board_sync.dart';
import 'package:var_app/features/mindmap/domain/collaboration_node_sync.dart';
import 'package:var_app/features/mindmap/domain/collaboration_room.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/application/sync_controller.dart';

class Collaborator {
  Collaborator({
    required this.id,
    required this.name,
    required this.color,
    required this.cursorPosition,
    this.selectedNodeId,
    this.isEditing = false,
  });

  final String id;
  final String name;
  final Color color;
  final Offset? cursorPosition;
  final String? selectedNodeId;
  final bool isEditing;

  Collaborator copyWith({
    Offset? cursorPosition,
    String? selectedNodeId,
    bool? isEditing,
  }) {
    return Collaborator(
      id: id,
      name: name,
      color: color,
      cursorPosition: cursorPosition ?? this.cursorPosition,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
      isEditing: isEditing ?? this.isEditing,
    );
  }
}

/// Short-lived visual ping (ripple) emitted by a collaborator at a scene position.
class PingEvent {
  PingEvent({
    required this.id,
    required this.fromId,
    required this.fromName,
    required this.color,
    required this.scenePosition,
    required this.createdAt,
  });

  final String id;
  final String fromId;
  final String fromName;
  final Color color;
  final Offset scenePosition;
  final DateTime createdAt;
}

class ReactionEvent {
  const ReactionEvent({
    required this.id,
    required this.fromId,
    required this.emoji,
    required this.createdAt,
  });

  final String id;
  final String fromId;
  final String emoji;
  final DateTime createdAt;
}

class CollaborationState {
  CollaborationState({
    required this.collaborators,
    required this.isDemoMode,
    required this.isConnected,
    this.roomId,
    this.roomDay,
    this.roomTarget,
    this.currentRole,
    this.members = const [],
    required this.localUserId,
    required this.localName,
    required this.localColor,
    this.roomHistory = const [],
    this.reactionTotals = const <String, int>{},
    this.recentReactions = const <ReactionEvent>[],
    this.boardComments = const <String, List<CanvasObjectComment>>{},
  });

  final Map<String, Collaborator> collaborators;
  final bool isDemoMode;
  final bool isConnected;
  final String? roomId;
  final String? roomDay;
  final CollaborationTarget? roomTarget;
  final CollaborationRole? currentRole;
  final List<CollaborationMember> members;
  final String localUserId;
  final String localName;
  final Color localColor;
  final List<String> roomHistory;
  final Map<String, int> reactionTotals;
  final List<ReactionEvent> recentReactions;
  final Map<String, List<CanvasObjectComment>> boardComments;

  CollaborationState copyWith({
    Map<String, Collaborator>? collaborators,
    bool? isDemoMode,
    bool? isConnected,
    String? roomId,
    String? roomDay,
    CollaborationTarget? roomTarget,
    CollaborationRole? currentRole,
    List<CollaborationMember>? members,
    bool clearRoom = false,
    String? localUserId,
    String? localName,
    Color? localColor,
    List<String>? roomHistory,
    Map<String, int>? reactionTotals,
    List<ReactionEvent>? recentReactions,
    Map<String, List<CanvasObjectComment>>? boardComments,
  }) {
    return CollaborationState(
      collaborators: collaborators ?? this.collaborators,
      isDemoMode: isDemoMode ?? this.isDemoMode,
      isConnected: isConnected ?? this.isConnected,
      roomId: clearRoom ? null : roomId ?? this.roomId,
      roomDay: clearRoom ? null : roomDay ?? this.roomDay,
      roomTarget: clearRoom ? null : roomTarget ?? this.roomTarget,
      currentRole: clearRoom ? null : currentRole ?? this.currentRole,
      members: clearRoom ? const [] : members ?? this.members,
      localUserId: localUserId ?? this.localUserId,
      localName: localName ?? this.localName,
      localColor: localColor ?? this.localColor,
      roomHistory: roomHistory ?? this.roomHistory,
      reactionTotals: clearRoom
          ? const <String, int>{}
          : reactionTotals ?? this.reactionTotals,
      recentReactions: clearRoom
          ? const <ReactionEvent>[]
          : recentReactions ?? this.recentReactions,
      boardComments: clearRoom
          ? const <String, List<CanvasObjectComment>>{}
          : boardComments ?? this.boardComments,
    );
  }
}

abstract interface class CollaborationActions {
  Future<String> createProjectRoom({
    required String boardId,
    required String label,
  });

  Future<void> openRoomChecked(
    String urlOrId, {
    CollaborationTarget? expectedTarget,
    bool navigate = true,
  });

  Future<void> acceptInvite(String link);

  Future<CollaborationInvite> createInvite(
    String email,
    CollaborationRole role,
    Duration validity,
  );

  Future<void> updateMemberRole(String uid, CollaborationRole role);

  Future<void> removeMember(String uid);

  Future<void> retryOutboxNow();

  Future<void> leaveRoom();
}

class CollaborationNotifier extends StateNotifier<CollaborationState>
    implements CollaborationActions {
  /// Time a ping document stays valid in Firestore before peers can drop it.
  /// Matches the maximum ripple animation duration (≈900ms) plus generous slack
  /// for late-joining clients and reconnect grace.
  static const Duration _pingTtl = Duration(seconds: 30);

  CollaborationNotifier(this._ref)
    : super(
        CollaborationState(
          collaborators: {},
          isDemoMode: false,
          isConnected: true,
          localUserId: const Uuid().v4(),
          localName: 'User',
          localColor: _randomColor(),
          roomHistory: const [],
        ),
      ) {
    _loadHistory();
    // Late init local name based on sync device name if available
    Future.microtask(() {
      try {
        final syncState = _ref.read(syncControllerProvider);
        final String? label = syncState.deviceIdentity?.label;
        if (label != null && label.trim().isNotEmpty) {
          state = state.copyWith(localName: label.trim());
        } else {
          state = state.copyWith(
            localName: 'User-${state.localUserId.substring(0, 4)}',
          );
        }
      } catch (_) {}
    });
  }

  final Ref _ref;
  Timer? _simulationTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _membersFirestoreSub;
  CollaborationNodeSyncService? _nodeSyncService;
  CollaborationBoardSyncService? _boardSyncService;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pingsFirestoreSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _reactionsFirestoreSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _boardCommentsFirestoreSub;
  final _random = Random();
  bool _presencePrivacyMode = false;
  static const Duration presenceTtl = Duration(minutes: 2);

  /// Broadcast stream of pings received from peers. UI subscribes to render ripples.
  final StreamController<PingEvent> _pingsController =
      StreamController<PingEvent>.broadcast();
  Stream<PingEvent> get pingStream => _pingsController.stream;

  SharedPreferencesAsync? get _prefs {
    try {
      return SharedPreferencesAsync();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = _prefs;
      if (prefs == null) return;
      final list = await prefs.getStringList('collab_room_history');
      if (list != null) {
        state = state.copyWith(roomHistory: list);
      }
    } catch (_) {}
  }

  Future<void> _addToHistory(String roomId) async {
    if (roomId.isEmpty) return;
    final current = List<String>.from(state.roomHistory);
    current.remove(roomId);
    current.insert(0, roomId);
    if (current.length > 5) {
      current.removeLast();
    }
    state = state.copyWith(roomHistory: current);
    try {
      final prefs = _prefs;
      if (prefs != null) {
        await prefs.setStringList('collab_room_history', current);
      }
    } catch (_) {}
  }

  static Color _randomColor() {
    final colors = [
      Colors.amberAccent,
      Colors.cyanAccent,
      Colors.pinkAccent,
      Colors.yellowAccent,
      Colors.lightGreenAccent,
      Colors.deepOrangeAccent,
      Colors.purpleAccent,
    ];
    return colors[Random().nextInt(colors.length)];
  }

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  static String cleanRoomId(String urlOrId) =>
      CollaborationRoomLink.tryParse(urlOrId)?.roomId ?? '';

  User _eligibleUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const CollaborationException(
        CollaborationErrorCode.unauthenticated,
        'Sign in to use collaboration.',
      );
    }
    if (user.isAnonymous || !user.emailVerified || user.email == null) {
      throw const CollaborationException(
        CollaborationErrorCode.emailNotVerified,
        'Verified email account required.',
      );
    }
    return user;
  }

  FirebaseFirestore _requiredFirestore() {
    return _firestore ??
        (throw const CollaborationException(
          CollaborationErrorCode.unavailable,
          'Collaboration unavailable on this platform.',
        ));
  }

  Future<String> createRoom(DateTime day) =>
      createRoomForTarget(CollaborationTarget.day(dayKey(day)));

  @override
  Future<String> createProjectRoom({
    required String boardId,
    required String label,
  }) async {
    final normalizedBoardId = boardId.trim();
    final normalizedLabel = label.trim();
    if (normalizedBoardId.isEmpty ||
        normalizedLabel.isEmpty ||
        normalizedLabel.length > 160) {
      throw const CollaborationException(
        CollaborationErrorCode.invalidInput,
        'Valid board and label up to 160 characters required.',
      );
    }
    final repository = _ref.read(canvasBoardRepositoryProvider);
    final board = await repository.getBoard(normalizedBoardId);
    if (board == null || board.kind != CanvasBoardKind.project) {
      throw const CollaborationException(
        CollaborationErrorCode.notFound,
        'Project board not found.',
      );
    }

    final target = CollaborationTarget.projectBoard(
      boardId: normalizedBoardId,
      label: normalizedLabel,
    );
    final user = _eligibleUser();
    final fs = _requiredFirestore();
    final roomId = const Uuid().v4();
    final mutationId = const Uuid().v4();
    final roomRef = fs.collection('rooms').doc(roomId);
    final envelope = CollaborationBoardEnvelope(
      boardId: board.id,
      revision: 1,
      payload: collaborationBoardPayload(board.toJson()),
      createdByUid: user.uid,
      updatedByUid: user.uid,
      lastMutationId: mutationId,
    );
    final batch = fs.batch();
    batch.set(roomRef, {
      'schemaVersion': CollaborationRoom.currentSchemaVersion,
      'ownerUid': user.uid,
      ...target.toRoomJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(roomRef.collection('members').doc(user.uid), {
      'uid': user.uid,
      'email': normalizeCollaborationEmail(user.email!),
      'displayName': user.displayName ?? user.email!,
      'role': CollaborationRole.owner.name,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.set(roomRef.collection('boards').doc(board.id), {
      ...envelope.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      await batch.commit();
      if (!await openRoom(roomId, expectedTarget: target, navigate: false)) {
        throw const CollaborationException(
          CollaborationErrorCode.unknown,
          'Room created but could not be opened.',
        );
      }
      return roomId;
    } on FirebaseException catch (error) {
      throw _fromFirebase(error);
    }
  }

  Future<String> createRoomForTarget(CollaborationTarget target) async {
    if (target.kind == CollaborationTargetKind.projectBoard) {
      return createProjectRoom(boardId: target.id, label: target.label);
    }
    if (!target.isValid) {
      throw const CollaborationException(
        CollaborationErrorCode.invalidInput,
        'Invalid collaboration target.',
      );
    }
    final user = _eligibleUser();
    final fs = _requiredFirestore();
    final roomId = const Uuid().v4();
    final roomRef = fs.collection('rooms').doc(roomId);
    final batch = fs.batch();
    batch.set(roomRef, {
      'schemaVersion': CollaborationRoom.currentSchemaVersion,
      'ownerUid': user.uid,
      ...target.toRoomJson(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(roomRef.collection('members').doc(user.uid), {
      'uid': user.uid,
      'email': normalizeCollaborationEmail(user.email!),
      'displayName': user.displayName ?? user.email!,
      'role': CollaborationRole.owner.name,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    try {
      await batch.commit();
      if (!await openRoom(roomId, expectedTarget: target, navigate: false)) {
        throw const CollaborationException(
          CollaborationErrorCode.unknown,
          'Room created but could not be opened.',
        );
      }
      return roomId;
    } on FirebaseException catch (error) {
      throw _fromFirebase(error);
    }
  }

  @override
  Future<CollaborationInvite> createInvite(
    String email,
    CollaborationRole role,
    Duration validity,
  ) async {
    final user = _eligibleUser();
    final fs = _requiredFirestore();
    final roomId = state.roomId;
    if (roomId == null || state.currentRole != CollaborationRole.owner) {
      throw const CollaborationException(
        CollaborationErrorCode.permissionDenied,
        'Room owner access required.',
      );
    }
    final normalizedEmail = normalizeCollaborationEmail(email);
    if (!normalizedEmail.contains('@') ||
        role == CollaborationRole.owner ||
        validity <= Duration.zero ||
        validity > const Duration(days: 7)) {
      throw const CollaborationException(
        CollaborationErrorCode.invalidInput,
        'Valid email, member role, and validity up to 7 days required.',
      );
    }
    final inviteId = const Uuid().v4();
    final now = DateTime.now();
    final invite = CollaborationInvite(
      id: inviteId,
      roomId: roomId,
      email: normalizedEmail,
      role: role,
      status: CollaborationInviteStatus.active,
      createdByUid: user.uid,
      createdAt: now,
      expiresAt: now.add(validity),
    );
    try {
      await fs
          .collection('rooms')
          .doc(roomId)
          .collection('invites')
          .doc(inviteId)
          .set({
            'inviteId': inviteId,
            'roomId': roomId,
            'email': normalizedEmail,
            'role': role.name,
            'status': CollaborationInviteStatus.active.name,
            'createdAt': FieldValue.serverTimestamp(),
            'expiresAt': Timestamp.fromDate(invite.expiresAt),
            'createdByUid': user.uid,
          });
      return invite;
    } on FirebaseException catch (error) {
      throw _fromFirebase(error);
    }
  }

  @override
  Future<void> acceptInvite(String link) async {
    final parsed = CollaborationInviteLink.tryParse(link);
    if (parsed == null) {
      throw const CollaborationException(
        CollaborationErrorCode.invalidInput,
        'Invalid invite link.',
      );
    }
    final user = _eligibleUser();
    final fs = _requiredFirestore();
    final roomRef = fs.collection('rooms').doc(parsed.roomId);
    final inviteRef = roomRef.collection('invites').doc(parsed.inviteId);
    final memberRef = roomRef.collection('members').doc(user.uid);
    try {
      await fs.runTransaction((transaction) async {
        final inviteDoc = await transaction.get(inviteRef);
        final data = inviteDoc.data();
        if (data == null) {
          throw const CollaborationException(
            CollaborationErrorCode.notFound,
            'Invite not found.',
          );
        }
        if (data['status'] != CollaborationInviteStatus.active.name) {
          throw const CollaborationException(
            CollaborationErrorCode.inviteUsed,
            'Invite no longer active.',
          );
        }
        final expiresAt = data['expiresAt'];
        if (expiresAt is! Timestamp ||
            !expiresAt.toDate().isAfter(DateTime.now())) {
          throw const CollaborationException(
            CollaborationErrorCode.inviteExpired,
            'Invite expired.',
          );
        }
        if (data['email'] != normalizeCollaborationEmail(user.email!)) {
          throw const CollaborationException(
            CollaborationErrorCode.permissionDenied,
            'Invite belongs to another email.',
          );
        }
        final role = collaborationRoleFromString(data['role'] as String);
        transaction.update(inviteRef, {
          'status': CollaborationInviteStatus.redeemed.name,
          'redeemedByUid': user.uid,
          'redeemedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(memberRef, {
          'uid': user.uid,
          'email': normalizeCollaborationEmail(user.email!),
          'displayName': user.displayName ?? user.email!,
          'role': role.name,
          'joinedAt': FieldValue.serverTimestamp(),
          'inviteId': parsed.inviteId,
        });
      });
      await openRoomChecked(parsed.roomId);
    } on FirebaseException catch (error) {
      throw _fromFirebase(error);
    }
  }

  @override
  Future<void> updateMemberRole(String uid, CollaborationRole role) async {
    if (role == CollaborationRole.owner ||
        state.currentRole != CollaborationRole.owner ||
        state.roomId == null) {
      throw const CollaborationException(
        CollaborationErrorCode.permissionDenied,
        'Owner can assign non-owner roles only.',
      );
    }
    try {
      await _requiredFirestore()
          .collection('rooms')
          .doc(state.roomId)
          .collection('members')
          .doc(uid)
          .update({'role': role.name});
    } on FirebaseException catch (error) {
      throw _fromFirebase(error);
    }
  }

  @override
  Future<void> removeMember(String uid) async {
    if (state.currentRole != CollaborationRole.owner || state.roomId == null) {
      throw const CollaborationException(
        CollaborationErrorCode.permissionDenied,
        'Room owner access required.',
      );
    }
    try {
      await _requiredFirestore()
          .collection('rooms')
          .doc(state.roomId)
          .collection('members')
          .doc(uid)
          .delete();
    } on FirebaseException catch (error) {
      throw _fromFirebase(error);
    }
  }

  CollaborationException _fromFirebase(FirebaseException error) {
    final code = switch (error.code) {
      'permission-denied' => CollaborationErrorCode.permissionDenied,
      'not-found' => CollaborationErrorCode.notFound,
      'unauthenticated' => CollaborationErrorCode.unauthenticated,
      'unavailable' => CollaborationErrorCode.unavailable,
      _ => CollaborationErrorCode.unknown,
    };
    return CollaborationException(
      code,
      error.message ?? 'Collaboration failed.',
    );
  }

  Future<bool> joinRoom(String urlOrId, {String? dayKey}) => openRoom(
    urlOrId,
    expectedTarget: dayKey == null ? null : CollaborationTarget.day(dayKey),
  );

  Future<bool> joinTargetRoom(
    String urlOrId, {
    required CollaborationTarget target,
  }) => openRoom(urlOrId, expectedTarget: target);

  Future<bool> openRoom(
    String urlOrId, {
    CollaborationTarget? expectedTarget,
    bool navigate = true,
  }) async {
    try {
      await openRoomChecked(
        urlOrId,
        expectedTarget: expectedTarget,
        navigate: navigate,
      );
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Collab: Exception during openRoom: $error\n$stackTrace');
      return false;
    }
  }

  @override
  Future<void> openRoomChecked(
    String urlOrId, {
    CollaborationTarget? expectedTarget,
    bool navigate = true,
  }) async {
    final roomId = cleanRoomId(urlOrId);
    if (roomId.isEmpty) {
      throw const CollaborationException(
        CollaborationErrorCode.invalidInput,
        'Invalid collaboration room link.',
      );
    }

    final user = _eligibleUser();
    final fs = _requiredFirestore();

    try {
      final roomRef = fs.collection('rooms').doc(roomId);
      final roomDoc = await roomRef.get();
      final roomData = roomDoc.data();
      if (!roomDoc.exists || roomData == null) {
        throw const CollaborationException(
          CollaborationErrorCode.notFound,
          'Collaboration room not found.',
        );
      }
      final schemaVersion = roomData['schemaVersion'] as int?;
      if (schemaVersion != 2 && schemaVersion != 3) {
        throw const CollaborationException(
          CollaborationErrorCode.invalidInput,
          'Collaboration room format is unsupported.',
        );
      }
      final memberDoc = await roomRef.collection('members').doc(user.uid).get();
      if (!memberDoc.exists) {
        throw const CollaborationException(
          CollaborationErrorCode.permissionDenied,
          'Room membership or invite required.',
        );
      }
      final target = CollaborationTarget.fromRoomJson(
        Map<String, Object?>.from(roomData),
      );
      if (expectedTarget != null &&
          (expectedTarget.kind != target.kind ||
              expectedTarget.id != target.id)) {
        throw const CollaborationException(
          CollaborationErrorCode.invalidInput,
          'Collaboration room targets another board or day.',
        );
      }
      final memberData = memberDoc.data();
      if (memberData == null) {
        throw const CollaborationException(
          CollaborationErrorCode.permissionDenied,
          'Room membership is invalid.',
        );
      }
      final currentRole = collaborationRoleFromString(
        memberData['role'] as String,
      );
      await leaveRoom();
      state = state.copyWith(
        roomId: roomId,
        roomDay: target.dayKey,
        roomTarget: target,
        currentRole: currentRole,
        isDemoMode: false,
        isConnected: true,
        collaborators: {},
        localUserId: user.uid,
        localName: user.displayName ?? user.email ?? 'User',
      );
      _ref
          .read(activeCollaborationSessionProvider.notifier)
          .set(
            ActiveCollaborationSession(
              roomId: roomId,
              target: target,
              uid: user.uid,
              role: currentRole,
            ),
          );
      await _addToHistory(roomId);

      final targetDayKey = target.dayKey;
      if (navigate && targetDayKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            debugPrint('Collab: Navigating to day: $targetDayKey');
            _ref.read(appRouterProvider).go('/calendar/$targetDayKey');
          } catch (e) {
            debugPrint('Collab: GoRouter navigation failed: $e');
          }
        });
      }

      _membersFirestoreSub = roomRef.collection('members').snapshots().listen((
        snapshot,
      ) async {
        final members = snapshot.docs.map((document) {
          final data = document.data();
          final joinedAt = data['joinedAt'];
          return CollaborationMember(
            uid: document.id,
            email: data['email'] as String? ?? '',
            displayName: data['displayName'] as String? ?? '',
            role: collaborationRoleFromString(data['role'] as String),
            joinedAt: joinedAt is Timestamp
                ? joinedAt.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0),
          );
        }).toList();
        final local = members
            .where((member) => member.uid == user.uid)
            .firstOrNull;
        if (local == null) {
          _ref.read(activeCollaborationSessionProvider.notifier).set(null);
          await _nodeSyncService?.setWritePermission(
            false,
            'membership-revoked',
          );
          await _boardSyncService?.setWritePermission(
            false,
            'membership-revoked',
          );
          await _nodeSyncService?.stop(stopWrites: true);
          await _boardSyncService?.stop(stopWrites: true);
          state = state.copyWith(
            members: members,
            currentRole: CollaborationRole.viewer,
            isConnected: false,
          );
          return;
        }
        _ref
            .read(activeCollaborationSessionProvider.notifier)
            .set(
              ActiveCollaborationSession(
                roomId: roomId,
                target: target,
                uid: user.uid,
                role: local.role,
              ),
            );
        await _nodeSyncService?.setWritePermission(
          local.role.canWriteNodes,
          'role-${local.role.name}',
        );
        await _boardSyncService?.setWritePermission(
          local.role.canWriteNodes,
          'role-${local.role.name}',
        );
        state = state.copyWith(members: members, currentRole: local.role);
      });

      _firestoreSub = roomRef
          .collection('presence')
          .snapshots()
          .listen(
            (snapshot) {
              final peers = <String, Collaborator>{};
              for (final doc in snapshot.docs) {
                if (doc.id == state.localUserId) continue;
                final data = doc.data();
                final lastActive = data['lastActive'];
                if (lastActive is! Timestamp ||
                    DateTime.now().difference(lastActive.toDate()) >
                        presenceTtl) {
                  continue;
                }
                final name = data['name'] as String? ?? 'Unknown';
                final colorVal =
                    data['color'] as int? ?? Colors.blue.toARGB32();
                final cursorX = data['cursorX'] as num?;
                final cursorY = data['cursorY'] as num?;
                final selectedNodeId = data['selectedNodeId'] as String?;
                final isEditing = data['isEditing'] as bool? ?? false;

                peers[doc.id] = Collaborator(
                  id: doc.id,
                  name: name,
                  color: Color(colorVal),
                  cursorPosition: cursorX != null && cursorY != null
                      ? Offset(cursorX.toDouble(), cursorY.toDouble())
                      : null,
                  selectedNodeId: selectedNodeId,
                  isEditing: isEditing,
                );
              }
              state = state.copyWith(collaborators: peers, isConnected: true);
            },
            onError: (_) {
              state = state.copyWith(isConnected: false);
            },
          );

      final repository = _ref.read(mindmapRepositoryProvider);
      if (target.kind == CollaborationTargetKind.day &&
          repository is CollaborationMindmapRepository) {
        _nodeSyncService = CollaborationNodeSyncService(
          firestore: fs,
          store: _ref.read(collaborationSyncStoreProvider),
          repository: repository,
        );
        await _nodeSyncService!.start(roomId);
      }
      final boardRepository = _ref.read(canvasBoardRepositoryProvider);
      if (target.kind == CollaborationTargetKind.projectBoard) {
        if (boardRepository is! CollaborationCanvasBoardRepository) {
          throw const CollaborationException(
            CollaborationErrorCode.unavailable,
            'Project board collaboration is unavailable.',
          );
        }
        _boardSyncService = CollaborationBoardSyncService(
          firestore: fs,
          store: _ref.read(collaborationBoardSyncStoreProvider),
          repository: boardRepository,
          onRemoteApplied: () {
            _ref.invalidate(projectCanvasBoardsProvider);
            _ref.invalidate(projectCanvasBoardProvider);
          },
        );
        try {
          await _boardSyncService!.start(
            roomId: roomId,
            boardId: target.id,
            uid: state.localUserId,
          );
        } on FormatException {
          throw const CollaborationException(
            CollaborationErrorCode.invalidInput,
            'Shared project board is invalid.',
          );
        } on StateError {
          throw const CollaborationException(
            CollaborationErrorCode.notFound,
            'Shared project board is missing.',
          );
        }
      }

      // Subscribe to pings -> emit to local UI stream for ripple render
      _pingsFirestoreSub = roomRef
          .collection('pings')
          .orderBy('t', descending: true)
          .limit(20)
          .snapshots()
          .listen((snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final data = change.doc.data();
              if (data == null) continue;
              final fromId = data['fromId'] as String? ?? '';
              if (fromId == state.localUserId) continue; // ignore own echo
              final x = data['x'] as num?;
              final y = data['y'] as num?;
              if (x == null || y == null) continue;
              final t =
                  data['t'] as int? ?? DateTime.now().millisecondsSinceEpoch;
              if (DateTime.now().millisecondsSinceEpoch - t > 5000) continue;
              final colorVal = data['color'] as int? ?? Colors.cyan.toARGB32();
              _pingsController.add(
                PingEvent(
                  id: change.doc.id,
                  fromId: fromId,
                  fromName: data['fromName'] as String? ?? 'Peer',
                  color: Color(colorVal),
                  scenePosition: Offset(x.toDouble(), y.toDouble()),
                  createdAt: DateTime.fromMillisecondsSinceEpoch(t),
                ),
              );
            }
          }, onError: (_) {});

      _reactionsFirestoreSub = roomRef
          .collection('reactions')
          .orderBy('t', descending: true)
          .limit(30)
          .snapshots()
          .listen((snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type != DocumentChangeType.added) continue;
              final data = change.doc.data();
              if (data == null) continue;
              final emoji = data['emoji'] as String? ?? '';
              final fromId = data['fromId'] as String? ?? '';
              final timestamp = data['t'] as int? ?? 0;
              if (emoji.isEmpty ||
                  DateTime.now().millisecondsSinceEpoch - timestamp > 5000) {
                continue;
              }
              final event = ReactionEvent(
                id: change.doc.id,
                fromId: fromId,
                emoji: emoji,
                createdAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
              );
              state = state.copyWith(
                reactionTotals: <String, int>{
                  ...state.reactionTotals,
                  emoji: (state.reactionTotals[emoji] ?? 0) + 1,
                },
                recentReactions: <ReactionEvent>[
                  ...state.recentReactions,
                  event,
                ],
              );
              Timer(const Duration(seconds: 5), () {
                if (!mounted) return;
                state = state.copyWith(
                  recentReactions: state.recentReactions
                      .where((reaction) => reaction.id != event.id)
                      .toList(growable: false),
                );
              });
            }
          }, onError: (_) {});

      if (target.kind == CollaborationTargetKind.projectBoard) {
        _boardCommentsFirestoreSub = roomRef
            .collection('boardComments')
            .snapshots()
            .listen((snapshot) {
              final grouped = <String, List<CanvasObjectComment>>{};
              for (final document in snapshot.docs) {
                final data = document.data();
                final objectId = data['objectId'] as String? ?? '';
                if (objectId.isEmpty) continue;
                try {
                  final comment = CanvasObjectComment(
                    id: document.id,
                    body: data['body'] as String? ?? '',
                    authorName: data['authorName'] as String? ?? '',
                    createdAt: data['createdAt'] is Timestamp
                        ? (data['createdAt']! as Timestamp).toDate()
                        : DateTime.fromMillisecondsSinceEpoch(0),
                    parentId: data['parentId'] as String?,
                    isResolved: data['isResolved'] as bool? ?? false,
                  );
                  grouped.putIfAbsent(objectId, () => []).add(comment);
                } on FormatException {
                  continue;
                }
              }
              for (final comments in grouped.values) {
                comments.sort(
                  (left, right) => left.createdAt.compareTo(right.createdAt),
                );
              }
              state = state.copyWith(boardComments: grouped);
            }, onError: (_) {});
      }

      await _uploadLocalState();

      if (navigate && target.kind == CollaborationTargetKind.projectBoard) {
        final board = await boardRepository.getBoard(target.id);
        final workspaceName = board?.workspaceName;
        if (board == null || workspaceName == null) {
          throw const CollaborationException(
            CollaborationErrorCode.invalidInput,
            'Shared project board has no workspace target.',
          );
        }
        final location = projectCanvasLocation(
          workspaceName: workspaceName,
          boardId: board.id,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _ref.read(appRouterProvider).go(location);
          } on Object catch (error) {
            debugPrint('Collab: Project navigation failed: $error');
          }
        });
      }

      return;
    } on CollaborationException {
      await leaveRoom();
      rethrow;
    } on FirebaseException catch (error) {
      await leaveRoom();
      throw _fromFirebase(error);
    } on FormatException {
      await leaveRoom();
      throw const CollaborationException(
        CollaborationErrorCode.invalidInput,
        'Collaboration room data is invalid.',
      );
    } on Object catch (error, stackTrace) {
      await leaveRoom();
      debugPrint('Collab: Exception during openRoom: $error\n$stackTrace');
      throw const CollaborationException(
        CollaborationErrorCode.unknown,
        'Collaboration room could not be opened.',
      );
    }
  }

  Future<void> bindNode(MindmapNode node) async {
    final session = _ref.read(activeCollaborationSessionProvider);
    final repository = _ref.read(mindmapRepositoryProvider);
    if (session == null ||
        state.roomId != session.roomId ||
        repository is! CollaborationMindmapRepository) {
      throw const CollaborationException(
        CollaborationErrorCode.permissionDenied,
        'Active collaboration room required.',
      );
    }
    final latest = await repository.getNode(node.id);
    if (latest == null) {
      throw const CollaborationException(
        CollaborationErrorCode.notFound,
        'Node not found.',
      );
    }
    final usesLatest = node == latest;
    final publishNode = usesLatest ? latest : node;
    await repository.bindAndPublish(
      publishNode,
      session,
      persistLocally: usesLatest,
    );
    await _nodeSyncService?.drain();
    _invalidateNodeCollaboration(session.roomId, node.id);
  }

  Future<void> unbindNode(String localNodeId) async {
    final session = _ref.read(activeCollaborationSessionProvider);
    final repository = _ref.read(mindmapRepositoryProvider);
    if (session == null ||
        state.roomId != session.roomId ||
        repository is! CollaborationMindmapRepository) {
      throw const CollaborationException(
        CollaborationErrorCode.permissionDenied,
        'Active collaboration room required.',
      );
    }
    await repository.unbindNode(localNodeId, session);
    _invalidateNodeCollaboration(session.roomId, localNodeId);
  }

  void _invalidateNodeCollaboration(String roomId, String localNodeId) {
    _ref.invalidate(boundRoomNodesProvider(roomId));
    _ref.invalidate(
      nodeCommentThreadProvider(NodeCommentThreadKey(roomId, localNodeId)),
    );
  }

  Future<List<CollaborationNodeConflict>> listConflicts(String roomId) async {
    final service = _nodeSyncService;
    if (service == null || state.roomId != roomId) return const [];
    return service.listConflicts(roomId);
  }

  @override
  Future<void> retryOutboxNow() async {
    await _nodeSyncService?.retryNow();
    await _boardSyncService?.drain();
  }

  Future<List<CollaborationBoardConflict>> listBoardConflicts(
    String roomId,
  ) async {
    final service = _boardSyncService;
    if (service == null || state.roomId != roomId) return const [];
    return service.listConflicts(roomId);
  }

  Future<void> resolveBoardConflict(
    CollaborationBoardConflict conflict, {
    required bool keepRemote,
  }) async {
    final service = _boardSyncService;
    if (service == null || state.roomId != conflict.roomId) {
      throw StateError('Collaboration board sync is not active for this room.');
    }
    if (keepRemote) {
      await service.resolveKeepRemote(conflict);
    } else {
      await service.resolveKeepMine(conflict);
    }
    _ref.invalidate(collaborationBoardConflictsProvider(conflict.roomId));
  }

  Future<void> resolveConflict(
    CollaborationNodeConflict conflict, {
    required bool keepRemote,
  }) async {
    final service = _nodeSyncService;
    if (service == null || state.roomId != conflict.roomId) {
      throw StateError('Collaboration sync is not active for this room.');
    }
    if (keepRemote) {
      await service.resolveKeepRemote(conflict);
    } else {
      await service.resolveKeepMine(conflict);
    }
    _ref.invalidate(collaborationConflictsProvider(conflict.roomId));
  }

  @override
  Future<void> leaveRoom() async {
    final fs = _firestore;
    final roomId = state.roomId;
    final localUserId = state.localUserId;
    if (fs != null && roomId != null) {
      try {
        await fs
            .collection('rooms')
            .doc(roomId)
            .collection('presence')
            .doc(localUserId)
            .delete();
      } on Object catch (error) {
        debugPrint('Collab: Presence cleanup failed: $error');
      }
    }
    _simulationTimer?.cancel();
    await _firestoreSub?.cancel();
    _firestoreSub = null;
    await _membersFirestoreSub?.cancel();
    _membersFirestoreSub = null;
    await _nodeSyncService?.stop();
    _nodeSyncService = null;
    await _boardSyncService?.stop();
    _boardSyncService = null;
    _ref.read(activeCollaborationSessionProvider.notifier).set(null);
    await _pingsFirestoreSub?.cancel();
    _pingsFirestoreSub = null;
    await _reactionsFirestoreSub?.cancel();
    _reactionsFirestoreSub = null;
    await _boardCommentsFirestoreSub?.cancel();
    _boardCommentsFirestoreSub = null;
    state = state.copyWith(
      clearRoom: true,
      collaborators: {},
      isConnected: false,
    );
  }

  DateTime _lastUploadTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _uploadLocalState({
    Offset? cursorPosition,
    String? selectedNodeId,
    bool? isEditing,
  }) async {
    final fs = _firestore;
    final rId = state.roomId;
    if (fs == null || rId == null) return;

    // Rate-limit cursor moves, but allow click/edit changes immediately
    final now = DateTime.now();
    if (cursorPosition != null &&
        selectedNodeId == null &&
        isEditing == null &&
        now.difference(_lastUploadTime).inMilliseconds < 50) {
      return;
    }
    _lastUploadTime = now;

    try {
      final privacyMode = _presencePrivacyMode;
      await fs
          .collection('rooms')
          .doc(rId)
          .collection('presence')
          .doc(state.localUserId)
          .set({
            'name': state.localName,
            'color': state.localColor.toARGB32(),
            if (!privacyMode && cursorPosition != null)
              'cursorX': cursorPosition.dx,
            if (!privacyMode && cursorPosition != null)
              'cursorY': cursorPosition.dy,
            'selectedNodeId': privacyMode ? null : selectedNodeId,
            'isEditing': privacyMode ? false : isEditing ?? false,
            'lastActive': FieldValue.serverTimestamp(),
          });
    } catch (_) {}
  }

  Future<void> setPresencePrivacyMode(bool enabled) async {
    if (_presencePrivacyMode == enabled) return;
    _presencePrivacyMode = enabled;
    await _uploadLocalState();
  }

  void toggleDemoMode(bool enable) {
    if (enable) {
      leaveRoom().then((_) {
        state = state.copyWith(isDemoMode: true);
        _startDemoSimulation();
      });
    } else {
      _simulationTimer?.cancel();
      state = state.copyWith(isDemoMode: false, collaborators: {});
    }
  }

  // Broadcast local user cursor position
  void updateLocalCursor(Offset position) {
    if (state.roomId != null) {
      _uploadLocalState(cursorPosition: position);
    }
  }

  // Broadcast local user node selection
  void updateLocalSelection(String? nodeId, {bool isEditing = false}) {
    if (state.roomId != null) {
      _uploadLocalState(selectedNodeId: nodeId, isEditing: isEditing);
    }
  }

  /// Broadcast a short-lived visual ping at a scene position. Peers see an
  /// expanding ripple — useful for "look here" callouts during a session.
  Future<void> broadcastPing(Offset scenePosition) async {
    final fs = _firestore;
    final rId = state.roomId;
    final role = state.currentRole;
    if (fs == null || rId == null || role == null || !role.canPing) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await fs.collection('rooms').doc(rId).collection('pings').add({
        'fromId': state.localUserId,
        'fromName': state.localName,
        'color': state.localColor.toARGB32(),
        'x': scenePosition.dx,
        'y': scenePosition.dy,
        't': now,
        // TTL window — clients garbage-collect expired pings on join.
        'expiresAt': now + _pingTtl.inMilliseconds,
      });
    } catch (_) {}
  }

  Future<void> broadcastReaction(String emoji) async {
    final fs = _firestore;
    final roomId = state.roomId;
    final role = state.currentRole;
    if (fs == null ||
        roomId == null ||
        role == null ||
        !role.canReact ||
        emoji.isEmpty ||
        emoji.length > 16) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await fs.collection('rooms').doc(roomId).collection('reactions').add({
      'fromId': state.localUserId,
      'emoji': emoji,
      't': now,
      'expiresAt': now + const Duration(seconds: 5).inMilliseconds,
    });
  }

  Future<void> changeProjectBoardVotes({
    required String boardId,
    required Iterable<String> objectIds,
    required int delta,
  }) async {
    final fs = _firestore;
    final roomId = state.roomId;
    final role = state.currentRole;
    if (fs == null ||
        roomId == null ||
        role == null ||
        !role.canVote ||
        state.roomTarget?.kind != CollaborationTargetKind.projectBoard ||
        state.roomTarget?.id != boardId ||
        (delta != 1 && delta != -1)) {
      throw const CollaborationException(
        CollaborationErrorCode.permissionDenied,
        'Voting is not allowed in this room.',
      );
    }
    final boardReference = fs
        .collection('rooms')
        .doc(roomId)
        .collection('boards')
        .doc(boardId);
    final ballotReference = boardReference
        .collection('ballots')
        .doc(state.localUserId);
    // ponytail: Firestore persistence covers queued ballot writes, but transactions
    // need connectivity; add a ballot-only outbox when offline voting is required.
    await fs.runTransaction((transaction) async {
      final boardSnapshot = await transaction.get(boardReference);
      final data = boardSnapshot.data();
      if (data == null || data['payload'] is! Map) {
        throw const CollaborationException(
          CollaborationErrorCode.notFound,
          'Shared project board is not available.',
        );
      }
      final board = CanvasBoard.fromJson(
        Map<String, Object?>.from(data['payload']! as Map),
      );
      if (!board.votingSession.isActive ||
          board.votingSession.sessionId.isEmpty) {
        throw const CollaborationException(
          CollaborationErrorCode.invalidInput,
          'Voting session is not active.',
        );
      }
      final ballotSnapshot = await transaction.get(ballotReference);
      final current =
          (ballotSnapshot.data()?['objectIds'] as List?)
              ?.whereType<String>()
              .toSet() ??
          <String>{};
      for (final objectId in objectIds.where((id) => id.isNotEmpty)) {
        if (delta > 0) {
          current.add(objectId);
        } else {
          current.remove(objectId);
        }
      }
      if (current.length > board.votingSession.maxVotesPerParticipant) {
        throw const CollaborationException(
          CollaborationErrorCode.invalidInput,
          'Vote limit exceeded.',
        );
      }
      transaction.set(ballotReference, {
        'schemaVersion': 1,
        'ownerUid': state.localUserId,
        'sessionId': board.votingSession.sessionId,
        'objectIds': current.toList()..sort(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> saveProjectBoardComments(
    String objectId,
    List<CanvasObjectComment> comments,
  ) async {
    final fs = _firestore;
    final roomId = state.roomId;
    final role = state.currentRole;
    if (fs == null ||
        roomId == null ||
        role == null ||
        !role.canComment ||
        objectId.isEmpty) {
      throw const CollaborationException(
        CollaborationErrorCode.permissionDenied,
        'Commenting is not allowed in this room.',
      );
    }
    final existing = <String, CanvasObjectComment>{
      for (final comment
          in state.boardComments[objectId] ?? const <CanvasObjectComment>[])
        comment.id: comment,
    };
    final batch = fs.batch();
    for (final comment in comments) {
      final reference = fs
          .collection('rooms')
          .doc(roomId)
          .collection('boardComments')
          .doc(comment.id);
      final previous = existing[comment.id];
      if (previous == null) {
        batch.set(reference, {
          'id': comment.id,
          'objectId': objectId,
          'body': comment.body,
          'authorName': comment.authorName,
          'authorUid': state.localUserId,
          'createdAt': FieldValue.serverTimestamp(),
          'parentId': comment.parentId,
          'isResolved': false,
          'resolvedByUid': null,
        });
      } else if (previous.isResolved != comment.isResolved) {
        batch.update(reference, {
          'isResolved': comment.isResolved,
          'resolvedByUid': state.localUserId,
        });
      }
    }
    await batch.commit();
  }

  void _startDemoSimulation() {
    _simulationTimer?.cancel();

    // Initialize demo peers: "Alice" (Purple) and "Budi" (Green)
    state = state.copyWith(
      collaborators: {
        'alice': Collaborator(
          id: 'alice',
          name: 'Alice',
          color: Colors.purpleAccent,
          cursorPosition: const Offset(400, 300),
        ),
        'budi': Collaborator(
          id: 'budi',
          name: 'Budi (UX)',
          color: Colors.tealAccent,
          cursorPosition: const Offset(600, 450),
        ),
      },
    );

    // Periodic random movement simulating live Figma peers
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (!state.isDemoMode) {
        timer.cancel();
        return;
      }

      final updated = Map<String, Collaborator>.from(state.collaborators);

      // Simulating Alice moving cursor towards some node
      if (updated.containsKey('alice')) {
        final current = updated['alice']!;
        final pos = current.cursorPosition ?? const Offset(400, 300);
        final dx = (_random.nextDouble() - 0.5) * 20;
        final dy = (_random.nextDouble() - 0.5) * 20;

        // Randomly select/edit nodes sometimes
        String? sel = current.selectedNodeId;
        bool editing = current.isEditing;
        if (_random.nextDouble() < 0.02) {
          sel = _random.nextBool() ? 'node-a' : null;
          editing = sel != null && _random.nextBool();
        }

        updated['alice'] = current.copyWith(
          cursorPosition: Offset(
            (pos.dx + dx).clamp(100, 1000),
            (pos.dy + dy).clamp(100, 800),
          ),
          selectedNodeId: sel,
          isEditing: editing,
        );
      }

      // Simulating Budi moving cursor
      if (updated.containsKey('budi')) {
        final current = updated['budi']!;
        final pos = current.cursorPosition ?? const Offset(600, 450);
        final dx = (_random.nextDouble() - 0.5) * 15;
        final dy = (_random.nextDouble() - 0.5) * 15;

        String? sel = current.selectedNodeId;
        bool editing = current.isEditing;
        if (_random.nextDouble() < 0.015) {
          sel = _random.nextBool() ? 'node-b' : null;
          editing = sel != null && _random.nextBool();
        }

        updated['budi'] = current.copyWith(
          cursorPosition: Offset(
            (pos.dx + dx).clamp(200, 1200),
            (pos.dy + dy).clamp(200, 900),
          ),
          selectedNodeId: sel,
          isEditing: editing,
        );
      }

      state = state.copyWith(collaborators: updated);
    });
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _firestoreSub?.cancel();
    _membersFirestoreSub?.cancel();
    _nodeSyncService?.stop();
    _boardSyncService?.stop();
    _reactionsFirestoreSub?.cancel();
    _boardCommentsFirestoreSub?.cancel();
    _pingsFirestoreSub?.cancel();
    _pingsController.close();
    super.dispose();
  }
}

final collaborationProvider =
    StateNotifierProvider<CollaborationNotifier, CollaborationState>((ref) {
      return CollaborationNotifier(ref);
    });

final collaborationActionsProvider = Provider<CollaborationActions>((ref) {
  return ref.read(collaborationProvider.notifier);
});

final collaborationConflictsProvider = FutureProvider.autoDispose
    .family<List<CollaborationNodeConflict>, String>((ref, roomId) {
      ref.watch(collaborationProvider.select((state) => state.roomId));
      return ref.read(collaborationProvider.notifier).listConflicts(roomId);
    });

final collaborationBoardConflictsProvider = FutureProvider.autoDispose
    .family<List<CollaborationBoardConflict>, String>((ref, roomId) {
      ref.watch(collaborationProvider.select((state) => state.roomId));
      return ref
          .read(collaborationProvider.notifier)
          .listBoardConflicts(roomId);
    });

final collaborationOutboxProvider = StreamProvider.autoDispose
    .family<CollaborationOutboxSummary, String>((ref, roomId) async* {
      final store = ref.watch(collaborationSyncStoreProvider);
      yield await store.summary(roomId);
      await for (final _ in store.changes) {
        yield await store.summary(roomId);
      }
    });

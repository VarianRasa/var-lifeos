import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firestore_node_comment_repository.dart';
import '../domain/collaboration_node_sync.dart';
import '../domain/node_comment.dart';
import 'collaboration_session.dart';
import 'mindmap_providers.dart';

final class NodeCommentThreadKey {
  const NodeCommentThreadKey(this.roomId, this.localNodeId);

  final String roomId;
  final String localNodeId;

  @override
  bool operator ==(Object other) =>
      other is NodeCommentThreadKey &&
      other.roomId == roomId &&
      other.localNodeId == localNodeId;

  @override
  int get hashCode => Object.hash(roomId, localNodeId);
}

final class NodeCommentThreadState {
  const NodeCommentThreadState({
    this.comments = const AsyncLoading(),
    this.binding,
    this.submitting = false,
  });

  final AsyncValue<List<NodeComment>> comments;
  final CollaborationNodeBinding? binding;
  final bool submitting;

  NodeCommentThreadState copyWith({
    AsyncValue<List<NodeComment>>? comments,
    CollaborationNodeBinding? binding,
    bool? submitting,
  }) => NodeCommentThreadState(
    comments: comments ?? this.comments,
    binding: binding ?? this.binding,
    submitting: submitting ?? this.submitting,
  );
}

final nodeCommentRepositoryProvider = Provider<NodeCommentRepository>((ref) {
  return FirestoreNodeCommentRepository(
    firestore: FirebaseFirestore.instance,
    sessionReader: ref.watch(activeCollaborationSessionProvider.notifier),
    identityReader: _FirebaseCommentIdentityReader(),
  );
});

final boundRoomNodesProvider = FutureProvider.autoDispose
    .family<List<CollaborationNodeBinding>, String>((ref, roomId) {
      return ref.watch(collaborationSyncStoreProvider).listBindings(roomId);
    });

final collaborationNodeBindingProvider = FutureProvider.autoDispose
    .family<CollaborationNodeBinding?, NodeCommentThreadKey>((ref, key) {
      return ref
          .watch(collaborationSyncStoreProvider)
          .getBindingByLocal(key.roomId, key.localNodeId);
    });

final nodeCommentThreadProvider = StateNotifierProvider.autoDispose
    .family<
      NodeCommentThreadController,
      NodeCommentThreadState,
      NodeCommentThreadKey
    >((ref, key) {
      return NodeCommentThreadController(ref, key);
    });

final class NodeCommentThreadController
    extends StateNotifier<NodeCommentThreadState> {
  NodeCommentThreadController(this._ref, this._key)
    : super(const NodeCommentThreadState()) {
    _load();
  }

  final Ref _ref;
  final NodeCommentThreadKey _key;
  StreamSubscription<List<NodeComment>>? _subscription;

  Future<void> _load() async {
    try {
      final binding = await _ref
          .read(collaborationSyncStoreProvider)
          .getBindingByLocal(_key.roomId, _key.localNodeId);
      if (binding == null) {
        state = const NodeCommentThreadState(comments: AsyncData([]));
        return;
      }
      state = state.copyWith(binding: binding);
      final stream = _ref
          .read(nodeCommentRepositoryProvider)
          .watchComments(
            roomId: _key.roomId,
            remoteNodeId: binding.remoteNodeId,
          );
      _subscription = stream.listen(
        (comments) {
          if (mounted) state = state.copyWith(comments: AsyncData(comments));
        },
        onError: (Object error, StackTrace stackTrace) {
          if (mounted) {
            state = state.copyWith(comments: AsyncError(error, stackTrace));
          }
        },
      );
    } on Object catch (error, stackTrace) {
      if (mounted) {
        state = state.copyWith(comments: AsyncError(error, stackTrace));
      }
    }
  }

  Future<void> submit(String body) async {
    if (state.submitting || state.binding == null) return;
    state = state.copyWith(submitting: true);
    try {
      await _ref
          .read(nodeCommentRepositoryProvider)
          .addComment(
            roomId: _key.roomId,
            remoteNodeId: state.binding!.remoteNodeId,
            body: body,
          );
    } finally {
      if (mounted) state = state.copyWith(submitting: false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final class _FirebaseCommentIdentityReader
    implements CollaborationCommentIdentityReader {
  @override
  String? get displayName {
    try {
      if (Firebase.apps.isEmpty) return null;
      final user = FirebaseAuth.instance.currentUser;
      return user?.displayName ?? user?.email ?? user?.uid;
    } on FirebaseException {
      return null;
    }
  }
}

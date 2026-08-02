import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../application/collaboration_session.dart';
import '../domain/collaboration_room.dart';
import '../domain/node_comment.dart';

abstract interface class NodeCommentRepository {
  Stream<List<NodeComment>> watchComments({
    required String roomId,
    required String remoteNodeId,
  });

  Future<void> addComment({
    required String roomId,
    required String remoteNodeId,
    required String body,
  });
}

abstract interface class CollaborationCommentIdentityReader {
  String? get displayName;
}

final class FirestoreNodeCommentRepository implements NodeCommentRepository {
  FirestoreNodeCommentRepository({
    required FirebaseFirestore firestore,
    required ActiveCollaborationSessionReader sessionReader,
    required CollaborationCommentIdentityReader identityReader,
    Uuid uuid = const Uuid(),
  }) : _firestore = firestore,
       _sessionReader = sessionReader,
       _identityReader = identityReader,
       _uuid = uuid;

  final FirebaseFirestore _firestore;
  final ActiveCollaborationSessionReader _sessionReader;
  final CollaborationCommentIdentityReader _identityReader;
  final Uuid _uuid;

  CollectionReference<Map<String, dynamic>> _comments(
    String roomId,
    String remoteNodeId,
  ) => _firestore
      .collection('rooms')
      .doc(roomId)
      .collection('nodes')
      .doc(remoteNodeId)
      .collection('comments');

  @override
  Stream<List<NodeComment>> watchComments({
    required String roomId,
    required String remoteNodeId,
  }) {
    return _comments(roomId, remoteNodeId)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => List.unmodifiable(
            snapshot.docs.map((document) {
              final data = Map<String, Object?>.from(document.data());
              final timestamp = data['createdAt'];
              data['createdAt'] = timestamp is Timestamp
                  ? timestamp.toDate()
                  : DateTime.fromMillisecondsSinceEpoch(0);
              return NodeComment.fromJson(
                data,
                pending: document.metadata.hasPendingWrites,
              );
            }),
          ),
        );
  }

  @override
  Future<void> addComment({
    required String roomId,
    required String remoteNodeId,
    required String body,
  }) async {
    final session = _sessionReader.current;
    if (session == null || session.roomId != roomId) {
      throw const CollaborationException(
        CollaborationErrorCode.unauthenticated,
        'Active collaboration session required.',
      );
    }
    if (!session.role.canComment) {
      throw const CollaborationException(
        CollaborationErrorCode.permissionDenied,
        'Role cannot add comments.',
      );
    }
    final cleanBody = body.trim();
    final name = (_identityReader.displayName ?? '').trim();
    NodeComment(
      id: 'validation',
      roomId: roomId,
      nodeId: remoteNodeId,
      body: cleanBody,
      authorUid: session.uid,
      authorDisplayName: name,
      createdAt: DateTime.now(),
      pending: true,
    );
    if (!(await _firestore
            .collection('rooms')
            .doc(roomId)
            .collection('nodes')
            .doc(remoteNodeId)
            .get())
        .exists) {
      throw const CollaborationException(
        CollaborationErrorCode.notFound,
        'Bound collaboration node not found.',
      );
    }
    final id = _uuid.v4();
    await _comments(roomId, remoteNodeId).doc(id).set({
      'id': id,
      'nodeId': remoteNodeId,
      'roomId': roomId,
      'body': cleanBody,
      'authorUid': session.uid,
      'authorDisplayName': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

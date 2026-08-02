/// Firestore-backed per-node remote backup store.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../mindmap/domain/mindmap_node.dart';
import '../domain/mindmap_backup_document.dart';
import '../domain/sync_account.dart';
import 'http_sync_remote_backup_store.dart';

final class FirestoreSyncRemoteBackupStore implements SyncRemoteBackupStore {
  FirestoreSyncRemoteBackupStore({FirebaseFirestore? firestore})
    : _firestoreInstance = firestore;

  static const int _maxBatchOperations = 450;

  final FirebaseFirestore? _firestoreInstance;

  FirebaseFirestore get _firestore =>
      _firestoreInstance ?? FirebaseFirestore.instance;

  @override
  Future<MindmapBackupDocument?> fetchLatestBackup(SyncUser user) async {
    try {
      final userRef = _userRef(user);
      final metadataSnapshot = await userRef
          .collection('metadata')
          .doc('latest')
          .get();
      final nodesSnapshot = await userRef.collection('nodes').get();
      if (nodesSnapshot.docs.isEmpty) return null;

      final nodes = <MindmapNode>[];
      for (final doc in nodesSnapshot.docs) {
        final data = doc.data();
        final rawNode = data['node'];
        if (rawNode is Map<Object?, Object?>) {
          nodes.add(MindmapNode.fromJson(rawNode.cast<String, Object?>()));
        }
      }
      if (nodes.isEmpty) return null;

      final metadata =
          metadataSnapshot.data()?.cast<String, Object?>() ??
          const <String, Object?>{};
      return MindmapBackupDocument.fromJson({
        'type': metadata['type'] ?? MindmapBackupDocument.documentType,
        'schemaVersion':
            metadata['schemaVersion'] ??
            MindmapBackupDocument.currentSchemaVersion,
        'exportedAt':
            metadata['exportedAt'] ??
            DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        'sourceDevice':
            metadata['sourceDevice'] ?? const {'id': 'unknown', 'label': ''},
        'nodes': [for (final node in nodes) node.toJson()],
        if (metadata['warnings'] case final List<Object?> warnings)
          'warnings': warnings,
      });
    } on FormatException catch (error) {
      throw SyncRemoteStoreException(
        'Remote backup response is invalid.',
        cause: error,
      );
    } on FirebaseException catch (error) {
      throw SyncRemoteStoreException(
        'Remote sync request failed.',
        cause: error,
      );
    }
  }

  @override
  Future<void> uploadBackup(
    SyncUser user,
    MindmapBackupDocument document,
  ) async {
    if (document.attachments.isNotEmpty) {
      throw const SyncRemoteStoreException(
        'Remote backup cannot contain attachment payloads.',
      );
    }
    try {
      final userRef = _userRef(user);
      final nodesRef = userRef.collection('nodes');
      final existing = await nodesRef.get();
      final incomingIds = {for (final node in document.nodes) node.id};
      final writes = <_FirestoreWrite>[
        _FirestoreWrite.set(userRef.collection('metadata').doc('latest'), {
          'type': document.type,
          'schemaVersion': document.schemaVersion,
          'exportedAt': document.exportedAt.toIso8601String(),
          'sourceDevice': document.sourceDevice.toJson(),
          'nodeCount': document.nodes.length,
          if (document.warnings.isNotEmpty)
            'warnings': [
              for (final warning in document.warnings) warning.toJson(),
            ],
          'updatedAt': FieldValue.serverTimestamp(),
        }),
        for (final node in document.nodes)
          _FirestoreWrite.set(nodesRef.doc(_nodeDocId(node.id)), {
            'nodeId': node.id,
            'node': node.toJson(),
            'updatedAt': node.updatedAt.toIso8601String(),
            'exportedAt': document.exportedAt.toIso8601String(),
          }),
        for (final doc in existing.docs)
          if (!incomingIds.contains(_nodeIdFromDoc(doc)))
            _FirestoreWrite.delete(doc.reference),
      ];

      for (var start = 0; start < writes.length; start += _maxBatchOperations) {
        final batch = _firestore.batch();
        for (final write in writes.skip(start).take(_maxBatchOperations)) {
          write.apply(batch);
        }
        await batch.commit();
      }
    } on FirebaseException catch (error) {
      throw SyncRemoteStoreException(
        'Remote sync request failed.',
        cause: error,
      );
    }
  }

  DocumentReference<Map<String, dynamic>> _userRef(SyncUser user) {
    return _firestore.collection('users').doc(user.id);
  }
}

final class _FirestoreWrite {
  const _FirestoreWrite.set(this.reference, this.data) : delete = false;

  const _FirestoreWrite.delete(this.reference)
    : data = const <String, dynamic>{},
      delete = true;

  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic> data;
  final bool delete;

  void apply(WriteBatch batch) {
    if (delete) {
      batch.delete(reference);
    } else {
      batch.set(reference, data, SetOptions(merge: false));
    }
  }
}

String _nodeDocId(String nodeId) => nodeId.replaceAll('/', '%2F');

String _nodeIdFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  final nodeId = data['nodeId'];
  if (nodeId is String && nodeId.isNotEmpty) return nodeId;
  final rawNode = data['node'];
  if (rawNode is Map<Object?, Object?>) {
    final rawId = rawNode['id'];
    if (rawId is String && rawId.isNotEmpty) return rawId;
  }
  return doc.id.replaceAll('%2F', '/');
}

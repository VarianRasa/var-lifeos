import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../application/collaboration_session.dart';
import '../domain/collaboration_node_sync.dart';
import '../domain/collaboration_room.dart';
import '../domain/mindmap_node.dart';
import '../domain/mindmap_node_revision_repository.dart';
import '../domain/mindmap_repository.dart';
import '../domain/node_type_payloads.dart';
import 'sembast_collaboration_sync_store.dart';

final class CollaborationMindmapRepository implements MindmapRepository {
  CollaborationMindmapRepository({
    required MindmapRepository base,
    required SembastCollaborationSyncStore store,
    required MindmapNodeRevisionRepository revisionRepository,
    required ActiveCollaborationSessionReader sessionReader,
    this.onMutation,
  }) : _base = base,
       _revisionRepository = revisionRepository,
       _store = store,
       _sessionReader = sessionReader;

  final MindmapRepository _base;
  final MindmapNodeRevisionRepository _revisionRepository;
  final SembastCollaborationSyncStore _store;
  final ActiveCollaborationSessionReader _sessionReader;
  final void Function(String roomId)? onMutation;

  @override
  Future<void> deleteNode(String id) async {
    final session = _sessionReader.current;
    final binding = session == null
        ? null
        : await _store.getBindingByLocal(session.roomId, id);
    if (binding != null) {
      _validateWrite(session!, binding.dayKey);
    }
    await _base.deleteNode(id);
    if (binding != null) {
      await _store.enqueue(
        CollaborationPendingMutation(
          mutationId: const Uuid().v4(),
          roomId: binding.roomId,
          localNodeId: id,
          remoteNodeId: binding.remoteNodeId,
          dayKey: binding.dayKey,
          baseRevision: binding.revision,
          kind: CollaborationMutationKind.delete,
          payload: null,
          updatedByUid: session!.uid,
          attemptCount: 0,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          nextAttemptAt: DateTime.now().toUtc(),
          lastAttemptAt: null,
          lastErrorCode: null,
          deliveryState: CollaborationDeliveryState.pending,
        ),
      );
      onMutation?.call(binding.roomId);
    }
  }

  @override
  Future<MindmapNode?> getNode(String id) => _base.getNode(id);

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      _base.listNodes(day: day);

  @override
  Future<MindmapNode> saveNode(MindmapNode node) async {
    final session = _sessionReader.current;
    final binding = session == null
        ? null
        : await _store.getBindingByLocal(session.roomId, node.id);
    if (binding != null) {
      _validateWrite(session!, dayKey(node.day));
    }
    final saved = await _base.saveNode(node);
    if (binding != null) {
      await _enqueueUpsert(saved, binding, session!);
    }
    return saved;
  }

  Future<MindmapNode> restoreRevision(
    String revisionId, {
    required DateTime now,
  }) async {
    final revision = await _revisionRepository.getRevision(revisionId);
    if (revision == null) throw StateError('Revision not found: $revisionId');
    final session = _sessionReader.current;
    final binding = session == null
        ? null
        : await _store.getBindingByLocal(session.roomId, revision.nodeId);
    if (binding != null) {
      _validateWrite(session!, dayKey(revision.snapshot.day));
    }
    final restored = await _revisionRepository.restoreRevision(
      revisionId,
      now: now,
    );
    if (binding != null) await _enqueueUpsert(restored, binding, session!);
    return restored;
  }

  Future<MindmapNode> bindAndPublish(
    MindmapNode node,
    ActiveCollaborationSession session, {
    String? remoteNodeId,
    bool persistLocally = true,
  }) async {
    _validateWrite(session, dayKey(node.day));
    final sessionDayKey = session.dayKey;
    if (sessionDayKey == null) {
      throw const CollaborationException(
        CollaborationErrorCode.invalidInput,
        'Project collaboration rooms cannot bind day nodes.',
      );
    }
    final existing = await _store.getBindingByLocal(session.roomId, node.id);
    final binding =
        existing ??
        CollaborationNodeBinding(
          roomId: session.roomId,
          localNodeId: node.id,
          remoteNodeId: remoteNodeId ?? node.id,
          dayKey: sessionDayKey,
          revision: 0,
        );
    await _store.bind(binding);
    final published = persistLocally ? await _base.saveNode(node) : node;
    await _enqueueUpsert(published, binding, session);
    return published;
  }

  Future<void> unbindNode(
    String localNodeId,
    ActiveCollaborationSession session,
  ) async {
    final binding = await _store.getBindingByLocal(session.roomId, localNodeId);
    if (binding == null) return;
    _validateWrite(session, binding.dayKey);
    await _store.detach(binding);
  }

  Future<MindmapNode> applyRemoteUpsert(
    MindmapNode node,
    CollaborationNodeBinding binding,
  ) async {
    await _store.bind(binding);
    return _base.saveNode(node);
  }

  Future<void> applyRemoteDelete(CollaborationNodeBinding binding) async {
    await _base.deleteNode(binding.localNodeId);
    await _store.bind(binding);
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      _base.searchNodes(query);

  Future<void> _enqueueUpsert(
    MindmapNode node,
    CollaborationNodeBinding binding,
    ActiveCollaborationSession session,
  ) async {
    final shared = node.type == NodeType.expense
        ? node.copyWith(
            data: ExpensePayload.fromNode(
              node,
            ).copyWith(receipts: const []).toData(node.data),
          )
        : node;
    await _store.enqueue(
      CollaborationPendingMutation(
        mutationId: const Uuid().v4(),
        roomId: binding.roomId,
        localNodeId: node.id,
        remoteNodeId: binding.remoteNodeId,
        dayKey: binding.dayKey,
        baseRevision: binding.revision,
        kind: CollaborationMutationKind.upsert,
        payload: shared.toJson(),
        updatedByUid: session.uid,
        attemptCount: 0,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        nextAttemptAt: DateTime.now().toUtc(),
        lastAttemptAt: null,
        lastErrorCode: null,
        deliveryState: CollaborationDeliveryState.pending,
      ),
    );
    onMutation?.call(binding.roomId);
  }

  void _validateWrite(ActiveCollaborationSession session, String nodeDay) {
    if (!session.canWriteNodes) {
      throw const CollaborationException(
        CollaborationErrorCode.permissionDenied,
        'Role cannot write collaboration nodes.',
      );
    }
    final sessionDayKey = session.dayKey;
    if (sessionDayKey == null || nodeDay != sessionDayKey) {
      throw const CollaborationException(
        CollaborationErrorCode.invalidInput,
        'Bound collaboration node cannot move outside room day.',
      );
    }
  }
}

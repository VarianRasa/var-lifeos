/// Shared mutation helpers for mindmap nodes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/domain/time_block.dart';
import '../data/collaboration_mindmap_repository.dart';
import '../domain/inline_node_workspace_policy.dart';
import '../domain/mindmap_integrator.dart';
import '../domain/mindmap_node.dart';
import '../domain/mindmap_node_data.dart';
import 'mindmap_providers.dart';

final mindmapMutationControllerProvider = Provider<MindmapMutationController>((
  ref,
) {
  return MindmapMutationController(ref);
});

final class MindmapMutationController {
  const MindmapMutationController(this._ref);

  final Ref _ref;

  Future<MindmapNode> saveNode(
    MindmapNode node, {
    DateTime? previousDay,
  }) async {
    final repository = _ref.read(mindmapRepositoryProvider);
    final allNodes = await repository.listNodes();
    final saved = await repository.saveNode(node);

    const integrator = MindmapIntegrator();
    final sideEffects = integrator.integrateMutations(
      mutatedNode: saved,
      allNodes: allNodes,
    );
    for (final sideEffect in sideEffects) {
      await repository.saveNode(sideEffect);
    }

    invalidateMindmapStateFromRef(_ref, day: saved.day, extraDay: previousDay);
    return saved;
  }

  Future<MindmapNode?> savePatch(
    String nodeId,
    InlineNodeDraftPatch patch, {
    required DateTime now,
  }) async {
    final latest = await _ref.read(mindmapRepositoryProvider).getNode(nodeId);
    if (latest == null) return null;
    return saveNode(patch.mergeInto(latest, now), previousDay: latest.day);
  }

  Future<void> deleteNode(MindmapNode node) async {
    await deleteNodeById(node.id, day: node.day);
  }

  Future<void> deleteNodeById(String nodeId, {required DateTime day}) async {
    await _ref.read(mindmapRepositoryProvider).deleteNode(nodeId);
    invalidateMindmapStateFromRef(_ref, day: day);
  }

  Future<MindmapNode> restoreRevision(String revisionId) async {
    final revisionRepository = _ref.read(mindmapNodeRevisionRepositoryProvider);
    final revision = await revisionRepository.getRevision(revisionId);
    if (revision == null) throw StateError('Revision not found: $revisionId');
    final current = await _ref
        .read(mindmapRepositoryProvider)
        .getNode(revision.nodeId);
    final repository = _ref.read(mindmapRepositoryProvider);
    final restored = repository is CollaborationMindmapRepository
        ? await repository.restoreRevision(revisionId, now: DateTime.now())
        : await revisionRepository.restoreRevision(
            revisionId,
            now: DateTime.now(),
          );
    invalidateMindmapStateFromRef(
      _ref,
      day: restored.day,
      extraDay: current?.day,
    );
    _ref.invalidate(nodeRevisionsProvider(restored.id));
    return restored;
  }

  Future<MindmapNode> completeNode(MindmapNode node) async {
    return saveNode(
      node.copyWith(
        isDone: true,
        status: NodeStatus.done,
        progress: 1,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<MindmapNode> archiveNode(MindmapNode node) async {
    return saveNode(node.copyWith(isArchived: true, updatedAt: DateTime.now()));
  }

  Future<MindmapNode> rescheduleDueDate(
    MindmapNode node, {
    required DateTime dueDate,
  }) async {
    return saveNode(node.copyWith(dueDate: dueDate, updatedAt: DateTime.now()));
  }

  Future<MindmapNode> scheduleNode(MindmapNode node, TimeBlock block) async {
    return saveNode(
      node.copyWith(
        data: dataWithTimeBlock(node.data, block),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<MindmapNode> unscheduleNode(MindmapNode node) async {
    return saveNode(
      node.copyWith(
        data: dataWithoutTimeBlock(node.data),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<MindmapNode> rescheduleNode(
    MindmapNode node, {
    required DateTime day,
  }) async {
    return saveNode(
      node.copyWith(day: day, updatedAt: DateTime.now()),
      previousDay: node.day,
    );
  }

  Future<MindmapNode> rescheduleNodeById({
    required String nodeId,
    required DateTime day,
  }) async {
    final node = await _ref.read(mindmapRepositoryProvider).getNode(nodeId);
    if (node == null) {
      throw StateError('Mindmap node not found: $nodeId');
    }
    return rescheduleNode(node, day: day);
  }

  Future<MindmapNode> linkNodes({
    required MindmapNode source,
    required String targetNodeId,
  }) async {
    if (targetNodeId.trim().isEmpty || targetNodeId == source.id) {
      return source;
    }
    return saveNode(
      source.copyWith(
        relatedNodeIds: [...source.relatedNodeIds, targetNodeId],
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<MindmapNode> unlinkNodes({
    required MindmapNode source,
    required String targetNodeId,
  }) async {
    return saveNode(
      source.copyWith(
        relatedNodeIds: [
          for (final nodeId in source.relatedNodeIds)
            if (nodeId != targetNodeId) nodeId,
        ],
        updatedAt: DateTime.now(),
      ),
    );
  }
}

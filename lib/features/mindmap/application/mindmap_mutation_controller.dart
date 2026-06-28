/// Shared mutation helpers for mindmap nodes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/domain/time_block.dart';
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
    final saved = await _ref.read(mindmapRepositoryProvider).saveNode(node);
    invalidateMindmapStateFromRef(_ref, day: saved.day, extraDay: previousDay);
    return saved;
  }

  Future<void> deleteNode(MindmapNode node) async {
    await deleteNodeById(node.id, day: node.day);
  }

  Future<void> deleteNodeById(String nodeId, {required DateTime day}) async {
    await _ref.read(mindmapRepositoryProvider).deleteNode(nodeId);
    invalidateMindmapStateFromRef(_ref, day: day);
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

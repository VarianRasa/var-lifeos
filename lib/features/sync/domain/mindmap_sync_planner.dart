/// Merge planner for local-first mindmap sync and backup imports.
library;

import '../../mindmap/domain/mindmap_node.dart';

enum SyncConflictKind { editEdit, deleteEdit, createCreate }

enum SyncConflictStrategy { manual, latestUpdatedAt, keepLocal, keepRemote }

enum SyncResolution { unresolved, useLocal, useRemote, useDelete }

final class SyncConflict {
  const SyncConflict({
    required this.kind,
    required this.nodeId,
    this.baselineNode,
    this.localNode,
    this.remoteNode,
    this.resolution = SyncResolution.unresolved,
  });

  final SyncConflictKind kind;
  final String nodeId;
  final MindmapNode? baselineNode;
  final MindmapNode? localNode;
  final MindmapNode? remoteNode;
  final SyncResolution resolution;

  SyncConflict resolve(SyncResolution resolution) {
    return SyncConflict(
      kind: kind,
      nodeId: nodeId,
      baselineNode: baselineNode,
      localNode: localNode,
      remoteNode: remoteNode,
      resolution: resolution,
    );
  }
}

final class MindmapSyncPlan {
  const MindmapSyncPlan({
    required this.nodesToSave,
    required this.nodeIdsToDelete,
    required this.conflicts,
    required this.resolvedConflicts,
  });

  final List<MindmapNode> nodesToSave;
  final List<String> nodeIdsToDelete;
  final List<SyncConflict> conflicts;
  final List<SyncConflict> resolvedConflicts;

  bool get hasBlockingConflicts => conflicts.isNotEmpty;
}

final class MindmapSyncPlanner {
  const MindmapSyncPlanner({
    this.strategy = SyncConflictStrategy.manual,
    this.conflictResolutions = const {},
  });

  final SyncConflictStrategy strategy;
  final Map<String, SyncResolution> conflictResolutions;

  MindmapSyncPlan plan({
    required Iterable<MindmapNode> localNodes,
    required Iterable<MindmapNode> remoteNodes,
    Iterable<MindmapNode> baselineNodes = const [],
  }) {
    final localById = _nodesById(localNodes);
    final remoteById = _nodesById(remoteNodes);
    final baselineById = _nodesById(baselineNodes);
    final nodeIds = <String>{
      ...localById.keys,
      ...remoteById.keys,
      ...baselineById.keys,
    }.toList()..sort();

    final nodesToSave = <MindmapNode>[];
    final nodeIdsToDelete = <String>[];
    final conflicts = <SyncConflict>[];
    final resolvedConflicts = <SyncConflict>[];

    for (final nodeId in nodeIds) {
      final local = localById[nodeId];
      final remote = remoteById[nodeId];
      final baseline = baselineById[nodeId];

      if (baseline == null) {
        _planCreatedNode(
          nodeId: nodeId,
          local: local,
          remote: remote,
          nodesToSave: nodesToSave,
          conflicts: conflicts,
          resolvedConflicts: resolvedConflicts,
        );
        continue;
      }

      if (local == null && remote == null) continue;

      if (local == null) {
        if (remote == baseline) continue;
        _handleConflict(
          SyncConflict(
            kind: SyncConflictKind.deleteEdit,
            nodeId: nodeId,
            baselineNode: baseline,
            remoteNode: remote,
          ),
          nodesToSave: nodesToSave,
          nodeIdsToDelete: nodeIdsToDelete,
          conflicts: conflicts,
          resolvedConflicts: resolvedConflicts,
        );
        continue;
      }

      if (remote == null) {
        if (local == baseline) {
          nodeIdsToDelete.add(nodeId);
          continue;
        }
        _handleConflict(
          SyncConflict(
            kind: SyncConflictKind.deleteEdit,
            nodeId: nodeId,
            baselineNode: baseline,
            localNode: local,
          ),
          nodesToSave: nodesToSave,
          nodeIdsToDelete: nodeIdsToDelete,
          conflicts: conflicts,
          resolvedConflicts: resolvedConflicts,
        );
        continue;
      }

      final localChanged = local != baseline;
      final remoteChanged = remote != baseline;
      if (!localChanged && !remoteChanged) continue;
      if (!localChanged && remoteChanged) {
        nodesToSave.add(remote);
        continue;
      }
      if (localChanged && !remoteChanged) continue;
      if (local == remote) continue;

      _handleConflict(
        SyncConflict(
          kind: SyncConflictKind.editEdit,
          nodeId: nodeId,
          baselineNode: baseline,
          localNode: local,
          remoteNode: remote,
        ),
        nodesToSave: nodesToSave,
        nodeIdsToDelete: nodeIdsToDelete,
        conflicts: conflicts,
        resolvedConflicts: resolvedConflicts,
      );
    }

    return MindmapSyncPlan(
      nodesToSave: List.unmodifiable(_sortNodes(nodesToSave)),
      nodeIdsToDelete: List.unmodifiable(nodeIdsToDelete..sort()),
      conflicts: List.unmodifiable(conflicts),
      resolvedConflicts: List.unmodifiable(resolvedConflicts),
    );
  }

  void _planCreatedNode({
    required String nodeId,
    required MindmapNode? local,
    required MindmapNode? remote,
    required List<MindmapNode> nodesToSave,
    required List<SyncConflict> conflicts,
    required List<SyncConflict> resolvedConflicts,
  }) {
    if (local == null && remote == null) return;
    if (local == null && remote != null) {
      nodesToSave.add(remote);
      return;
    }
    if (local != null && remote == null) return;
    if (local == remote) return;

    _handleConflict(
      SyncConflict(
        kind: SyncConflictKind.createCreate,
        nodeId: nodeId,
        localNode: local,
        remoteNode: remote,
      ),
      nodesToSave: nodesToSave,
      nodeIdsToDelete: const [],
      conflicts: conflicts,
      resolvedConflicts: resolvedConflicts,
    );
  }

  void _handleConflict(
    SyncConflict conflict, {
    required List<MindmapNode> nodesToSave,
    required List<String> nodeIdsToDelete,
    required List<SyncConflict> conflicts,
    required List<SyncConflict> resolvedConflicts,
  }) {
    final resolution = _resolutionFor(conflict);
    if (resolution == SyncResolution.unresolved) {
      conflicts.add(conflict);
      return;
    }

    final resolved = conflict.resolve(resolution);
    resolvedConflicts.add(resolved);
    switch (resolution) {
      case SyncResolution.unresolved:
        conflicts.add(conflict);
      case SyncResolution.useLocal:
        if (conflict.localNode == null) nodeIdsToDelete.add(conflict.nodeId);
      case SyncResolution.useRemote:
        final remote = conflict.remoteNode;
        if (remote == null) {
          nodeIdsToDelete.add(conflict.nodeId);
        } else {
          nodesToSave.add(remote);
        }
      case SyncResolution.useDelete:
        nodeIdsToDelete.add(conflict.nodeId);
    }
  }

  SyncResolution _resolutionFor(SyncConflict conflict) {
    final explicitResolution = conflictResolutions[conflict.nodeId];
    if (explicitResolution != null) return explicitResolution;

    return switch (strategy) {
      SyncConflictStrategy.manual => SyncResolution.unresolved,
      SyncConflictStrategy.keepLocal =>
        conflict.localNode == null
            ? SyncResolution.useDelete
            : SyncResolution.useLocal,
      SyncConflictStrategy.keepRemote =>
        conflict.remoteNode == null
            ? SyncResolution.useDelete
            : SyncResolution.useRemote,
      SyncConflictStrategy.latestUpdatedAt => _latestResolutionFor(conflict),
    };
  }
}

SyncResolution _latestResolutionFor(SyncConflict conflict) {
  final local = conflict.localNode;
  final remote = conflict.remoteNode;
  if (local == null && remote == null) return SyncResolution.useDelete;
  if (local == null) return SyncResolution.useRemote;
  if (remote == null) return SyncResolution.useLocal;
  return remote.updatedAt.isAfter(local.updatedAt)
      ? SyncResolution.useRemote
      : SyncResolution.useLocal;
}

Map<String, MindmapNode> _nodesById(Iterable<MindmapNode> nodes) {
  return {for (final node in nodes) node.id: node};
}

List<MindmapNode> _sortNodes(List<MindmapNode> nodes) {
  return nodes..sort((a, b) {
    final day = a.day.compareTo(b.day);
    if (day != 0) return day;
    final created = a.createdAt.compareTo(b.createdAt);
    if (created != 0) return created;
    return a.title.compareTo(b.title);
  });
}

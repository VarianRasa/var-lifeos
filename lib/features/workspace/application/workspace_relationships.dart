import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/workspace_context.dart';

final class WorkspaceRelationshipSummary {
  const WorkspaceRelationshipSummary({
    required this.relationCount,
    required this.internalRelations,
    required this.externalRelations,
    required this.isolatedNodes,
    required this.hubNodes,
  });

  final int relationCount;
  final int internalRelations;
  final int externalRelations;
  final List<MindmapNode> isolatedNodes;
  final List<MindmapNode> hubNodes;
}

WorkspaceRelationshipSummary buildWorkspaceRelationshipSummary(
  WorkspaceContext workspace,
  List<MindmapNode> allNodes,
) {
  final ids = workspace.nodes.map((node) => node.id).toSet();
  final allIds = allNodes.map((node) => node.id).toSet();
  var internal = 0;
  var external = 0;
  final degree = <String, int>{};
  for (final node in workspace.nodes) {
    for (final related in node.relatedNodeIds.where(allIds.contains)) {
      degree[node.id] = (degree[node.id] ?? 0) + 1;
      if (ids.contains(related)) {
        internal += 1;
      } else {
        external += 1;
      }
    }
  }
  final isolated = workspace.nodes
      .where((node) {
        final outgoing = node.relatedNodeIds.where(allIds.contains).isNotEmpty;
        final incoming = allNodes.any(
          (other) => other.relatedNodeIds.contains(node.id),
        );
        return !outgoing && !incoming;
      })
      .toList(growable: false);
  final hubs = [...workspace.nodes]
    ..sort((a, b) => (degree[b.id] ?? 0).compareTo(degree[a.id] ?? 0));
  return WorkspaceRelationshipSummary(
    relationCount: internal + external,
    internalRelations: internal,
    externalRelations: external,
    isolatedNodes: isolated,
    hubNodes: hubs
        .where((node) => (degree[node.id] ?? 0) >= 2)
        .take(5)
        .toList(growable: false),
  );
}

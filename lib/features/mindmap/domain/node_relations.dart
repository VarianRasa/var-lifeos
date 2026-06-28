/// Computed outgoing and incoming links for one mindmap node.
library;

import 'mindmap_node.dart';

final class NodeRelations {
  const NodeRelations({
    required this.nodeId,
    this.relatedNodes = const [],
    this.backlinks = const [],
  });

  final String nodeId;
  final List<MindmapNode> relatedNodes;
  final List<MindmapNode> backlinks;

  bool get isEmpty => relatedNodes.isEmpty && backlinks.isEmpty;
}

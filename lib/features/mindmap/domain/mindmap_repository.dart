/// Repository boundary for local-first mindmap data.
library;

import 'mindmap_node.dart';

abstract interface class MindmapRepository {
  Future<List<MindmapNode>> listNodes({DateTime? day});

  Future<MindmapNode?> getNode(String id);

  Future<MindmapNode> saveNode(MindmapNode node);

  Future<void> deleteNode(String id);

  Future<List<MindmapNode>> searchNodes(String query);
}

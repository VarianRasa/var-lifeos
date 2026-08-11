import '../domain/mindmap_node.dart';
import '../domain/mindmap_node_revision.dart';

abstract interface class MindmapNodeRevisionRepository {
  Future<List<MindmapNodeRevision>> listRevisions(
    String nodeId, {
    int limit = 50,
  });

  Future<MindmapNodeRevision?> getRevision(String revisionId);

  Future<void> deleteRevisions(String nodeId);

  Future<MindmapNode> restoreRevision(
    String revisionId, {
    required DateTime now,
  });
}

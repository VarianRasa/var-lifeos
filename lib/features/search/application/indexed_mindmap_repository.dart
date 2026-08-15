import 'dart:async';

import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/mindmap_repository.dart';
import '../domain/search_document.dart';
import '../domain/search_index_repository.dart';
import 'search_document_projector.dart';
import 'search_index_coordinator.dart';

final class IndexedMindmapRepository implements MindmapRepository {
  const IndexedMindmapRepository({
    required MindmapRepository base,
    required FutureOr<SearchIndexCoordinator> coordinator,
    required SearchDocumentProjector projector,
  }) : _base = base,
       _coordinator = coordinator,
       _projector = projector;

  final MindmapRepository _base;
  final FutureOr<SearchIndexCoordinator> _coordinator;
  final SearchDocumentProjector _projector;

  @override
  Future<MindmapNode> saveNode(MindmapNode node) async {
    final saved = await _base.saveNode(node);
    try {
      await (await Future.value(_coordinator)).indexDocuments(
        _projector.projectNode(saved, workspaceId: _workspaceId(saved)),
      );
    } on Object {
      return saved;
    }
    return saved;
  }

  @override
  Future<void> deleteNode(String id) async {
    await _base.deleteNode(id);
    try {
      await (await Future.value(_coordinator)).removeSource(
        SearchSourceRef(kind: SearchSourceKind.node, sourceId: id),
      );
    } on Object {
      return;
    }
  }

  @override
  Future<MindmapNode?> getNode(String id) => _base.getNode(id);

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      _base.listNodes(day: day);

  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      _base.searchNodes(query);
}

String _workspaceId(MindmapNode node) {
  final project = node.project.trim();
  if (project.isNotEmpty) return 'project:$project';
  final area = node.area.trim();
  if (area.isNotEmpty) return 'area:$area';
  return 'daily';
}

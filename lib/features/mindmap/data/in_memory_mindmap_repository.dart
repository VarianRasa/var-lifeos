/// In-memory repository used until the persistent DB adapter is introduced.
library;

import '../../../core/utils/date_utils.dart';
import '../domain/mindmap_node.dart';
import '../domain/mindmap_repository.dart';

final class InMemoryMindmapRepository implements MindmapRepository {
  InMemoryMindmapRepository({Iterable<MindmapNode> seedNodes = const []})
    : _nodesById = {
        for (final node in seedNodes) node.id: node.copyWith(day: node.day),
      };

  final Map<String, MindmapNode> _nodesById;

  @override
  Future<void> deleteNode(String id) async {
    _nodesById.remove(id);
  }

  @override
  Future<MindmapNode?> getNode(String id) async => _nodesById[id];

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) async {
    final normalizedDay = day?.dateOnly;
    final nodes = _nodesById.values.where((node) {
      return normalizedDay == null || node.day.isSameDay(normalizedDay);
    }).toList();

    nodes.sort(_compareNodes);
    return List.unmodifiable(nodes);
  }

  @override
  Future<MindmapNode> saveNode(MindmapNode node) async {
    final saved = node.copyWith(day: node.day.dateOnly);
    _nodesById[saved.id] = saved;
    return saved;
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return listNodes();

    final nodes = _nodesById.values
        .where((node) => _matchesNode(node, normalized))
        .toList();

    nodes.sort(_compareNodes);
    return List.unmodifiable(nodes);
  }
}

bool _matchesNode(MindmapNode node, String query) {
  return node.title.toLowerCase().contains(query) ||
      node.body.toLowerCase().contains(query) ||
      node.type.label.toLowerCase().contains(query) ||
      node.project.toLowerCase().contains(query) ||
      node.area.toLowerCase().contains(query) ||
      node.tags.any((tag) => tag.contains(query));
}

int _compareNodes(MindmapNode a, MindmapNode b) {
  final day = a.day.compareTo(b.day);
  if (day != 0) return day;
  final created = a.createdAt.compareTo(b.createdAt);
  if (created != 0) return created;
  return a.title.compareTo(b.title);
}

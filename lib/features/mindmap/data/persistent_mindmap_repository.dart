/// JSON-backed mindmap repository for local persistence adapters.
library;

import 'dart:convert';

import '../../../core/utils/date_utils.dart';
import '../domain/mindmap_node.dart';
import '../domain/mindmap_repository.dart';

abstract interface class MindmapNodeStore {
  Future<String?> readNodesJson();

  Future<void> writeNodesJson(String value);
}

final class PersistentMindmapRepository implements MindmapRepository {
  PersistentMindmapRepository({
    required MindmapNodeStore store,
    Iterable<MindmapNode> seedNodes = const [],
  }) : _store = store,
       _seedNodes = List.unmodifiable(seedNodes);

  static const int _schemaVersion = 1;

  final MindmapNodeStore _store;
  final List<MindmapNode> _seedNodes;
  final Map<String, MindmapNode> _nodesById = {};
  bool _didLoad = false;

  @override
  Future<void> deleteNode(String id) async {
    await _load();
    if (_nodesById.remove(id) != null) await _persist();
  }

  @override
  Future<MindmapNode?> getNode(String id) async {
    await _load();
    return _nodesById[id];
  }

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) async {
    await _load();
    final normalizedDay = day?.dateOnly;
    final nodes = _nodesById.values.where((node) {
      return normalizedDay == null || node.day.isSameDay(normalizedDay);
    }).toList();

    nodes.sort(_compareNodes);
    return List.unmodifiable(nodes);
  }

  @override
  Future<MindmapNode> saveNode(MindmapNode node) async {
    await _load();
    final saved = node.copyWith(day: node.day.dateOnly);
    _nodesById[saved.id] = saved;
    await _persist();
    return saved;
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) async {
    await _load();
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return listNodes();

    final nodes = _nodesById.values
        .where((node) => _matchesNode(node, normalized))
        .toList();

    nodes.sort(_compareNodes);
    return List.unmodifiable(nodes);
  }

  Future<void> _load() async {
    if (_didLoad) return;
    _didLoad = true;

    final rawJson = await _store.readNodesJson();
    if (rawJson == null) {
      for (final node in _seedNodes) {
        final normalized = node.copyWith(day: node.day.dateOnly);
        _nodesById[normalized.id] = normalized;
      }
      if (_nodesById.isNotEmpty) await _persist();
      return;
    }

    final decoded = jsonDecode(rawJson);
    final rawNodes = decoded is Map<String, Object?>
        ? decoded['nodes']
        : decoded is List
        ? decoded
        : const <Object?>[];

    if (rawNodes is! List) return;

    for (final rawNode in rawNodes) {
      if (rawNode is Map) {
        final node = MindmapNode.fromJson(rawNode.cast<String, Object?>());
        _nodesById[node.id] = node;
      }
    }
  }

  Future<void> _persist() async {
    final nodes = _nodesById.values.toList()..sort(_compareNodes);
    await _store.writeNodesJson(
      jsonEncode({
        'version': _schemaVersion,
        'nodes': [for (final node in nodes) node.toJson()],
      }),
    );
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

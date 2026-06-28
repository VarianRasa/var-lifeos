/// Mindmap repository backed by the local database with legacy migration.
library;

import 'dart:convert';

import '../../../core/utils/date_utils.dart';
import '../domain/mindmap_node.dart';
import '../domain/mindmap_repository.dart';
import 'persistent_mindmap_repository.dart';
import 'sembast_mindmap_node_database.dart';

final class LocalDatabaseMindmapRepository implements MindmapRepository {
  LocalDatabaseMindmapRepository({
    required MindmapNodeDatabase database,
    MindmapNodeStore? legacyStore,
    Iterable<MindmapNode> seedNodes = const [],
  }) : _database = database,
       _legacyStore = legacyStore,
       _seedNodes = List.unmodifiable(seedNodes);

  final MindmapNodeDatabase _database;
  final MindmapNodeStore? _legacyStore;
  final List<MindmapNode> _seedNodes;
  Future<void>? _initialization;

  @override
  Future<void> deleteNode(String id) async {
    await _ensureInitialized();
    await _database.deleteNode(id);
  }

  @override
  Future<MindmapNode?> getNode(String id) async {
    await _ensureInitialized();
    return _database.getNode(id);
  }

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) async {
    await _ensureInitialized();
    return _database.listNodes(day: day?.dateOnly);
  }

  @override
  Future<MindmapNode> saveNode(MindmapNode node) async {
    await _ensureInitialized();
    return _database.upsertNode(node.copyWith(day: node.day.dateOnly));
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) async {
    await _ensureInitialized();
    return _database.searchNodes(query);
  }

  Future<void> _ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    if (await _database.isInitialized) return;

    final migratedNodes = await _readLegacyNodes();
    final initialNodes = migratedNodes.isNotEmpty ? migratedNodes : _seedNodes;

    for (final node in initialNodes) {
      await _database.upsertNode(node.copyWith(day: node.day.dateOnly));
    }

    await _database.markInitialized();
    if (migratedNodes.isNotEmpty) {
      await _archiveLegacyNodes();
    }
  }

  Future<List<MindmapNode>> _readLegacyNodes() async {
    final legacyStore = _legacyStore;
    if (legacyStore == null) return const [];

    final rawJson = await legacyStore.readNodesJson();
    if (rawJson == null || rawJson.trim().isEmpty) return const [];

    Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException {
      return const [];
    }

    final rawNodes = decoded is Map<String, Object?>
        ? decoded['nodes']
        : decoded is List
        ? decoded
        : const <Object?>[];
    if (rawNodes is! List) return const [];

    final nodes = <MindmapNode>[];
    for (final rawNode in rawNodes) {
      if (rawNode is! Map) continue;

      try {
        nodes.add(MindmapNode.fromJson(rawNode.cast<String, Object?>()));
      } on FormatException {
        continue;
      } on ArgumentError {
        continue;
      } on TypeError {
        continue;
      }
    }

    return List.unmodifiable(nodes);
  }

  Future<void> _archiveLegacyNodes() async {
    final legacyStore = _legacyStore;
    if (legacyStore == null) return;

    await legacyStore.writeNodesJson(
      jsonEncode({
        'version': 2,
        'migratedToLocalDatabase': true,
        'nodes': <Object?>[],
      }),
    );
  }
}

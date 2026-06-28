/// Sembast-backed local database for mindmap nodes.
library;

import 'dart:async';

import 'package:sembast/sembast.dart';

import '../../../core/utils/date_utils.dart';
import '../domain/mindmap_node.dart';

abstract interface class MindmapNodeDatabase {
  Future<bool> get isInitialized;

  Future<void> markInitialized();

  Future<List<MindmapNode>> listNodes({DateTime? day});

  Future<MindmapNode?> getNode(String id);

  Future<MindmapNode> upsertNode(MindmapNode node);

  Future<void> deleteNode(String id);

  Future<List<MindmapNode>> searchNodes(String query);
}

final class SembastMindmapNodeDatabase implements MindmapNodeDatabase {
  SembastMindmapNodeDatabase({required FutureOr<Database> database})
    : _databaseSource = database;

  static const String _nodeStoreName = 'mindmap_nodes';
  static const String _metaStoreName = 'mindmap_meta';
  static const String _stateKey = 'state';

  final FutureOr<Database> _databaseSource;
  final StoreRef<String, Map<String, Object?>> _nodeStore =
      stringMapStoreFactory.store(_nodeStoreName);
  final StoreRef<String, Map<String, Object?>> _metaStore =
      stringMapStoreFactory.store(_metaStoreName);
  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;

    final opened = await Future<Database>.value(_databaseSource);
    _database = opened;
    return opened;
  }

  @override
  Future<bool> get isInitialized async {
    final db = await _db;
    final state = await _metaStore.record(_stateKey).get(db);
    return state?['initialized'] == true;
  }

  @override
  Future<void> markInitialized() async {
    final db = await _db;
    await _metaStore.record(_stateKey).put(db, {
      'initialized': true,
      'schemaVersion': 2,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> deleteNode(String id) async {
    final db = await _db;
    await _nodeStore.record(id).delete(db);
  }

  @override
  Future<MindmapNode?> getNode(String id) async {
    final db = await _db;
    final value = await _nodeStore.record(id).get(db);
    if (value == null) return null;
    return _nodeFromRecordValue(value);
  }

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) async {
    final db = await _db;
    final finder = Finder(
      filter: day == null ? null : Filter.equals('day', dayKey(day)),
      sortOrders: _sortOrders,
    );
    final records = await _nodeStore.find(db, finder: finder);

    return List.unmodifiable(
      records.map((record) {
        return _nodeFromRecordValue(record.value);
      }),
    );
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) async {
    final normalized = _normalizeSearchText(query);
    if (normalized.isEmpty) return listNodes();

    final db = await _db;
    final records = await _nodeStore.find(
      db,
      finder: Finder(sortOrders: _sortOrders),
    );
    final matches = records
        .where((record) {
          final searchText = record.value['searchText'] as String? ?? '';
          return searchText.contains(normalized);
        })
        .map((record) {
          return _nodeFromRecordValue(record.value);
        });

    return List.unmodifiable(matches);
  }

  @override
  Future<MindmapNode> upsertNode(MindmapNode node) async {
    final db = await _db;
    final saved = node.copyWith(day: node.day.dateOnly);
    await _nodeStore.record(saved.id).put(db, _recordValueFor(saved));
    return saved;
  }

  List<SortOrder> get _sortOrders => [
    SortOrder('day'),
    SortOrder('createdAt'),
    SortOrder('titleSearch'),
  ];
}

MindmapNode _nodeFromRecordValue(Map<String, Object?> value) {
  final rawNode = value['node'];
  if (rawNode is! Map) {
    throw const FormatException(
      'Mindmap node database record is missing node.',
    );
  }

  return MindmapNode.fromJson(rawNode.cast<String, Object?>());
}

Map<String, Object?> _recordValueFor(MindmapNode node) {
  return {
    'node': node.toJson(),
    'day': dayKey(node.day),
    'type': node.type.name,
    'status': node.status.name,
    'priority': node.priority.name,
    'titleSearch': _normalizeSearchText(node.title),
    'projectSearch': _normalizeSearchText(node.project),
    'areaSearch': _normalizeSearchText(node.area),
    'tags': node.tags,
    'createdAt': node.createdAt.toIso8601String(),
    'updatedAt': node.updatedAt.toIso8601String(),
    'searchText': _searchTextFor(node),
  };
}

String _searchTextFor(MindmapNode node) {
  final values = <String>[
    node.id,
    node.title,
    node.body,
    node.type.name,
    node.type.label,
    node.status.name,
    node.status.label,
    node.priority.name,
    node.priority.label,
    node.project,
    node.area,
    dayKey(node.day),
    if (node.dueDate != null) dayKey(node.dueDate!),
    ...node.tags,
    ...node.relatedNodeIds,
  ];

  return _normalizeSearchText(values.join(' '));
}

String _normalizeSearchText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

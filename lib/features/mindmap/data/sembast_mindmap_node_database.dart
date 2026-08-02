library;

import 'dart:async';

import 'package:sembast/sembast.dart';

import '../../../core/utils/date_utils.dart';
import '../domain/mindmap_node.dart';
import '../domain/mindmap_node_revision.dart';
import '../domain/mindmap_node_revision_repository.dart';

abstract interface class MindmapNodeDatabase
    implements MindmapNodeRevisionRepository {
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

  static const String _stateKey = 'state';
  static const int _revisionLimit = 50;

  final FutureOr<Database> _databaseSource;
  final StoreRef<String, Map<String, Object?>> _nodeStore =
      stringMapStoreFactory.store('mindmap_nodes');
  final StoreRef<String, Map<String, Object?>> _metaStore =
      stringMapStoreFactory.store('mindmap_meta');
  final StoreRef<String, Map<String, Object?>> _revisionStore =
      stringMapStoreFactory.store('mindmap_node_revisions');
  final StoreRef<String, Map<String, Object?>> _revisionHeadStore =
      stringMapStoreFactory.store('mindmap_node_revision_heads');
  Database? _database;

  Future<Database> get _db async =>
      _database ??= await Future<Database>.value(_databaseSource);

  Future<Database> get database => _db;

  @override
  Future<bool> get isInitialized async {
    final state = await _metaStore.record(_stateKey).get(await _db);
    return state?['initialized'] == true;
  }

  @override
  Future<void> markInitialized() async {
    await _metaStore.record(_stateKey).put(await _db, {
      'initialized': true,
      'schemaVersion': 3,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> deleteNode(String id) async {
    final db = await _db;
    await db.transaction((transaction) async {
      final value = await _nodeStore.record(id).get(transaction);
      if (value == null) return;
      final node = _nodeFromRecordValue(value);
      await _appendRevision(transaction, node, MindmapNodeRevisionKind.deleted);
      await _nodeStore.record(id).delete(transaction);
    });
  }

  @override
  Future<MindmapNode?> getNode(String id) async {
    final value = await _nodeStore.record(id).get(await _db);
    return value == null ? null : _nodeFromRecordValue(value);
  }

  @override
  Future<MindmapNodeRevision?> getRevision(String revisionId) async {
    final value = await _revisionStore.record(revisionId).get(await _db);
    return value == null ? null : MindmapNodeRevision.fromJson(value);
  }

  @override
  Future<List<MindmapNodeRevision>> listRevisions(
    String nodeId, {
    int limit = 50,
  }) async {
    if (limit < 1 || limit > _revisionLimit) {
      throw RangeError.range(limit, 1, _revisionLimit, 'limit');
    }
    final records = await _revisionStore.find(
      await _db,
      finder: Finder(
        filter: Filter.equals('nodeId', nodeId),
        sortOrders: [SortOrder('sequence', false)],
        limit: limit,
      ),
    );
    return List.unmodifiable(
      records.map((record) => MindmapNodeRevision.fromJson(record.value)),
    );
  }

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) async {
    final records = await _nodeStore.find(
      await _db,
      finder: Finder(
        filter: day == null ? null : Filter.equals('day', dayKey(day)),
        sortOrders: _sortOrders,
      ),
    );
    return List.unmodifiable(
      records.map((record) => _nodeFromRecordValue(record.value)),
    );
  }

  @override
  Future<MindmapNode> restoreRevision(
    String revisionId, {
    required DateTime now,
  }) async {
    final db = await _db;
    return db.transaction((transaction) async {
      final value = await _revisionStore.record(revisionId).get(transaction);
      if (value == null) throw StateError('Revision not found: $revisionId');
      final revision = MindmapNodeRevision.fromJson(value);
      final restored = revision.snapshot.copyWith(updatedAt: now);
      await _appendRevision(
        transaction,
        restored,
        MindmapNodeRevisionKind.restored,
      );
      await _nodeStore
          .record(restored.id)
          .put(transaction, _recordValueFor(restored));
      return restored;
    });
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) async {
    final normalized = _normalizeSearchText(query);
    if (normalized.isEmpty) return listNodes();
    final records = await _nodeStore.find(
      await _db,
      finder: Finder(sortOrders: _sortOrders),
    );
    return List.unmodifiable(
      records
          .where(
            (record) => (record.value['searchText'] as String? ?? '').contains(
              normalized,
            ),
          )
          .map((record) => _nodeFromRecordValue(record.value)),
    );
  }

  @override
  Future<MindmapNode> upsertNode(MindmapNode node) async {
    final saved = node.copyWith(day: node.day.dateOnly);
    final db = await _db;
    return db.transaction((transaction) async {
      final oldValue = await _nodeStore.record(saved.id).get(transaction);
      final old = oldValue == null ? null : _nodeFromRecordValue(oldValue);
      if (old == saved) return saved;
      final head = await _revisionHeadStore.record(saved.id).get(transaction);
      if (old != null && head == null) {
        await _appendRevision(
          transaction,
          old,
          MindmapNodeRevisionKind.baseline,
        );
      }
      await _appendRevision(
        transaction,
        saved,
        old == null
            ? MindmapNodeRevisionKind.created
            : MindmapNodeRevisionKind.updated,
      );
      await _nodeStore
          .record(saved.id)
          .put(transaction, _recordValueFor(saved));
      return saved;
    });
  }

  Future<void> _appendRevision(
    DatabaseClient transaction,
    MindmapNode snapshot,
    MindmapNodeRevisionKind kind,
  ) async {
    final headRecord = _revisionHeadStore.record(snapshot.id);
    final head = await headRecord.get(transaction);
    final sequence = (head?['sequence'] as int? ?? 0) + 1;
    final id = '${snapshot.id}:$sequence';
    final revision = MindmapNodeRevision(
      id: id,
      nodeId: snapshot.id,
      sequence: sequence,
      kind: kind,
      recordedAt: DateTime.now().toUtc(),
      snapshot: snapshot,
    );
    await _revisionStore.record(id).put(transaction, revision.toJson());
    await headRecord.put(transaction, {'sequence': sequence});
    final stale = await _revisionStore.findKeys(
      transaction,
      finder: Finder(
        filter: Filter.equals('nodeId', snapshot.id),
        sortOrders: [SortOrder('sequence', false)],
        offset: _revisionLimit,
      ),
    );
    for (final key in stale) {
      await _revisionStore.record(key).delete(transaction);
    }
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

Map<String, Object?> _recordValueFor(MindmapNode node) => {
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

String _searchTextFor(MindmapNode node) => _normalizeSearchText(
  [
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
  ].join(' '),
);

String _normalizeSearchText(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

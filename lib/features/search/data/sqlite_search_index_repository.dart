import 'package:sqlite3/common.dart';

import '../domain/search_document.dart';
import '../domain/search_index_repository.dart';
import '../domain/search_query.dart';
import '../domain/search_ranking.dart';
import '../domain/search_result.dart';

final class SqliteSearchIndexRepository implements SearchIndexRepository {
  SqliteSearchIndexRepository(this._database) {
    _database.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS search_documents USING fts5(
        id UNINDEXED,
        source_id UNINDEXED,
        fragment_id UNINDEXED,
        source_kind UNINDEXED,
        workspace_id UNINDEXED,
        board_id UNINDEXED,
        creator_id UNINDEXED,
        status UNINDEXED,
        title,
        snippet,
        text,
        date_millis UNINDEXED,
        modified_millis UNINDEXED,
        extraction_state UNINDEXED
      )
    ''');
  }

  final CommonDatabase _database;

  @override
  Future<void> upsertAll(Iterable<SearchDocument> documents) async {
    final grouped = <SearchSourceRef, List<SearchDocument>>{};
    for (final document in documents) {
      final source = SearchSourceRef(
        kind: document.sourceKind,
        sourceId: document.sourceId,
      );
      grouped.putIfAbsent(source, () => []).add(document);
    }
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final entry in grouped.entries) {
        _database.execute(
          'DELETE FROM search_documents WHERE source_kind = ? AND source_id = ?',
          [entry.key.kind.name, entry.key.sourceId],
        );
        for (final document in entry.value) {
          _database.execute(
            '''INSERT INTO search_documents (
              id, source_id, fragment_id, source_kind, workspace_id, board_id,
              creator_id, status, title, snippet, text, date_millis,
              modified_millis, extraction_state
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
            [
              document.id,
              document.sourceId,
              document.fragmentId,
              document.sourceKind.name,
              document.workspaceId,
              document.boardId,
              document.creatorId,
              document.status,
              document.title,
              document.snippet,
              document.text,
              document.date?.millisecondsSinceEpoch,
              document.modifiedAt.millisecondsSinceEpoch,
              document.extractionState.name,
            ],
          );
        }
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> deleteSources(Set<SearchSourceRef> sources) async {
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final source in sources) {
        _database.execute(
          'DELETE FROM search_documents WHERE source_kind = ? AND source_id = ?',
          [source.kind.name, source.sourceId],
        );
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> deleteBoard(String boardId) async {
    _database.execute('DELETE FROM search_documents WHERE board_id = ?', [
      boardId,
    ]);
  }

  @override
  Future<List<SearchResult>> search(SearchQuery query, {int limit = 50}) async {
    final conditions = <String>[];
    final parameters = <Object?>[];
    final text = query.text.trim();
    if (text.isNotEmpty) {
      conditions.add('search_documents MATCH ?');
      parameters.add(_ftsQuery(text));
    }
    _appendSetFilter(
      conditions,
      parameters,
      'workspace_id',
      query.filters.workspaceIds,
    );
    _appendSetFilter(
      conditions,
      parameters,
      'board_id',
      query.filters.boardIds,
    );
    _appendSetFilter(
      conditions,
      parameters,
      'creator_id',
      query.filters.creatorIds,
    );
    _appendSetFilter(conditions, parameters, 'status', query.filters.statuses);
    _appendSetFilter(
      conditions,
      parameters,
      'source_kind',
      query.filters.sourceKinds.map((kind) => kind.name).toSet(),
    );
    if (query.filters.dateFrom != null) {
      conditions.add('date_millis >= ?');
      parameters.add(query.filters.dateFrom!.millisecondsSinceEpoch);
    }
    if (query.filters.dateTo != null) {
      conditions.add('date_millis <= ?');
      parameters.add(query.filters.dateTo!.millisecondsSinceEpoch);
    }
    parameters.add(limit);
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rankExpression = text.isEmpty ? '0.0' : 'bm25(search_documents)';
    final rows = _database.select('''SELECT *, $rankExpression AS text_rank
         FROM search_documents $where
         ORDER BY text_rank, modified_millis DESC, id
         LIMIT ?''', parameters);
    final now = DateTime.now().toUtc();
    return [
      for (final row in rows)
        SearchResult(
          document: _documentFromRow(row),
          rank: rankSearchResult(
            bm25: (row['text_rank'] as num).toDouble(),
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(
              row['modified_millis'] as int,
              isUtc: true,
            ),
            workspaceId: row['workspace_id'] as String,
            activeWorkspaceId: query.activeWorkspaceId,
            now: now,
          ),
        ),
    ]..sort((left, right) {
      final rank = right.rank.compareTo(left.rank);
      if (rank != 0) return rank;
      final modified = right.document.modifiedAt.compareTo(
        left.document.modifiedAt,
      );
      if (modified != 0) return modified;
      return left.document.id.compareTo(right.document.id);
    });
  }

  @override
  Future<void> clear() async {
    _database.execute('DELETE FROM search_documents');
  }

  @override
  void close() => _database.close();
}

void _appendSetFilter(
  List<String> conditions,
  List<Object?> parameters,
  String column,
  Set<String> values,
) {
  if (values.isEmpty) return;
  conditions.add('$column IN (${List.filled(values.length, '?').join(', ')})');
  parameters.addAll(values);
}

String _ftsQuery(String input) {
  final tokens = input
      .split(RegExp(r'\s+'))
      .map((token) => token.replaceAll('"', ''))
      .where((token) => token.isNotEmpty);
  return tokens.map((token) => '"$token"*').join(' AND ');
}

SearchDocument _documentFromRow(Row row) {
  return SearchDocument(
    id: row['id'] as String,
    sourceId: row['source_id'] as String,
    fragmentId: row['fragment_id'] as String,
    sourceKind: SearchSourceKind.values.byName(row['source_kind'] as String),
    workspaceId: row['workspace_id'] as String,
    boardId: row['board_id'] as String?,
    creatorId: row['creator_id'] as String?,
    status: row['status'] as String?,
    title: row['title'] as String,
    snippet: row['snippet'] as String,
    text: row['text'] as String,
    date: row['date_millis'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            row['date_millis'] as int,
            isUtc: true,
          ),
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(
      row['modified_millis'] as int,
      isUtc: true,
    ),
    extractionState: SearchExtractionState.values.byName(
      row['extraction_state'] as String,
    ),
  );
}

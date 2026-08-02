import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:var_app/features/search/data/sqlite_search_index_repository.dart';
import 'package:var_app/features/search/domain/search_document.dart';
import 'package:var_app/features/search/domain/search_index_repository.dart';
import 'package:var_app/features/search/domain/search_query.dart';

void main() {
  late Database database;
  late SqliteSearchIndexRepository repository;

  setUp(() {
    database = sqlite3.openInMemory();
    repository = SqliteSearchIndexRepository(database);
  });

  tearDown(() => repository.close());

  SearchDocument document({
    required String id,
    required String sourceId,
    required String text,
    String workspaceId = 'work',
    String? boardId,
  }) => SearchDocument(
    id: id,
    sourceId: sourceId,
    fragmentId: id,
    sourceKind: SearchSourceKind.node,
    workspaceId: workspaceId,
    boardId: boardId,
    title: text,
    snippet: text,
    text: text,
    modifiedAt: DateTime.utc(2026, 8, 3),
  );

  test('upsert replaces stale source fragments atomically', () async {
    await repository.upsertAll([
      document(id: 'node:1:old', sourceId: '1', text: 'old phrase'),
    ]);
    await repository.upsertAll([
      document(id: 'node:1:new', sourceId: '1', text: 'new phrase'),
    ]);

    expect(await repository.search(const SearchQuery(text: 'old')), isEmpty);
    expect(
      await repository.search(const SearchQuery(text: 'new')),
      hasLength(1),
    );
  });

  test('search applies workspace and board filters', () async {
    await repository.upsertAll([
      document(
        id: 'node:1:main',
        sourceId: '1',
        text: 'launch plan',
        workspaceId: 'alpha',
        boardId: 'roadmap',
      ),
      document(
        id: 'node:2:main',
        sourceId: '2',
        text: 'launch notes',
        workspaceId: 'beta',
        boardId: 'notes',
      ),
    ]);

    final results = await repository.search(
      const SearchQuery(
        text: 'launch',
        filters: SearchFilters(workspaceIds: {'alpha'}, boardIds: {'roadmap'}),
      ),
    );

    expect(results.map((result) => result.document.sourceId), ['1']);
  });

  test('deleteSources removes every fragment', () async {
    await repository.upsertAll([
      document(id: 'node:1:a', sourceId: '1', text: 'shared alpha'),
      document(id: 'node:1:b', sourceId: '1', text: 'shared beta'),
    ]);

    await repository.deleteSources({
      const SearchSourceRef(kind: SearchSourceKind.node, sourceId: '1'),
    });

    expect(await repository.search(const SearchQuery(text: 'shared')), isEmpty);
  });
}

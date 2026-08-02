import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/search/application/search_index_coordinator.dart';
import 'package:var_app/features/search/domain/search_document.dart';
import 'package:var_app/features/search/domain/search_index_repository.dart';
import 'package:var_app/features/search/domain/search_query.dart';
import 'package:var_app/features/search/domain/search_result.dart';

void main() {
  test('indexes replacement documents and deletes sources', () async {
    final repository = _RecordingRepository();
    final coordinator = SearchIndexCoordinator(repository);
    final document = SearchDocument(
      id: 'node:1:main',
      sourceId: '1',
      fragmentId: 'main',
      sourceKind: SearchSourceKind.node,
      workspaceId: 'daily',
      title: 'One',
      snippet: '',
      text: 'One',
      modifiedAt: DateTime.utc(2026, 8, 3),
    );

    await coordinator.indexDocuments([document]);
    await coordinator.removeSource(
      const SearchSourceRef(kind: SearchSourceKind.node, sourceId: '1'),
    );

    expect(repository.upserts.single, [document]);
    expect(repository.deletions.single.single.sourceId, '1');
  });
}

final class _RecordingRepository implements SearchIndexRepository {
  final upserts = <List<SearchDocument>>[];
  final deletions = <Set<SearchSourceRef>>[];

  @override
  Future<void> upsertAll(Iterable<SearchDocument> documents) async {
    upserts.add(documents.toList());
  }

  @override
  Future<void> deleteSources(Set<SearchSourceRef> sources) async {
    deletions.add(sources);
  }

  @override
  Future<List<SearchResult>> search(
    SearchQuery query, {
    int limit = 50,
  }) async => const [];

  @override
  Future<void> clear() async {}

  @override
  void close() {}
}

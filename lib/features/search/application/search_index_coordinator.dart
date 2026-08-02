import '../domain/search_document.dart';
import '../domain/search_index_repository.dart';

final class SearchIndexCoordinator {
  const SearchIndexCoordinator(this._repository);

  final SearchIndexRepository _repository;

  Future<void> indexDocuments(Iterable<SearchDocument> documents) =>
      _repository.upsertAll(documents);

  Future<void> removeSource(SearchSourceRef source) =>
      _repository.deleteSources({source});

  Future<void> rebuild(Iterable<SearchDocument> documents) async {
    await _repository.clear();
    for (final batch in _batches(documents, 200)) {
      await _repository.upsertAll(batch);
    }
  }
}

Iterable<List<SearchDocument>> _batches(
  Iterable<SearchDocument> documents,
  int size,
) sync* {
  var batch = <SearchDocument>[];
  for (final document in documents) {
    batch.add(document);
    if (batch.length == size) {
      yield batch;
      batch = <SearchDocument>[];
    }
  }
  if (batch.isNotEmpty) yield batch;
}

import 'search_document.dart';
import 'search_query.dart';
import 'search_result.dart';

final class SearchSourceRef {
  const SearchSourceRef({required this.kind, required this.sourceId});

  final SearchSourceKind kind;
  final String sourceId;

  @override
  bool operator ==(Object other) =>
      other is SearchSourceRef &&
      other.kind == kind &&
      other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(kind, sourceId);
}

abstract interface class SearchIndexRepository {
  Future<void> upsertAll(Iterable<SearchDocument> documents);

  Future<void> deleteSources(Set<SearchSourceRef> sources);

  Future<void> deleteBoard(String boardId);

  Future<List<SearchResult>> search(SearchQuery query, {int limit = 50});

  Future<void> clear();

  void close();
}

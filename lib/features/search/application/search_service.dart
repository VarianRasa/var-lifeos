import '../domain/search_index_repository.dart';
import '../domain/search_query.dart';
import '../domain/search_result.dart';

final class SearchService {
  const SearchService(this._repository);

  final SearchIndexRepository _repository;

  Future<List<SearchResult>> search(SearchQuery query, {int limit = 50}) =>
      _repository.search(query, limit: limit.clamp(1, 100));
}

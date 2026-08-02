import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/search/application/search_service.dart';
import 'package:var_app/features/search/domain/search_document.dart';
import 'package:var_app/features/search/domain/search_index_repository.dart';
import 'package:var_app/features/search/domain/search_query.dart';
import 'package:var_app/features/search/domain/search_result.dart';

void main() {
  test('delegates query and bounded page size', () async {
    final repository = _Repository();
    final service = SearchService(repository);

    await service.search(const SearchQuery(text: 'launch'), limit: 25);

    expect(repository.query?.text, 'launch');
    expect(repository.limit, 25);
  });
}

final class _Repository implements SearchIndexRepository {
  SearchQuery? query;
  int? limit;

  @override
  Future<List<SearchResult>> search(SearchQuery query, {int limit = 50}) async {
    this.query = query;
    this.limit = limit;
    return const [];
  }

  @override
  Future<void> upsertAll(Iterable<SearchDocument> documents) async {}

  @override
  Future<void> deleteSources(Set<SearchSourceRef> sources) async {}

  @override
  Future<void> clear() async {}

  @override
  void close() {}
}

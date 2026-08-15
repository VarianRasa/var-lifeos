import 'search_document.dart';

final class SearchResult {
  const SearchResult({required this.document, required this.rank});

  final SearchDocument document;
  final double rank;
}

/// Quote discovery contracts independent from Firebase and Flutter.
library;

String normalizeLegacyQuoteBody(String value) {
  if (!value.contains('Quote text here.')) return value;
  if (value.contains('Author: Unknown') || value.contains('?')) {
    return '?Quote text here.?';
  }
  return value;
}

final class QuoteAuthor {
  const QuoteAuthor({
    required this.id,
    required this.name,
    required this.slug,
    this.description = '',
    this.quoteCount = 0,
  });

  factory QuoteAuthor.fromMap(Map<Object?, Object?> map) => QuoteAuthor(
    id: _requiredString(map, 'id'),
    name: _requiredString(map, 'name'),
    slug: _requiredString(map, 'slug'),
    description: _optionalString(map, 'description'),
    quoteCount: _boundedInt(map['quoteCount'], min: 0, max: 100000),
  );

  final String id;
  final String name;
  final String slug;
  final String description;
  final int quoteCount;
}

final class CatalogQuote {
  const CatalogQuote({
    required this.id,
    required this.text,
    required this.authorName,
    required this.authorSlug,
    required this.provider,
    this.tags = const <String>[],
    this.sourceUrl = '',
  });

  factory CatalogQuote.fromMap(Map<Object?, Object?> map) => CatalogQuote(
    id: _requiredString(map, 'id'),
    text: _requiredString(map, 'text', maxLength: 4000),
    authorName: _requiredString(map, 'authorName'),
    authorSlug: _requiredString(map, 'authorSlug'),
    provider: _requiredString(map, 'provider'),
    tags: _stringList(map['tags'], maxItems: 20, maxLength: 80),
    sourceUrl: _optionalString(map, 'sourceUrl', maxLength: 2000),
  );

  final String id;
  final String text;
  final String authorName;
  final String authorSlug;
  final String provider;
  final List<String> tags;
  final String sourceUrl;
}

final class QuoteAuthorPage {
  const QuoteAuthorPage({
    required this.authors,
    required this.page,
    required this.totalPages,
    required this.hasNextPage,
  });

  factory QuoteAuthorPage.fromMap(Map<Object?, Object?> map) => QuoteAuthorPage(
    authors: _mapList(map['authors'], QuoteAuthor.fromMap, maxItems: 30),
    page: _boundedInt(map['page'], min: 1, max: 1000, fallback: 1),
    totalPages: _boundedInt(map['totalPages'], min: 0, max: 1000, fallback: 0),
    hasNextPage: map['hasNextPage'] == true,
  );

  final List<QuoteAuthor> authors;
  final int page;
  final int totalPages;
  final bool hasNextPage;
}

final class CatalogQuotePage {
  const CatalogQuotePage({
    required this.quotes,
    required this.page,
    required this.totalPages,
    required this.hasNextPage,
  });

  factory CatalogQuotePage.fromMap(Map<Object?, Object?> map) =>
      CatalogQuotePage(
        quotes: _mapList(map['quotes'], CatalogQuote.fromMap, maxItems: 30),
        page: _boundedInt(map['page'], min: 1, max: 1000, fallback: 1),
        totalPages: _boundedInt(
          map['totalPages'],
          min: 0,
          max: 1000,
          fallback: 0,
        ),
        hasNextPage: map['hasNextPage'] == true,
      );

  final List<CatalogQuote> quotes;
  final int page;
  final int totalPages;
  final bool hasNextPage;
}

class QuoteCatalogException implements Exception {
  const QuoteCatalogException(this.message, {this.code = 'unknown'});

  final String code;
  final String message;

  @override
  String toString() => 'QuoteCatalogException($code): $message';
}

abstract interface class QuoteCatalogRepository {
  Future<List<QuoteAuthor>> popularAuthors();

  Future<QuoteAuthorPage> searchAuthors({
    required String query,
    int page = 1,
    int limit = 20,
  });

  Future<CatalogQuotePage> quotesByAuthor({
    required String authorSlug,
    int page = 1,
    int limit = 20,
  });
}

String _requiredString(
  Map<Object?, Object?> map,
  String key, {
  int maxLength = 500,
}) {
  final value = _optionalString(map, key, maxLength: maxLength);
  if (value.isEmpty) {
    throw QuoteCatalogException('Missing $key.', code: 'invalid-response');
  }
  return value;
}

String _optionalString(
  Map<Object?, Object?> map,
  String key, {
  int maxLength = 500,
}) {
  final value = map[key];
  if (value is! String) return '';
  final trimmed = value.trim();
  return trimmed.length <= maxLength
      ? trimmed
      : trimmed.substring(0, maxLength);
}

int _boundedInt(
  Object? value, {
  required int min,
  required int max,
  int fallback = 0,
}) {
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (parsed == null) return fallback;
  return parsed.clamp(min, max);
}

List<String> _stringList(
  Object? value, {
  required int maxItems,
  required int maxLength,
}) {
  if (value is! List) return const <String>[];
  return List<String>.unmodifiable([
    for (final item in value.take(maxItems))
      if (item is String && item.trim().isNotEmpty)
        item.trim().length <= maxLength
            ? item.trim()
            : item.trim().substring(0, maxLength),
  ]);
}

List<T> _mapList<T>(
  Object? value,
  T Function(Map<Object?, Object?> map) parser, {
  required int maxItems,
}) {
  if (value is! List) {
    throw const QuoteCatalogException(
      'Expected a list response.',
      code: 'invalid-response',
    );
  }
  return List<T>.unmodifiable([
    for (final item in value.take(maxItems))
      if (item is Map) parser(Map<Object?, Object?>.from(item)),
  ]);
}

/// HTTP adapter for the Cloudflare Quote catalog Worker.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/quote_catalog.dart';

final class HttpQuoteCatalog implements QuoteCatalogRepository {
  const HttpQuoteCatalog({required this.endpoint, required http.Client client})
    : _client = client;

  final Uri endpoint;
  final http.Client _client;

  @override
  Future<List<QuoteAuthor>> popularAuthors() async {
    final map = await _get('authors/popular');
    final authors = map['authors'];
    if (authors is! List) {
      throw const QuoteCatalogException(
        'Invalid popular authors response.',
        code: 'invalid-response',
      );
    }
    return List<QuoteAuthor>.unmodifiable([
      for (final item in authors.take(30))
        if (item is Map) QuoteAuthor.fromMap(Map<Object?, Object?>.from(item)),
    ]);
  }

  @override
  Future<QuoteAuthorPage> searchAuthors({
    required String query,
    int page = 1,
    int limit = 20,
  }) async => QuoteAuthorPage.fromMap(
    await _get(
      'authors/search',
      query: <String, String>{
        'q': query.trim(),
        'page': '$page',
        'limit': '$limit',
      },
    ),
  );

  @override
  Future<CatalogQuotePage> quotesByAuthor({
    required String authorSlug,
    int page = 1,
    int limit = 20,
  }) async => CatalogQuotePage.fromMap(
    await _get(
      'quotes',
      query: <String, String>{
        'author': authorSlug.trim(),
        'page': '$page',
        'limit': '$limit',
      },
    ),
  );

  Future<Map<Object?, Object?>> _get(
    String path, {
    Map<String, String> query = const <String, String>{},
  }) async {
    final base = endpoint.path.endsWith('/')
        ? endpoint
        : endpoint.replace(path: '${endpoint.path}/');
    final uri = base.resolve(path).replace(queryParameters: query);
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw QuoteCatalogException(
          'Quote catalog returned HTTP ${response.statusCode}.',
          code: 'http-${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const QuoteCatalogException(
          'Invalid catalog response.',
          code: 'invalid-response',
        );
      }
      return Map<Object?, Object?>.from(decoded);
    } on TimeoutException {
      throw const QuoteCatalogException(
        'Quote catalog request timed out.',
        code: 'timeout',
      );
    } on FormatException {
      throw const QuoteCatalogException(
        'Quote catalog returned malformed JSON.',
        code: 'invalid-response',
      );
    } on QuoteCatalogException {
      rethrow;
    } on Object {
      throw const QuoteCatalogException(
        'Quote catalog is unavailable.',
        code: 'unavailable',
      );
    }
  }
}

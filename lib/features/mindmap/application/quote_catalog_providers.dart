/// Quote catalog dependency providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/runtime_config.dart';
import '../data/http_quote_catalog.dart';
import '../domain/quote_catalog.dart';

final quoteHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final quoteCatalogRepositoryProvider = Provider<QuoteCatalogRepository>((ref) {
  final endpoint = ref.watch(runtimeConfigProvider).quoteEndpoint;
  if (endpoint == null) return const UnsupportedQuoteCatalog();
  return HttpQuoteCatalog(
    endpoint: endpoint,
    client: ref.watch(quoteHttpClientProvider),
  );
});

final class UnsupportedQuoteCatalog implements QuoteCatalogRepository {
  const UnsupportedQuoteCatalog();

  Never _unsupported() => throw const QuoteCatalogException(
    'Online Quote discovery is not configured.',
    code: 'unsupported-platform',
  );

  @override
  Future<List<QuoteAuthor>> popularAuthors() async => _unsupported();

  @override
  Future<QuoteAuthorPage> searchAuthors({
    required String query,
    int page = 1,
    int limit = 20,
  }) async => _unsupported();

  @override
  Future<CatalogQuotePage> quotesByAuthor({
    required String authorSlug,
    int page = 1,
    int limit = 20,
  }) async => _unsupported();
}

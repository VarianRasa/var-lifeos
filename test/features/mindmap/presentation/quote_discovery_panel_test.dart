import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/quote_catalog_providers.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/domain/quote_catalog.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/quote_discovery_panel.dart';

void main() {
  testWidgets('discover selects internet quote into local draft', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 17);
    final node = MindmapNode.create(
      id: 'quote',
      type: NodeType.quote,
      title: 'New Quote',
      body: '“Quote text here.”',
      day: now,
      now: now,
    );
    String? body;
    QuotePayload? payload;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quoteCatalogRepositoryProvider.overrideWithValue(_FakeCatalog()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: QuoteDiscoveryPanel(
              node: node,
              payload: const QuotePayload(collection: 'Favorites'),
              manualEditor: const Text('Manual editor'),
              onBodyChanged: (value) => body = value,
              onPayloadChanged: (value) => payload = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(
      find.byKey(const ValueKey('quote-author-grid')),
    );
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      3,
    );
    expect(find.text('MA'), findsOneWidget);
    expect(find.text('0 quotes'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quote-author-maya-angelou')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quote-author-back')), findsOneWidget);
    expect(find.text('Use this quote'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quote-use-quote-1')));
    await tester.pumpAndSettle();

    expect(body, 'Do the best you can.');
    expect(payload?.author, 'Maya Angelou');
    expect(payload?.remoteQuoteId, 'quote-1');
    expect(payload?.quoteProvider, 'quotable');
    expect(payload?.collection, 'Favorites');
    expect(find.text('Manual editor'), findsOneWidget);
  });
}

final class _FakeCatalog implements QuoteCatalogRepository {
  @override
  Future<List<QuoteAuthor>> popularAuthors() async => const [
    QuoteAuthor(id: 'maya', name: 'Maya Angelou', slug: 'maya-angelou'),
  ];

  @override
  Future<QuoteAuthorPage> searchAuthors({
    required String query,
    int page = 1,
    int limit = 20,
  }) async => QuoteAuthorPage(
    authors: await popularAuthors(),
    page: 1,
    totalPages: 1,
    hasNextPage: false,
  );

  @override
  Future<CatalogQuotePage> quotesByAuthor({
    required String authorSlug,
    int page = 1,
    int limit = 20,
  }) async => const CatalogQuotePage(
    quotes: [
      CatalogQuote(
        id: 'quote-1',
        text: 'Do the best you can.',
        authorName: 'Maya Angelou',
        authorSlug: 'maya-angelou',
        provider: 'quotable',
        tags: ['wisdom'],
        sourceUrl: 'https://example.test/quote-1',
      ),
    ],
    page: 1,
    totalPages: 1,
    hasNextPage: false,
  );
}

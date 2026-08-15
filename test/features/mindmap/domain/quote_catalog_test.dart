import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/quote_catalog.dart';

void main() {
  test('catalog pages parse bounded provider responses', () {
    final authors = QuoteAuthorPage.fromMap(<Object?, Object?>{
      'authors': <Object?>[
        <Object?, Object?>{
          'id': 'maya',
          'name': 'Maya Angelou',
          'slug': 'maya-angelou',
          'description': 'Poet',
          'quoteCount': 42,
        },
      ],
      'page': 1,
      'totalPages': 2,
      'hasNextPage': true,
    });
    final quotes = CatalogQuotePage.fromMap(<Object?, Object?>{
      'quotes': <Object?>[
        <Object?, Object?>{
          'id': 'quote-1',
          'text': 'Do the best you can until you know better.',
          'authorName': 'Maya Angelou',
          'authorSlug': 'maya-angelou',
          'provider': 'quotable',
          'tags': <Object?>['wisdom'],
          'sourceUrl': 'https://example.test/quote-1',
        },
      ],
      'page': 1,
      'totalPages': 1,
      'hasNextPage': false,
    });

    expect(authors.authors.single.name, 'Maya Angelou');
    expect(authors.hasNextPage, isTrue);
    expect(quotes.quotes.single.tags, <String>['wisdom']);
    expect(quotes.hasNextPage, isFalse);
  });

  test('legacy Quote template mojibake is normalized', () {
    expect(
      normalizeLegacyQuoteBody(
        '????Quote text here.????\n\nAuthor: Unknown\nSource: ',
      ),
      '?Quote text here.?',
    );
  });

  test('catalog parser rejects malformed required fields', () {
    expect(
      () => CatalogQuote.fromMap(<Object?, Object?>{
        'id': 'quote-1',
        'authorName': 'Author',
        'authorSlug': 'author',
        'provider': 'quotable',
      }),
      throwsA(isA<QuoteCatalogException>()),
    );
  });
}

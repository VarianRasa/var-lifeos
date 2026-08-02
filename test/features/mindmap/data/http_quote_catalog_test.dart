import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:var_app/features/mindmap/data/http_quote_catalog.dart';

void main() {
  test('HTTP quote catalog maps paths and query parameters', () async {
    final requests = <Uri>[];
    final catalog = HttpQuoteCatalog(
      endpoint: Uri.parse('https://quotes.example.test/api'),
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/authors/popular')) {
          return http.Response('{"authors":[]}', 200);
        }
        if (request.url.path.endsWith('/authors/search')) {
          return http.Response(
            '{"authors":[],"page":2,"totalPages":2,"hasNextPage":false}',
            200,
          );
        }
        return http.Response(
          '{"quotes":[],"page":3,"totalPages":3,"hasNextPage":false}',
          200,
        );
      }),
    );

    await catalog.popularAuthors();
    await catalog.searchAuthors(query: ' maya ', page: 2, limit: 10);
    await catalog.quotesByAuthor(
      authorSlug: ' maya-angelou ',
      page: 3,
      limit: 12,
    );

    expect(requests[0].path, '/api/authors/popular');
    expect(requests[1].queryParameters['q'], 'maya');
    expect(requests[1].queryParameters['page'], '2');
    expect(requests[2].queryParameters['author'], 'maya-angelou');
  });

  test('HTTP quote catalog rejects non-success responses', () async {
    final catalog = HttpQuoteCatalog(
      endpoint: Uri.parse('https://quotes.example.test'),
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );

    expect(catalog.popularAuthors(), throwsA(isA<Exception>()));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:var_app/features/capture/application/url_classifier_service.dart';
import 'package:var_app/features/capture/domain/captured_url_result.dart';

void main() {
  group('UrlClassifierService', () {
    test(
      'classifies HTML article (>200 chars text) and extracts snapshot',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            '''
          <html>
            <head><title>Test Article Title</title></head>
            <body>
              <article>
                <p>This is a long article content designed to exceed two hundred characters in length.
                It contains detailed information and structured text so that the classifier detects
                it as an article rather than a simple bookmark link. Verification requires sufficient text length.</p>
              </article>
            </body>
          </html>
          ''',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        });

        final service = UrlClassifierService(httpClient: client);
        final result = await service.processUrl(
          'https://example.com/blog/test',
        );

        expect(result.type, equals(CapturedUrlType.article));
        expect(result.title, equals('Test Article Title'));
        expect(result.extractedText, contains('exceed two hundred characters'));
      },
    );

    test(
      'classifies html containing <article tag as article even if short',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            '<html><head><title>Short Article</title></head><body><article>Short piece</article></body></html>',
            200,
            headers: {'content-type': 'text/html'},
          );
        });

        final service = UrlClassifierService(httpClient: client);
        final result = await service.processUrl(
          'https://example.com/short-article',
        );

        expect(result.type, equals(CapturedUrlType.article));
        expect(result.title, equals('Short Article'));
      },
    );

    test(
      'classifies page with short text and no <article> as bookmark',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            '<html><head><title>Simple Bookmark</title></head><body><div>Hello world</div></body></html>',
            200,
            headers: {'content-type': 'text/html'},
          );
        });

        final service = UrlClassifierService(httpClient: client);
        final result = await service.processUrl('https://example.com/link');

        expect(result.type, equals(CapturedUrlType.bookmark));
        expect(result.title, equals('Simple Bookmark'));
      },
    );

    test(
      'rejects private/local network URL before fetch and returns fallback bookmark',
      () async {
        var fetchAttempted = false;
        final client = MockClient((request) async {
          fetchAttempted = true;
          return http.Response('OK', 200);
        });

        final service = UrlClassifierService(httpClient: client);
        final result = await service.processUrl('http://127.0.0.1/admin');

        expect(fetchAttempted, isFalse);
        expect(result.type, equals(CapturedUrlType.bookmark));
        expect(result.title, equals('http://127.0.0.1/admin'));
      },
    );

    test('blocks redirects to private host bounds', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'example.com') {
          return http.Response(
            '',
            302,
            headers: {'location': 'http://192.168.1.1/secret'},
          );
        }
        return http.Response('Internal page', 200);
      });

      final service = UrlClassifierService(httpClient: client);
      final result = await service.processUrl('https://example.com/redirect');

      expect(result.type, equals(CapturedUrlType.bookmark));
      expect(result.title, equals('https://example.com/redirect'));
    });

    test(
      'falls back to bookmark on network/HTTP errors or non-HTML content',
      () async {
        final client = MockClient((request) async {
          return http.Response('Server Error', 500);
        });

        final service = UrlClassifierService(httpClient: client);
        final result = await service.processUrl('https://example.com/error');

        expect(result.type, equals(CapturedUrlType.bookmark));
        expect(result.title, equals('https://example.com/error'));
      },
    );
  });
}

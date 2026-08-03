import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:var_app/core/services/url_metadata_scraper_service.dart';

void main() {
  group('UrlMetadataScraperService', () {
    test('parses OpenGraph meta tags from HTML correctly', () async {
      const mockHtml = '''
        <!DOCTYPE html>
        <html>
        <head>
          <meta property="og:title" content="Test Article Title" />
          <meta property="og:description" content="Test description content" />
          <meta property="og:image" content="/relative-image.png" />
          <meta property="og:site_name" content="Example Site" />
        </head>
        <body></body>
        </html>
      ''';

      final mockClient = MockClient((request) async {
        return http.Response(mockHtml, 200);
      });

      final service = UrlMetadataScraperService(client: mockClient);
      final metadata = await service.fetchMetadata(
        'https://example.com/article',
      );

      expect(metadata.title, equals('Test Article Title'));
      expect(metadata.description, equals('Test description content'));
      expect(metadata.imageUrl, equals('https://example.com/relative-image.png'));
      expect(metadata.siteName, equals('Example Site'));
      expect(metadata.faviconUrl, contains('google.com/s2/favicons'));
    });

    test('returns fallback metadata when network request fails', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('CORS or Network failure');
      });

      final service = UrlMetadataScraperService(client: mockClient);
      final metadata = await service.fetchMetadata(
        'https://example.com/blocked',
      );

      expect(metadata.url, equals('https://example.com/blocked'));
      expect(metadata.title, equals('example.com'));
      expect(metadata.faviconUrl, contains('google.com/s2/favicons'));
    });
  });
}

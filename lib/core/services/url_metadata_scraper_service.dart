import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:var_app/features/mindmap/domain/link_metadata.dart';

class UrlMetadataScraperService {
  UrlMetadataScraperService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, LinkMetadata> _cache = <String, LinkMetadata>{};

  Future<LinkMetadata> fetchMetadata(String urlString) async {
    final cached = _cache[urlString];
    if (cached != null) {
      return cached;
    }

    final uri = Uri.tryParse(urlString);
    final host = uri?.host.isNotEmpty ?? false ? uri!.host : urlString;
    final favicon = Uri.https(
      'www.google.com',
      '/s2/favicons',
      <String, String>{'domain': host, 'sz': '64'},
    ).toString();

    try {
      final targetUri = Uri.parse(urlString);
      final response = await _client.get(
        targetUri,
        headers: const <String, String>{
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        String? meta(String property) {
          final val = (document.querySelector('meta[property="$property"]') ??
                  document.querySelector('meta[name="$property"]'))
              ?.attributes['content']?.trim();
          return (val != null && val.isNotEmpty) ? val : null;
        }

        final rawTitle = meta('og:title') ?? document.querySelector('title')?.text.trim();
        final title = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : host;
        final rawImage = meta('og:image');
        String? resolvedImage;
        if (rawImage != null) {
          final parsedImg = Uri.tryParse(rawImage);
          if (parsedImg != null) {
            resolvedImage = targetUri.resolveUri(parsedImg).toString();
          }
        }

        final metadata = LinkMetadata(
          url: urlString,
          title: title,
          description: meta('og:description'),
          imageUrl: resolvedImage,
          siteName: meta('og:site_name') ?? host,
          faviconUrl: favicon,
          fetchedAt: DateTime.now(),
        );
        _cache[urlString] = metadata;
        return metadata;
      }
    } on Exception {
      return _fallback(urlString, host, favicon);
    }

    return _fallback(urlString, host, favicon);
  }

  LinkMetadata _fallback(String url, String host, String favicon) {
    return _cache[url] = LinkMetadata(
      url: url,
      title: host,
      faviconUrl: favicon,
      fetchedAt: DateTime.now(),
    );
  }
}

final urlMetadataScraperProvider = Provider<UrlMetadataScraperService>((ref) {
  return UrlMetadataScraperService();
});

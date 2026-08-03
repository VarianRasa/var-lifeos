import 'package:http/http.dart' as http;
import 'package:var_app/features/capture/application/dns_lookup.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/capture_validation.dart';
import 'package:var_app/features/capture/domain/captured_url_result.dart';
import 'package:var_app/features/capture/domain/duplicate_detector.dart';

class UrlClassifierService {
  final http.Client _httpClient;
  final Duration _timeout;
  final DnsResolver _dnsResolver;

  UrlClassifierService({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 5),
    DnsResolver? dnsResolver,
  }) : _httpClient = httpClient ?? http.Client(),
       _timeout = timeout,
       _dnsResolver = dnsResolver ?? defaultDnsResolver;

  Future<CapturedUrlResult> processUrl(String rawUrl) async {
    final initialUri = Uri.tryParse(rawUrl);
    final canonicalUrl = initialUri == null
        ? rawUrl
        : DuplicateDetector.normalizeUrl(rawUrl);
    if (!await _isAllowed(rawUrl)) return _fallback(rawUrl, canonicalUrl);
    try {
      final response = await _fetch(initialUri!).timeout(_timeout);
      if (response.statusCode != 200 ||
          !(response.headers['content-type'] ?? '').toLowerCase().contains(
            'text/html',
          )) {
        return _fallback(rawUrl, canonicalUrl);
      }
      final body = response.body;
      final title = _plainText(
        RegExp(
              r'<title\b[^>]*>([\s\S]*?)</title>',
              caseSensitive: false,
            ).firstMatch(body)?.group(1) ??
            '',
      );
      final text = _plainText(
        body
            .replaceAll(
              RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
              ' ',
            )
            .replaceAll(
              RegExp(r'<style\b[^>]*>[\s\S]*?</style>', caseSensitive: false),
              ' ',
            ),
      );
      return CapturedUrlResult(
        url: rawUrl,
        canonicalUrl: canonicalUrl,
        type:
            text.length > 200 ||
                RegExp(r'<article(?:\s|>)', caseSensitive: false).hasMatch(body)
            ? CapturedUrlType.article
            : CapturedUrlType.bookmark,
        title: title.isEmpty ? rawUrl : title,
        extractedText: text,
        htmlSnapshot: body,
      );
    } on Object {
      return _fallback(rawUrl, canonicalUrl);
    }
  }

  Future<http.Response> _fetch(Uri initialUri) async {
    var uri = initialUri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!await _isAllowed(uri.toString())) throw const FormatException();
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await http.Response.fromStream(
        await _httpClient.send(request),
      );
      if (!_isRedirect(response.statusCode)) return response;
      final location = response.headers['location'];
      if (location == null || redirects == 5) throw const FormatException();
      uri = uri.resolve(location);
    }
    throw const FormatException();
  }

  Future<bool> _isAllowed(String url) async {
    if (!CaptureValidator.validate(CapturePayload(urls: [url])).isValid) {
      return false;
    }
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.host.isNotEmpty &&
        !await CaptureValidator.isPrivateOrLocalHostAsync(
          uri.host,
          dnsResolver: _dnsResolver,
        );
  }

  bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  String _plainText(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  CapturedUrlResult _fallback(String rawUrl, String canonicalUrl) =>
      CapturedUrlResult(
        url: rawUrl,
        canonicalUrl: canonicalUrl,
        type: CapturedUrlType.bookmark,
        title: rawUrl,
      );
}

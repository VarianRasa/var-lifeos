enum CapturedUrlType { article, bookmark }

class CapturedUrlResult {
  final String url;
  final String canonicalUrl;
  final CapturedUrlType type;
  final String title;
  final String? metaDescription;
  final String? extractedText;
  final String? htmlSnapshot;

  const CapturedUrlResult({
    required this.url,
    required this.canonicalUrl,
    required this.type,
    required this.title,
    this.metaDescription,
    this.extractedText,
    this.htmlSnapshot,
  });
}

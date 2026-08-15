enum LinkPreviewStyle { banner, compact, quote }

class LinkMetadata {
  const LinkMetadata({
    required this.url,
    required this.fetchedAt,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.faviconUrl,
    this.style = LinkPreviewStyle.banner,
  });

  factory LinkMetadata.fromJson(Map<String, Object?> json) {
    final styleName = json['style'] as String?;
    return LinkMetadata(
      url: json['url']! as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      siteName: json['siteName'] as String?,
      faviconUrl: json['faviconUrl'] as String?,
      fetchedAt: DateTime.parse(json['fetchedAt']! as String),
      style: LinkPreviewStyle.values.firstWhere(
        (candidate) => candidate.name == styleName,
        orElse: () => LinkPreviewStyle.banner,
      ),
    );
  }

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? faviconUrl;
  final DateTime fetchedAt;
  final LinkPreviewStyle style;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'url': url,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'siteName': siteName,
      'faviconUrl': faviconUrl,
      'fetchedAt': fetchedAt.toIso8601String(),
      'style': style.name,
    };
  }
}

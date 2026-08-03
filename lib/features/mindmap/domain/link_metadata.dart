class LinkMetadata {
  const LinkMetadata({
    required this.url,
    required this.fetchedAt,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.faviconUrl,
  });

  factory LinkMetadata.fromJson(Map<String, Object?> json) {
    return LinkMetadata(
      url: json['url']! as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      siteName: json['siteName'] as String?,
      faviconUrl: json['faviconUrl'] as String?,
      fetchedAt: DateTime.parse(json['fetchedAt']! as String),
    );
  }

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? faviconUrl;
  final DateTime fetchedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'url': url,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'siteName': siteName,
      'faviconUrl': faviconUrl,
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }
}

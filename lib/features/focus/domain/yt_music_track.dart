import 'dart:convert';

class YtMusicTrack {
  const YtMusicTrack({
    required this.id,
    required this.title,
    required this.url,
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String url;
  final bool isFavorite;

  YtMusicTrack copyWith({
    String? id,
    String? title,
    String? url,
    bool? isFavorite,
  }) {
    return YtMusicTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'isFavorite': isFavorite,
  };

  factory YtMusicTrack.fromJson(Map<String, dynamic> json) {
    return YtMusicTrack(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      isFavorite: (json['isFavorite'] as bool?) ?? false,
    );
  }

  static String encodeList(List<YtMusicTrack> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList());
  }

  static List<YtMusicTrack> decodeList(String raw) {
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => YtMusicTrack.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

import 'dart:convert';

enum AudioLoopMode { off, all, one }

class FocusAudioTrack {
  const FocusAudioTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.audioUrl,
    this.isPreset = false,
    this.category = 'Focus',
  });

  final String id;
  final String title;
  final String artist;
  final String audioUrl;
  final bool isPreset;
  final String category;

  FocusAudioTrack copyWith({
    String? id,
    String? title,
    String? artist,
    String? audioUrl,
    bool? isPreset,
    String? category,
  }) {
    return FocusAudioTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      audioUrl: audioUrl ?? this.audioUrl,
      isPreset: isPreset ?? this.isPreset,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'audioUrl': audioUrl,
    'isPreset': isPreset,
    'category': category,
  };

  factory FocusAudioTrack.fromJson(Map<String, dynamic> json) =>
      FocusAudioTrack(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String? ?? 'Custom Stream',
        audioUrl: json['audioUrl'] as String,
        isPreset: json['isPreset'] as bool? ?? false,
        category: json['category'] as String? ?? 'Custom',
      );

  static String encodeList(List<FocusAudioTrack> tracks) =>
      jsonEncode(tracks.map((t) => t.toJson()).toList());

  static List<FocusAudioTrack> decodeList(String rawJson) {
    if (rawJson.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(rawJson) as List;
      return decoded
          .map((e) => FocusAudioTrack.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static const List<FocusAudioTrack> defaultFocusPresets = [
    FocusAudioTrack(
      id: 'preset-rain',
      title: 'Hujan Deras',
      artist: 'Nature Sounds',
      audioUrl:
          'https://assets.mixkit.co/active_storage/sfx/2517/2517-preview.mp3',
      isPreset: true,
      category: 'Ambience',
    ),
    FocusAudioTrack(
      id: 'preset-forest',
      title: 'Suasana Hutan',
      artist: 'Nature Sounds',
      audioUrl:
          'https://assets.mixkit.co/active_storage/sfx/2520/2520-preview.mp3',
      isPreset: true,
      category: 'Ambience',
    ),
    FocusAudioTrack(
      id: 'preset-cafe',
      title: 'Cafe Chatter',
      artist: 'Ambient Sound',
      audioUrl:
          'https://assets.mixkit.co/active_storage/sfx/306/306-preview.mp3',
      isPreset: true,
      category: 'Ambience',
    ),
    FocusAudioTrack(
      id: 'preset-white-noise',
      title: 'White Noise',
      artist: 'Focus Audio',
      audioUrl:
          'https://assets.mixkit.co/active_storage/sfx/2432/2432-preview.mp3',
      isPreset: true,
      category: 'White Noise',
    ),
    FocusAudioTrack(
      id: 'preset-binaural-beta',
      title: 'Binaural Beta 14Hz',
      artist: 'Brainwave Sync',
      audioUrl:
          'https://assets.mixkit.co/active_storage/sfx/2515/2515-preview.mp3',
      isPreset: true,
      category: 'Binaural',
    ),
  ];
}

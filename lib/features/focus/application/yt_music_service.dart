import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/yt_music_track.dart';

const String _ytMusicPrefsKey = 'focus_yt_music_tracks';
const String _activeYtMusicIdKey = 'focus_active_yt_music_id';

final ytMusicServiceProvider = Provider((ref) => YtMusicService());

class YtMusicService {
  final _prefs = SharedPreferencesAsync();

  Future<List<YtMusicTrack>> loadTracks() async {
    final raw = await _prefs.getString(_ytMusicPrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return _defaultPresets;
    }
    final tracks = YtMusicTrack.decodeList(raw);
    return tracks.isEmpty ? _defaultPresets : tracks;
  }

  Future<void> saveTracks(List<YtMusicTrack> tracks) async {
    await _prefs.setString(_ytMusicPrefsKey, YtMusicTrack.encodeList(tracks));
  }

  Future<String?> getActiveTrackId() async {
    return _prefs.getString(_activeYtMusicIdKey);
  }

  Future<void> setActiveTrackId(String? id) async {
    if (id == null) {
      await _prefs.remove(_activeYtMusicIdKey);
    } else {
      await _prefs.setString(_activeYtMusicIdKey, id);
    }
  }

  Future<bool> launchTrack(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  List<YtMusicTrack> get _defaultPresets => const [
    YtMusicTrack(
      id: 'preset-lofi',
      title: 'Lofi Girl - Chill & Study Beats',
      url: 'https://music.youtube.com/watch?v=jfKfPfyJRdk',
      isFavorite: true,
    ),
    YtMusicTrack(
      id: 'preset-deep-focus',
      title: 'Deep Focus Ambient & Synth',
      url: 'https://music.youtube.com/playlist?list=RDCLAK5uy_kbcj-m8rJ9fX4S9',
    ),
  ];
}

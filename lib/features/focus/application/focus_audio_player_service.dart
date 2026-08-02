import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../domain/focus_audio_track.dart';

const String _customAudioTracksKey = 'focus_custom_audio_tracks';
const String _activeAudioTrackIdKey = 'focus_active_audio_track_id';

final focusAudioPlayerServiceProvider =
    StateNotifierProvider<FocusAudioPlayerNotifier, FocusAudioPlayerState>((
      ref,
    ) {
      return FocusAudioPlayerNotifier();
    });

class FocusAudioPlayerState {
  const FocusAudioPlayerState({
    required this.tracks,
    this.currentTrack,
    this.isPlaying = false,
    this.isLoadingStream = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.isMuted = false,
    this.loopMode = AudioLoopMode.all,
    this.speed = 1.0,
    this.error,
  });

  final List<FocusAudioTrack> tracks;
  final FocusAudioTrack? currentTrack;
  final bool isPlaying;
  final bool isLoadingStream;
  final Duration position;
  final Duration duration;
  final double volume;
  final bool isMuted;
  final AudioLoopMode loopMode;
  final double speed;
  final String? error;

  FocusAudioPlayerState copyWith({
    List<FocusAudioTrack>? tracks,
    FocusAudioTrack? Function()? currentTrack,
    bool? isPlaying,
    bool? isLoadingStream,
    Duration? position,
    Duration? duration,
    double? volume,
    bool? isMuted,
    AudioLoopMode? loopMode,
    double? speed,
    String? Function()? error,
  }) {
    return FocusAudioPlayerState(
      tracks: tracks ?? this.tracks,
      currentTrack: currentTrack != null ? currentTrack() : this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoadingStream: isLoadingStream ?? this.isLoadingStream,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      loopMode: loopMode ?? this.loopMode,
      speed: speed ?? this.speed,
      error: error != null ? error() : this.error,
    );
  }
}

class FocusAudioPlayerNotifier extends StateNotifier<FocusAudioPlayerState> {
  FocusAudioPlayerNotifier()
    : super(const FocusAudioPlayerState(tracks: defaultFocusPresets)) {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();
  final YoutubeExplode _ytExplode = YoutubeExplode();
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<List<int>>? _downloadSub;
  File? _activeTempFile;

  static const List<FocusAudioTrack> defaultFocusPresets = [
    FocusAudioTrack(
      id: 'preset-lofi',
      title: 'Lofi Study Beats',
      artist: 'Focus Chill Beats',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      isPreset: true,
      category: 'Lofi',
    ),
    FocusAudioTrack(
      id: 'preset-ambient',
      title: 'Deep Focus Ambient Piano',
      artist: 'Var LifeOS Ambient',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      isPreset: true,
      category: 'Ambient',
    ),
    FocusAudioTrack(
      id: 'preset-rain',
      title: 'Cozy Rain & Soundscape',
      artist: 'Nature Focus Ambience',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
      isPreset: true,
      category: 'Nature',
    ),
    FocusAudioTrack(
      id: 'preset-cafe',
      title: 'Coffee Shop & White Noise',
      artist: 'Focus Ambience',
      audioUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
      isPreset: true,
      category: 'White Noise',
    ),
  ];

  static bool isYoutubeUrl(String url) {
    final lower = url.toLowerCase().trim();
    return lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('music.youtube.com');
  }

  Future<void> _init() async {
    _playerStateSub = _player.playerStateStream.listen((stateData) {
      state = state.copyWith(isPlaying: stateData.playing);
      if (stateData.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
      }
    });

    _positionSub = _player.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });

    _durationSub = _player.durationStream.listen((dur) {
      if (dur != null) {
        state = state.copyWith(duration: dur);
      }
    });

    await loadSavedTracks();
  }

  Future<void> loadSavedTracks() async {
    try {
      final raw = await _prefs.getString(_customAudioTracksKey);
      final custom = FocusAudioTrack.decodeList(raw ?? '');
      final allTracks = [...defaultFocusPresets, ...custom];

      final activeId = await _prefs.getString(_activeAudioTrackIdKey);
      FocusAudioTrack? activeTrack;
      if (activeId != null) {
        activeTrack = allTracks.where((t) => t.id == activeId).firstOrNull;
      }
      activeTrack ??= allTracks.first;

      state = state.copyWith(
        tracks: allTracks,
        currentTrack: () => activeTrack,
      );
    } catch (_) {}
  }

  Future<void> selectTrack(FocusAudioTrack track) async {
    state = state.copyWith(currentTrack: () => track, error: () => null);
    await _prefs.setString(_activeAudioTrackIdKey, track.id);
    if (state.isPlaying) {
      await playTrack(track);
    }
  }

  Future<void> _cleanupTempFile() async {
    await _downloadSub?.cancel();
    _downloadSub = null;
    final file = _activeTempFile;
    _activeTempFile = null;
    if (file != null && await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> playTrack(FocusAudioTrack track) async {
    state = state.copyWith(
      currentTrack: () => track,
      error: () => null,
      isLoadingStream: true,
    );

    try {
      await _cleanupTempFile();
      final url = track.audioUrl.trim();

      if (isYoutubeUrl(url)) {
        final manifest = await _ytExplode.videos.streamsClient.getManifest(url);
        final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

        try {
          final audioSource = AudioSource.uri(
            audioStreamInfo.url,
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          );
          await _player.setAudioSource(audioSource);
        } catch (_) {
          // Fallback: download full file and close sink before MPV opens file
          await _cleanupTempFile();
          final tempDir = await getTemporaryDirectory();
          final ext = audioStreamInfo.container.name;
          final tempFile = File(
            path.join(
              tempDir.path,
              'var-focus-yt-${DateTime.now().millisecondsSinceEpoch}.$ext',
            ),
          );

          final fileSink = tempFile.openWrite();
          final audioStream = _ytExplode.videos.streamsClient.get(
            audioStreamInfo,
          );
          await fileSink.addStream(audioStream);
          await fileSink.flush();
          await fileSink.close();

          _activeTempFile = tempFile;
          await _player.setFilePath(tempFile.path);
        }

        state = state.copyWith(isLoadingStream: false);
        await _player.play();
      } else {
        final uri = Uri.parse(url);
        final audioSource = AudioSource.uri(
          uri,
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          },
        );
        await _player.setAudioSource(audioSource);
        state = state.copyWith(isLoadingStream: false);
        await _player.play();
      }
    } catch (e) {
      state = state.copyWith(
        isLoadingStream: false,
        error: () => 'Gagal memuat stream audio in-app: $e',
      );
    }
  }

  Future<void> play() async {
    final track = state.currentTrack;
    if (track == null) return;

    if (_player.audioSource == null || state.error != null) {
      await playTrack(track);
    } else {
      await _player.play();
    }
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration pos) async {
    await _player.seek(pos);
  }

  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: clamped, isMuted: clamped == 0.0);
    await _player.setVolume(state.isMuted ? 0.0 : clamped);
  }

  Future<void> toggleMute() async {
    final newMute = !state.isMuted;
    state = state.copyWith(isMuted: newMute);
    await _player.setVolume(newMute ? 0.0 : state.volume);
  }

  Future<void> nextTrack() async {
    if (state.tracks.isEmpty) return;
    final currentIndex = state.tracks.indexWhere(
      (t) => t.id == state.currentTrack?.id,
    );
    final nextIndex = (currentIndex + 1) % state.tracks.length;
    final next = state.tracks[nextIndex];
    await selectTrack(next);
    await playTrack(next);
  }

  Future<void> previousTrack() async {
    if (state.tracks.isEmpty) return;
    final currentIndex = state.tracks.indexWhere(
      (t) => t.id == state.currentTrack?.id,
    );
    final prevIndex =
        (currentIndex - 1 + state.tracks.length) % state.tracks.length;
    final prev = state.tracks[prevIndex];
    await selectTrack(prev);
    await playTrack(prev);
  }

  Future<void> setLoopMode(AudioLoopMode mode) async {
    state = state.copyWith(loopMode: mode);
    switch (mode) {
      case AudioLoopMode.off:
        await _player.setLoopMode(LoopMode.off);
      case AudioLoopMode.one:
        await _player.setLoopMode(LoopMode.one);
      case AudioLoopMode.all:
        await _player.setLoopMode(LoopMode.all);
    }
  }

  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _player.setSpeed(speed);
  }

  Future<void> addCustomTrack(FocusAudioTrack track) async {
    await addCustomTracks([track]);
  }

  Future<void> addCustomTracks(List<FocusAudioTrack> tracks) async {
    final updated = [...state.tracks, ...tracks];
    state = state.copyWith(tracks: updated);

    final customTracks = updated.where((t) => !t.isPreset).toList();
    await _prefs.setString(
      _customAudioTracksKey,
      FocusAudioTrack.encodeList(customTracks),
    );
  }

  Future<int> importYoutubePlaylist(String playlistUrl) async {
    state = state.copyWith(isLoadingStream: true, error: () => null);
    try {
      final playlistId = PlaylistId(playlistUrl);
      final videoStream = _ytExplode.playlists.getVideos(playlistId);
      final List<FocusAudioTrack> importedTracks = [];

      await for (final video in videoStream) {
        importedTracks.add(
          FocusAudioTrack(
            id: 'yt-${video.id.value}',
            title: video.title,
            artist: video.author,
            audioUrl: video.url,
            isPreset: false,
            category: 'YT Music',
          ),
        );
      }

      if (importedTracks.isNotEmpty) {
        await addCustomTracks(importedTracks);
      }
      state = state.copyWith(isLoadingStream: false);
      return importedTracks.length;
    } catch (e) {
      state = state.copyWith(
        isLoadingStream: false,
        error: () => 'Gagal mengimpor playlist YouTube: $e',
      );
      rethrow;
    }
  }

  Future<List<FocusAudioTrack>> searchYoutube(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final searchList = await _ytExplode.search.search(query);
      return searchList.map((video) {
        return FocusAudioTrack(
          id: 'yt-${video.id.value}',
          title: video.title,
          artist: video.author,
          audioUrl: video.url,
          isPreset: false,
          category: 'YT Music',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteTrack(String id) async {
    final updated = state.tracks.where((t) => t.id != id).toList();
    FocusAudioTrack? newCurrent = state.currentTrack;
    if (state.currentTrack?.id == id) {
      newCurrent = updated.isNotEmpty ? updated.first : null;
    }

    state = state.copyWith(tracks: updated, currentTrack: () => newCurrent);

    final customTracks = updated.where((t) => !t.isPreset).toList();
    await _prefs.setString(
      _customAudioTracksKey,
      FocusAudioTrack.encodeList(customTracks),
    );
  }

  void _handleTrackCompleted() {
    if (state.loopMode == AudioLoopMode.all) {
      nextTrack();
    }
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    unawaited(_cleanupTempFile());
    _ytExplode.close();
    _player.dispose();
    super.dispose();
  }
}

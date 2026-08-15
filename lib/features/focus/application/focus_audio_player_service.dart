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
const String focusAudioLoadError = 'Audio gagal dimuat. Silakan coba lagi.';
const String focusPlaylistImportError =
    'Playlist YouTube gagal diimpor. Silakan coba lagi.';
const Duration defaultFocusAudioOperationTimeout = Duration(seconds: 30);

typedef AudioLoader = Future<Duration?> Function(String value);
typedef UriAudioLoader = Future<Duration?> Function(Uri value);

class AudioDownloadCancelled implements Exception {
  const AudioDownloadCancelled();
}

class YoutubeAudioDownload {
  const YoutubeAudioDownload({required this.extension, required this.bytes});

  final String extension;
  final Stream<List<int>> bytes;
}

class YoutubeAudioDownloader {
  YoutubeAudioDownloader({
    required this.resolveAudio,
    this.temporaryDirectory = getTemporaryDirectory,
    this.onFileCreated,
    this.downloadTimeout,
  });

  final Future<YoutubeAudioDownload> Function(String url) resolveAudio;
  final Future<Directory> Function() temporaryDirectory;
  final void Function(File file)? onFileCreated;
  final Duration? downloadTimeout;

  StreamSubscription<List<int>>? _subscription;
  IOSink? _sink;
  File? _file;
  Timer? _timer;
  bool _cancelled = false;
  final Completer<void> _cancelSignal = Completer<void>();
  Completer<void>? _activeCompleter;

  Future<T> _awaitBoundary<T>(Future<T> future) => Future.any<T>([
    future,
    _cancelSignal.future.then<T>((_) => throw const AudioDownloadCancelled()),
  ]);

  void _throwIfCancelled() {
    if (_cancelled) throw const AudioDownloadCancelled();
  }

  Future<File> download(String url) async {
    _throwIfCancelled();
    final audio = await _awaitBoundary(resolveAudio(url));
    _throwIfCancelled();
    final directory = await _awaitBoundary(temporaryDirectory());
    _throwIfCancelled();
    final file = File(
      path.join(
        directory.path,
        'var-focus-yt-${DateTime.now().microsecondsSinceEpoch}.${audio.extension}',
      ),
    );
    _file = file;
    onFileCreated?.call(file);
    _throwIfCancelled();
    final sink = file.openWrite();
    _sink = sink;
    _throwIfCancelled();
    final completer = Completer<void>();
    _activeCompleter = completer;
    _subscription = audio.bytes.listen(
      sink.add,
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
      onDone: completer.complete,
      cancelOnError: true,
    );
    if (downloadTimeout != null) {
      _timer = Timer(downloadTimeout!, () {
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException('Audio download timed out'));
        }
      });
    }
    try {
      await completer.future;
      _throwIfCancelled();
      _activeCompleter = null;
      _timer?.cancel();
      await _subscription?.cancel();
      _throwIfCancelled();
      _subscription = null;
      await sink.flush();
      _throwIfCancelled();
      await sink.close();
      _throwIfCancelled();
      _sink = null;
      return file;
    } catch (_) {
      await cancel();
      rethrow;
    }
  }

  void releaseFileOwnership() {
    _file = null;
  }

  Future<void> cancel() async {
    _cancelled = true;
    if (!_cancelSignal.isCompleted) _cancelSignal.complete();
    if (_activeCompleter case final active? when !active.isCompleted) {
      active.completeError(const AudioDownloadCancelled());
    }
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    final file = _file;
    _file = null;
    if (file != null && await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}

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
  FocusAudioPlayerNotifier({
    Future<File> Function(String url)? downloadYoutubeAudio,
    AudioLoader? setFilePath,
    UriAudioLoader? setUri,
    Future<void> Function()? startPlayback,
    Future<void> Function()? stopPlayback,
    Future<void> Function()? disposePlayback,
    Future<void> Function(File file)? deleteTempFile,
    Stream<ProcessingState>? processingStateEvents,
    Stream<Object>? playbackErrorEvents,
    this.operationTimeout = defaultFocusAudioOperationTimeout,
    bool subscribeToPlayer = true,
  }) : _downloadYoutubeAudio = downloadYoutubeAudio,
       _setFilePath = setFilePath,
       _setUri = setUri,
       _startPlayback = startPlayback,
       _stopPlayback = stopPlayback,
       _disposePlayback = disposePlayback,
       _deleteTempFile = deleteTempFile,
       super(const FocusAudioPlayerState(tracks: defaultFocusPresets)) {
    _init(
      subscribeToPlayer: subscribeToPlayer,
      processingStateEvents: processingStateEvents,
      playbackErrorEvents: playbackErrorEvents,
    );
  }

  final AudioPlayer _player = AudioPlayer();
  final YoutubeExplode _ytExplode = YoutubeExplode();
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final Future<File> Function(String url)? _downloadYoutubeAudio;
  final AudioLoader? _setFilePath;
  final UriAudioLoader? _setUri;
  final Future<void> Function()? _startPlayback;
  final Future<void> Function()? _stopPlayback;
  final Future<void> Function()? _disposePlayback;
  final Future<void> Function(File file)? _deleteTempFile;
  final Duration operationTimeout;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerException>? _errorSub;
  StreamSubscription<ProcessingState>? _processingTestSub;
  StreamSubscription<Object>? _errorTestSub;
  YoutubeAudioDownloader? _activeDownloader;
  File? _activeTempFile;
  int _operationGeneration = 0;
  bool _disposed = false;
  final Set<Timer> _deadlineTimers = {};
  final List<File> _pendingDeleteFiles = [];
  int? _loadedGeneration;
  bool _completionHandled = false;
  bool _completionArmed = false;
  Future<void> _sourceMutationTail = Future<void>.value();
  Future<void>? _cleanupFuture;

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
    final host = Uri.tryParse(url.trim())?.host.toLowerCase();
    if (host == null) return false;
    return host == 'youtu.be' ||
        host == 'youtube.com' ||
        host.endsWith('.youtube.com');
  }

  Future<void> _init({
    required bool subscribeToPlayer,
    Stream<ProcessingState>? processingStateEvents,
    Stream<Object>? playbackErrorEvents,
  }) async {
    if (processingStateEvents != null) {
      _processingTestSub = processingStateEvents.listen(_onProcessingState);
    }
    if (playbackErrorEvents != null) {
      _errorTestSub = playbackErrorEvents.listen((_) => _onPlaybackError());
    }
    if (!subscribeToPlayer) {
      await loadSavedTracks();
      return;
    }
    _playerStateSub = _player.playerStateStream.listen((stateData) {
      if (_disposed) return;
      state = state.copyWith(isPlaying: stateData.playing);
      _onProcessingState(stateData.processingState);
    });

    _positionSub = _player.positionStream.listen((pos) {
      if (_disposed) return;
      state = state.copyWith(position: pos);
    });

    _durationSub = _player.durationStream.listen((dur) {
      if (_disposed) return;
      if (dur != null) {
        state = state.copyWith(duration: dur);
      }
    });
    _errorSub = _player.errorStream.listen((_) => _onPlaybackError());

    await loadSavedTracks();
  }

  void _onProcessingState(ProcessingState processingState) {
    if (_disposed || state.isLoadingStream || _loadedGeneration == null) return;
    if (processingState != ProcessingState.completed) {
      _completionHandled = false;
      _completionArmed = true;
      return;
    }
    if (!_completionArmed || _completionHandled) return;
    _completionHandled = true;
    _handleTrackCompleted();
  }

  void _onPlaybackError() {
    if (_disposed ||
        state.isLoadingStream ||
        _loadedGeneration != _operationGeneration) {
      return;
    }
    state = state.copyWith(
      isLoadingStream: false,
      isPlaying: false,
      error: () => focusAudioLoadError,
    );
  }

  Future<void> loadSavedTracks() async {
    final operation = _operationGeneration;
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

      if (_disposed || operation != _operationGeneration) return;
      state = state.copyWith(
        tracks: allTracks,
        currentTrack: () => activeTrack,
      );
    } catch (_) {}
  }

  Future<void> selectTrack(FocusAudioTrack track) async {
    final shouldPlay = state.isPlaying;
    await _selectTrack(track, autoplay: shouldPlay);
  }

  Future<void> _selectTrack(
    FocusAudioTrack track, {
    required bool autoplay,
  }) async {
    if (_disposed) return;
    state = state.copyWith(currentTrack: () => track, error: () => null);
    await _prefs.setString(_activeAudioTrackIdKey, track.id);
    if (autoplay && !_disposed) await playTrack(track);
  }

  Future<void> _cleanupTempFile([
    File? ownedFile,
    bool retryPending = true,
  ]) async {
    final files = <File>[
      if (retryPending) ..._pendingDeleteFiles,
      ?ownedFile ?? _activeTempFile,
    ];
    if (retryPending) _pendingDeleteFiles.clear();
    final active = ownedFile ?? _activeTempFile;
    if (active == _activeTempFile) _activeTempFile = null;
    for (final file in files.toSet()) {
      try {
        if (_deleteTempFile != null) {
          await _deleteTempFile(file);
        } else if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        _pendingDeleteFiles.add(file);
      }
    }
  }

  Future<void> _retryPendingDeletes() async {
    final files = [..._pendingDeleteFiles];
    _pendingDeleteFiles.clear();
    for (final file in files) {
      try {
        if (_deleteTempFile != null) {
          await _deleteTempFile(file);
        } else if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        _pendingDeleteFiles.add(file);
      }
    }
  }

  Future<void> _mutateSource(
    int operation,
    Future<Duration?> Function() load,
    DateTime deadline,
  ) async {
    final previous = _sourceMutationTail;
    final completer = Completer<void>();
    _sourceMutationTail = completer.future;
    try {
      await previous;
      if (!_isCurrent(operation)) return;
      final loadFuture = load();
      try {
        await _withinDeadline(loadFuture, deadline);
      } on TimeoutException {
        unawaited(
          loadFuture
              .then((_) async {
                if (!_isCurrent(operation)) {
                  await (_stopPlayback?.call() ?? _player.stop());
                }
              })
              .catchError((Object _) {}),
        );
        rethrow;
      }
    } finally {
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> playTrack(FocusAudioTrack track) async {
    final operation = ++_operationGeneration;
    final deadline = DateTime.now().add(operationTimeout);
    unawaited(_retryPendingDeletes());
    final previousDownloader = _activeDownloader;
    _activeDownloader = null;
    unawaited(previousDownloader?.cancel());
    final previousFile = _activeTempFile;
    _activeTempFile = null;
    if (!_isCurrent(operation)) return;
    state = state.copyWith(
      currentTrack: () => track,
      error: () => null,
      isLoadingStream: true,
    );
    _loadedGeneration = null;
    _completionHandled = false;
    _completionArmed = false;
    File? ownedFile;

    try {
      final url = track.audioUrl.trim();
      if (previousFile != null) {
        await _withinDeadline(
          _stopPlayback?.call() ?? _player.stop(),
          deadline,
        );
      }
      if (isYoutubeUrl(url)) {
        ownedFile = await _withinDeadline(
          _downloadYoutubeAudio?.call(url) ?? _downloadYoutube(url, deadline),
          deadline,
        );
        if (!_isCurrent(operation)) {
          unawaited(_cleanupTempFile(ownedFile));
          return;
        }
        final downloadedFile = ownedFile!;
        _activeDownloader?.releaseFileOwnership();
        _activeDownloader = null;
        _activeTempFile = downloadedFile;
        await _mutateSource(
          operation,
          () =>
              _setFilePath?.call(downloadedFile.path) ??
              _player.setFilePath(downloadedFile.path),
          deadline,
        );
      } else {
        final uri = Uri.parse(url);
        await _mutateSource(
          operation,
          () =>
              _setUri?.call(uri) ??
              _player.setAudioSource(AudioSource.uri(uri)),
          deadline,
        );
      }
      if (!_isCurrent(operation)) return;
      if (previousFile != null) await _cleanupTempFile(previousFile);
      if (!_isCurrent(operation)) return;
      _loadedGeneration = operation;
      state = state.copyWith(isLoadingStream: false);
      unawaited(
        (_startPlayback?.call() ?? _player.play()).catchError((Object _) {
          if (_loadedGeneration == operation && _isCurrent(operation)) {
            _onPlaybackError();
          }
        }),
      );
    } catch (_) {
      if (previousFile != null && !_pendingDeleteFiles.contains(previousFile)) {
        _pendingDeleteFiles.add(previousFile);
      }
      if (!_isCurrent(operation)) {
        if (ownedFile != null) {
          unawaited(_cleanupTempFile(ownedFile, false));
        }
        return;
      }
      state = state.copyWith(
        isLoadingStream: false,
        isPlaying: false,
        error: () => focusAudioLoadError,
      );
      if (ownedFile != null) {
        unawaited(_cleanupTempFile(ownedFile, false));
      }
    }
  }

  bool _isCurrent(int operation) =>
      !_disposed && mounted && operation == _operationGeneration;

  Future<T> _withinDeadline<T>(Future<T> future, DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return Future<T>.error(TimeoutException('Audio operation timed out'));
    }
    final completer = Completer<T>();
    late final Timer timer;
    timer = Timer(remaining, () {
      _deadlineTimers.remove(timer);
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Audio operation timed out'));
      }
    });
    _deadlineTimers.add(timer);
    future.then(
      (value) {
        timer.cancel();
        _deadlineTimers.remove(timer);
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        timer.cancel();
        _deadlineTimers.remove(timer);
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    return completer.future;
  }

  Future<File> _downloadYoutube(String url, DateTime deadline) {
    final downloader = YoutubeAudioDownloader(
      downloadTimeout: deadline.difference(DateTime.now()),
      resolveAudio: (value) async {
        final manifest = await _withinDeadline(
          _ytExplode.videos.streamsClient.getManifest(value),
          deadline,
        );
        final info = manifest.audioOnly.withHighestBitrate();
        return YoutubeAudioDownload(
          extension: info.container.name,
          bytes: _ytExplode.videos.streamsClient.get(info),
        );
      },
    );
    _activeDownloader = downloader;
    return downloader.download(url);
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
    await _selectTrack(next, autoplay: false);
    if (!_disposed) await playTrack(next);
  }

  Future<void> previousTrack() async {
    if (state.tracks.isEmpty) return;
    final currentIndex = state.tracks.indexWhere(
      (t) => t.id == state.currentTrack?.id,
    );
    final prevIndex =
        (currentIndex - 1 + state.tracks.length) % state.tracks.length;
    final prev = state.tracks[prevIndex];
    await _selectTrack(prev, autoplay: false);
    if (!_disposed) await playTrack(prev);
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
    } catch (_) {
      state = state.copyWith(
        isLoadingStream: false,
        error: () => focusPlaylistImportError,
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
      unawaited(nextTrack());
    }
  }

  Future<void> cleanup() => _cleanupFuture ??= _cleanup();

  Future<void> _cleanup() async {
    _disposed = true;
    _operationGeneration++;
    for (final timer in _deadlineTimers) {
      timer.cancel();
    }
    _deadlineTimers.clear();
    await _activeDownloader?.cancel();
    _activeDownloader = null;
    await Future.wait<void>([
      ?_playerStateSub?.cancel(),
      ?_positionSub?.cancel(),
      ?_durationSub?.cancel(),
      ?_errorSub?.cancel(),
      ?_processingTestSub?.cancel(),
      ?_errorTestSub?.cancel(),
    ]);
    await (_stopPlayback?.call() ?? _player.stop());
    if (_disposePlayback != null) {
      await _disposePlayback();
    } else {
      await _player.dispose();
    }
    await _cleanupTempFile();
    await _retryPendingDeletes();
    _ytExplode.close();
  }

  @override
  void dispose() {
    unawaited(cleanup());
    super.dispose();
  }
}

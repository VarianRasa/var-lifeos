import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'video_playback_factory_stub.dart'
    if (dart.library.io) 'video_playback_factory_io.dart'
    if (dart.library.js_interop) 'video_playback_factory_web.dart'
    as platform;

final class VideoPlaybackSource {
  const VideoPlaybackSource.local({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  }) : remoteUrl = null;
  const VideoPlaybackSource.remote(this.remoteUrl)
    : bytes = null,
      mimeType = '',
      fileName = '';
  final Uint8List? bytes;
  final Uri? remoteUrl;
  final String mimeType;
  final String fileName;
  String get identity =>
      remoteUrl?.toString() ??
      '$fileName|$mimeType|${bytes?.length ?? 0}|${identityHashCode(bytes)}';
}

final class VideoPlaybackState {
  const VideoPlaybackState({
    this.initialized = false,
    this.playing = false,
    this.muted = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playbackSpeed = 1,
    this.error,
    this.unsupported = false,
  });
  final bool initialized;
  final bool playing;
  final bool muted;
  final Duration position;
  final Duration duration;
  final double playbackSpeed;
  final Object? error;
  final bool unsupported;
}

abstract interface class VideoPlaybackAdapter {
  ValueListenable<VideoPlaybackState> get state;
  Future<void> initialize({
    required Duration initialPosition,
    required bool muted,
  });
  Widget buildView({required BoxFit fit});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setMuted(bool muted);
  Future<void> setPlaybackSpeed(double speed);
  Future<void> close();
}

typedef VideoPlaybackAdapterFactory =
    Future<VideoPlaybackAdapter> Function(VideoPlaybackSource source);

bool isAllowedVideoRemoteUri(Uri uri) {
  if (uri.userInfo.isNotEmpty || uri.hasFragment || uri.host.isEmpty) {
    return false;
  }
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

final class TemporaryVideoFileLease {
  TemporaryVideoFileLease(this.path, this._delete);
  final String path;
  final Future<void> Function(String path) _delete;
  bool _closed = false;
  bool get isClosed => _closed;
  Future<void> close() async {
    if (_closed) return;
    try {
      await _delete(path);
      _closed = true;
    } on Object {
      return;
    }
  }
}

Future<void> cleanupVideoPlaybackResources({
  required Future<void> Function() disposeController,
  required Future<void> Function() releaseSource,
}) async {
  try {
    await disposeController();
  } on Object catch (error) {
    _ignoreCleanupError(error);
  }
  await releaseSource();
}

final class VideoObjectUrlLease {
  VideoObjectUrlLease(this.url, this._revoke);
  final String url;
  final void Function(String url) _revoke;
  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _revoke(url);
    } on Object {
      return;
    }
  }
}

Future<VideoPlaybackAdapter> createPlatformVideoPlaybackAdapter(
  VideoPlaybackSource source,
) {
  final remote = source.remoteUrl;
  if (remote != null && !isAllowedVideoRemoteUri(remote)) {
    throw const FormatException('Video URL is invalid.');
  }
  return platform.createVideoPlaybackAdapter(source);
}

final class VideoPlaybackSurface extends StatefulWidget {
  const VideoPlaybackSurface({
    required this.source,
    required this.poster,
    required this.initialPosition,
    required this.initialMuted,
    this.fit = BoxFit.contain,
    this.adapterFactory = createPlatformVideoPlaybackAdapter,
    this.onPositionChanged,
    this.onMutedChanged,
    this.onDurationChanged,
    this.recoveryActions = const <Widget>[],
    super.key,
  });
  final VideoPlaybackSource? source;
  final Widget poster;
  final Duration initialPosition;
  final bool initialMuted;
  final BoxFit fit;
  final VideoPlaybackAdapterFactory adapterFactory;
  final ValueChanged<Duration>? onPositionChanged;
  final ValueChanged<bool>? onMutedChanged;
  final ValueChanged<Duration>? onDurationChanged;
  final List<Widget> recoveryActions;
  @override
  State<VideoPlaybackSurface> createState() => _VideoPlaybackSurfaceState();
}

final class _VideoPlaybackSurfaceState extends State<VideoPlaybackSurface>
    with WidgetsBindingObserver {
  VideoPlaybackAdapter? _adapter;
  int _generation = 0;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;
  bool? _lastMuted;
  Object? _loadError;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant VideoPlaybackSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source?.identity != widget.source?.identity) {
      unawaited(_load());
      return;
    }
    final adapter = _adapter;
    if (adapter != null && oldWidget.initialMuted != widget.initialMuted) {
      unawaited(adapter.setMuted(widget.initialMuted));
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final previous = _adapter;
    _adapter = null;
    _loadError = null;
    _loading = widget.source != null;
    if (mounted) setState(() {});
    if (previous != null) {
      previous.state.removeListener(_stateChanged);
      await previous.close();
    }
    final source = widget.source;
    if (source == null || generation != _generation || !mounted) {
      _loading = false;
      return;
    }
    VideoPlaybackAdapter? next;
    try {
      next = await widget.adapterFactory(source);
      await next.initialize(
        initialPosition: widget.initialPosition,
        muted: widget.initialMuted,
      );
      if (generation != _generation || !mounted) {
        await next.close();
        return;
      }
      next.state.addListener(_stateChanged);
      _adapter = next;
      _loading = false;
      _stateChanged();
    } on Object catch (error) {
      if (next != null) {
        next.state.removeListener(_stateChanged);
        await next.close();
      }
      if (generation == _generation && mounted) {
        _adapter = null;
        _loadError = error;
        _loading = false;
        setState(() {});
      }
    }
  }

  void _stateChanged() {
    if (!mounted) return;
    final current = _adapter?.state.value;
    if (current == null) return;
    if (current.position != _lastPosition) {
      _lastPosition = current.position;
      widget.onPositionChanged?.call(current.position);
    }
    if (current.duration != _lastDuration && current.duration > Duration.zero) {
      _lastDuration = current.duration;
      widget.onDurationChanged?.call(current.duration);
    }
    if (current.muted != _lastMuted) {
      _lastMuted = current.muted;
      widget.onMutedChanged?.call(current.muted);
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_adapter?.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation += 1;
    final adapter = _adapter;
    if (adapter != null) {
      adapter.state.removeListener(_stateChanged);
      unawaited(adapter.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adapter = _adapter;
    if (adapter == null) {
      if (widget.source == null) return widget.poster;
      return _VideoFallback(
        poster: widget.poster,
        loading: _loading,
        error: _loadError,
        onRetry: () => unawaited(_load()),
        recoveryActions: widget.recoveryActions,
        showRetry: true,
      );
    }
    return ValueListenableBuilder<VideoPlaybackState>(
      valueListenable: adapter.state,
      builder: (context, state, _) {
        if (!state.initialized || state.unsupported || state.error != null) {
          return _VideoFallback(
            poster: widget.poster,
            loading: false,
            error:
                state.error ??
                (state.unsupported
                    ? 'Playback unsupported on this platform.'
                    : null),
            onRetry: () => unawaited(_load()),
            recoveryActions: widget.recoveryActions,
            showRetry: !state.unsupported,
          );
        }
        final durationMs = state.duration.inMilliseconds.clamp(1, 1 << 53);
        void seekBy(Duration offset) {
          final target = state.position + offset;
          unawaited(
            adapter.seek(
              target < Duration.zero
                  ? Duration.zero
                  : target > state.duration
                  ? state.duration
                  : target,
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.black,
                child: adapter.buildView(fit: widget.fit),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Material(
                  type: MaterialType.transparency,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.78),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Slider(
                          key: const ValueKey('video-seek'),
                          semanticFormatterCallback: (value) =>
                              'Seek video to ${Duration(milliseconds: value.round()).inSeconds} seconds',
                          value: state.position.inMilliseconds
                              .clamp(0, durationMs)
                              .toDouble(),
                          max: durationMs.toDouble(),
                          onChanged: (value) => unawaited(
                            adapter.seek(Duration(milliseconds: value.round())),
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              key: const ValueKey('video-play-pause'),
                              tooltip: state.playing
                                  ? 'Pause video'
                                  : 'Play video',
                              onPressed: () => unawaited(
                                state.playing
                                    ? adapter.pause()
                                    : adapter.play(),
                              ),
                              color: Colors.white,
                              icon: Icon(
                                state.playing ? Icons.pause : Icons.play_arrow,
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('video-rewind-10'),
                              tooltip: 'Rewind 10 seconds',
                              onPressed: () =>
                                  seekBy(const Duration(seconds: -10)),
                              color: Colors.white,
                              icon: const Icon(Icons.replay_10),
                            ),
                            IconButton(
                              key: const ValueKey('video-forward-10'),
                              tooltip: 'Forward 10 seconds',
                              onPressed: () =>
                                  seekBy(const Duration(seconds: 10)),
                              color: Colors.white,
                              icon: const Icon(Icons.forward_10),
                            ),
                            Text(
                              '${_formatPlaybackTime(state.position)} / ${_formatPlaybackTime(state.duration)}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            const Spacer(),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<double>(
                                key: const ValueKey('video-speed'),
                                value: state.playbackSpeed,
                                dropdownColor: Colors.black87,
                                style: const TextStyle(color: Colors.white),
                                items: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                                    .map(
                                      (speed) => DropdownMenuItem(
                                        value: speed,
                                        child: Text('$speed×'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (speed) {
                                  if (speed != null) {
                                    unawaited(adapter.setPlaybackSpeed(speed));
                                  }
                                },
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('video-mute'),
                              tooltip: state.muted
                                  ? 'Unmute video'
                                  : 'Mute video',
                              onPressed: () =>
                                  unawaited(adapter.setMuted(!state.muted)),
                              color: Colors.white,
                              icon: Icon(
                                state.muted
                                    ? Icons.volume_off
                                    : Icons.volume_up,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

final class _VideoFallback extends StatelessWidget {
  const _VideoFallback({
    required this.poster,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.recoveryActions,
    required this.showRetry,
  });
  final Widget poster;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;
  final List<Widget> recoveryActions;
  final bool showRetry;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      poster,
      if (loading) const Center(child: CircularProgressIndicator()),
      if (!loading && error != null)
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.black.withValues(alpha: 0.72),
            child: Semantics(
              liveRegion: true,
              label: 'Video playback failed',
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Playback unavailable',
                      style: TextStyle(color: Colors.white),
                    ),
                    if (showRetry)
                      TextButton(
                        onPressed: onRetry,
                        child: const Text('Retry'),
                      ),
                    ...recoveryActions,
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

String _formatPlaybackTime(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

void _ignoreCleanupError(Object error) {}

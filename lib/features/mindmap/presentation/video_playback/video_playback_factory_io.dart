import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'video_playback.dart';

typedef TemporaryVideoWriter =
    Future<void> Function(String path, Uint8List bytes);
typedef TemporaryVideoDeleter = Future<void> Function(String path);

Future<TemporaryVideoFileLease> writeTemporaryVideoFile({
  required String filePath,
  required Uint8List bytes,
  TemporaryVideoWriter writer = _writeTemporaryVideoFile,
  TemporaryVideoDeleter deleter = _deleteTemporaryVideoFile,
  ValueChanged<TemporaryVideoFileLease>? onLeaseCreated,
}) async {
  final lease = TemporaryVideoFileLease(filePath, deleter);
  onLeaseCreated?.call(lease);
  try {
    await writer(filePath, bytes);
    return lease;
  } on Object {
    await lease.close();
    rethrow;
  }
}

Future<void> _writeTemporaryVideoFile(String target, Uint8List bytes) =>
    File(target).writeAsBytes(bytes, flush: true);
Future<void> _deleteTemporaryVideoFile(String target) => File(target).delete();

Future<VideoPlaybackAdapter> createVideoPlaybackAdapter(
  VideoPlaybackSource source,
) async {
  if (Platform.isWindows) return _WindowsVideoPlaybackAdapter(source);
  if (Platform.isLinux) return _UnsupportedVideoPlaybackAdapter();
  return _IoVideoPlaybackAdapter(source);
}

final class _IoVideoPlaybackAdapter implements VideoPlaybackAdapter {
  _IoVideoPlaybackAdapter(this.source);
  final VideoPlaybackSource source;
  final ValueNotifier<VideoPlaybackState> _state = ValueNotifier(
    const VideoPlaybackState(),
  );
  VideoPlayerController? _controller;
  TemporaryVideoFileLease? _temporaryFile;
  bool _closed = false;
  @override
  ValueListenable<VideoPlaybackState> get state => _state;

  @override
  Future<void> initialize({
    required Duration initialPosition,
    required bool muted,
  }) async {
    if (_closed) throw StateError('Video playback adapter is closed.');
    try {
      final remote = source.remoteUrl;
      if (remote != null) {
        _controller = VideoPlayerController.networkUrl(remote);
      } else {
        final bytes = source.bytes;
        if (bytes == null || bytes.isEmpty) {
          throw const FormatException('Video bytes are unavailable.');
        }
        final directory = await getTemporaryDirectory();
        final extension = path.extension(source.fileName).isEmpty
            ? '.mp4'
            : path.extension(source.fileName);
        final filePath = path.join(
          directory.path,
          'var-video-${DateTime.now().microsecondsSinceEpoch}$extension',
        );
        _temporaryFile = await writeTemporaryVideoFile(
          filePath: filePath,
          bytes: bytes,
          onLeaseCreated: (lease) => _temporaryFile = lease,
        );
        _controller = VideoPlayerController.file(File(filePath));
      }
      final controller = _controller!;
      controller.addListener(_changed);
      await controller.initialize();
      await controller.setVolume(muted ? 0 : 1);
      if (initialPosition > Duration.zero) {
        await controller.seekTo(
          initialPosition > controller.value.duration
              ? controller.value.duration
              : initialPosition,
        );
      }
      _changed();
    } on Object {
      await _cleanupResources();
      rethrow;
    }
  }

  void _changed() {
    if (_closed) return;
    final value = _controller?.value;
    if (value == null) return;
    _state.value = VideoPlaybackState(
      initialized: value.isInitialized,
      playing: value.isPlaying,
      muted: value.volume == 0,
      position: value.position,
      duration: value.duration,
      playbackSpeed: value.playbackSpeed,
      error: value.hasError ? value.errorDescription : null,
    );
  }

  Future<void> _cleanupResources() async {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_changed);
    final temporaryFile = _temporaryFile;
    await cleanupVideoPlaybackResources(
      disposeController: () async => controller?.dispose(),
      releaseSource: () async {
        await temporaryFile?.close();
        if (temporaryFile?.isClosed ?? true) {
          if (identical(_temporaryFile, temporaryFile)) {
            _temporaryFile = null;
          }
        }
      },
    );
  }

  @override
  Widget buildView({required BoxFit fit}) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return FittedBox(
      fit: fit,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  @override
  Future<void> play() async => _controller?.play();
  @override
  Future<void> pause() async => _controller?.pause();
  @override
  Future<void> seek(Duration position) async => _controller?.seekTo(position);
  @override
  Future<void> setMuted(bool muted) async =>
      _controller?.setVolume(muted ? 0 : 1);
  @override
  Future<void> setPlaybackSpeed(double speed) async =>
      _controller?.setPlaybackSpeed(speed);
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _cleanupResources();
    _state.dispose();
  }
}

final class _WindowsVideoPlaybackAdapter implements VideoPlaybackAdapter {
  _WindowsVideoPlaybackAdapter(this.source);

  final VideoPlaybackSource source;
  final ValueNotifier<VideoPlaybackState> _state = ValueNotifier(
    const VideoPlaybackState(),
  );
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Player? _player;
  VideoController? _controller;
  TemporaryVideoFileLease? _temporaryFile;
  bool _closed = false;

  @override
  ValueListenable<VideoPlaybackState> get state => _state;

  @override
  Future<void> initialize({
    required Duration initialPosition,
    required bool muted,
  }) async {
    if (_closed) throw StateError('Video playback adapter is closed.');
    try {
      final remote = source.remoteUrl;
      String mediaPath;
      if (remote != null) {
        mediaPath = remote.toString();
      } else {
        final bytes = source.bytes;
        if (bytes == null || bytes.isEmpty) {
          throw const FormatException('Video bytes are unavailable.');
        }
        final directory = await getTemporaryDirectory();
        final extension = path.extension(source.fileName).isEmpty
            ? '.mp4'
            : path.extension(source.fileName);
        final filePath = path.join(
          directory.path,
          'var-video-${DateTime.now().microsecondsSinceEpoch}$extension',
        );
        _temporaryFile = await writeTemporaryVideoFile(
          filePath: filePath,
          bytes: bytes,
          onLeaseCreated: (lease) => _temporaryFile = lease,
        );
        mediaPath = filePath;
      }

      final player = Player();
      _player = player;
      _controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: false,
          hwdec: 'no',
        ),
      );
      _subscriptions.addAll([
        player.stream.playing.listen((_) => _changed()),
        player.stream.position.listen((_) => _changed()),
        player.stream.duration.listen((_) => _changed()),
        player.stream.volume.listen((_) => _changed()),
        player.stream.error.listen((error) => _changed(error: error)),
      ]);
      await player.open(Media(mediaPath), play: false);
      await player.setVolume(muted ? 0 : 100);
      if (initialPosition > Duration.zero) {
        final duration = player.state.duration;
        await player.seek(
          duration > Duration.zero && initialPosition > duration
              ? duration
              : initialPosition,
        );
      }
      _changed();
    } on Object {
      await _cleanupResources();
      rethrow;
    }
  }

  void _changed({Object? error}) {
    if (_closed) return;
    final player = _player;
    if (player == null) return;
    final value = player.state;
    _state.value = VideoPlaybackState(
      initialized: value.duration > Duration.zero,
      playing: value.playing,
      muted: value.volume == 0,
      position: value.position,
      duration: value.duration,
      playbackSpeed: value.rate,
      error: error,
    );
  }

  Future<void> _cleanupResources() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    _controller = null;
    final temporaryFile = _temporaryFile;
    await cleanupVideoPlaybackResources(
      disposeController: () async => player?.dispose(),
      releaseSource: () async {
        await temporaryFile?.close();
        if (temporaryFile?.isClosed ?? true) _temporaryFile = null;
      },
    );
  }

  @override
  Widget buildView({required BoxFit fit}) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.black,
      child: Video(
        controller: controller,
        fit: fit,
        controls: (_) => const SizedBox.shrink(),
      ),
    );
  }

  @override
  Future<void> play() async => _player?.play();
  @override
  Future<void> pause() async => _player?.pause();
  @override
  Future<void> seek(Duration position) async => _player?.seek(position);
  @override
  Future<void> setMuted(bool muted) async =>
      _player?.setVolume(muted ? 0 : 100);
  @override
  Future<void> setPlaybackSpeed(double speed) async => _player?.setRate(speed);
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _cleanupResources();
    _state.dispose();
  }
}

final class _UnsupportedVideoPlaybackAdapter implements VideoPlaybackAdapter {
  final ValueNotifier<VideoPlaybackState> _state = ValueNotifier(
    const VideoPlaybackState(unsupported: true),
  );
  bool _closed = false;
  @override
  ValueListenable<VideoPlaybackState> get state => _state;
  @override
  Future<void> initialize({
    required Duration initialPosition,
    required bool muted,
  }) async {}
  @override
  Widget buildView({required BoxFit fit}) => const SizedBox.shrink();
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> setPlaybackSpeed(double speed) async {}
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _state.dispose();
  }
}

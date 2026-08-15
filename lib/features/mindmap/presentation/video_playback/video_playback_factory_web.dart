import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

import 'video_playback.dart';

Future<VideoPlaybackAdapter> createVideoPlaybackAdapter(
  VideoPlaybackSource source,
) async => _WebVideoPlaybackAdapter(source);

final class _WebVideoPlaybackAdapter implements VideoPlaybackAdapter {
  _WebVideoPlaybackAdapter(this.source);
  final VideoPlaybackSource source;
  final ValueNotifier<VideoPlaybackState> _state = ValueNotifier(
    const VideoPlaybackState(),
  );
  VideoPlayerController? _controller;
  VideoObjectUrlLease? _objectUrl;
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
      Uri uri;
      if (remote != null) {
        uri = remote;
      } else {
        final bytes = source.bytes;
        if (bytes == null || bytes.isEmpty) {
          throw const FormatException('Video bytes are unavailable.');
        }
        final blob = web.Blob(
          <JSAny>[bytes.toJS].toJS,
          web.BlobPropertyBag(type: source.mimeType),
        );
        final url = web.URL.createObjectURL(blob);
        _objectUrl = VideoObjectUrlLease(
          url,
          (value) => web.URL.revokeObjectURL(value),
        );
        uri = Uri.parse(url);
      }
      final controller = VideoPlayerController.networkUrl(uri);
      _controller = controller;
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
    final objectUrl = _objectUrl;
    _objectUrl = null;
    await cleanupVideoPlaybackResources(
      disposeController: () async => controller?.dispose(),
      releaseSource: () async => objectUrl?.close(),
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

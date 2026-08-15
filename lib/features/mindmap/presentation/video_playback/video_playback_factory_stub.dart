import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'video_playback.dart';

Future<VideoPlaybackAdapter> createVideoPlaybackAdapter(
  VideoPlaybackSource source,
) async => _UnsupportedVideoPlaybackAdapter();

final class _UnsupportedVideoPlaybackAdapter implements VideoPlaybackAdapter {
  final ValueNotifier<VideoPlaybackState> _state = ValueNotifier(
    const VideoPlaybackState(unsupported: true),
  );
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
  Future<void> close() async => _state.dispose();
}

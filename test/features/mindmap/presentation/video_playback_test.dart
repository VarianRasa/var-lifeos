import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/presentation/video_playback/video_playback.dart';
import 'package:var_app/features/mindmap/presentation/video_playback/video_playback_factory_io.dart';

void main() {
  testWidgets('initializes controls and closes adapter on dispose', (
    tester,
  ) async {
    final adapter = _FakeAdapter();
    await tester.pumpWidget(
      _host(
        source: VideoPlaybackSource.remote(
          Uri.parse('https://example.test/video.mp4'),
        ),
        factory: (_) async => adapter,
      ),
    );
    await tester.pump();
    expect(adapter.initialized, isTrue);
    await tester.tap(find.byKey(const ValueKey('video-play-pause')));
    await tester.pump();
    expect(adapter.playCalls, 1);
    await tester.tap(find.byKey(const ValueKey('video-mute')));
    await tester.pump();
    expect(adapter.muteCalls, [true]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(adapter.closed, isTrue);
  });

  testWidgets(
    'source switch closes old adapter and ignores stale initialization',
    (tester) async {
      final first = _FakeAdapter(blockInitialize: true);
      final second = _FakeAdapter();
      var count = 0;
      Future<VideoPlaybackAdapter> factory(VideoPlaybackSource _) async =>
          count++ == 0 ? first : second;
      await tester.pumpWidget(
        _host(
          source: VideoPlaybackSource.remote(
            Uri.parse('https://example.test/one.mp4'),
          ),
          factory: factory,
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        _host(
          source: VideoPlaybackSource.remote(
            Uri.parse('https://example.test/two.mp4'),
          ),
          factory: factory,
        ),
      );
      first.releaseInitialize();
      await tester.pump();
      await tester.pump();
      expect(first.closed, isTrue);
      expect(second.initialized, isTrue);
    },
  );

  testWidgets('position duration mute callbacks follow adapter state', (
    tester,
  ) async {
    final adapter = _FakeAdapter();
    Duration? position;
    Duration? duration;
    bool? muted;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 240,
          child: VideoPlaybackSurface(
            source: VideoPlaybackSource.remote(
              Uri.parse('https://example.test/video.mp4'),
            ),
            poster: const Text('poster'),
            initialPosition: Duration.zero,
            initialMuted: false,
            adapterFactory: (_) async => adapter,
            onPositionChanged: (value) => position = value,
            onDurationChanged: (value) => duration = value,
            onMutedChanged: (value) => muted = value,
          ),
        ),
      ),
    );
    await tester.pump();
    adapter.emit(
      position: const Duration(seconds: 4),
      duration: const Duration(seconds: 20),
      muted: true,
    );
    await tester.pump();
    expect(position, const Duration(seconds: 4));
    expect(duration, const Duration(seconds: 20));
    expect(muted, isTrue);
  });

  testWidgets('advanced controls seek and change playback speed', (
    tester,
  ) async {
    final adapter = _FakeAdapter();
    await tester.pumpWidget(
      _host(
        source: VideoPlaybackSource.remote(
          Uri.parse('https://example.test/video.mp4'),
        ),
        factory: (_) async => adapter,
      ),
    );
    await tester.pump();
    adapter.emit(
      position: const Duration(seconds: 15),
      duration: const Duration(seconds: 30),
      muted: false,
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('video-rewind-10')));
    await tester.pump();
    expect(adapter.notifier.value.position, const Duration(seconds: 5));

    await tester.tap(find.byKey(const ValueKey('video-forward-10')));
    await tester.pump();
    expect(adapter.notifier.value.position, const Duration(seconds: 15));

    await tester.tap(find.byKey(const ValueKey('video-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5×').last);
    await tester.pumpAndSettle();
    expect(adapter.speedCalls, [1.5]);
  });

  testWidgets('error and unsupported adapters keep poster fallback', (
    tester,
  ) async {
    final adapter = _FakeAdapter(error: StateError('codec'));
    await tester.pumpWidget(
      _host(
        source: VideoPlaybackSource.remote(
          Uri.parse('https://example.test/video.mp4'),
        ),
        factory: (_) async => adapter,
      ),
    );
    await tester.pump();
    expect(find.text('poster'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-play-pause')), findsNothing);
  });

  test('rejects unsafe remote URL before platform adapter', () async {
    expect(
      () => createPlatformVideoPlaybackAdapter(
        VideoPlaybackSource.remote(Uri.parse('file:///tmp/video.mp4')),
      ),
      throwsFormatException,
    );
  });
  testWidgets('controls expose accessible labels', (tester) async {
    final adapter = _FakeAdapter();
    await tester.pumpWidget(
      _host(
        source: VideoPlaybackSource.remote(
          Uri.parse('https://example.test/video.mp4'),
        ),
        factory: (_) async => adapter,
      ),
    );
    await tester.pump();
    final play = tester.widget<IconButton>(
      find.byKey(const ValueKey('video-play-pause')),
    );
    final mute = tester.widget<IconButton>(
      find.byKey(const ValueKey('video-mute')),
    );
    final seek = tester.widget<Slider>(
      find.byKey(const ValueKey('video-seek')),
    );
    expect(play.tooltip, 'Play video');
    expect(mute.tooltip, 'Mute video');
    expect(
      seek.semanticFormatterCallback?.call(5000),
      'Seek video to 5 seconds',
    );
  });

  testWidgets('initialize exception detaches listener and closes adapter', (
    tester,
  ) async {
    final adapter = _FakeAdapter(throwOnInitialize: true);
    await tester.pumpWidget(
      _host(
        source: VideoPlaybackSource.remote(
          Uri.parse('https://example.test/video.mp4'),
        ),
        factory: (_) async => adapter,
      ),
    );
    await tester.pump();
    expect(adapter.closed, isTrue);
    expect(adapter.notifier.listening, isFalse);
    expect(find.text('Playback unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  test(
    'temporary file lease deletes once and contains delete failure',
    () async {
      var successCalls = 0;
      final success = TemporaryVideoFileLease('/tmp/video.mp4', (_) async {
        successCalls += 1;
      });
      await success.close();
      await success.close();
      expect(successCalls, 1);
      var failureCalls = 0;
      final failure = TemporaryVideoFileLease('/tmp/fail.mp4', (_) async {
        failureCalls += 1;
        if (failureCalls == 1) throw StateError('delete');
      });
      await expectLater(failure.close(), completes);
      expect(failure.isClosed, isFalse);
      await failure.close();
      expect(failureCalls, 2);
      expect(failure.isClosed, isTrue);
    },
  );

  test('partial temporary write deletes tracked file before rethrow', () async {
    final order = <String>[];
    await expectLater(
      writeTemporaryVideoFile(
        filePath: '/tmp/partial.mp4',
        bytes: Uint8List.fromList([1, 2, 3]),
        onLeaseCreated: (_) => order.add('lease'),
        writer: (target, bytes) async {
          order.add('write:$target:${bytes.length}');
          throw StateError('partial write');
        },
        deleter: (target) async => order.add('delete:$target'),
      ),
      throwsStateError,
    );
    expect(order, [
      'lease',
      'write:/tmp/partial.mp4:3',
      'delete:/tmp/partial.mp4',
    ]);
  });

  test(
    'cleanup seam disposes controller before source release despite failure',
    () async {
      final order = <String>[];
      await cleanupVideoPlaybackResources(
        disposeController: () async {
          order.add('controller');
          throw StateError('dispose');
        },
        releaseSource: () async => order.add('source'),
      );
      expect(order, ['controller', 'source']);
    },
  );

  testWidgets('unsupported fallback omits retry and keeps recovery action', (
    tester,
  ) async {
    final adapter = _FakeAdapter(unsupported: true);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 240,
          child: VideoPlaybackSurface(
            source: VideoPlaybackSource.remote(
              Uri.parse('https://example.test/video.mp4'),
            ),
            poster: const Text('poster'),
            initialPosition: Duration.zero,
            initialMuted: false,
            adapterFactory: (_) async => adapter,
            recoveryActions: const [
              TextButton(onPressed: null, child: Text('Export')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Playback unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Export'), findsOneWidget);
  });

  test(
    'web-style cleanup disposes controller before revoking object URL',
    () async {
      final order = <String>[];
      final lease = VideoObjectUrlLease(
        'blob:test',
        (_) => order.add('revoke'),
      );
      await cleanupVideoPlaybackResources(
        disposeController: () async => order.add('controller'),
        releaseSource: lease.close,
      );
      await lease.close();
      expect(order, ['controller', 'revoke']);
    },
  );

  test('object URL lease revokes once and contains revoke failure', () async {
    var successCalls = 0;
    final success = VideoObjectUrlLease('blob:success', (_) {
      successCalls += 1;
    });
    await success.close();
    await success.close();
    expect(successCalls, 1);
    var failureCalls = 0;
    final failure = VideoObjectUrlLease('blob:failure', (_) {
      failureCalls += 1;
      throw StateError('revoke');
    });
    await expectLater(failure.close(), completes);
    await failure.close();
    expect(failureCalls, 1);
  });

  test(
    'remote policy requires HTTPS except loopback HTTP and permits query',
    () {
      expect(
        isAllowedVideoRemoteUri(
          Uri.parse('https://cdn.test/video.mp4?token=signed'),
        ),
        isTrue,
      );
      expect(
        isAllowedVideoRemoteUri(Uri.parse('http://localhost:8080/video.mp4')),
        isTrue,
      );
      expect(
        isAllowedVideoRemoteUri(Uri.parse('http://127.0.0.1/video.mp4')),
        isTrue,
      );
      expect(
        isAllowedVideoRemoteUri(Uri.parse('http://[::1]/video.mp4')),
        isTrue,
      );
      expect(
        isAllowedVideoRemoteUri(Uri.parse('http://example.test/video.mp4')),
        isFalse,
      );
      expect(
        isAllowedVideoRemoteUri(
          Uri.parse('https://user:pass@example.test/video.mp4'),
        ),
        isFalse,
      );
      expect(
        isAllowedVideoRemoteUri(
          Uri.parse('https://example.test/video.mp4#part'),
        ),
        isFalse,
      );
    },
  );

  testWidgets('dispose during pending initialization closes adapter once', (
    tester,
  ) async {
    final adapter = _FakeAdapter(blockInitialize: true);
    await tester.pumpWidget(
      _host(
        source: VideoPlaybackSource.remote(
          Uri.parse('https://example.test/video.mp4'),
        ),
        factory: (_) async => adapter,
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    adapter.releaseInitialize();
    await tester.pump();
    await tester.pump();
    expect(adapter.closeCalls, 1);
  });
}

Widget _host({
  required VideoPlaybackSource source,
  required VideoPlaybackAdapterFactory factory,
}) => MaterialApp(
  home: SizedBox(
    width: 400,
    height: 240,
    child: VideoPlaybackSurface(
      source: source,
      poster: const Text('poster'),
      initialPosition: const Duration(seconds: 2),
      initialMuted: false,
      adapterFactory: factory,
    ),
  ),
);

final class _FakeAdapter implements VideoPlaybackAdapter {
  _FakeAdapter({
    this.blockInitialize = false,
    this.throwOnInitialize = false,
    this.unsupported = false,
    this.error,
  });
  final bool blockInitialize;
  final bool throwOnInitialize;
  final bool unsupported;
  final Object? error;
  final _TrackingNotifier notifier = _TrackingNotifier(
    const VideoPlaybackState(),
  );
  final Completer<void> _initializeCompleter = Completer<void>();
  bool initialized = false;
  bool closed = false;
  int closeCalls = 0;
  int playCalls = 0;
  final List<bool> muteCalls = [];
  final List<double> speedCalls = [];
  @override
  ValueListenable<VideoPlaybackState> get state => notifier;
  @override
  Future<void> initialize({
    required Duration initialPosition,
    required bool muted,
  }) async {
    if (blockInitialize) await _initializeCompleter.future;
    if (throwOnInitialize) throw StateError('initialize failed');
    initialized = true;
    notifier.value = VideoPlaybackState(
      initialized: error == null && !unsupported,
      error: error,
      unsupported: unsupported,
      position: initialPosition,
      duration: const Duration(seconds: 30),
      muted: muted,
    );
  }

  void releaseInitialize() {
    if (!_initializeCompleter.isCompleted) _initializeCompleter.complete();
  }

  void emit({
    required Duration position,
    required Duration duration,
    required bool muted,
  }) {
    notifier.value = VideoPlaybackState(
      initialized: true,
      position: position,
      duration: duration,
      muted: muted,
    );
  }

  @override
  Widget buildView({required BoxFit fit}) =>
      const ColoredBox(color: Colors.black);
  @override
  Future<void> play() async {
    playCalls += 1;
    notifier.value = VideoPlaybackState(
      initialized: true,
      playing: true,
      duration: notifier.value.duration,
      position: notifier.value.position,
      muted: notifier.value.muted,
    );
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {
    emit(
      position: position,
      duration: notifier.value.duration,
      muted: notifier.value.muted,
    );
  }

  @override
  Future<void> setMuted(bool muted) async {
    muteCalls.add(muted);
    emit(
      position: notifier.value.position,
      duration: notifier.value.duration,
      muted: muted,
    );
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    speedCalls.add(speed);
    notifier.value = VideoPlaybackState(
      initialized: true,
      position: notifier.value.position,
      duration: notifier.value.duration,
      muted: notifier.value.muted,
      playbackSpeed: speed,
    );
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (closed) return;
    closed = true;
    if (!blockInitialize && !throwOnInitialize) notifier.dispose();
  }
}

final class _TrackingNotifier extends ValueNotifier<VideoPlaybackState> {
  _TrackingNotifier(super.value);
  bool get listening => hasListeners;
}

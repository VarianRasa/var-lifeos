import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/features/focus/application/focus_audio_player_service.dart';
import 'package:var_app/features/focus/domain/focus_audio_track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('classifies only YouTube hosts as YouTube URLs', () {
    expect(
      FocusAudioPlayerNotifier.isYoutubeUrl(
        'https://music.youtube.com/watch?v=abc',
      ),
      isTrue,
    );
    expect(
      FocusAudioPlayerNotifier.isYoutubeUrl(
        'https://example.com/?next=youtube.com',
      ),
      isFalse,
    );
  });

  test('YouTube playback opens downloaded file, never signed URL', () async {
    final openedFiles = <String>[];
    final openedUris = <Uri>[];
    final notifier = FocusAudioPlayerNotifier(
      downloadYoutubeAudio: (_) async => File('downloaded.webm'),
      setFilePath: (value) async {
        openedFiles.add(value);
        return null;
      },
      setUri: (value) async {
        openedUris.add(value);
        return null;
      },
      startPlayback: () async {},
      subscribeToPlayer: false,
    );
    addTearDown(notifier.dispose);

    await notifier.playTrack(_track('https://youtu.be/abc'));

    expect(openedFiles, ['downloaded.webm']);
    expect(openedUris, isEmpty);
  });

  test('timeout clears loading and exposes stable error', () async {
    final notifier = FocusAudioPlayerNotifier(
      downloadYoutubeAudio: (_) => Completer<File>().future,
      setFilePath: (_) async => null,
      startPlayback: () async {},
      operationTimeout: const Duration(milliseconds: 10),
      subscribeToPlayer: false,
    );
    addTearDown(notifier.dispose);

    await notifier.playTrack(
      _track('https://youtube.com/watch?v=signed-secret'),
    );

    expect(notifier.state.isLoadingStream, isFalse);
    expect(notifier.state.error, focusAudioLoadError);
    expect(notifier.state.error, isNot(contains('signed-secret')));
  });

  test('next and previous open selected track once while paused', () async {
    var opens = 0;
    final notifier = FocusAudioPlayerNotifier(
      setUri: (_) async {
        opens++;
        return null;
      },
      startPlayback: () async {},
      subscribeToPlayer: false,
    );
    addTearDown(notifier.dispose);

    await notifier.nextTrack();
    expect(opens, 1);
    await notifier.previousTrack();
    expect(opens, 2);
  });

  test('next opens once while playing', () async {
    var opens = 0;
    final notifier = _PlayingNotifier(
      setUri: (_) async {
        opens++;
        return null;
      },
      startPlayback: () async {},
    );
    addTearDown(notifier.dispose);

    await notifier.nextTrack();

    expect(opens, 1);
  });

  test('downloader returns only after complete bytes are readable', () async {
    final directory = await Directory.systemTemp.createTemp('focus-bytes-');
    addTearDown(() => directory.delete(recursive: true));
    final downloader = YoutubeAudioDownloader(
      resolveAudio: (_) async => YoutubeAudioDownload(
        extension: 'webm',
        bytes: Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]),
      ),
      temporaryDirectory: () async => directory,
    );

    final file = await downloader.download('https://youtu.be/abc');

    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    await file.delete();
  });

  test('stale concurrent completion cannot load or play', () async {
    final first = Completer<File>();
    final loaded = <String>[];
    var plays = 0;
    final notifier = FocusAudioPlayerNotifier(
      downloadYoutubeAudio: (url) => url.contains('first')
          ? first.future
          : Future.value(File('second.webm')),
      setFilePath: (value) async {
        loaded.add(value);
        return null;
      },
      startPlayback: () async => plays++,
      subscribeToPlayer: false,
    );
    addTearDown(notifier.dispose);

    final stale = notifier.playTrack(_track('https://youtu.be/first'));
    await notifier.playTrack(_track('https://youtu.be/second'));
    first.complete(File('first.webm'));
    await stale;

    expect(loaded, ['second.webm']);
    expect(plays, 1);
    expect(notifier.state.currentTrack?.audioUrl, contains('second'));
  });

  test(
    'play startup is invoked once and does not block source readiness',
    () async {
      final playback = Completer<void>();
      var starts = 0;
      final notifier = FocusAudioPlayerNotifier(
        setUri: (_) async => null,
        startPlayback: () {
          starts++;
          return playback.future;
        },
        operationTimeout: const Duration(milliseconds: 10),
        subscribeToPlayer: false,
      );
      addTearDown(() {
        playback.complete();
        notifier.dispose();
      });

      await notifier
          .playTrack(_track('https://example.com/audio.mp3'))
          .timeout(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(starts, 1);
      expect(notifier.state.isLoadingStream, isFalse);
      expect(notifier.state.error, isNull);
    },
  );

  test('late stale source load settles before newer source starts', () async {
    final first = Completer<Duration?>();
    final second = Completer<Duration?>();
    final calls = <String>[];
    final processing = StreamController<ProcessingState>.broadcast();
    final errors = StreamController<Object>.broadcast();
    final notifier = FocusAudioPlayerNotifier(
      setUri: (uri) {
        calls.add('load:${uri.path}');
        return uri.path.contains('first') ? first.future : second.future;
      },
      stopPlayback: () async => calls.add('stop'),
      startPlayback: () async => calls.add('play'),
      processingStateEvents: processing.stream,
      playbackErrorEvents: errors.stream,
      operationTimeout: const Duration(milliseconds: 10),
      subscribeToPlayer: false,
    );
    addTearDown(notifier.dispose);
    addTearDown(processing.close);
    addTearDown(errors.close);

    final stale = notifier.playTrack(_track('https://example.com/first.mp3'));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    final current = notifier.playTrack(
      _track('https://example.com/second.mp3'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(calls, ['load:/first.mp3', 'load:/second.mp3']);
    errors.add('stale');
    processing.add(ProcessingState.completed);
    first.complete(null);
    second.complete(null);
    await stale;
    await current;
    await Future<void>.delayed(Duration.zero);

    expect(calls, ['load:/first.mp3', 'load:/second.mp3', 'stop', 'play']);
    expect(notifier.state.currentTrack?.audioUrl, contains('second'));
    expect(notifier.state.error, isNull);
  });

  test('never completing stale source does not block next source', () async {
    final calls = <String>[];
    final notifier = FocusAudioPlayerNotifier(
      setUri: (uri) {
        calls.add(uri.path);
        if (uri.path.contains('first')) return Completer<Duration?>().future;
        return Future.value(null);
      },
      startPlayback: () async {},
      operationTimeout: const Duration(milliseconds: 10),
      subscribeToPlayer: false,
    );
    addTearDown(notifier.dispose);

    await notifier.playTrack(_track('https://example.com/first.mp3'));
    await notifier
        .playTrack(_track('https://example.com/second.mp3'))
        .timeout(const Duration(milliseconds: 100));

    expect(calls, ['/first.mp3', '/second.mp3']);
  });

  test(
    'completed event requires active non-completed event before advance',
    () async {
      final processing = StreamController<ProcessingState>.broadcast();
      var opens = 0;
      final notifier = FocusAudioPlayerNotifier(
        setUri: (_) async {
          opens++;
          return null;
        },
        startPlayback: () async {},
        processingStateEvents: processing.stream,
        subscribeToPlayer: false,
      );
      addTearDown(notifier.dispose);
      addTearDown(processing.close);

      await notifier.playTrack(
        FocusAudioPlayerNotifier.defaultFocusPresets.first,
      );
      processing.add(ProcessingState.completed);
      await Future<void>.delayed(Duration.zero);
      expect(opens, 1);
      processing.add(ProcessingState.ready);
      processing.add(ProcessingState.completed);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(opens, 2);
    },
  );

  test(
    'async cleanup stops and disposes before deleting active file',
    () async {
      final events = <String>[];
      final notifier = FocusAudioPlayerNotifier(
        downloadYoutubeAudio: (_) async => File('active.webm'),
        setFilePath: (_) async => null,
        startPlayback: () async {},
        stopPlayback: () async => events.add('stop'),
        disposePlayback: () async => events.add('dispose'),
        deleteTempFile: (file) async => events.add('delete:${file.path}'),
        subscribeToPlayer: false,
      );

      await notifier.playTrack(_track('https://youtu.be/active'));
      await notifier.cleanup();

      expect(events, ['stop', 'dispose', 'delete:active.webm']);
      notifier.dispose();
    },
  );

  test('one deadline bounds download and load together', () async {
    final stopwatch = Stopwatch()..start();
    final notifier = FocusAudioPlayerNotifier(
      downloadYoutubeAudio: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return File('audio.webm');
      },
      setFilePath: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return null;
      },
      startPlayback: () async {},
      operationTimeout: const Duration(milliseconds: 45),
      subscribeToPlayer: false,
    );
    addTearDown(notifier.dispose);

    await notifier.playTrack(_track('https://youtu.be/deadline'));

    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 60)));
    expect(notifier.state.error, focusAudioLoadError);
  });

  test(
    'cancel before resolve prevents file creation and completes download',
    () async {
      final directory = await Directory.systemTemp.createTemp('focus-latch-');
      addTearDown(() => directory.delete(recursive: true));
      final resolved = Completer<YoutubeAudioDownload>();
      var created = false;
      final downloader = YoutubeAudioDownloader(
        resolveAudio: (_) => resolved.future,
        temporaryDirectory: () async => directory,
        onFileCreated: (_) => created = true,
      );
      final future = downloader.download('https://youtu.be/abc');
      final expectation = expectLater(
        future,
        throwsA(isA<AudioDownloadCancelled>()),
      );

      await downloader.cancel();
      resolved.complete(
        const YoutubeAudioDownload(extension: 'webm', bytes: Stream.empty()),
      );

      await expectation;
      expect(created, isFalse);
    },
  );

  test('old temp deletion occurs after stop and source switch', () async {
    final events = <String>[];
    final files = <String, File>{};
    var sequence = 0;
    final notifier = FocusAudioPlayerNotifier(
      downloadYoutubeAudio: (_) async {
        final file = File('audio-${++sequence}.webm');
        files[file.path] = file;
        return file;
      },
      stopPlayback: () async => events.add('stop'),
      setFilePath: (value) async {
        events.add('load:$value');
        return null;
      },
      deleteTempFile: (file) async => events.add('delete:${file.path}'),
      startPlayback: () async {},
      subscribeToPlayer: false,
    );
    addTearDown(notifier.dispose);

    await notifier.playTrack(_track('https://youtu.be/one'));
    events.clear();
    await notifier.playTrack(_track('https://youtu.be/two'));
    await Future<void>.delayed(Duration.zero);

    expect(events, ['stop', 'load:audio-2.webm', 'delete:audio-1.webm']);
  });

  test(
    'duplicate completed events advance once and stale error is ignored',
    () async {
      final processing = StreamController<ProcessingState>.broadcast();
      final errors = StreamController<Object>.broadcast();
      var opens = 0;
      final notifier = FocusAudioPlayerNotifier(
        setUri: (_) async {
          opens++;
          return null;
        },
        startPlayback: () async {},
        processingStateEvents: processing.stream,
        playbackErrorEvents: errors.stream,
        subscribeToPlayer: false,
      );
      addTearDown(notifier.dispose);
      addTearDown(processing.close);
      addTearDown(errors.close);

      await notifier.playTrack(
        FocusAudioPlayerNotifier.defaultFocusPresets.first,
      );
      errors.add('stale');
      processing.add(ProcessingState.ready);
      processing.add(ProcessingState.completed);
      processing.add(ProcessingState.completed);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(opens, 2);
      expect(notifier.state.error, isNull);
    },
  );

  test(
    'cancel mid-stream completes promptly and deletes partial file',
    () async {
      final directory = await Directory.systemTemp.createTemp('focus-mid-');
      addTearDown(() => directory.delete(recursive: true));
      final controller = StreamController<List<int>>();
      File? created;
      final downloader = YoutubeAudioDownloader(
        resolveAudio: (_) async =>
            YoutubeAudioDownload(extension: 'webm', bytes: controller.stream),
        temporaryDirectory: () async => directory,
        onFileCreated: (file) => created = file,
      );
      final future = downloader.download('https://youtu.be/abc');
      final expectation = expectLater(
        future,
        throwsA(isA<AudioDownloadCancelled>()),
      );
      controller.add([1, 2, 3]);
      await Future<void>.delayed(Duration.zero);

      await downloader.cancel();
      await expectation.timeout(const Duration(milliseconds: 100));

      expect(await created!.exists(), isFalse);
      await controller.close();
    },
  );

  test('cancel while temporary directory pending creates no file', () async {
    final directory = Completer<Directory>();
    var created = false;
    final downloader = YoutubeAudioDownloader(
      resolveAudio: (_) async =>
          const YoutubeAudioDownload(extension: 'webm', bytes: Stream.empty()),
      temporaryDirectory: () => directory.future,
      onFileCreated: (_) => created = true,
    );
    final future = downloader.download('https://youtu.be/abc');
    final expectation = expectLater(
      future,
      throwsA(isA<AudioDownloadCancelled>()),
    );
    await Future<void>.delayed(Duration.zero);

    await downloader.cancel();
    directory.complete(Directory.systemTemp);
    await expectation;

    expect(created, isFalse);
  });

  test(
    'failed source switch retains previous file for later cleanup',
    () async {
      var sequence = 0;
      final deleted = <String>[];
      var fail = true;
      final notifier = FocusAudioPlayerNotifier(
        downloadYoutubeAudio: (_) async => File('audio-${++sequence}.webm'),
        stopPlayback: () async {},
        setFilePath: (value) async {
          if (value == 'audio-2.webm' && fail) {
            throw StateError('switch failed');
          }
          return null;
        },
        deleteTempFile: (file) async => deleted.add(file.path),
        startPlayback: () async {},
        subscribeToPlayer: false,
      );
      addTearDown(notifier.dispose);

      await notifier.playTrack(_track('https://youtu.be/one'));
      await notifier.playTrack(_track('https://youtu.be/two'));
      expect(deleted, isNot(contains('audio-1.webm')));
      fail = false;
      await notifier.playTrack(_track('https://youtu.be/three'));

      expect(deleted, contains('audio-1.webm'));
    },
  );

  test('downloader timeout cancels stream and removes partial file', () async {
    final directory = await Directory.systemTemp.createTemp('focus-cancel-');
    addTearDown(() => directory.delete(recursive: true));
    final controller = StreamController<List<int>>(onCancel: () {});
    var cancelled = false;
    controller.onCancel = () => cancelled = true;
    File? created;
    final downloader = YoutubeAudioDownloader(
      resolveAudio: (_) async =>
          YoutubeAudioDownload(extension: 'webm', bytes: controller.stream),
      temporaryDirectory: () async => directory,
      onFileCreated: (file) => created = file,
      downloadTimeout: const Duration(milliseconds: 10),
    );
    final future = downloader.download('https://youtu.be/abc');
    controller.add([1, 2, 3]);

    await expectLater(future, throwsA(isA<TimeoutException>()));
    expect(cancelled, isTrue);
    expect(await created!.exists(), isFalse);
    await controller.close();
  });

  test('downloader removes partial file when stream fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'focus-audio-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    File? created;
    final downloader = YoutubeAudioDownloader(
      resolveAudio: (_) async => YoutubeAudioDownload(
        extension: 'webm',
        bytes: Stream<List<int>>.error('download failed'),
      ),
      temporaryDirectory: () async => directory,
      onFileCreated: (file) => created = file,
    );

    await expectLater(
      downloader.download('https://youtu.be/abc'),
      throwsA(anything),
    );
    expect(created, isNotNull);
    expect(await created!.exists(), isFalse);
  });
}

class _PlayingNotifier extends FocusAudioPlayerNotifier {
  _PlayingNotifier({required super.setUri, required super.startPlayback})
    : super(subscribeToPlayer: false) {
    state = state.copyWith(isPlaying: true);
  }
}

FocusAudioTrack _track(String url) => FocusAudioTrack(
  id: 'test',
  title: 'Test',
  artist: 'Test',
  audioUrl: url,
  isPreset: false,
  category: 'Test',
);

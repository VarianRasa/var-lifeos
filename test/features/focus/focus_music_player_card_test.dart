import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/features/focus/application/focus_audio_player_service.dart';
import 'package:var_app/features/focus/widgets/focus_music_player_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('unknown duration disables seek and shows placeholder', (
    tester,
  ) async {
    final notifier = _TestNotifier(
      const FocusAudioPlayerState(
        tracks: FocusAudioPlayerNotifier.defaultFocusPresets,
        duration: Duration.zero,
      ),
    );
    await tester.pumpWidget(_app(notifier));

    expect(find.text('--:--'), findsNWidgets(2));
    expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNull);
  });

  testWidgets('loading disables play', (tester) async {
    final notifier = _TestNotifier(
      const FocusAudioPlayerState(
        tracks: FocusAudioPlayerNotifier.defaultFocusPresets,
        isLoadingStream: true,
      ),
    );
    await tester.pumpWidget(_app(notifier));

    final button = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey('focus-music-play-pause')),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('error retry invokes playback', (tester) async {
    final notifier = _TestNotifier(
      FocusAudioPlayerState(
        tracks: FocusAudioPlayerNotifier.defaultFocusPresets,
        currentTrack: FocusAudioPlayerNotifier.defaultFocusPresets.first,
        error: focusAudioLoadError,
      ),
    );
    await tester.pumpWidget(_app(notifier));

    await tester.tap(find.widgetWithText(TextButton, 'Coba lagi'));
    await tester.pump();

    expect(notifier.playCalls, 1);
  });

  testWidgets('error provides retry action', (tester) async {
    final notifier = _TestNotifier(
      const FocusAudioPlayerState(
        tracks: FocusAudioPlayerNotifier.defaultFocusPresets,
        error: focusAudioLoadError,
      ),
    );
    await tester.pumpWidget(_app(notifier));

    expect(find.text(focusAudioLoadError), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Coba lagi'), findsOneWidget);
  });
}

Widget _app(FocusAudioPlayerNotifier notifier) => ProviderScope(
  overrides: [focusAudioPlayerServiceProvider.overrideWith((ref) => notifier)],
  child: const MaterialApp(
    home: Scaffold(body: FocusMusicPlayerCard(onOpenPlaylistDialog: _noop)),
  ),
);

void _noop() {}

class _TestNotifier extends FocusAudioPlayerNotifier {
  _TestNotifier(FocusAudioPlayerState initial)
    : super(subscribeToPlayer: false) {
    state = initial;
  }

  int playCalls = 0;

  @override
  Future<void> play() async {
    playCalls++;
  }
}

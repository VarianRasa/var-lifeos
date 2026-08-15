import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/focus/application/focus_audio_player_service.dart';
import 'package:var_app/features/focus/focus_page.dart';
import 'package:var_app/features/mindmap/application/focus_timer_provider.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Widget focusTestApp({List<MindmapNode> nodes = const []}) {
    return ProviderScope(
      overrides: [
        allMindmapNodesProvider.overrideWith((ref) async => nodes),
        focusAudioPlayerServiceProvider.overrideWith(
          (ref) => _NoopFocusAudioNotifier(),
        ),
      ],
      child: const MaterialApp(home: FocusPage()),
    );
  }

  testWidgets('focus page fits representative widths at two times text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in <double>[320, 768, 1024, 1440]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(focusTestApp());
      await tester.pumpAndSettle();
      expect(find.text('Focus Mode & Pomodoro'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(width < 900 ? 'focus-compact-column' : 'focus-expanded-row'),
        ),
        findsOneWidget,
      );
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Zen mode exposes exit button and Escape returns focus', (
    tester,
  ) async {
    await tester.pumpWidget(focusTestApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mode Zen Fullscreen'));
    await tester.pumpAndSettle();
    final exit = find.byTooltip('Exit Zen mode');
    expect(exit, findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('focus-zen-exit'))).label,
      'Exit Zen mode',
    );
    await tester.tap(exit);
    await tester.pumpAndSettle();
    expect(find.text('Focus Mode & Pomodoro'), findsOneWidget);

    await tester.tap(find.byTooltip('Mode Zen Fullscreen'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Focus Mode & Pomodoro'), findsOneWidget);
  });

  testWidgets('timer summary keeps action button semantics exposed', (
    tester,
  ) async {
    await tester.pumpWidget(focusTestApp());
    await tester.pumpAndSettle();
    for (final tooltip in <String>['Start', 'Reset', 'Skip']) {
      final action = find.descendant(
        of: find.byKey(const ValueKey('pomodoro-timer-semantics')),
        matching: find.byTooltip(tooltip),
      );
      expect(action, findsOneWidget);
      expect(tester.getSemantics(action).flagsCollection.isButton, isTrue);
    }
  });

  testWidgets('expanded task selector updates current timer task', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final task = MindmapNode(
      id: 'task-1',
      day: now,
      type: NodeType.task,
      title: 'Ship release',
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(focusTestApp(nodes: [task]));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('focus-task-selector')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('focus-task-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ship release').last);
    await tester.pumpAndSettle();
    expect(find.text('Ship release'), findsOneWidget);
    expect(find.text('Lepas Task'), findsOneWidget);
  });

  testWidgets('focus music transport controls expose labels', (tester) async {
    await tester.pumpWidget(focusTestApp());
    await tester.pumpAndSettle();
    for (final entry in <String, String>{
      'focus-music-previous': 'Previous focus track',
      'focus-music-play-pause': 'Play focus audio',
      'focus-music-next': 'Next focus track',
    }.entries) {
      expect(find.byTooltip(entry.value), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(ValueKey(entry.key))).label,
        entry.value,
      );
    }
  });

  testWidgets('timer exposes phase remaining time and running state', (
    tester,
  ) async {
    await tester.pumpWidget(focusTestApp());
    await tester.pumpAndSettle();
    final timer = tester.getSemantics(
      find.byKey(const ValueKey('pomodoro-timer-semantics')),
    );
    expect(timer.label, 'Focus timer');
    expect(timer.value, contains('Focus'));
    expect(timer.value, contains('25:00'));
    expect(timer.value, contains('paused'));
  });

  testWidgets('timer controls preserve start pause reset and task selection', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        focusAudioPlayerServiceProvider.overrideWith(
          (ref) => _NoopFocusAudioNotifier(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FocusPage()),
      ),
    );
    await tester.pumpAndSettle();

    Finder timerControl(String tooltip) => find.descendant(
      of: find.byKey(const ValueKey('pomodoro-timer-semantics')),
      matching: find.byTooltip(tooltip),
    );

    await tester.ensureVisible(timerControl('Start'));
    await tester.pumpAndSettle();
    await tester.tap(timerControl('Start'));
    await tester.pump();
    expect(container.read(focusTimerProvider).isRunning, isTrue);
    await tester.ensureVisible(timerControl('Pause'));
    await tester.tap(timerControl('Pause'));
    await tester.pump();
    expect(container.read(focusTimerProvider).isRunning, isFalse);
    container.read(focusTimerProvider.notifier).reset();
    expect(container.read(focusTimerProvider).remainingSeconds, 25 * 60);
    container.read(focusTimerProvider.notifier).selectNode('task-1', 'Ship');
    expect(container.read(focusTimerProvider).selectedNodeId, 'task-1');
    expect(container.read(focusTimerProvider).selectedNodeTitle, 'Ship');
  });

  group('FocusTimerNotifier Unit Test', () {
    test('Timer default berdurasi 25 menit (1500 detik)', () {
      final container = ProviderContainer(
        overrides: [
          focusAudioPlayerServiceProvider.overrideWith(
            (ref) => _NoopFocusAudioNotifier(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(focusTimerProvider);
      expect(state.durationSeconds, equals(25 * 60));
      expect(state.phase, equals(FocusTimerPhase.focus));
      expect(state.isRunning, isFalse);
    });

    test(
      'Ubah durasi timer mengubah durationSeconds dan mereset elapsedSeconds',
      () {
        final container = ProviderContainer(
          overrides: [
            focusAudioPlayerServiceProvider.overrideWith(
              (ref) => _NoopFocusAudioNotifier(),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(focusTimerProvider.notifier);
        notifier.setDuration(45);

        final state = container.read(focusTimerProvider);
        expect(state.durationSeconds, equals(45 * 60));
        expect(state.remainingSeconds, equals(45 * 60));
      },
    );
  });
}

class _NoopFocusAudioNotifier extends FocusAudioPlayerNotifier {
  _NoopFocusAudioNotifier() : super(subscribeToPlayer: false);

  @override
  Future<void> play() async {}
}

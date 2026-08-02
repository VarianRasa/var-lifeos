import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/features/mindmap/application/focus_timer_provider.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('FocusTimerNotifier Unit Test', () {
    test('Timer default berdurasi 25 menit (1500 detik)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(focusTimerProvider);
      expect(state.durationSeconds, equals(25 * 60));
      expect(state.phase, equals(FocusTimerPhase.focus));
      expect(state.isRunning, isFalse);
    });

    test(
      'Ubah durasi timer mengubah durationSeconds dan mereset elapsedSeconds',
      () {
        final container = ProviderContainer();
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

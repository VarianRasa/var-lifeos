import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/hybrid_timer.dart';

void main() {
  test('running countdown derives time from persisted timestamp', () {
    final state = HybridTimerState(
      mode: TimerMode.countdown,
      status: TimerRunStatus.running,
      plannedSeconds: 1500,
      accumulatedSeconds: 120,
      startedAt: DateTime(2026, 7, 16, 10),
    );

    expect(state.elapsedSecondsAt(DateTime(2026, 7, 16, 10, 3)), 300);
    expect(state.remainingSecondsAt(DateTime(2026, 7, 16, 10, 3)), 1200);
    expect(state.progressAt(DateTime(2026, 7, 16, 10, 3)), 0.2);
  });

  test('pause resume and lap preserve accumulated elapsed time', () {
    final started = const HybridTimerState(
      mode: TimerMode.stopwatch,
    ).start(DateTime(2026, 7, 16, 10));
    final paused = started.pause(DateTime(2026, 7, 16, 10, 5));
    final resumed = paused.start(DateTime(2026, 7, 16, 11));
    final lapped = resumed.addLap(DateTime(2026, 7, 16, 11, 2), id: 'lap-1');

    expect(paused.accumulatedSeconds, 300);
    expect(lapped.laps.single.elapsedSeconds, 420);
  });

  test('completion records metadata and bounds history', () {
    var state = HybridTimerState(
      mode: TimerMode.focus,
      status: TimerRunStatus.running,
      startedAt: DateTime(2026, 7, 16, 10),
      sessionStartedAt: DateTime(2026, 7, 16, 10),
      distractions: <TimerDistraction>[
        TimerDistraction(
          id: 'd',
          text: 'Phone',
          createdAt: DateTime(2026, 7, 16, 10, 1),
        ),
      ],
    );
    for (var index = 0; index < 105; index++) {
      state = state
          .copyWith(
            status: TimerRunStatus.running,
            startedAt: DateTime(2026, 7, 16, 10),
            sessionStartedAt: DateTime(2026, 7, 16, 10),
          )
          .complete(DateTime(2026, 7, 16, 10, 1), recordId: 'session-$index');
    }

    expect(state.history, hasLength(maxTimerHistory));
    expect(state.history.first.id, 'session-104');
    expect(state.history.last.id, 'session-5');
    expect(state.completedCycles, 4);
  });

  test('rich state round trips through JSON', () {
    final source = HybridTimerState(
      mode: TimerMode.stopwatch,
      status: TimerRunStatus.paused,
      label: 'Deep work',
      accumulatedSeconds: 90,
      laps: <TimerLap>[
        TimerLap(
          id: 'lap',
          elapsedSeconds: 45,
          createdAt: DateTime(2026, 7, 16, 9),
        ),
      ],
    );

    expect(HybridTimerState.fromJson(source.toJson()), source);
  });
}

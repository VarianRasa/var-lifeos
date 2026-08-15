# Timer Node Hybrid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build persistent Focus, Countdown, and Stopwatch modes with timestamp-correct state, distractions, laps, history, dynamic sizing, and read-only collapsed preview.

**Architecture:** Put immutable state and transitions in a pure Dart domain file. Keep `TimerPayload` as migration/persistence boundary. Dedicated editor uses a repaint-only ticker; explicit actions flow through existing node draft and database mutation pipeline.

**Tech Stack:** Flutter, Dart 3.11, Material 3, existing local-first node persistence, `flutter_test`.

---

## File Map

- Create `lib/features/mindmap/domain/hybrid_timer.dart` for timer state, codecs, calculations, and transitions.
- Modify `lib/features/mindmap/domain/node_type_payloads.dart` for migration and compatibility fields.
- Create `lib/features/mindmap/presentation/node_editors/timer_node_editor.dart` for expanded UI.
- Modify `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart` for editor routing.
- Modify `lib/features/mindmap/domain/inline_node_workspace_policy.dart` for dynamic size.
- Modify `lib/features/mindmap/presentation/mindmap_canvas.dart` for collapsed preview.
- Add domain and widget tests under matching `test/features/mindmap/` paths.

### Task 1: Hybrid Timer Domain

**Files:**
- Create: `lib/features/mindmap/domain/hybrid_timer.dart`
- Test: `test/features/mindmap/domain/hybrid_timer_test.dart`

- [ ] Write failing tests for timestamp-derived elapsed/remaining time, JSON round-trip, pause/resume, completion history, distractions, laps, Focus cycles, malformed JSON, and 100-record history cap.
- [ ] Run `flutter test --no-pub test/features/mindmap/domain/hybrid_timer_test.dart`; expect missing-type compilation failure.
- [ ] Define `TimerMode { focus, countdown, stopwatch }`, `TimerRunStatus { idle, running, paused, expired, completed }`, and `FocusSegment { focus, breakTime }`.
- [ ] Define immutable `TimerDistraction`, `TimerLap`, `TimerSessionRecord`, and `HybridTimerState` with safe JSON codecs, equality, and `copyWith`.
- [ ] Implement `elapsedSecondsAt`, `remainingSecondsAt`, `progressAt`, `start`, `pause`, `reset`, `complete`, `addDistraction`, and `addLap`. Clamp negative clock differences; never persist on each second.
- [ ] Run domain tests; expect all pass.

Core state shape:

```dart
final class HybridTimerState {
  const HybridTimerState({
    this.mode = TimerMode.focus,
    this.status = TimerRunStatus.idle,
    this.label = '',
    this.plannedSeconds = 1500,
    this.accumulatedSeconds = 0,
    this.startedAt,
    this.sessionStartedAt,
    this.focusSeconds = 1500,
    this.breakSeconds = 300,
    this.cycleTarget = 4,
    this.completedCycles = 0,
    this.segment = FocusSegment.focus,
    this.autoStartBreak = false,
    this.distractions = const <TimerDistraction>[],
    this.laps = const <TimerLap>[],
    this.history = const <TimerSessionRecord>[],
  });
}
```

### Task 2: TimerPayload Migration

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart:947`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart`

- [ ] Write failing test migrating `timerSeconds: 1200` and `timerInitialSeconds: 1500` into Countdown state with 300 elapsed seconds.
- [ ] Test preservation of unrelated node keys and unknown nested `timer` keys.
- [ ] Change `TimerPayload` to own `HybridTimerState timer`; keep compatibility getters for `timerSeconds` and `timerInitialSeconds`.
- [ ] Make `fromNode()` prefer valid nested state, otherwise migrate flat values.
- [ ] Make `toData()` merge nested unknown keys, write nested state, and retain flat compatibility values.
- [ ] Validate title, durations 1-86400 seconds, cycle target 1-12, label length 80, distraction length 160, and non-negative elapsed values.
- [ ] Run `flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart`; expect all pass.

### Task 3: Expanded Timer Editor

**Files:**
- Create: `lib/features/mindmap/presentation/node_editors/timer_node_editor.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart:258`
- Test: `test/features/mindmap/presentation/timer_node_editor_test.dart`

- [ ] Write failing widget tests for stable editor, mode, primary action, complete, reset, distraction, lap, and history keys.
- [ ] Test start emits running timestamp state, pause emits accumulated elapsed time, complete appends history, and mode changes emit defaults.
- [ ] Build stateful editor with a one-second periodic repaint only while running. Cancel ticker in `dispose` and update it in `didUpdateWidget`.
- [ ] Build segmented mode header, status badge, editable label, monospaced hero time, bounded progress, and Focus cycles.
- [ ] Build Focus presets 25/5 and 50/10, custom durations, cycle target, and auto-start break.
- [ ] Build Countdown presets 5/15/25/45/60 and custom duration.
- [ ] Build Stopwatch lap action and lap list.
- [ ] Build start, pause, resume, complete, and reset controls. Confirm before losing elapsed work.
- [ ] Build distraction input, daily summary, and latest five history cards.
- [ ] Use scroll fallback, Wrap, Expanded, and Flexible to prevent narrow-layout overflow.
- [ ] Route Timer nodes to dedicated editor and remove duplicated reset-only action.
- [ ] Run Timer editor tests; expect all pass without rendering exceptions.

Editor routing must pass current node, typed Timer payload, title/body callbacks, and draft callback directly to `TimerNodeEditor`.

### Task 4: Dynamic Size and Collapsed Preview

**Files:**
- Modify: `lib/features/mindmap/domain/inline_node_workspace_policy.dart:62`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart:9630`
- Test: `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] Write failing size test using distractions, laps, and five history records. Require width at least 620 and height above base Timer size.
- [ ] Add Timer content-aware sizing from mode settings, distractions, laps, and at most five visible history cards.
- [ ] Use normal minimum near 620 by 620 and keep computed values finite. Scroll remains fallback for smaller viewports.
- [ ] Replace collapsed controls with read-only mode icon, status, formatted timestamp-derived time, progress, and Focus cycles.
- [ ] Add repaint-only collapsed ticker while running; never mutate node from ticker.
- [ ] Test collapsed preview has no expanded action keys and displayed time changes after two pumped seconds.
- [ ] Run policy and Timer canvas tests; expect no overflow.

### Task 5: Integration Validation

**Files:**
- Modify compatibility tests only where reset-only Timer behavior is intentionally replaced.

- [ ] Format all changed Dart files with `dart format`.
- [ ] Run domain, payload, sizing, Timer editor, productivity editor, and inline workspace tests together.
- [ ] Run `flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name timer`.
- [ ] Run `flutter analyze --no-pub`; expect no issues.
- [ ] Run `git diff --check -- lib/features/mindmap test/features/mindmap`; expect no whitespace errors.
- [ ] Manually verify all modes across collapse, navigation, and app restart; complete a session and confirm history survives reload.

Focused suite:

```powershell
flutter test --no-pub `
  test/features/mindmap/domain/hybrid_timer_test.dart `
  test/features/mindmap/domain/node_type_payloads_test.dart `
  test/features/mindmap/domain/inline_node_workspace_policy_test.dart `
  test/features/mindmap/presentation/timer_node_editor_test.dart `
  test/features/mindmap/presentation/productivity_node_editors_test.dart `
  test/features/mindmap/presentation/inline_node_workspace_test.dart
```

No commit step is included because current task policy prohibits commits unless user explicitly requests one.

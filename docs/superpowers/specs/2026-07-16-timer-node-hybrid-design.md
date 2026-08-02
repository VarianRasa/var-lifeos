# Timer Node Hybrid Design

## Goal

Replace the minimal countdown-only Timer node with a professional hybrid timer supporting focus sessions, custom countdowns, and stopwatch tracking. State must survive collapse, navigation, app backgrounding, and app restart through timestamp-based local-first persistence.

## Product Scope

### Modes

- **Focus:** configurable focus and break durations, cycle target, optional automatic break start, and Pomodoro presets.
- **Countdown:** arbitrary duration with quick presets and editable session label.
- **Stopwatch:** elapsed-time tracking with pause, resume, and laps.

One Timer node owns one active session. Starting another mode ends or resets current active state only after explicit confirmation when elapsed work would be lost.

### Session Controls

- Start, pause, resume, complete, and reset.
- Completion writes immutable history entry.
- Reset clears active state but does not delete history.
- Countdown and Focus derive remaining time from `startedAt`, accumulated elapsed time, and current time instead of relying on an in-memory tick counter.
- Stopwatch uses the same timestamp model and has no planned duration ceiling.

### Focus Workflow

- Default preset: 25-minute focus and 5-minute break.
- Presets: 25/5, 50/10, and custom.
- Cycle target defaults to four.
- Completed focus interval increments cycle count and daily focus totals.
- Break interval is stored as a session segment but excluded from focused-duration totals.

### Distraction Log

- User can add short distraction notes while a session exists.
- Each entry stores stable ID, text, and timestamp.
- Entries remain attached to active session and copied into completed history.

### Stopwatch Laps

- Lap stores stable ID, elapsed duration, and timestamp.
- Laps remain attached to active session and copied into completed history.

### History and Summary

Each completed session stores:

- ID and mode.
- Label.
- Start and completion timestamps.
- Planned and actual duration.
- Completion status.
- Focus/break segment type when relevant.
- Distraction entries.
- Stopwatch laps.

Expanded node shows recent history and daily summary: focused duration, completed sessions, and distraction count. History deletion is out of scope for this phase to avoid accidental data loss.

## Data Model

`TimerPayload` remains persistence boundary and gains a nested `timer` map while preserving compatibility keys:

- `timerSeconds`
- `timerInitialSeconds`

New nested state contains:

- mode and run status.
- current session timestamps and accumulated elapsed seconds.
- planned duration.
- focus/break configuration and cycle state.
- distraction log.
- lap list.
- bounded session history.

Legacy countdown values migrate into Countdown mode. Unknown keys inside `timer` and unrelated node data must survive round trips.

History is bounded to latest 100 sessions inside node payload. This prevents uncontrolled node growth. Larger analytics storage can move to a dedicated repository later.

## Runtime Semantics

- Running elapsed time equals persisted accumulated elapsed duration plus difference between current time and `startedAt`.
- Pausing persists calculated elapsed duration and clears `startedAt`.
- Opening app after planned end marks timer visually expired, but does not auto-complete history without user confirmation.
- UI ticker only triggers repaint; persisted timestamps remain source of truth.
- Payload writes occur on explicit actions and lifecycle-safe state transitions, not every second.

## UI Design

### Expanded Mode

- Header: mode segmented control and compact status badge.
- Hero timer: large monospaced time, progress ring/bar for bounded modes, current session label.
- Primary control row: start/pause/resume, complete, reset.
- Mode settings card.
- Focus cycle indicator when Focus mode is active.
- Distraction input and timestamped log.
- Stopwatch lap action and lap list.
- Daily summary chips.
- Recent session history cards.

Expanded node size follows visible content. Narrow constraints use fallback scrolling to prevent overflow; normal policy size should show primary controls without scrolling.

### Collapsed Mode

- Read-only mode icon, status, formatted time, and bounded-mode progress.
- No mutation controls.
- Running display continues repainting from timestamp state.

### Visual Language

- Graphite/Fuchsia-compatible Material 3 styling.
- Square professional cards with restrained radius, consistent spacing, and no overlapping controls.
- Fuchsia reserved for active state and primary actions; warning/error colors indicate expired or blocked states.

## Persistence Integration

- Existing inline draft pipeline writes `TimerPayload.toData()` into `MindmapNode.data`.
- Existing mindmap mutation flow persists node changes to current local-first database and optional sync layer.
- No new backend service or dependency.
- Existing `onTimerAction` callback remains supported for merge-safe updates.

## Validation

- Durations must be positive and bounded to 24 hours for Focus/Countdown settings.
- Cycle target range: 1-12.
- Distraction text: maximum 160 characters.
- Session label: maximum 80 characters.
- History decoder ignores malformed entries rather than crashing.
- Self-declared elapsed values must be finite non-negative integers.

## Testing

- Domain round-trip and legacy migration.
- Timestamp elapsed calculation across restart.
- Pause/resume/complete/reset transitions.
- Focus cycles, distractions, laps, and history bounding.
- Expanded editor controls emit exact payload changes.
- Collapsed preview remains read-only.
- Dynamic sizing and narrow-layout overflow regression.
- Analyzer and existing Timer compatibility tests.

## Deliberate Limits

- No OS-level background notification or alarm in this phase. Add platform scheduling when timer alerts must fire while app is fully terminated.
- No cloud-specific timer endpoint. Existing node sync carries payload.
- No history editing or deletion. Add dedicated history management when users need long-term reporting.

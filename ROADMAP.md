# Var Roadmap

Var is a local-first life OS / mindmap planner. This roadmap tracks the current working phases after the Calendar routine work completed in Codex.

## Phase 1 - Local-first app foundation

Status: done.

- Adaptive `MaterialApp.router` shell with Calendar as the home surface.
- Local-first mindmap domain model with typed nodes: task, note, journal, kanban, plan, habit, goal, link, and placeholder.
- Sembast local database plus legacy SharedPreferences migration.
- Day mindmap canvas, node editor, command palette, graph, insights, workspaces, settings, backup, and optional sync scaffolding.
- Core test harness for domain, data, application, widget, and app boot flows.

## Phase 2 - Calendar planning foundation

Status: done.

Closeout: `docs/phase_2_closeout.md`.

- Persisted Calendar view modes: Month, Week, Agenda.
- Persisted Agenda filters: All, Tasks, Events, Habits, Done.
- Mode-aware Calendar navigation and Today behavior.
- Agenda grouped day sections, metadata, sorted items, empty/loading/error states, and day/item jump actions.
- Keyboard shortcuts: `M`, `W`, `A`, Agenda filters, focused-day arrows, shortcut help, and Agenda `Shift+Left/Right` rescheduling.
- Rescheduling via Agenda date picker, Month/Week drag-drop, Agenda keyboard move, selected Agenda row state, and snackbar undo.

## Phase 3 - Calendar recurring routine execution

Status: done.

Closeout: `docs/phase_3_closeout.md`.

- Agenda routine banner appears when today has due recurring routines.
- Routine dialog previews ready routines and supports per-routine selection.
- Selection controls: individual checkboxes, `Select all`, and `Clear`.
- Apply creates selected routine nodes for today.
- Skip creates archived skip markers for selected routines.
- Snooze opens a custom date picker and creates archived snooze markers with `automation.snoozedTo`.
- Skip/snooze markers surface in Agenda with `Skipped routine` / `Snoozed routine` badges.
- Agenda adds persisted `Routines` filter. Shortcuts: `1` All, `2` Tasks, `3` Events, `4` Habits, `5` Routines, `6` Done.
- Skip/snooze snackbars support Undo by deleting generated marker nodes and refreshing Calendar/Mindmap state.

## Phase 4 - Routine marker management

Status: next.

Goal: make skip/snooze markers actionable, auditable, and easy to correct after creation.

Planned scope:

- Add routine marker detail actions from Agenda rows.
- Allow deleting skip/snooze markers outside snackbar Undo.
- Add action to open the source routine/template where possible.
- Add action to resnooze a snoozed marker to another date.
- Add action to apply a skipped/snoozed routine immediately.
- Add tests for marker action menus, marker deletion, reapply, and resnooze behavior.
- Update `docs/phase_3_closeout.md`, `docs/release/beta_release_checklist.md`, and `CLAUDE.md` after implementation.

## Phase 5 - Beta release hardening

Status: planned.

- Run full release preflight from `docs/release/beta_release_checklist.md`.
- Keep `README.md`, closeout docs, and this roadmap aligned.
- Verify local-only beta path, demo seed path, and optional sync endpoint path.
- Add/refresh docs for known caveats and release blockers.
- Run full `flutter test`, `flutter analyze`, and web release build before sharing beta.

## Phase 6 - Accessibility and performance

Status: planned.

- Keyboard/focus traversal audit across Calendar, Agenda, Day mindmap, dialogs, and command palette.
- Screen-reader labels for routine actions, drag/drop, shortcut help, and node editor flows.
- Contrast/visual density pass for dark-first UI.
- Performance pass for dense calendars, large mindmaps, graph rendering, and Sembast hotspots.
- Add targeted regression tests or benchmarks where practical.

## Phase 7 - Sync productization

Status: planned.

- Harden HTTP backend contract and auth flows.
- Add conflict review UX where automatic merge is insufficient.
- Add sync diagnostics and restore-point recovery flows.
- Document production deployment, backup, recovery, and support operations.

## Current validation snapshot

Latest focused validation after Phase 3 routine work:

```bash
flutter test test/features/calendar/calendar_page_test.dart
flutter analyze
```

Result:

- Calendar test suite: pass, 27 tests.
- Analyzer: no issues found.

Before release or cross-agent handoff, also run:

```bash
flutter test
```


# Var Roadmap

Var is moving from prototype foundation into beta hardening. This document tracks the practical phase boundary for the current working tree.

## Phase 0 — Bootstrap & branding

Status: done.

- Flutter package renamed to Var.
- Basic Material app bootstrapped.
- Initial repository and test harness established.

## Phase 1 — App foundation and local-first surfaces

Status: done.

- `MaterialApp.router` shell with adaptive navigation.
- Calendar home and day routes.
- Mindmap node model with typed task, note, journal, kanban, plan, habit, goal, link, and placeholder nodes.
- Sembast local database with legacy SharedPreferences migration.
- Day mindmap canvas, node editor, command palette, graph, insights, workspaces, settings.
- Portable encrypted backups and optional HTTP sync adapters.

## Phase 2 — Stabilization & release gate

Status: done.

- Documentation aligned with the implemented Sembast/HTTP architecture.
- Demo seed data gated behind explicit runtime config.
- CI added for format, analyzer, and tests.
- Repeatable verification checklist established before feature expansion.

## Phase 3 — Local-first productivity depth

Status: done.

- Daily timeline, smart node views, relations, graph exploration, and workspace context flows expanded.
- Node progress models cover tasks, habits, goals, plans, and kanban boards.
- Automation suggestions and recurring routine application added.
- Sync, backup, restore point, activity, auth, and device identity domain/application/data layers covered by tests.

## Phase 4 — Sync foundation

Status: done; productization remains planned.

- Optional HTTP adapters wired behind `VAR_SYNC_ENDPOINT`.
- Local/in-memory fallbacks retained for offline-first usage and tests.
- Portable backup codec and restore-point services covered by automated tests.
- Full backend contract, auth UX, conflict review, and diagnostics are deferred to Phase 8.

## Phase 5 — UX polish, onboarding, platform readiness

Status: done.

- Onboarding overlay, providers, and widget tests added.
- Calendar onboarding entry point wired.
- Empty states added for workspaces and graph.
- Platform window/app titles normalized to `Var` where source metadata is available.
- Verification snapshot: `dart format` pass, `flutter analyze` pass with 7 info, `flutter test` 308/308 pass.
- App icon and splash are still deferred until a final design asset exists.

## Phase 6 — Beta release hardening

Status: current phase.

- Keep roadmap and README aligned with beta readiness.
- Add a beta release checklist for automated preflight, manual smoke, platform sanity, and known blockers.
- Extend CI with a web release smoke build using safe local-only defaults.
- Add platform metadata regression tests so app title/name stays `Var` across supported targets.
- Calendar home now supports persisted Month, Week, and Agenda views.
- Agenda supports persisted filters for all nodes, tasks, calendar payloads, habits, and done items.
- Calendar keyboard shortcuts cover view switching (`M`, `W`, `A`) and agenda filters (`1`–`5`).
- Week and Agenda views have responsive mobile/desktop behavior and tested empty/loading/error states.
- Calendar rescheduling is wired across Agenda date picker, Month/Week drag-drop, and Agenda keyboard shortcuts with undo.

## Phase 7 — Accessibility and performance

Status: planned.

- Accessibility audit for keyboard navigation, focus traversal, contrast, and screen-reader labels.
- Performance pass for dense calendars, large mindmaps, persistence hotspots, and graph rendering.
- Add targeted regression tests or benchmarks where practical.

## Phase 8 — Sync productization

Status: planned.

- Harden HTTP backend contract and auth flows.
- Add conflict review UX where automatic merge is insufficient.
- Add sync diagnostics and restore-point recovery flows.
- Document production deployment and recovery operations.

# Var

**Var** is a calendar-centric productivity app built with Flutter. Time is the
center of everything: the main screen is a calendar, and every day is an open
canvas. Each day cell opens a **mindmap** where you can drop tasks, kanban
boards, plans (itinerary, workout, work), notes, habits, and goals — all as
nodes you can connect, even across days.

> Every day is a variable. Make it count.

## Concept

```
Calendar (when)  →  Day cell (summary)  →  Mindmap (anything)
```

- **Calendar is the home.** Month, Week, and Agenda views are persisted per
  user. Month cells show density dots by node type; hover / long-press previews
  the day, click opens its mindmap.
- **Mindmap is a universal canvas per day.** Anything you create is a typed
  node: Task, Kanban, Plan, Note, Habit, Goal, and cross-day links.
- **Floating index menu** lists every node globally; click one to jump and
  highlight the day it was created.
- **Agenda filters and shortcuts** keep navigation fast: `M`, `W`, `A` switch
  calendar views, and `1`–`5` switch Agenda filters.
- **Calendar affordances** highlight the focused day, expose date-picker access
  from the header, offer Agenda CTAs to open the target day quickly, and support
  rescheduling nodes from Agenda, Month, and Week surfaces with undo.
- **Local-first + optional HTTP sync/backup** so it works fully offline, with
  sync adapters layered behind runtime configuration.

## Status

Under active development. Built phase by phase — see [ROADMAP.md](ROADMAP.md).
The current phase focuses on stabilization, CI, and release-readiness for the
local-first app foundation.

## Getting Started

```bash
flutter pub get
flutter run
```

Enable optional HTTP sync by passing a runtime endpoint:

```bash
flutter run --dart-define=VAR_SYNC_ENDPOINT=https://sync.example.test
```

Enable demo seed data explicitly for development:

```bash
flutter run --dart-define=VAR_DEMO_SEED=true
```

Without these flags, the app uses local/offline fallbacks and starts without
seeding demo nodes into a fresh database.

This project is a multi-platform Flutter application (Android, iOS, macOS,
Windows, Linux, Web).

## Beta verification

Before sharing a beta build, run the automated preflight and manual smoke flow in
[docs/release/beta_release_checklist.md](docs/release/beta_release_checklist.md).
The checklist covers the local-only default path first, then optional demo seed
and sync endpoint paths.

## Tech

- **Flutter** + **Dart**
- **Riverpod** (state), **go_router** (routing)
- **Sembast** (local-first DB), **shared_preferences** (prefs/bootstrap)
- **HTTP sync adapters** behind `VAR_SYNC_ENDPOINT`; local fallbacks otherwise
- Custom mindmap canvas (`InteractiveViewer`)

## License

Proprietary. All rights reserved.


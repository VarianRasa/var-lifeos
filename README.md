# Var

[![Web App](https://img.shields.io/badge/Web-var--lifeos.web.app-039BE5?logo=firebase)](https://var-lifeos.web.app)

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

## Use Var

- **Landing page:** [var-lifeos.web.app](https://var-lifeos.web.app)
- **Web app:** [var-lifeos.web.app/app/](https://var-lifeos.web.app/app/)
- **Windows and Android:** download latest files from [GitHub Releases](https://github.com/VarianRasa/var-lifeos/releases/latest).
- **iOS:** no public build yet. Apple builds require macOS, Xcode, signing, and App Store/TestFlight distribution.

Windows packages are portable ZIP files. Extract the full folder, then run
`var_app.exe`. Android packages are APK files; Android may ask permission to
install apps from the browser or file manager used to open the APK.

## Status

Public beta. Data is local-first, so keep backups before testing sync or restore
flows with important data.

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

Firebase platform configuration is intentionally excluded from source control.
Contributors need their own Firebase project and generated platform config.

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

Proprietary. See [LICENSE](LICENSE). Source visibility does not grant permission
to use, copy, modify, or redistribute the software.


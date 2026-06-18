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

- **Calendar is the home.** Each cell shows density dots by node type; hover /
  long-press previews the day, click opens its mindmap.
- **Mindmap is a universal canvas per day.** Anything you create is a typed
  node: Task, Kanban, Plan, Note, Habit, Goal, and cross-day links.
- **Floating index menu** lists every node globally; click one to jump and
  highlight the day it was created.
- **Local-first + cloud sync** (Firebase) so it works fully offline and syncs
  across devices.

## Status

Under active development. Built phase by phase — see the project roadmap.

## Getting Started

```bash
flutter pub get
flutter run
```

This project is a multi-platform Flutter application (Android, iOS, macOS,
Windows, Linux, Web).

## Tech

- **Flutter** + **Dart**
- **Riverpod** (state), **go_router** (routing)
- **Isar** (local-first DB), **Firebase** (sync & auth)
- Custom mindmap canvas (`InteractiveViewer`)

## License

Proprietary. All rights reserved.

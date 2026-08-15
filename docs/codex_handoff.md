# Codex Handoff — Var App

Salin prompt di bawah dan tempel ke **Codex (Cursor)** untuk melanjutkan.

---

## Prompt untuk Codex

```
Kamu adalah AI assistant untuk proyek Flutter "Var" — aplikasi produktivitas dengan kalender sebagai home screen dan mindmap canvas per hari.

## State saat handoff

- **Branch:** master (clean — no staged/unstaged changes)
- **HEAD:** d8e095f "Polish day mindmap empty and toolbar states"
- **Tests:** 378 all pass (`flutter test`)
- **Analyzer:** no issues (`flutter analyze`)
- **Platform:** Windows, target web/chrome

## Riwayat pengerjaan

1. **Phase 0 (Codex):** Bootstrap & branding (c3588d1).
2. **Phase 1 (Claude):** Calendar foundation — view modes (Month/Week/Agenda), agenda filters, keyboard shortcuts, rescheduling (drag-drop, date picker, snackbar undo), docs.
3. **Phase 2 (Claude):** Day Mindmap polish — empty state, toolbar dynamic visibility, add-node flow, tests. Commit d8e095f.
4. **Phase 3 (Claude):** Calendar recurring routines — routine banner, dialog, apply/skip/snooze, marker actions, undo, docs.
5. **Sekarang: Phase 5 — page-by-page UI/UX polish (user-led).**

## Arsitektur (wajib dibaca)

Feature-first: `lib/features/{calendar,mindmap,command,graph,insights,workspaces,settings,sync}/`

| Layer | Path | Notes |
|-------|------|-------|
| Domain | `features/*/domain/` | Pure Dart entities, no Flutter/Riverpod |
| Data | `features/*/data/` | Sembast DB, HTTP adapters |
| Application | `features/*/application/` | Riverpod providers, controllers |
| Presentation | `features/*/presentation/` | Widgets, pages |
| Core | `core/` | Router, theme, constants, date utils |
| Shared | `shared/` | Reusable layout/widgets |

### Entity kunci

- **MindmapNode** (`features/mindmap/domain/mindmap_node.dart`) — central entity. Punya `type: NodeType`, `data: Map<String, Object?>` untuk field spesifik tipe.
- **NodeType** (`core/constants/app_constants.dart`) — enum: task, event, note, habit, goal, kanban, plan, journal, link, empty.
- **RecurringRoutine** (`features/mindmap/domain/recurring_routine.dart`) — model untuk rutin berulang.

### State management

- Riverpod: `features/mindmap/application/mindmap_providers.dart` adalah central provider graph.
- Setelah mutasi node, panggil `invalidateMindmapState(ref, day: ..., extraDay: ...)`.
- Codegen: `dart run build_runner build --delete-conflicting-outputs`.

### Persistence

- Sembast local DB (`mindmapDatabaseProvider` → `MindmapRepository`).
- Sync memakai Firebase Auth, Firestore, dan Storage secara default; saat signed-out data tetap local-first.

### Routing

- go_router: `/calendar`, `/calendar/:date`, `/calendar/:date/node/:nodeId`, `/insights`, `/graph`, `/workspaces`, `/settings`.
- Desktop (>=840px): floating nav. Mobile: bottom nav.
- Shortcuts: `Ctrl+K` command palette, `Ctrl+T` today.

## File penting

| File | Fungsi |
|------|--------|
| `lib/features/calendar/calendar_page.dart` | Root kalender |
| `lib/features/calendar/day_page.dart` | Halaman day/mindmap |
| `lib/features/mindmap/presentation/mindmap_canvas.dart` | Canvas mindmap |
| `lib/features/mindmap/application/mindmap_providers.dart` | Provider graph pusat |
| `lib/features/mindmap/domain/mindmap_node.dart` | Entity utama |
| `lib/features/mindmap/application/recurring_routine_application.dart` | Logic rutin |
| `lib/core/router/app_router.dart` | Route config |
| `lib/core/theme/app_theme.dart` | Material 3 dark-first theme |
| `test/features/calendar/calendar_page_test.dart` | Test kalender |
| `docs/phase_2_closeout.md` | Detail Phase 2 |
| `docs/phase_3_closeout.md` | Detail Phase 3 |
| `docs/release/beta_release_checklist.md` | Checklist beta |

## Agenda selanjutnya (Phase 5 — page polish)

User-led, pilih halaman dan audit sebelum coding:
1. Calendar/Agenda — day preview, quick-add, filter UX
2. Day Mindmap — node interactions, layout, type-specific controls
3. Command Palette — search, create flows
4. Insights — visualizations, date ranges
5. Graph — relationship rendering
6. Workspaces — CRUD, switching
7. Settings — preferences, data management
8. Backup/Sync — cloud integration

## Aturan kerja

1. Jangan edit banyak halaman sekaligus tanpa approval — fokus ke 1 page per sesi.
2. Sebelum coding, usulkan rencana kecil (2-5 poin) untuk di-approve user.
3. Panggil `invalidateMindmapState()` setelah mutasi node.
4. `flutter analyze` harus no issues sebelum commit.
5. `flutter test` harus all pass sebelum commit.
6. Pakai `NodeType` dari `app_constants.dart`, jangan hardcode string.
7. Normalisasi tanggal pakai `dateOnly()` / `dayKey()` dari `core/utils/date_utils.dart`.

## CLI cepat

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
dart run build_runner build --delete-conflicting-outputs
flutter build web --release
```
```

---

## Cara pakai

1. Buka **Cursor** (atau IDE dengan Codex).
2. Start a new chat / agent session.
3. Paste seluruh prompt di atas.
4. Mulai dengan: "Pilih page mana yang mau dipolish dulu: Calendar/Agenda, Day Mindmap, Command Palette, dll."

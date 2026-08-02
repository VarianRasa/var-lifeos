# AGENTS.md

## Project

Var is a Flutter productivity app. Calendar is home; each day opens a mindmap canvas for typed nodes: tasks, kanban, plans, notes, journals, habits, goals, links, and placeholders. App is local-first with optional sync/backup.

Platforms: Android, iOS, macOS, Windows, Linux, Web. Package: `var_app`. Dart SDK: `^3.11.4`.

## Main directories

- `lib/main.dart`: app bootstrap, Firebase init only on Web/Android/iOS/macOS, web context menu disable.
- `lib/app.dart`: `MaterialApp.router`, theme providers, router config.
- `lib/core/`: runtime config, constants, router, theme, date utilities.
- `lib/features/`: feature modules: calendar, command, graph, insights, mindmap, onboarding, settings, sync, workspace.
- `lib/shared/`: reusable layout/widgets.
- `lib/dataconnect_generated/`: generated, do not hand-edit.
- `test/`: Flutter/widget/unit tests, usually mirrors `lib/features/...`.
- `docs/release/beta_release_checklist.md`: required beta preflight + manual smoke list.

## Commands

```bash
flutter pub get
flutter run
flutter run -d chrome
flutter run -d chrome --dart-define=VAR_DEMO_SEED=false

dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter test test/features/calendar/day_page_test.dart
flutter test --name "goalMilestones returns trimmed milestones"

flutter build web --release --dart-define=VAR_DEMO_SEED=false
flutter build apk
flutter build windows

dart run build_runner build --delete-conflicting-outputs
```

Use build_runner only when adding/changing Riverpod generated annotations.

## Runtime flags

Defined in `lib/core/config/runtime_config.dart`:

- `VAR_DEMO_SEED`: truthy values are `1`, `true`, `yes`, `on`; absent/false means no demo nodes in fresh DB.

## Architecture rules

Feature-first layers where present:

- `domain/`: pure Dart entities/value objects/algorithms. No Flutter or Riverpod imports.
- `data/`: persistence, HTTP, Sembast/shared_preferences adapters.
- `application/`: Riverpod providers/controllers/orchestration.
- `presentation/`: widgets/pages/dialogs.

Mindmap gotchas:

- `NodeType` lives in `lib/core/constants/app_constants.dart`.
- `MindmapNode` central entity lives in `lib/features/mindmap/domain/mindmap_node.dart`; type-specific fields go in `data: Map<String, Object?>`.
- Normalize dates with `dateOnly`/`dayKey()` from `lib/core/utils/date_utils.dart`; keep comparisons local-day based.
- After node mutations, invalidate via `invalidateMindmapState(ref, day: ..., extraDay: ...)` or `invalidateMindmapStateFromRef(...)` so derived providers refresh.

Sync gotchas:

- Sync domain/planning lives in `lib/features/sync/domain/`.
- `sync_providers.dart` uses Firebase Auth, Firestore, and eligible Firebase Storage by default; signed-out use stays local-first.
- Portable backups use `cryptography`; avoid data-loss changes without tests.

## Style and tests

- Analyzer uses strict casts/inference/raw-types. Lints include `always_declare_return_types`, `avoid_dynamic_calls`, `prefer_single_quotes`, `require_trailing_commas`, `unawaited_futures`, `directives_ordering`, and `sort_child_properties_last`.
- `avoid_print` is warning; prefer existing logging/status patterns.
- Keep Material 3 dark-first visual style; color tokens in `lib/core/theme/app_colors.dart`, theme in `lib/core/theme/app_theme.dart`.
- Widget/app tests wrap in `ProviderScope`; override providers for in-memory data.
- Sembast tests use `databaseFactoryMemory`; call `disableSembastCooperator()` when scheduling gets flaky.
- Shared preferences tests use `InMemorySharedPreferencesAsync.empty()`.

## Before release/beta changes

Run preflight from `docs/release/beta_release_checklist.md`:

```bash
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release --dart-define=VAR_DEMO_SEED=false
```

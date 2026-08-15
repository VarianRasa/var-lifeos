# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Var** is a Flutter productivity app where the calendar is the home screen and each day opens a mindmap canvas for typed nodes: tasks, kanban boards, plans, notes, journals, habits, goals, links, and empty placeholders. It is local-first, with sync/backup abstractions layered on top.

- Package: `var_app`
- Dart SDK: `^3.11.4`
- Platforms: Android, iOS, macOS, Windows, Linux, Web
- Core deps: Flutter, Riverpod, go_router, Sembast, shared_preferences, http, cryptography

## Commands

```bash
# Install deps
flutter pub get

# Run app
flutter run
flutter run -d chrome
flutter run -d chrome --dart-define=VAR_DEMO_SEED=false
flutter run -d chrome --dart-define=VAR_DEMO_SEED=true

# Format + analyze/lint
dart format --set-exit-if-changed .
flutter analyze

# Test
flutter test
flutter test test/features/mindmap/domain/mindmap_node_test.dart
flutter test --name "goalMilestones returns trimmed milestones"

# Build common targets
flutter build web
flutter build web --release --dart-define=VAR_DEMO_SEED=false
flutter build apk
flutter build windows

# Riverpod codegen, when adding @riverpod annotations
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch --delete-conflicting-outputs

# Dependency maintenance
flutter pub outdated
flutter pub upgrade --major-versions
```

Runtime flags are parsed in `lib/core/config/runtime_config.dart`:

- `VAR_DEMO_SEED`: accepts `1`, `true`, `yes`, or `on`; without it, fresh local DBs start without demo seed nodes.

Before sharing a beta build, follow `docs/release/beta_release_checklist.md`. Its automated preflight is `flutter pub get`, `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`, and `flutter build web --release --dart-define=VAR_DEMO_SEED=false`.

## Architecture

### App composition

- Entry point: `lib/main.dart` initializes Flutter, then wraps `VarApp` in `ProviderScope`.
- `lib/app.dart` builds `MaterialApp.router`, watches theme providers, and wires `appRouterProvider`.
- `lib/core/router/app_router.dart` owns `go_router` config. Routes are flat and URL-friendly: `/calendar`, `/calendar/:date`, `/calendar/:date/node/:nodeId`, `/insights`, `/graph`, `/workspaces`, `/workspaces/:type/:name`, `/settings`. Day routes support `?highlight=<nodeId>`.
- `lib/shared/layout/adaptive_scaffold.dart` wraps top-level routes. Desktop (>= 840px) uses floating nav + command/focus buttons; mobile uses bottom nav. Global shortcuts include `Ctrl+K` command palette and `Ctrl+T` today.

### Feature-first layout

```text
lib/
├── core/        # constants, runtime config, router, theme, date utilities
├── features/    # calendar, command, graph, insights, mindmap, settings, sync, workspace
├── shared/      # reusable layout/widgets
├── app.dart
└── main.dart
```

Feature modules follow layered boundaries where practical:

- `domain/`: pure Dart entities/value objects/algorithms. No Flutter/Riverpod imports.
- `data/`: persistence, HTTP, Sembast/shared_preferences adapters.
- `application/`: Riverpod providers, controllers, orchestration services.
- `presentation/`: widgets/pages/dialogs.

### Mindmap data model

- `NodeType` lives in `lib/core/constants/app_constants.dart`.
- `MindmapNode` is the central entity in `features/mindmap/domain/mindmap_node.dart`. It stores common fields plus type-specific `data: Map<String, Object?>`.
- Dates are normalized via `dateOnly`/`dayKey()` in `core/utils/date_utils.dart`; keep comparisons and keys local-day based.
- Node progress models are split by type (kanban board, plan progress, task checklist, habit completion, goal progress).
- Cross-node relationships use `relatedNodeIds`; graph derivation lives in `NodeGraph` and `NodeGraphExplorer`.

### Local persistence

- `mindmapDatabaseProvider` opens a platform-specific Sembast database through `mindmap_database_opener*` files.
- `mindmapNodeDatabaseProvider` wraps Sembast access.
- `mindmapRepositoryProvider` exposes `MindmapRepository`, currently backed by `LocalDatabaseMindmapRepository`.
- `SharedPreferencesMindmapNodeStore` is legacy storage used during local DB initialization/migration.
- Seed data comes from `buildSeedMindmapNodes()` only when `VAR_DEMO_SEED` is enabled.

### Riverpod state graph

`features/mindmap/application/mindmap_providers.dart` is the central provider graph:

- `nodesForDayProvider(day)` and `allMindmapNodesProvider` read repository data.
- Derived providers compute day summaries, smart views, life OS summary, insights, automation suggestions, workspace contexts, relations, and graph.
- After any node mutation, call `invalidateMindmapState(ref, day: ..., extraDay: ...)` or `invalidateMindmapStateFromRef(...)` so the full derived graph refreshes consistently.

### Sync/backup

- Sync domain models/planning live in `features/sync/domain/`.
- `MindmapSyncPlanner` performs merge/planning logic.
- `CloudSyncService`, `MindmapBackupService`, `PortableMindmapBackupCodec`, and `SyncController` orchestrate sync, backup export/import, restore points, activity, auth, and device identity.
- `sync_providers.dart` uses Firebase Auth, Firestore, and eligible Firebase Storage by default; signed-out use remains local-first.
- Portable backups are encrypted via `cryptography`.

### Command palette and automation

- `features/command/global_command_palette.dart` implements the global palette.
- Parsing is split into `command_date_parser.dart`, `quick_create_command_parser.dart`, and `command_node_query.dart`.
- Recurring routines/automation are modeled in mindmap domain files and applied through `recurring_routine_application.dart`.

### Theme/design

- Material 3 theme lives in `core/theme/app_theme.dart` and color tokens in `core/theme/app_colors.dart`.
- Dark-first styling uses dense typography and per-node-type accent colors.
- Theme mode/accent preference is persisted via `theme_controller.dart` using `SharedPreferencesAsync`.

## Testing

- Test framework: `flutter_test`.
- Sembast tests use `databaseFactoryMemory`; call `disableSembastCooperator()` where async scheduling would make tests flaky.
- Shared preferences tests set `SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty()`.
- Widget/app tests wrap widgets in `ProviderScope` and override providers such as `mindmapNodeDatabaseProvider` with an in-memory `SembastMindmapNodeDatabase`.
- Domain tests are pure Dart-style unit tests; data/application/presentation tests live under matching `test/features/...` paths.

## Code quality

`analysis_options.yaml` enables strict Dart analyzer modes:

- `strict-casts`, `strict-inference`, `strict-raw-types`
- generated files excluded: `*.g.dart`, `*.freezed.dart`, generated plugin registrants
- notable lints: `always_declare_return_types`, `avoid_dynamic_calls`, `prefer_single_quotes`, `require_trailing_commas`, `unawaited_futures`, `use_key_in_widget_constructors`, `directives_ordering`, `sort_child_properties_last`, `cancel_subscriptions`, `close_sinks`
- `avoid_print` is a warning; prefer a logging approach

## Notes for future agents

- Current code and `pubspec.yaml` use Sembast plus optional HTTP sync adapters.
- No Cursor rules or GitHub Copilot instruction file were present when this file was generated.

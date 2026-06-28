# Beta Release Checklist

Use this checklist before sharing a beta build of Var. It verifies the local-first default path first, then optional sync behavior when an endpoint is available.

## Automated preflight

Run from the repository root:

```bash
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release --dart-define=VAR_DEMO_SEED=false
```

Expected result:

- Dependencies resolve without lockfile drift.
- Formatting is clean.
- Analyzer has no errors; known info-level lint output is acceptable only when already tracked.
- All tests pass.
- Web release build succeeds without demo seed data or a sync endpoint.

## Manual smoke: local-only beta path

Run without sync or demo seed data:

```bash
flutter run -d chrome --dart-define=VAR_DEMO_SEED=false
```

Check:

- App cold-boots to the calendar without seeding demo content.
- Onboarding appears for a fresh profile and can be dismissed.
- Calendar navigation opens today and another day.
- Calendar switches between Month, Week, and Agenda; the chosen view persists after reload.
- Week view is usable on desktop and narrow/mobile widths.
- Focused/selected day remains visually obvious while using keyboard arrows.
- Header date/range title exposes date picker affordance.
- Agenda filters (All, Tasks, Events, Habits, Done) show the expected nodes and persist after reload.
- Agenda empty state and group header CTAs open the intended day.
- Calendar shortcuts work: `M`, `W`, `A` switch views and `1`-`5` switch Agenda filters.
- Calendar shortcut help opens from the keyboard icon and lists all view/filter shortcuts.
- Agenda item move-to-date, Month/Week drag-drop rescheduling, `Shift+Left/Right` Agenda rescheduling, and snackbar undo work.
- A day mindmap can create, edit, and delete a node.
- Command palette opens with `Ctrl+K` and can search/create expected node actions.
- Graph, insights, and workspaces render sensible empty states when there is no data.
- Settings open and theme/accent preferences persist after reload.
- Backup export creates a portable backup.
- Backup import/restore loads the expected nodes in a fresh profile.
- Sync-disabled state is clear and does not block local usage.

## Optional smoke: demo seed path

Run with explicit seed data:

```bash
flutter run -d chrome --dart-define=VAR_DEMO_SEED=true
```

Check:

- Demo nodes appear only when the flag is set.
- Calendar density, Month/Week/Agenda views, day summary, mindmap nodes, graph, insights, and workspace surfaces all render seeded data.

## Optional smoke: sync endpoint path

Run only when a test endpoint is available:

```bash
flutter run -d chrome --dart-define=VAR_SYNC_ENDPOINT=https://sync.example.test
```

Check:

- Sync UI detects that sync is enabled.
- Auth/setup flow handles valid and invalid credentials without losing local data.
- Sync activity and restore-point flows show clear status.
- App remains usable when the endpoint is unavailable or returns an error.

## Platform sanity

Before platform-specific beta distribution, confirm visible metadata:

- App title/name is `Var` on Web, Android, iOS, macOS, Windows, and Linux.
- Web manifest uses `name` and `short_name` as `Var`.
- Runtime title bars show `Var` on desktop targets.
- Package IDs/bundle IDs still use the chosen beta namespace.

## Known blockers before public release

- App icon and splash screen need a final design asset.
- Store signing, installer packaging, and store metadata are not finalized.
- Production sync backend contract, auth UX, conflict review, and diagnostics are still planned work.
- Full accessibility audit is pending.
- Large-data performance optimization is pending.



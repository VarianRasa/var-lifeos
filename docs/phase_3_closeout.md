# Phase 3 Closeout

Phase 3 focused on turning Calendar into a routine execution surface: users can preview due recurring routines from Agenda, apply them, defer them, and audit the resulting markers without leaving Calendar.

## Completed scope

- Routine preview: Agenda shows a banner when today has due recurring routines.
- Routine dialog: Apply action opens a selectable confirmation dialog with the ready routine count and preview names.
- Routine selection: Users can select individual routines, clear the selection, or select all.
- Routine apply: Confirming creates the selected due routine nodes for today and refreshes Calendar state.
- Routine skip: Users can mark selected routines as skipped for today from the same dialog.
- Routine snooze: Users can snooze selected routines to a custom date from the same dialog.
- Undo support: Skip and snooze snackbars expose Undo, deleting the generated marker nodes and restoring the Agenda banner.
- Agenda surfacing: archived skip/snooze automation markers are visible in Agenda with `Skipped routine` / `Snoozed routine` badges.
- Agenda filters: added persisted `Routines` filter, with keyboard shortcut `5`; `Done` moved to `6`.
- Shortcut help: Calendar shortcut dialog lists the updated filter shortcuts.
- Tests: Calendar widget coverage added for apply, preview dialog, partial selection, select all/clear, skip, custom-date snooze, undo, routine badges, and the Routines filter.

## Validation snapshot

Last verified from repo root:

```bash
flutter analyze
flutter test
```

Result:

- `flutter analyze`: no issues found.
- `flutter test`: all tests passed, 358 total.

## Commit snapshot

- `01f7c98 Add calendar recurring routine actions`
- `0241dae Add calendar routine selection controls`
- `23e17f2 Add calendar routine snooze date picker`

## Known caveats

- Routine actions support per-routine selection, but not persisted selection presets.
- Snooze supports a custom date, but not a custom time.
- Skip/snooze markers are archived but intentionally surfaced in Agenda when they contain routine automation state.
- Calendar routine execution is local-first and depends on existing routine definitions from mindmap automation data.

## Suggested next phase

- Add routine marker detail actions for undo/delete/open-source routine.
- Expand release smoke checks around routine execution, filters, and keyboard shortcuts.

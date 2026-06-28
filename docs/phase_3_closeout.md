# Phase 3 Closeout

Phase 3 focused on turning Calendar into a routine execution surface: users can preview due recurring routines from Agenda, apply them, defer them, and audit the resulting markers without leaving Calendar.

## Completed scope

- Routine preview: Agenda shows a banner when today has due recurring routines.
- Routine dialog: Apply action opens a confirmation dialog with the ready routine count and preview names.
- Routine apply: Confirming creates the due routine nodes for today and refreshes Calendar state.
- Routine skip: Users can mark all ready routines as skipped for today from the same dialog.
- Routine snooze: Users can snooze ready routines to tomorrow from the same dialog.
- Undo support: Skip and snooze snackbars expose Undo, deleting the generated marker nodes and restoring the Agenda banner.
- Agenda surfacing: archived skip/snooze automation markers are visible in Agenda with `Skipped routine` / `Snoozed routine` badges.
- Agenda filters: added persisted `Routines` filter, with keyboard shortcut `5`; `Done` moved to `6`.
- Shortcut help: Calendar shortcut dialog lists the updated filter shortcuts.
- Tests: Calendar widget coverage added for apply, preview dialog, skip, snooze, undo, routine badges, and the Routines filter.

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

## Known caveats

- Routine actions currently apply to all ready routines in the day banner; per-routine selection is not implemented yet.
- Snooze currently targets tomorrow only; custom snooze date/time is not implemented yet.
- Skip/snooze markers are archived but intentionally surfaced in Agenda when they contain routine automation state.
- Calendar routine execution is local-first and depends on existing routine definitions from mindmap automation data.

## Suggested next phase

- Add per-routine selection in the Calendar routine dialog.
- Add custom snooze date picker.
- Add routine marker detail actions for undo/delete/open-source routine.
- Expand release smoke checks around routine execution, filters, and keyboard shortcuts.

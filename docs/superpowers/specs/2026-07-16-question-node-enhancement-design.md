# Question Node Enhancement Design

## Goal

Turn Question nodes into structured research and answer-tracking cards while preserving existing Question data.

## Scope

- Add structured question, context, possible answers, sources, next research action, and confidence fields.
- Keep existing investigation status, accepted answer, and evidence fields.
- Support manual lifecycle with non-destructive status suggestions.
- Provide editable possible-answer and source lists.
- Add research progress and a useful collapsed preview.
- Reuse existing node tags and relations.

## Data Model

Extend `QuestionPayload` using flat keys:

- Existing `investigationStatus`: `open`, `researching`, `answered`, or `blocked`.
- Existing `answer`: accepted answer.
- Existing `evidence`: evidence summary.
- New `questionText`: full question.
- New `questionContext`: background and constraints.
- New `possibleAnswers`: list of candidate answers.
- New `questionSources`: list of source URLs or references.
- New `nextResearchAction`: next investigation step.
- New `questionConfidence`: integer percentage from 0 through 100.

`toData` preserves unknown root keys. Missing fields use safe defaults, so no database migration is required.

## Hybrid Status Guidance

Status remains user-controlled. UI may suggest one status:

- Accepted answer present: suggest `answered`.
- Possible answers, evidence, sources, or next research action present: suggest `researching`.
- Otherwise: suggest `open`.
- `blocked` is never suggested automatically.

Suggestion changes no saved status until the user presses **Apply**.

## Editor

Question editor contains:

1. Status choice chips.
2. Status suggestion banner when suggested status differs from saved status.
3. Research progress indicator.
4. Full question multiline field.
5. Context multiline field.
6. Possible-answer list with add, edit, and delete actions.
7. Accepted-answer multiline field.
8. Evidence multiline field.
9. Source list with add, edit, and delete actions.
10. Next research action multiline field.
11. Continuous confidence slider.

Text controllers and focus nodes remain stable across local draft echoes so typing and slider gestures are not interrupted.

## Research Progress

Progress uses four equal checkpoints:

- Question present.
- At least one possible answer present.
- Evidence or source present.
- Accepted answer present.

Displayed progress is `0/4` through `4/4` with matching linear progress.

## Collapsed Preview

Collapsed Question node displays:

- Status badge.
- Confidence when greater than zero.
- Research progress.
- Question preview limited to two lines.
- Up to two possible answers.
- Accepted answer when present; otherwise next research action.

If structured fields are empty, preview falls back to existing body content and legacy answer/evidence values. Collapse mode retains manual resizing.

## Validation

- Title remains required.
- Status must use a supported value.
- Confidence must be between 0 and 100.
- Empty list entries are removed during normalization.
- Source references remain plain strings; URL-only validation is not required because references may be non-URL citations.

## Compatibility

- Existing `investigationStatus`, `answer`, and `evidence` keys remain authoritative.
- Existing generic Content Markdown remains unchanged.
- No generated code or database migration is required.
- Existing tags, relations, status, review state, and resize metadata remain unchanged.

## Tests

- Payload round-trip preserves new fields and unknown keys.
- Progress and suggested status remain deterministic and non-destructive.
- Confidence validation rejects out-of-range values.
- Editor typing and confidence drag survive reconstructed payload echoes.
- Possible answers and sources support add, edit, and delete.
- External draft changes still synchronize safely.
- Collapsed preview renders structured content without overflow.
- Legacy Question nodes still render and edit.

## Out of Scope

- Automatic status mutation.
- Web fetching or source verification.
- AI-generated answers.
- Research history or answer versioning.
- New global filters or analytics screens.

# Idea Node Enhancement Design

## Goal

Turn Idea nodes from generic text cards into structured incubation and experiment cards while preserving existing data.

## Scope

- Add structured fields for hypothesis, impact, effort, confidence, evidence, and next experiment.
- Keep manual lifecycle stages: `spark`, `exploring`, `validated`, and `archived`.
- Show non-destructive stage suggestions based on completed fields.
- Show validation progress derived from hypothesis, evidence, and next experiment.
- Polish collapsed cards with stage, impact, effort, hypothesis preview, progress, and next experiment.
- Reuse existing node tags and relations.

## Data Model

Extend `IdeaPayload` flat keys to avoid migration:

- Existing `maturity` stores lifecycle stage.
- Existing `evidence` remains evidence text.
- Existing `nextAction` stores next experiment for backward compatibility.
- New `hypothesis` stores testable idea statement.
- New `impact` stores `low`, `medium`, or `high`.
- New `effort` stores `low`, `medium`, or `high`.
- New `confidence` stores integer percentage from 0 through 100.

Unknown root data keys remain preserved by `toData`.

## Hybrid Stage Guidance

Stage remains user-controlled. UI may display one suggestion:

- Empty hypothesis: suggest `spark`.
- Hypothesis present without evidence: suggest `exploring`.
- Hypothesis and evidence present: suggest `validated`.
- `archived` is never suggested automatically.

Suggestion changes no saved data until user selects it.

## Editor

Idea editor contains:

1. Lifecycle segmented control.
2. Hypothesis multiline field.
3. Impact and effort selectors.
4. Confidence percentage selector/input.
5. Evidence multiline field.
6. Next experiment multiline field.
7. Stage suggestion banner when suggested stage differs from saved stage.
8. Validation progress indicator.

Each change emits an `IdeaPayload` draft through existing inline editor flow.

## Collapsed Preview

Collapsed Idea node displays:

- Lifecycle badge.
- Impact and effort indicators when set.
- Hypothesis preview limited to two lines.
- Validation progress.
- Next experiment preview limited to two lines.

Generic body remains available as supporting context but does not replace structured preview. Layout must avoid internal scrolling and rendering overflow.

## Validation Progress

Progress uses three equal checkpoints:

- Hypothesis present.
- Evidence present.
- Next experiment present.

Displayed progress is `0/3` through `3/3` with matching linear progress.

## Compatibility

- Existing Idea nodes continue reading `maturity`, `evidence`, and `nextAction`.
- Missing new fields use empty/default values.
- No database migration or generated code required.
- Existing tags, relations, body Markdown, status, and review state remain unchanged.

## Tests

- Payload round-trip preserves new and unknown keys.
- Confidence validation rejects values outside 0 through 100.
- Editor emits updated lifecycle and experiment fields.
- Stage suggestion never mutates saved lifecycle automatically.
- Collapsed preview renders structured summary without overflow.
- Legacy Idea payload still renders and edits correctly.

## Out of Scope

- Automatic lifecycle mutation.
- Experiment history or multiple experiments.
- Separate idea database or migration.
- New filtering or analytics screens.

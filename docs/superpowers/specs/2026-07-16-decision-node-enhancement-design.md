# Decision Node Enhancement Design

**Date:** 2026-07-16
**Status:** Approved design, pending written-spec review

## Goal

Turn Decision nodes into complete decision records: compare options with weighted criteria, preserve human control over final outcome, and support later review without breaking legacy data.

## Scope

Decision node adds:

- lifecycle status
- decision question and context
- owner, deadline, and review date
- weighted criteria
- rich options with pros, cons, and risks
- per-option criterion scores
- automatic weighted ranking
- non-destructive recommended outcome
- manual selected outcome
- confidence
- rationale, assumptions, expected outcome, and review notes
- progress indicator
- structured collapse preview
- expanded auto-size with no manual resize
- collapsed manual resize

No collaboration workflow, voting, attachments, AI-generated decisions, or external integrations are included.

## Domain Model

### DecisionPayload

`DecisionPayload` remains the typed payload for `NodeType.decision`. It gains these fields:

- `status`: one of `draft`, `evaluating`, `decided`, `reviewing`, `reversed`
- `question`: decision statement or question
- `context`: background and constraints
- `owner`: accountable person or role
- `deadline`: optional ISO date text
- `reviewDate`: optional ISO date text
- `confidence`: integer from 0 through 100
- `criteria`: list of `DecisionCriterion`
- `options`: list of `DecisionOption`
- `selectedOptionId`: manually accepted option ID
- `rationale`: reason for final selection
- `assumptions`: assumptions behind the decision
- `expectedOutcome`: expected result or success condition
- `reviewNotes`: later outcome/review notes

### DecisionCriterion

Each criterion contains:

- stable `id`
- `name`
- positive numeric `weight`

Weights do not need to total 100. Ranking normalizes using the sum of all positive criterion weights. If every weight is zero, weighted ranking is unavailable.

### DecisionOption

Each option contains:

- stable `id`
- `title`
- `description`
- `pros`: editable string list
- `cons`: editable string list
- `risks`: editable string list
- `scores`: map from criterion ID to integer score `1..10`

Deleting a criterion removes its scores from every option. Deleting the selected option clears `selectedOptionId`. IDs remain stable during editing.

## Ranking Rules

For each option:

```text
weightedScore = sum(score * criterionWeight) / sum(criterionWeight)
```

Only criteria with positive weight and a valid score participate. An option without any scored criterion has no ranking score.

`recommendedOptionId` is the highest ranked option. Equal scores preserve option order. Recommendation never mutates `selectedOptionId` automatically.

When recommendation differs from manual outcome, editor shows a non-destructive suggestion with an Apply action.

## Lifecycle and Progress

Statuses are manually controlled:

- `draft`: decision still being framed
- `evaluating`: criteria/options are being compared
- `decided`: outcome selected
- `reviewing`: outcome is being checked after execution
- `reversed`: previous decision was intentionally reversed

Suggested status remains non-destructive:

- selected outcome and rationale present: `decided`
- criteria or options present: `evaluating`
- otherwise: `draft`
- never auto-suggest `reviewing` or `reversed`

Progress has five checkpoints:

1. decision question exists
2. at least one valid criterion exists
3. at least two valid options exist
4. selected outcome exists
5. rationale exists

Editor displays `Decision X/5` and a linear progress indicator.

## Persistence and Compatibility

New structured data is stored under a `decision` map to keep related records together. Unknown root keys and unknown keys inside `decision` are preserved.

Legacy keys remain readable:

- legacy `options` text/list becomes options with generated stable IDs
- legacy `criteria` text becomes one criterion
- legacy `selectedOption` resolves by option title when possible
- legacy `reason` becomes rationale

Writes retain the legacy summary keys for existing readers:

- `options`: newline-separated option titles
- `criteria`: newline-separated criterion names
- `selectedOption`: selected option title
- `reason`: rationale

Structured data is authoritative when present.

## Editor Design

### Header and workflow

- status ChoiceChips
- suggested-status panel with Apply action
- progress label and indicator
- confidence slider without divisions for continuous drag

### Decision framing

Persistent multiline fields:

- Decision question
- Context
- Assumptions
- Expected outcome
- Rationale
- Review notes

Persistent single-line/date fields:

- Owner
- Deadline
- Review date

Controllers and focus nodes follow Idea/Question draft-echo protection so progressive typing and pointer drags survive reconstructed payload updates.

### Criteria editor

Each criterion row supports:

- edit name
- edit positive weight
- delete

An Add criterion action appends a valid starter criterion. Invalid or empty values show local validation errors rather than crashing.

### Options editor

Each option section supports:

- edit title and description
- add/edit/delete pros
- add/edit/delete cons
- add/edit/delete risks
- delete option
- score slider or compact numeric control for every criterion

An Add option action appends a valid starter option. At least two options are encouraged by progress, not required for draft persistence.

### Ranking and outcome

- ranked options show weighted score
- recommended option is visually identified
- manual outcome uses option selection control
- mismatch shows recommendation panel with Apply action
- selecting outcome never deletes option data

## Collapse Preview

Collapsed Decision preview is bounded and overflow-safe:

- lifecycle status
- confidence
- progress `X/5`
- decision question, maximum two lines
- top two ranked options with scores
- selected outcome when present
- otherwise recommended option when available
- review date when present

Legacy-only Decision nodes fall back to existing summary content.

## Sizing and Resize

Expanded Decision size comes from `InlineNodeWorkspacePolicy.expandedSizeForNode` using:

- multiline text line estimates
- criterion count
- option count
- pros/cons/risk item count
- score matrix row count
- suggestion visibility

Expanded Decision ignores persisted custom dimensions and has no resize handle. Collapsed Decision keeps persisted/manual resize behavior.

## Validation

Validation errors include:

- unsupported lifecycle status
- confidence outside `0..100`
- empty criterion name
- non-positive criterion weight
- duplicate criterion IDs
- empty option title
- duplicate option IDs
- score referencing unknown criterion
- score outside `1..10`
- selected option ID not found
- malformed optional deadline/review date

Title validation remains unchanged.

## Tests

### Domain

- structured round-trip and unknown-key preservation
- legacy migration/read compatibility
- normalized weighted ranking
- deterministic tie handling
- recommendation non-destructive behavior
- progress and suggested status
- deletion cleanup rules
- validation boundaries

### Editor

- status, suggestion, and progress
- add/edit/delete criteria
- add/edit/delete options
- add/edit/delete pros, cons, and risks
- scoring updates ranking
- recommendation Apply action
- manual outcome remains independent
- multiline fields survive reconstructed draft echo
- confidence and score sliders support continuous drag

### Canvas and sizing

- structured collapsed preview
- preview bounded to two ranked options
- expanded size grows with structured content
- expanded resize controls absent
- collapsed resize controls remain
- no rendering overflow

## Deliberate Simplifications

- Scores use integers `1..10`; add decimal scoring only if users need finer comparisons.
- Weights are normalized automatically; add a forced 100% total only if strict governance requires it.
- Dates remain local ISO date strings; add reminders/calendar integration separately.
- One manual outcome only; add multi-select outcomes only when real decisions require combined options.

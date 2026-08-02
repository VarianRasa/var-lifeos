# Checklist Node Enhancement Design

## Goal

Turn `NodeType.checklist` into a dedicated interactive checklist workspace without changing task-node checklist behavior.

## Scope

- Dedicated checklist domain payload and item model.
- Backward-compatible migration from legacy `MindmapNode.checklist` data.
- Expanded checklist editor with item CRUD, completion, priority, deadline, filtering, reorder, progress, and clear-completed action.
- Collapsed checklist view with progress, quick completion, active-item preview, and quick add.
- Expanded node height derived from checklist content with no internal scrolling.
- Focused domain and widget regression tests.

## Data Model

Add `ChecklistPayload` containing ordered `ChecklistEntry` values.

Each `ChecklistEntry` contains:

- `id`: stable non-empty identifier.
- `title`: trimmed item title.
- `isDone`: completion state.
- `priority`: none, low, medium, or high.
- `dueDate`: optional local calendar date.

New checklist data is stored under `MindmapNode.data['checklist']` as a versioned map containing an `items` list. List order is authoritative for drag reorder.

`TaskChecklistPayload` remains unchanged and continues serving task nodes.

## Compatibility

`ChecklistPayload.fromNode` reads the new payload first. When absent, it converts legacy `MindmapNode.checklist` items into `ChecklistEntry` values with priority `none` and no deadline.

Writing a checklist payload stores the new structure and keeps `MindmapNode.checklist` synchronized with basic `id`, `title`, and `isDone` fields. This preserves compatibility with existing previews, exports, backups, and older code paths during transition.

Malformed entries are skipped when their title is empty. Missing IDs receive generated IDs at the mutation boundary, not during read-only parsing.

## Expanded Editor

Header area contains progress count, percentage bar, filter segmented control (`All`, `Active`, `Done`), add-item action, and clear-completed action.

Each visible row contains:

- Drag handle.
- Checkbox.
- Editable title.
- Priority control.
- Optional deadline picker and clear action.
- Delete action.

Adding creates an item with a generated ID, empty completion state, no priority, and no deadline. Empty submissions are rejected. Editing preserves ID and metadata.

Reorder applies to full payload order. While a filter is active, drag reorder is disabled to avoid ambiguous hidden-item placement.

Clear completed requires at least one completed item and removes only completed entries.

## Collapsed View

Collapsed checklist shows:

- Completed/total count and progress bar.
- Up to four active items, then completed items if space remains.
- Quick checkbox mutation.
- Compact add-item field/action.
- Remaining-item count when more than four entries exist.

Collapsed interactions use `onNodeUpdated` and do not expand or drag the node.

## Sizing

`InlineNodeWorkspacePolicy.expandedSizeForNode` calculates checklist height from a fixed editor chrome base plus one row allowance per checklist entry. Empty and filtered states retain enough height for controls. Expanded checklist editor uses normal column layout and no `SingleChildScrollView`.

Collapsed node size remains user-configurable and uses truncation for previews.

## Validation

- Checklist title remains required through existing node validation.
- Item titles must be non-empty after trimming.
- Due dates use local date-only normalization.
- Duplicate item IDs are rejected or regenerated at mutation boundaries.
- Unknown priority values decode as `none`.

## Tests

- New payload JSON round trip.
- Legacy `MindmapNode.checklist` migration.
- Task checklist payload remains unchanged.
- Add, edit, toggle, delete, priority, and deadline mutations.
- Reorder persistence and filtered reorder disabled state.
- Clear-completed behavior.
- Collapsed quick toggle and add actions.
- Expanded checklist contains no internal scroll view.
- Expanded node height grows with item count.

## Non-Goals

- Recurring checklist items.
- Nested checklist items.
- Assignees, attachments, comments, or reminders.
- Cross-node checklist templates.
- Automatic overdue notifications.
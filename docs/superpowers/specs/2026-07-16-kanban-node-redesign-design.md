# Kanban Node Redesign

Date: 2026-07-16
Status: Approved design, pending implementation

## Goal

Replace the basic Kanban inline editor with a professional board that supports flexible columns, rich cards, drag-and-drop, attachments, local-first persistence, sync compatibility, and automatic node sizing.

## Scope

### Board

- Default columns: Backlog, In Progress, Done.
- Users can add, rename, reorder, and delete columns.
- Maximum six columns per board.
- Deleting a non-empty column requires selecting a destination column for its cards.
- Board header shows total cards, completed cards, and checklist progress.

### Cards

Each card supports:

- Title, limited to 120 characters.
- Description, limited to 500 characters.
- Priority: none, low, medium, high, urgent.
- Optional deadline using local-day semantics.
- Labels.
- Checklist items with completion state.
- File attachments without assignees.
- Duplicate and delete actions.

Cards can be reordered within a column and dragged between columns. Keyboard-accessible move actions remain available from each card menu as a fallback.

### Attachments

- Reuse `NodeAttachmentRepository` and existing 100 MB validation.
- Store attachment bytes in the attachment repository.
- Store attachment references inside the Kanban card payload.
- Support existing image/text preview and file export behavior.
- Removing a card or attachment removes unreferenced attachment bytes.

## Domain Model

Replace the fixed `KanbanColumn` enum as the persisted source of truth with `KanbanColumnDefinition`:

- `id`
- `title`
- `order`
- `isDoneColumn`

Extend `KanbanCard` with:

- `columnId`
- `order`
- `description`
- `priority`
- `dueDate`
- `labels`
- `checklist`
- `attachments`

`KanbanBoard` owns ordered columns and cards. Domain methods perform add, rename, reorder, delete-with-migration, card move, card reorder, duplicate, checklist updates, and attachment reference updates.

## Backward Compatibility

Existing payloads use fixed column names `todo`, `doing`, and `done`. Decoder migration maps them to stable default IDs:

- `todo` to `backlog`
- `doing` to `in-progress`
- `done` to `done`

Existing cards keep IDs and titles. Unknown legacy column names fall back to `backlog`. Existing extra keys inside the `kanban` section remain preserved when payload data is rewritten.

## Persistence

- Keep Kanban metadata inside `MindmapNode.data['kanban']`.
- Continue saving through `InlineNodeWorkspaceController` and `MindmapRepository`.
- Use merge-safe `InlineNodeDraftPatch` updates.
- Invalidate mindmap providers through existing mutation flow.
- Existing local database, portable backup, and optional sync carry the expanded JSON payload without a new database table.
- Attachment bytes continue through `NodeAttachmentRepository`.

## Inline UI

- Retain node title and description fields at the top.
- Add a compact board summary and Add column action.
- Render columns horizontally with professional rectangular surfaces matching the active palette.
- Render cards as compact rectangular cards with priority, deadline, labels, checklist progress, and attachment count.
- Card detail editing opens inside the Kanban node, not a separate page.
- Column and card menus expose rename, duplicate, move, and delete actions.
- Drag targets provide clear hover and drop feedback.
- Empty columns show an Add card target.

## Node Sizing

Kanban expanded size follows content without internal scrolling:

- Width derives from column count and column width.
- Height derives from the tallest column and its cards.
- Minimum size remains usable for an empty three-column board.
- Maximum six columns prevents unbounded horizontal growth.
- Draft snapshots drive size immediately, before database persistence completes.
- Collapsed nodes keep existing compact presentation rules.

## Error Handling

- Reject empty column and card titles.
- Prevent deleting the final column.
- Prevent duplicate column IDs during decoding.
- Preserve cards if malformed payload data is encountered by moving them to Backlog.
- Surface attachment import/open/remove failures through existing inline action error handling.
- Confirm destructive column and card deletion.

## Testing

### Domain

- Legacy payload migration.
- Column add, rename, reorder, and delete migration.
- Card reorder and cross-column move.
- Card metadata and checklist serialization.
- Unknown/malformed data fallback.

### Widget

- Professional board renders all columns and cards.
- Add/edit/delete column and card flows emit draft patches.
- Drag-and-drop changes card column and order.
- Attachment actions invoke repository-backed callbacks.
- Node size follows latest draft column/card content.
- No RenderFlex overflow for empty and populated boards.

### Integration

- Inline draft saves to repository and survives reload.
- Attachment reference and bytes survive reload.
- Existing legacy Kanban nodes open without data loss.

## Deliberate Limits

- No assignees.
- No comments, activity feed, automation rules, or WIP limits.
- No separate Kanban database tables.
- No nested cards or card dependencies.

These can be added later if real usage requires them.
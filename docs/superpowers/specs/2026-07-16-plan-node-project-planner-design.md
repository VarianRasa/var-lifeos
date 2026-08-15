# Plan Node Project Planner Design

Date: July 16, 2026
Status: Approved design, pending implementation-plan review

## Goal

Replace the basic Plan inline editor with a professional project planner that supports phase, milestone, and task hierarchy directly inside the mindmap node. All project content remains visible in normal expanded mode, persists through the existing local-first node data flow, and remains compatible with legacy Plan data.

## Scope

### Included

- Project-level summary, status, period, and computed progress.
- Phase, milestone, and task hierarchy.
- Full task metadata and inline interactions.
- Drag reordering for phases, milestones, and tasks.
- Attachment add, preview/open, and remove through the existing attachment repository.
- Dynamic expanded node sizing based on complete visible content.
- Read-only collapsed preview.
- Legacy `steps` and `completedSteps` migration.
- Domain, payload, widget, persistence, and sizing tests.

### Excluded

- Multi-user assignees.
- Network-only project management integrations.
- Gantt chart and calendar scheduling engine.
- Automatic critical-path calculation.
- Hidden internal scrolling in normal expanded mode.

## Domain Model

Plan data remains under `MindmapNode.data['plan']`.

### Project

- `status`: planning, active, blocked, completed, or archived.
- `startDate`: optional local date.
- `targetDate`: optional local date.
- `phases`: ordered phase collection.

Project progress is derived from completed tasks. Completed content remains visible.

### Phase

- Stable ID.
- Title and description.
- Status.
- Optional target date.
- Explicit order.
- Ordered milestones.

### Milestone

- Stable ID.
- Title and description.
- Status.
- Optional deadline.
- Explicit order.
- Ordered tasks.

Milestone progress is derived from its tasks.

### Task

- Stable ID.
- Title and description.
- Status: planned, in progress, blocked, or done.
- Priority: none, low, medium, high, or urgent.
- Optional deadline.
- Labels.
- Checklist items.
- Attachment references.
- Dependency task IDs.
- Optional estimated minutes.
- Optional actual minutes.
- Optional blocking reason.
- Explicit order.

## Legacy Migration

- Existing `steps` become tasks inside a generated default phase and milestone.
- Existing `completedSteps` mark matching migrated tasks as done.
- Unknown keys inside `data['plan']` are preserved during writes.
- Malformed nested values fall back safely without throwing.
- New writes emit the hierarchical structure while retaining compatibility fields when existing consumers still require them.

## Expanded UI

### Project Header

- Editable project title and context.
- Status selector.
- Optional start and target date controls.
- Computed progress bar.
- Summary chips for phase, milestone, task, completed, and blocked counts.
- Primary `Add phase` action.

### Phase Card

- Rectangular professional card using active palette tokens.
- Drag handle, phase number, title, status, target date, and progress.
- Rename, duplicate, and delete actions.
- `Add milestone` action.

### Milestone Card

- Nested rectangular card with flag icon.
- Drag handle, title, status, deadline, and task progress.
- Rename, duplicate, and delete actions.
- `Add task` action.

### Task Card

All task content remains visible:

- Completion checkbox.
- Title and description.
- Status, priority, deadline, labels.
- Estimated and actual time.
- Dependency list.
- Blocking reason when blocked.
- Interactive checklist.
- Attachment names with open/preview action.
- Edit, duplicate, and delete actions.
- Drag handle for reordering or movement between milestones.

## Drag and Drop

- Phases reorder horizontally or vertically according to rendered layout.
- Milestones reorder within a phase and move between phases.
- Tasks reorder within a milestone and move between milestones.
- Drag feedback follows the pointer freely.
- Drop targets receive visible accent highlighting.
- Every successful drop emits one updated Plan payload through the existing draft save flow.

## Attachment Integration

- Reuse `NodeAttachmentRepository` and existing file picker behavior.
- Reuse current file-size and platform validation.
- Store only attachment references inside Plan payload.
- Support preview/open and removal using the same production adapters used by Task and Kanban.
- Removing a task or milestone removes associated attachment records after confirmation.

## Dynamic Sizing

Expanded Plan size is calculated from:

- Header height.
- Phase count.
- Milestone count.
- Task descriptions and metadata.
- Checklist item count.
- Attachment count.
- Dependency and blocking sections.

Normal expanded mode must show all components without internal scrolling. Narrow safety fallback may scroll only when host constraints are smaller than the policy minimum.

## Collapsed Preview

Collapsed Plan is read-only:

- Project status and overall progress.
- Phase and milestone names.
- Compact task completion summary.
- No editing, drag, delete, or completion controls.
- Responsive metadata hiding prevents overflow on narrow cards.

## Persistence Flow

1. Inline interaction produces an updated typed Plan payload.
2. Existing draft merge writes only owned Plan fields.
3. Unknown node and nested Plan fields remain intact.
4. Canvas invalidation follows existing mindmap mutation helpers.
5. Local-first storage remains authoritative; optional sync receives normal node updates.

## Validation

- Required non-empty titles for phase, milestone, and task creation.
- End/target dates cannot precede applicable start dates.
- Actual and estimated minutes must be non-negative integers.
- Dependencies must reference existing tasks and cannot reference the task itself.
- Duplicate dependency IDs are normalized.
- Deleting containers requires confirmation and clearly reports nested content impact.

## Tests

- Domain round-trip and malformed migration.
- Legacy steps migration.
- Progress calculation.
- Reordering and cross-container movement.
- Dependency validation.
- Checklist toggle persistence.
- Attachment callback wiring.
- Dynamic size growth.
- Expanded editor overflow regression.
- Collapsed preview read-only behavior.
- Canvas persistence integration.

## Success Criteria

- Plan works as a complete project planner directly inside the node.
- All phase, milestone, and task content is visible in expanded mode.
- Every interaction persists through the existing local-first backend/database path.
- Legacy Plan nodes open without data loss.
- Collapsed Plan remains clean and non-interactive.
- Focused tests and `flutter analyze --no-pub` pass.
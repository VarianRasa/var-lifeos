# Live Board Templates Design

## Goal

Speed board creation through eight built-in templates and user templates that always mirror their source board.

## Scope

- Built-ins: Project Plan, Kanban, Brainstorm, Content Calendar, Weekly Planner, Research Board, Moodboard, Goal Tracker.
- Users can save an active project board as a template.
- User templates store source board ID plus editable template name, not copied board content.
- Using a user template clones current source content and layout into a new project board.
- Board-reference objects are omitted. Connectors and parent relationships left invalid by omission are removed or cleared.
- Source updates appear automatically because instantiation reads source at creation time.
- Template disappears when source enters Trash or is permanently deleted.
- Gallery appears in board creation and Settings, with search, preview, rename, and delete.

## Architecture

Add a small `CanvasBoardTemplate` metadata model and repository. Built-ins remain immutable definitions; user records contain `id`, `name`, `sourceBoardId`, and timestamps. Store user metadata in Sembast, while source board content stays authoritative in existing board repository.

Extract one pure clone/remap helper from nested-board selection copying. It creates fresh object IDs, rewrites frame, column, connector, and ordered-child relationships, excludes board-reference objects, removes connectors whose endpoints were excluded, and clears invalid parent IDs.

`BoardTemplateService` validates project/workspace/source state, lists available templates, saves metadata, renames/deletes it, and atomically creates a board plus parent reference when invoked from nested creation. Built-in instantiation uses the same clone result shape.

## Data and Failure Handling

- User template IDs use UUID.
- Names are trimmed and non-empty.
- Source must be an active project board.
- Missing or trashed sources are filtered from reads and rejected again at instantiation.
- Board creation writes no partial board: clone and validation finish before existing atomic board transaction.
- No new dependency.

## Testing

- Metadata codec and validation.
- Clone fidelity and ID remapping for frames, columns, connectors, and ordered children.
- Board-reference exclusion and orphan connector cleanup.
- Live source update and automatic disappearance after Trash/deletion.
- Eight built-in definitions and instantiation.
- Gallery search/preview, save, rename, delete, and create flows.
- Existing nested board, workspace, repository, analyze, and Flutter tests.

## Deliberate Limits

- No frozen snapshots or template version history.
- No nested-board tree duplication.
- No cross-workspace template sharing.
- No import/export marketplace.
- Preview uses existing canvas preview; no persisted raster cache.

# Nested Board Design

## Goal

Add Milanote-style nested project boards. Users open child boards inside current canvas flow, navigate with breadcrumbs, and return to exact parent viewport.

## Scope

### Board References

- Add `CanvasObjectType.boardReference` as native canvas card.
- Reference points to project board in same workspace.
- Board cannot reference itself or any ancestor; validation rejects cycles.
- Existing board can have multiple reference cards.
- Trashed boards cannot open until restored.

### Creation

Creating Nested board opens one dialog with four choices:

1. Create empty board.
2. Create from existing project template.
3. Copy current selection into new board while keeping source items unchanged.
4. Search and link existing board in same workspace.

Search includes trashed boards with a Trash label and **Restore and link** action. Copy selection remaps copied object IDs, connectors, frames, columns, and internal references while preserving source content.

### Navigation

- Opening a board-reference card replaces active canvas in same workspace route.
- URL remains `/workspaces/:type/:name?view=canvas&board=<boardId>`.
- Navigation stack stores parent board ID, activating reference ID, and parent viewport.
- Breadcrumb displays root-to-current board path.
- Back and breadcrumb navigation restore saved viewport exactly.
- Direct child-board URLs load without requiring an in-memory stack.

### Card Presentation

Board-reference card displays:

- Board title.
- Board preview thumbnail.
- Item count.
- Last-edited time.

Metadata updates after successful board save. Thumbnail regeneration is debounced. Failed thumbnail generation keeps last thumbnail or placeholder and never fails board persistence.

### Deletion and Trash

Deleting board-reference card always opens confirmation.

- **Delete this card only** removes reference and leaves board active.
- **Delete board and all links** moves target board intact to Trash and disables all cards pointing to it.

Boards remain restorable for 30 days. Restore reactivates all surviving references. Cleanup permanently deletes expired board content and all references. Descendant boards remain intact; links inside restored or permanently deleted content follow same reference rules rather than implicit cascading deletion.

### Data Model

Extend `CanvasObject` with typed nullable `referencedBoardId`. Add `boardReference` to `CanvasObjectType`.

Extend `CanvasBoard` with:

- `parentBoardId` for canonical breadcrumb ancestry of newly created child boards.
- `trashedAt` for 30-day retention.
- Existing `workspaceName` as workspace boundary.

Do not store depth. Compute ancestry from parent IDs. Linking existing board does not change canonical parent. New boards created through a reference use current board as canonical parent.

### Architecture

- Domain service validates same-workspace references, ancestry, dangling IDs, and cycles.
- Repository gains workspace graph reads and an atomic multi-board mutation boundary.
- Riverpod providers load arbitrary board IDs and workspace board graphs.
- Existing canvas command stack remains for single-board edits. Cross-board create, link, trash, restore, and purge use a repository transaction command carrying before/after board snapshots.
- Existing route supports deep links; workspace page owns breadcrumb history and viewport restoration.
- Existing preview painter becomes reusable. Persisted image thumbnails are deferred until profiling requires them.
- Collaboration sync treats each changed project board as a separate revision, then runs deterministic graph repair. Cross-board operations enqueue one mutation group so retries are idempotent.

### Atomicity and Failure Handling

- Create board and reference card commit together or roll back together.
- Copy selection creates child content and parent reference atomically.
- Trash/restore updates target and affected references atomically.
- Permanent purge removes target, contained objects, and external references atomically.
- Permission, stale revision, persistence, or sync preparation failure leaves all boards unchanged.
- Undo/Redo replays complete cross-board transaction snapshots.
- Missing references render unavailable cards and expose repair/remove actions; they never crash canvas loading.

### Accessibility and Platforms

- Board cards expose title, item count, edit time, trash state, and open action through semantics.
- Keyboard activation opens cards; Back and breadcrumb work on desktop/web/mobile.
- Mobile uses existing long-press drag behavior.
- Focus returns to activating reference card when navigating back.

## Testing

- Model codec, legacy migration, equality, copy, typed reference parsing.
- Cycle, self-link, ancestor-link, workspace boundary, missing-reference validation.
- Repository atomic create/link/copy/trash/restore/purge and rollback tests for memory and Sembast.
- Selection copy ID and relationship remapping.
- Card rendering, placeholder/error states, semantics, keyboard opening.
- Breadcrumb, direct URL, browser/app Back, exact viewport restoration, focus restoration.
- Multi-link delete choices, restore, and 30-day cleanup.
- Undo/Redo across all affected boards.
- Collaboration grouped retry, stale conflict, and graph repair tests.
- Existing canvas, workspace, router, export, analyze, and full Flutter test suites.

## Deliberate Limits

- Nested boards are project boards without calendar dates.
- References stay within one workspace.
- No cyclic graph links.
- No cross-workspace search or permissions.
- No persisted raster thumbnail cache in first release; add when live preview profiling shows frame or memory regressions.
- No automatic descendant trash cascade.
- Export/import of recursive board trees remains separate work; current export reports external board references explicitly.

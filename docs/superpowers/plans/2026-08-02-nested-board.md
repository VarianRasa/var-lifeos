# Nested Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add same-workspace nested project boards with board-reference cards, breadcrumb navigation, selection copy, atomic Trash lifecycle, Undo/Redo, and collaboration-safe persistence.

**Architecture:** Extend existing `CanvasBoard` and `CanvasObject` models, then place hierarchy invariants and multi-board mutations behind one focused domain/application service. Reuse existing workspace route, canvas renderer, preview painter, Sembast repositories, and Riverpod patterns; avoid new dependencies and persisted thumbnail infrastructure.

**Tech Stack:** Flutter, Dart 3.11.4, Riverpod, Sembast, go_router, existing collaboration board sync.

## Global Constraints

- Nested boards use `CanvasBoardKind.project` and have no calendar date.
- References and search stay within same workspace.
- Self-links, ancestor-links, and cycles are rejected.
- Trash retention is exactly 30 days.
- Board content remains intact while trashed.
- Existing source objects remain unchanged when copying selection.
- Board persistence must not fail when preview rendering fails.
- No new package.
- Do not hand-edit generated files.

---

### Task 1: Typed Board Reference and Trash Model

**Files:**
- Modify: `lib/features/mindmap/domain/canvas_board.dart`
- Test: `test/features/mindmap/domain/canvas_board_test.dart`

**Interfaces:**
- Produces: `CanvasObjectType.boardReference`, `CanvasObject.referencedBoardId`, `CanvasBoard.parentBoardId`, `CanvasBoard.trashedAt`, `CanvasBoard.isTrashed`, `CanvasBoard.isTrashExpired(DateTime now)`.

- [ ] **Step 1: Add failing codec and invariant tests**

Add tests proving board-reference round-trip, legacy JSON defaults, blank reference rejection, project-only parent relation, `trashedAt` round-trip, and exact expiration boundary:

```dart
expect(board.isTrashExpired(trashedAt.add(const Duration(days: 30))), isTrue);
expect(
  board.isTrashExpired(
    trashedAt.add(const Duration(days: 30)).subtract(const Duration(microseconds: 1)),
  ),
  isFalse,
);
```

- [ ] **Step 2: Verify failure**

Run: `flutter test test/features/mindmap/domain/canvas_board_test.dart`
Expected: FAIL because nested-board fields and enum value do not exist.

- [ ] **Step 3: Implement minimum immutable model**

Add typed fields to constructors, `fromJson`, `copyWith`, `toJson`, equality, and hash. Normalize blank optional IDs to null. Define:

```dart
bool get isTrashed => trashedAt != null;

bool isTrashExpired(DateTime now) =>
    trashedAt != null &&
    !now.toUtc().isBefore(
      trashedAt!.toUtc().add(const Duration(days: 30)),
    );
```

Increment `CanvasBoard.currentSchemaVersion`; old JSON remains readable.

- [ ] **Step 4: Verify pass**

Run: `flutter test test/features/mindmap/domain/canvas_board_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/domain/canvas_board.dart test/features/mindmap/domain/canvas_board_test.dart
git commit -m "feat: add nested board model"
```

### Task 2: Workspace Board Graph Validation

**Files:**
- Create: `lib/features/mindmap/domain/canvas_board_graph.dart`
- Create: `test/features/mindmap/domain/canvas_board_graph_test.dart`

**Interfaces:**
- Consumes: model fields from Task 1.
- Produces:

```dart
final class CanvasBoardGraph {
  CanvasBoardGraph(Iterable<CanvasBoard> boards);
  List<CanvasBoard> ancestorsOf(String boardId);
  bool canReference({required String sourceBoardId, required String targetBoardId});
  void validateReference({required String sourceBoardId, required String targetBoardId});
  List<String> referencingObjectIds(String boardId);
}
```

- [ ] **Step 1: Write failing graph tests**

Cover same-workspace success, self-link rejection, ancestor-link rejection, canonical-parent cycle rejection, missing board rejection, trashed target rejection, and duplicate references allowed.

- [ ] **Step 2: Verify failure**

Run: `flutter test test/features/mindmap/domain/canvas_board_graph_test.dart`
Expected: FAIL because `CanvasBoardGraph` does not exist.

- [ ] **Step 3: Implement graph indexes and deterministic validation**

Index boards by ID, parent by child ID, and references by target ID. Throw `FormatException` with stable messages for malformed stored graphs and `StateError` for rejected user operations. Traverse with visited sets; never recurse without cycle guards.

- [ ] **Step 4: Verify pass**

Run: `flutter test test/features/mindmap/domain/canvas_board_graph_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/domain/canvas_board_graph.dart test/features/mindmap/domain/canvas_board_graph_test.dart
git commit -m "feat: validate nested board graph"
```

### Task 3: Repository Graph Reads and Atomic Mutations

**Files:**
- Modify: `lib/features/mindmap/domain/canvas_board_repository.dart`
- Modify: `lib/features/mindmap/data/canvas_board_repositories.dart`
- Modify: `lib/features/mindmap/data/collaboration_canvas_board_repository.dart`
- Test: `test/features/mindmap/data/canvas_board_repositories_test.dart`
- Test: `test/features/mindmap/data/collaboration_canvas_board_repository_test.dart`

**Interfaces:**
- Produces:

```dart
Future<List<CanvasBoard>> listWorkspaceBoards(
  String workspaceName, {
  bool includeArchived = false,
  bool includeTrashed = false,
});

Future<void> saveBoardsAtomically(Iterable<CanvasBoard> boards);
Future<void> deleteBoardsAtomically(Iterable<String> boardIds);
```

- [ ] **Step 1: Add failing shared repository contract tests**

Test memory and Sembast implementations for trash filtering, complete workspace graph reads, all-or-nothing multi-save, all-or-nothing multi-delete, and unchanged records after injected transaction failure.

- [ ] **Step 2: Verify failure**

Run: `flutter test test/features/mindmap/data/canvas_board_repositories_test.dart`
Expected: FAIL because graph and transaction methods do not exist.

- [ ] **Step 3: Implement repository methods**

Use one Sembast transaction for every multi-board write/delete. Memory repository computes validated replacement map before assigning `_boards`. Keep `listBoards` backward-compatible and exclude Trash unless explicitly requested.

- [ ] **Step 4: Make collaboration wrapper enqueue changed project boards only after local transaction succeeds**

Assign one generated mutation-group ID to every board payload in an atomic operation. `deleteBoardsAtomically` records tombstones before local hard deletion; do not silently bypass sync.

- [ ] **Step 5: Verify pass**

Run:

```bash
flutter test test/features/mindmap/data/canvas_board_repositories_test.dart
flutter test test/features/mindmap/data/collaboration_canvas_board_repository_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/mindmap/domain/canvas_board_repository.dart lib/features/mindmap/data/canvas_board_repositories.dart lib/features/mindmap/data/collaboration_canvas_board_repository.dart test/features/mindmap/data/canvas_board_repositories_test.dart test/features/mindmap/data/collaboration_canvas_board_repository_test.dart
git commit -m "feat: add atomic board graph persistence"
```

### Task 4: Nested Board Transaction Service and Selection Copy

**Files:**
- Create: `lib/features/mindmap/application/nested_board_service.dart`
- Create: `test/features/mindmap/application/nested_board_service_test.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`

**Interfaces:**
- Consumes: `CanvasBoardGraph`, atomic repository methods, selected `CanvasObject` IDs.
- Produces:

```dart
enum NestedBoardCreationKind { empty, template, copySelection, existing }

enum BoardReferenceDeleteChoice { referenceOnly, boardAndAllReferences }

final class NestedBoardMutation {
  const NestedBoardMutation({required this.before, required this.after});
  final List<CanvasBoard> before;
  final List<CanvasBoard> after;
}

Future<NestedBoardMutation> createNestedBoard(...);
Future<NestedBoardMutation> linkExistingBoard(...);
Future<NestedBoardMutation> deleteBoardReference(...);
Future<NestedBoardMutation> restoreBoard(...);
Future<NestedBoardMutation> purgeExpiredTrash(DateTime now);
Future<void> revertMutation(NestedBoardMutation mutation);
Future<void> reapplyMutation(NestedBoardMutation mutation);
```

- [ ] **Step 1: Add failing service tests**

Test empty creation, template creation, existing link, copy selection, connector endpoint remap, frame/column parent remap, source unchanged, duplicate link, rollback after failure, both delete choices, restore, exact 30-day purge, and mutation Undo/Redo.

- [ ] **Step 2: Verify failure**

Run: `flutter test test/features/mindmap/application/nested_board_service_test.dart`
Expected: FAIL because service does not exist.

- [ ] **Step 3: Extract pure selection clone helper from canvas duplication logic**

Create fresh IDs for every copied object, then rewrite connector endpoints, `parentFrameId`, `parentColumnId`, and internal object references through ID map. Do not duplicate referenced target boards; copied board-reference cards point to same eligible board.

- [ ] **Step 4: Implement atomic service operations**

Validate graph before writes, build complete before/after snapshots, persist once through repository transaction, and expose snapshots for Undo/Redo. New board IDs use UUID and never derive from title or hierarchy.

- [ ] **Step 5: Verify pass**

Run: `flutter test test/features/mindmap/application/nested_board_service_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/mindmap/application/nested_board_service.dart lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/application/nested_board_service_test.dart
git commit -m "feat: add nested board transactions"
```

### Task 5: Providers, URL Navigation, Breadcrumb, and Viewport Restore

**Files:**
- Modify: `lib/features/mindmap/application/mindmap_providers.dart`
- Modify: `lib/features/workspace/workspace_detail_page.dart`
- Modify: `lib/core/router/app_router.dart`
- Test: `test/features/workspace/workspace_detail_page_test.dart`
- Test: `test/core/router/app_router_test.dart`

**Interfaces:**
- Produces: `canvasBoardByIdProvider`, `workspaceBoardGraphProvider`, local `CanvasBoardNavigationEntry(boardId, referenceObjectId, viewport)`.

- [ ] **Step 1: Add failing provider/router/widget tests**

Cover arbitrary board loading, root-to-child breadcrumb, direct child URL, URL update after card open, browser/app Back, exact viewport restoration, focus returning to reference card, missing child fallback, and provider invalidation after graph mutation.

- [ ] **Step 2: Verify failure**

Run:

```bash
flutter test test/features/workspace/workspace_detail_page_test.dart
flutter test test/core/router/app_router_test.dart
```

Expected: FAIL because nested navigation UI/providers do not exist.

- [ ] **Step 3: Add board-by-ID and workspace graph providers**

Load through repository methods from Task 3. Invalidate board ID, workspace graph, parent, and target after every service mutation.

- [ ] **Step 4: Implement navigation stack and breadcrumb**

Keep existing route shape. Before opening child, persist current viewport and activating object ID. On Back, restore exact viewport after child canvas mounts, then request focus for reference card semantics node.

- [ ] **Step 5: Verify pass**

Run targeted tests from Step 2. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/mindmap/application/mindmap_providers.dart lib/features/workspace/workspace_detail_page.dart lib/core/router/app_router.dart test/features/workspace/workspace_detail_page_test.dart test/core/router/app_router_test.dart
git commit -m "feat: navigate nested boards"
```

### Task 6: Creation Dialog, Board Search, and Trash Restore

**Files:**
- Modify: `lib/features/workspace/workspace_detail_page.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/workspace/workspace_detail_page_test.dart`
- Test: `test/features/mindmap/presentation/canvas_board_integration_test.dart`

**Interfaces:**
- Consumes: service creation kinds and graph providers.
- Produces: Nested board tool/menu action and dialog returning selected creation request.

- [ ] **Step 1: Add failing interaction tests**

Cover four creation choices, template picker, empty selection disabled state, same-workspace search, Trash label, Restore and link, cycle candidates disabled, cancellation with no writes, and keyboard/mobile activation.

- [ ] **Step 2: Verify failure**

Run targeted workspace and canvas tests by test name. Expected: FAIL because dialog/action does not exist.

- [ ] **Step 3: Implement one creation dialog**

Reuse existing templates and board list providers. Search title case-insensitively. Exclude current board and ancestors. Show trashed matches with Restore and link action. Keep submit disabled until required choice data exists.

- [ ] **Step 4: Wire canvas action to service**

Create/link atomically, invalidate providers, select new card, and open child only after persistence succeeds. Surface errors in existing snackbar/status pattern.

- [ ] **Step 5: Verify pass**

Run:

```bash
flutter test test/features/workspace/workspace_detail_page_test.dart --name "nested board"
flutter test test/features/mindmap/presentation/canvas_board_integration_test.dart --name "board reference"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/workspace/workspace_detail_page.dart lib/features/mindmap/presentation/mindmap_canvas.dart test/features/workspace/workspace_detail_page_test.dart test/features/mindmap/presentation/canvas_board_integration_test.dart
git commit -m "feat: add nested board creation flow"
```

### Task 7: Board Card Preview, Semantics, and Delete Choices

**Files:**
- Create: `lib/features/mindmap/presentation/canvas_board_preview.dart`
- Modify: `lib/features/workspace/workspace_detail_page.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/canvas_board_preview_test.dart`
- Test: `test/features/mindmap/presentation/canvas_board_integration_test.dart`

**Interfaces:**
- Produces reusable `CanvasBoardPreview`, board-reference renderer, open callback, and delete-choice dialog.

- [ ] **Step 1: Add failing presentation tests**

Cover title, item count, relative edit time, live preview, placeholder after preview error, trashed/unavailable state, semantics label/action, Enter/Space activation, and both delete choices.

- [ ] **Step 2: Verify failure**

Run targeted preview and integration tests. Expected: FAIL because reusable preview and card renderer do not exist.

- [ ] **Step 3: Extract existing private preview painter**

Move `_CanvasBoardPreview` and painter from workspace page into reusable file without visual changes. Add debounced repaint scheduling around successful saves; preview exceptions use last render or placeholder and never enter persistence path.

- [ ] **Step 4: Render board-reference objects above containing frame/column backgrounds**

Use existing geometry, selection, lock, drag, resize, copy/paste, culling, minimap, search, export fallback, and hit-test paths. Open on activation; preserve direct manipulation behavior.

- [ ] **Step 5: Wire delete confirmation to transaction service**

Show exactly **Delete this card only** and **Delete board and all links**. Keep destructive choice visually marked and require confirmation.

- [ ] **Step 6: Verify pass**

Run:

```bash
flutter test test/features/mindmap/presentation/canvas_board_preview_test.dart
flutter test test/features/mindmap/presentation/canvas_board_integration_test.dart --name "board reference"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/mindmap/presentation/canvas_board_preview.dart lib/features/workspace/workspace_detail_page.dart lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/presentation/canvas_board_preview_test.dart test/features/mindmap/presentation/canvas_board_integration_test.dart
git commit -m "feat: render nested board cards"
```

### Task 8: Trash Cleanup and Collaboration Conflict Repair

**Files:**
- Modify: `lib/features/mindmap/domain/collaboration_board_sync.dart`
- Modify: `lib/features/mindmap/application/collaboration_board_sync_service.dart`
- Modify: `lib/features/mindmap/application/collaboration_controller.dart`
- Modify: `lib/features/mindmap/data/collaboration_canvas_board_repository.dart`
- Test: `test/features/mindmap/domain/collaboration_board_sync_test.dart`
- Test: `test/features/mindmap/data/collaboration_canvas_board_repository_test.dart`
- Create: `test/features/mindmap/application/nested_board_sync_test.dart`

**Interfaces:**
- Consumes: mutation-group IDs and `CanvasBoardGraph`.
- Produces idempotent grouped retries, deterministic invalid-reference repair, and startup purge call.

- [ ] **Step 1: Add failing sync tests**

Cover grouped parent/child retry, duplicate delivery, stale parent plus new child, concurrent trash/edit, remote cycle, missing target, keep-mine, keep-remote, deterministic repair, and purge after 30 days.

- [ ] **Step 2: Verify failure**

Run targeted collaboration and nested sync tests. Expected: FAIL because grouped graph sync does not exist.

- [ ] **Step 3: Extend pending mutation metadata**

Persist mutation-group ID and operation ID. Deduplicate completed operation IDs. Apply all available group members before graph validation; incomplete groups stay pending rather than exposing partial references.

- [ ] **Step 4: Add deterministic graph repair**

Reject self/ancestor/cross-workspace references, mark missing targets unavailable, and choose lower lexical parent board ID only when malformed remote data assigns multiple canonical parents. Record repair in existing conflict/activity status path.

- [ ] **Step 5: Trigger retention cleanup**

Call `purgeExpiredTrash(clock.now())` during project-board repository initialization and after successful sync. Never use device-local date-only comparison; compare UTC instants.

- [ ] **Step 6: Verify pass**

Run:

```bash
flutter test test/features/mindmap/domain/collaboration_board_sync_test.dart
flutter test test/features/mindmap/data/collaboration_canvas_board_repository_test.dart
flutter test test/features/mindmap/application/nested_board_sync_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/mindmap/domain/collaboration_board_sync.dart lib/features/mindmap/application/collaboration_board_sync_service.dart lib/features/mindmap/application/collaboration_controller.dart lib/features/mindmap/data/collaboration_canvas_board_repository.dart test/features/mindmap/domain/collaboration_board_sync_test.dart test/features/mindmap/data/collaboration_canvas_board_repository_test.dart test/features/mindmap/application/nested_board_sync_test.dart
git commit -m "feat: sync nested board lifecycle"
```

### Task 9: Full Regression and Release Verification

**Files:**
- Modify: `docs/superpowers/specs/2026-08-02-nested-board-design.md` only if implementation reveals a required clarification.

**Interfaces:**
- Consumes: completed Tasks 1–8.
- Produces: verified multi-platform nested-board release candidate.

- [ ] **Step 1: Format changed Dart files**

Run: `dart format --set-exit-if-changed lib test`
Expected: exit 0 and no unformatted files.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run focused suites**

```bash
flutter test test/features/mindmap/domain/canvas_board_test.dart
flutter test test/features/mindmap/domain/canvas_board_graph_test.dart
flutter test test/features/mindmap/application/nested_board_service_test.dart
flutter test test/features/mindmap/presentation/canvas_board_integration_test.dart
flutter test test/features/workspace/workspace_detail_page_test.dart
flutter test test/core/router/app_router_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run full suite**

Run: `flutter test`
Expected: PASS. If baseline failures remain, record exact existing failures separately; do not weaken new tests.

- [ ] **Step 5: Build supported release targets**

```bash
flutter build web --release --dart-define=VAR_DEMO_SEED=false
flutter build windows
```

Expected: both builds succeed.

- [ ] **Step 6: Manual smoke**

On desktop and mobile-width viewport: create each of four modes, open nested board, navigate Back, verify exact viewport and focus, link Trash board through restore, exercise both delete choices, Undo/Redo, restart app, direct-open child URL, and verify 30-day boundary with injected clock.

- [ ] **Step 7: Commit verification-only clarifications if any**

```bash
git add docs/superpowers/specs/2026-08-02-nested-board-design.md
git commit -m "docs: clarify nested board behavior"
```

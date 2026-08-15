# Kanban Node Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a flexible, rich, backend-persisted Kanban board directly inside expanded mindmap nodes.

**Architecture:** Extend the existing Kanban domain and `KanbanPayload` while preserving legacy `todo/doing/done` data. Render a dedicated inline editor that emits merge-safe node draft updates, reuses the attachment repository callbacks, and lets canvas sizing consume the latest draft.

**Tech Stack:** Flutter, Dart 3.11, Riverpod, existing mindmap repository, existing node attachment repository, Flutter widget tests.

---

### Task 1: Rich Kanban domain and migration

**Files:**
- Modify: `lib/features/mindmap/domain/kanban_board.dart`
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Test: `test/features/mindmap/domain/kanban_board_test.dart`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart`

- [ ] **Step 1: Write failing legacy migration and rich-card tests**

Cover default columns, legacy enum names, custom columns, card order, priority, deadline, labels, checklist, and attachment references.

- [ ] **Step 2: Run domain tests and verify failure**

Run: `flutter test --no-pub test/features/mindmap/domain/kanban_board_test.dart test/features/mindmap/domain/node_type_payloads_test.dart`
Expected: failures for missing flexible columns and rich card fields.

- [ ] **Step 3: Implement immutable domain models**

Add `KanbanColumnDefinition`, rich `KanbanCard`, `KanbanChecklistItem`, default column constants, safe JSON decoding, migration, reorder/move/duplicate/delete methods, and validation limits.

- [ ] **Step 4: Extend `KanbanPayload` merge-safe serialization**

Persist `columns` and `cards` under `data['kanban']` while preserving unknown existing section keys.

- [ ] **Step 5: Run domain tests**

Expected: all Kanban domain and payload tests pass.

### Task 2: Dedicated inline Kanban editor

**Files:**
- Create: `lib/features/mindmap/presentation/node_editors/kanban_node_editor.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart`
- Modify: `lib/features/mindmap/presentation/node_type_inline_editor.dart`
- Test: `test/features/mindmap/presentation/kanban_node_editor_test.dart`

- [ ] **Step 1: Write failing editor rendering tests**

Assert board summary, flexible columns, empty states, card metadata, Add column, Add card, and absence of old `All cards complete` UI.

- [ ] **Step 2: Implement professional board layout**

Build rectangular column surfaces, compact cards, priority/deadline/labels/checklist/attachment indicators, and inline title/body fields using active theme colors.

- [ ] **Step 3: Implement column dialogs**

Add, rename, reorder, and delete columns. Deleting a non-empty column requires a destination column. Prevent deleting the final column and cap boards at six columns.

- [ ] **Step 4: Implement card editor dialog**

Support title, description, priority, deadline, labels, checklist add/edit/toggle/delete, duplicate, and delete. Enforce title 120 and description 500 character limits with input formatters.

- [ ] **Step 5: Run editor tests**

Expected: editor rendering and action tests pass without RenderFlex overflow.

### Task 3: Drag-and-drop and accessible move actions

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/kanban_node_editor.dart`
- Test: `test/features/mindmap/presentation/kanban_node_editor_test.dart`

- [ ] **Step 1: Write failing card move tests**

Test same-column reorder, cross-column move, drop feedback, and card-menu fallback move.

- [ ] **Step 2: Implement `LongPressDraggable` and `DragTarget`**

Emit updated `KanbanPayload` with deterministic card order. Keep menu-based Move left/right actions for keyboard access.

- [ ] **Step 3: Run drag-and-drop tests**

Expected: order and column IDs update exactly once per drop.

### Task 4: Kanban attachment backend actions

**Files:**
- Modify: `lib/features/mindmap/presentation/node_type_inline_editor.dart`
- Modify: `lib/features/mindmap/presentation/inline_node_workspace.dart`
- Modify: `lib/features/calendar/day_page.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/kanban_node_editor.dart`
- Test: `test/features/calendar/day_page_test.dart`
- Test: `test/features/mindmap/presentation/kanban_node_editor_test.dart`

- [ ] **Step 1: Add Kanban attachment callback contracts**

Expose add/open/remove callbacks using `TaskAttachmentReference`, reusing existing repository storage and preview/export implementation.

- [ ] **Step 2: Wire callbacks through workspace and DayPage**

Use the same file picker, 100 MB validation, attachment repository, preview, export, and removal behavior as Task nodes.

- [ ] **Step 3: Update card payload after attachment actions**

Add references after import, open previews without mutating payload, and remove references plus repository bytes after confirmation.

- [ ] **Step 4: Run attachment integration tests**

Expected: callback wiring and repository-backed actions pass.

### Task 5: Dynamic Kanban node sizing

**Files:**
- Modify: `lib/features/mindmap/domain/inline_node_workspace_policy.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Write failing size policy tests**

Verify width follows one to six columns and height follows the tallest column card content using latest draft snapshots.

- [ ] **Step 2: Implement Kanban content size calculation**

Use a fixed column width, header/footer allowance, and per-card height derived from visible metadata/checklist/attachment rows. No internal board scrolling.

- [ ] **Step 3: Run sizing and canvas tests**

Expected: populated boards render at policy size with no overflow.

### Task 6: Compatibility and full validation

**Files:**
- Modify: affected existing Kanban tests and templates only where expectations changed.

- [ ] **Step 1: Run focused Kanban suite**

Run domain, payload, editor, workspace, canvas, and DayPage Kanban tests.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze --no-pub`
Expected: no issues.

- [ ] **Step 3: Run diff validation**

Run `git diff --check` for all modified files.

- [ ] **Step 4: Report deliberate omissions**

Confirm no assignees, comments, automation, WIP limits, nested cards, or separate database tables were added.
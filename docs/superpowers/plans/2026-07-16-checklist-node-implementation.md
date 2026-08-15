# Checklist Node Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a dedicated, backward-compatible checklist node with rich item management in expanded and collapsed modes.

**Architecture:** Add checklist-only domain types serialized under `data['checklist']`, while synchronizing legacy `MindmapNode.checklist`. Route `NodeType.checklist` through a dedicated editor and collapsed preview; keep task checklist code unchanged.

**Tech Stack:** Dart 3.11, Flutter Material 3, existing Riverpod mutation callbacks, Flutter widget tests.

---

### Task 1: Checklist Domain Payload

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart`

- [x] Add failing tests for new JSON round trip, legacy migration, date-only decoding, unknown priority fallback, and task payload isolation.
- [x] Add `ChecklistPriority`, `ChecklistEntry`, and `ChecklistPayload` with `fromNode`, `copyWith`, `toJson`, `toData`, `toNode`, and validation.
- [x] Update typed payload parsing/application switches so `NodeType.checklist` uses `ChecklistPayload`, while `NodeType.task` remains `TaskChecklistPayload`.
- [x] Run `flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart` and expect all tests to pass.

### Task 2: Expanded Checklist Editor

**Files:**
- Create: `lib/features/mindmap/presentation/node_editors/checklist_node_editor.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart`
- Test: `test/features/mindmap/presentation/productivity_node_editors_test.dart`

- [x] Add failing widget test covering progress, add, toggle, edit, priority, deadline, delete, clear completed, filters, and no internal `SingleChildScrollView`.
- [x] Build `ChecklistNodeEditor` with a normal `Column`, segmented filter, progress bar, add field, reorderable item rows, metadata controls, and clear-completed action.
- [x] Disable reorder unless filter is `All`; preserve full payload order on reorder.
- [x] Route only `NodeType.checklist` to `ChecklistNodeEditor`.
- [x] Run task-specific editor tests and expect all tests to pass.

### Task 3: Collapsed Checklist Actions

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [x] Add failing widget tests for collapsed quick toggle and quick add without expansion or node drag.
- [x] Replace legacy `_ChecklistNodeDetails` reads with `ChecklistPayload`.
- [x] Show progress, up to four prioritized active-first entries, quick checkboxes, compact add field, and remaining count.
- [x] Persist collapsed changes through `onNodeUpdated` using `ChecklistPayload.toNode`.
- [x] Run collapsed checklist tests and expect all tests to pass.

### Task 4: Dynamic Expanded Sizing

**Files:**
- Modify: `lib/features/mindmap/domain/inline_node_workspace_policy.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [x] Add failing tests proving checklist expanded height grows per item and uses fixed policy size while expanded.
- [x] Calculate checklist height from editor chrome plus item-row allowance.
- [x] Treat expanded checklist like task/timer fixed policy sizing so old persisted height cannot force blank space or clipping.
- [x] Run policy and canvas sizing tests and expect all tests to pass.

### Task 5: Final Validation

**Files:**
- Modify: `docs/superpowers/plans/2026-07-16-checklist-node-implementation.md`

- [x] Run `dart format` on edited Dart files.
- [x] Run focused domain, editor, and canvas tests.
- [x] Run `flutter analyze --no-pub` on edited Dart files.
- [x] Mark plan tasks complete and report any unrelated failures without changing unrelated code.
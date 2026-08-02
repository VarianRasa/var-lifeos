# Canvas Node Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a structured visual Canvas workspace with drawing tools, visual elements, undo/redo, collapsed thumbnail, fixed expanded sizing, and legacy stroke compatibility.

**Architecture:** Replace string-only Canvas data with immutable typed element records stored in a nested `canvas` document. Add a shared renderer used by an interactive stateful editor and a non-interactive collapsed preview. Keep history session-local, persist only committed payload changes, and preserve the existing `OpenSubCanvasAction` integration.

**Tech Stack:** Flutter, Dart 3.11, CustomPainter, gesture recognizers, Material 3, flutter_test.

---

### Task 1: Structured Canvas domain document

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart`

- [ ] **Step 1: Write failing structured round-trip tests**

Create a payload containing stroke, text, sticky, rectangle, ellipse, and arrow elements. Assert schema/tool/background/pen settings, element order, normalized coordinates, and unknown root/nested keys survive `toData` and `fromNode`.

- [ ] **Step 2: Write failing legacy migration tests**

Feed valid and malformed legacy `strokes: List<String>` records. Assert valid records become deterministic `CanvasStroke` elements, malformed records are ignored, and writing retains legacy stroke/background summaries.

- [ ] **Step 3: Write failing validation tests**

Cover invalid schema, background/tool/color, pen width, duplicate IDs, invalid normalized points, empty text, invalid sizes, short strokes, and unsupported shapes.

- [ ] **Step 4: Run focused domain tests**

Run: `flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart --name "canvas payload" -r expanded`
Expected: FAIL before implementation.

- [ ] **Step 5: Implement typed Canvas models**

Add `CanvasPoint`, sealed `CanvasElement` hierarchy, map parsing/serialization, immutable `copyWith`, `CanvasPayload`, nested section merging, legacy readers/writers, count helpers, and validation.

- [ ] **Step 6: Re-run focused domain tests**

Expected: PASS.

### Task 2: Shared Canvas renderer

**Files:**
- Create: `lib/features/mindmap/presentation/node_editors/canvas_document_renderer.dart`
- Test: `test/features/mindmap/presentation/canvas_document_renderer_test.dart`

- [ ] **Step 1: Write failing renderer smoke tests**

Render each element type on plain, grid, and dots backgrounds at two sizes. Assert no exceptions and expected painter/widget keys exist.

- [ ] **Step 2: Implement normalized rendering**

Create a bounded `CustomPainter` that converts normalized coordinates to local pixels, paints background and ordered elements, clips bounds, and optionally paints active draft/selection decoration.

- [ ] **Step 3: Implement hit testing helpers**

Add pure helpers for topmost element hit testing, normalized bounds, point distance, and clamped movement. Keep these outside widgets for direct tests.

- [ ] **Step 4: Add hit testing tests**

Cover reverse painter order, stroke distance, shape bounds, arrow proximity, text/sticky rectangles, and movement clamping.

- [ ] **Step 5: Run renderer tests**

Run: `flutter test --no-pub test/features/mindmap/presentation/canvas_document_renderer_test.dart -r expanded`
Expected: PASS.

### Task 3: Stateful Canvas editor shell

**Files:**
- Create: `lib/features/mindmap/presentation/node_editors/canvas_node_editor.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/canvas_node_editor_test.dart`

- [ ] **Step 1: Write failing toolbar test**

Assert Select, Pen, Eraser, Text, Sticky, Rectangle, Ellipse, Arrow, color, width, background, Undo, Redo, Delete, Clear, and Open canvas controls.

- [ ] **Step 2: Implement editor state**

Own current payload, selected element ID, active gesture draft, undo stack, and redo stack. Synchronize external payload changes only when no local gesture is active.

- [ ] **Step 3: Implement toolbar and settings**

Add tool selection, color choices, continuous width slider, background control, disabled action states, and Open canvas callback.

- [ ] **Step 4: Wire knowledge editor**

Replace generic `_canvasFields` with `CanvasNodeEditor`, passing typed payload changes and the existing action callback. Avoid duplicating title/content fields.

- [ ] **Step 5: Run toolbar test**

Expected: PASS.

### Task 4: Drawing and shape gestures

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/canvas_node_editor.dart`
- Test: `test/features/mindmap/presentation/canvas_node_editor_test.dart`

- [ ] **Step 1: Write failing pen gesture test**

Drag through several points. Assert one committed stroke, normalized points, configured color/width, one undo step, and no repeated history entries during pointer movement.

- [ ] **Step 2: Implement pen gesture**

Start draft on pointer down, append distinct normalized points on move, commit valid stroke on pointer up, and discard negligible strokes.

- [ ] **Step 3: Write failing shape/arrow tests**

Drag rectangle, ellipse, and arrow. Assert correct element type, normalized geometry, and negligible gesture discard.

- [ ] **Step 4: Implement shape and arrow gestures**

Use one active geometry draft and commit on pointer up.

- [ ] **Step 5: Run gesture tests**

Expected: PASS.

### Task 5: Text, sticky, selection, move, and erase

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/canvas_node_editor.dart`
- Test: `test/features/mindmap/presentation/canvas_node_editor_test.dart`

- [ ] **Step 1: Write failing text/sticky dialog tests**

Tap workspace with Text or Sticky tool, submit content, edit existing content, cancel, and reject empty submission.

- [ ] **Step 2: Implement text/sticky dialogs**

Create elements at tapped normalized location. Reopen dialog for selected existing text/sticky elements.

- [ ] **Step 3: Write failing select/move/delete tests**

Select topmost overlapping element, drag within bounds, clamp movement, clear selection on empty tap, and delete selected element.

- [ ] **Step 4: Implement selection and movement**

Use shared hit testing, one history entry per completed move, and selected decoration.

- [ ] **Step 5: Write failing eraser test**

Touch overlapping elements and assert only the topmost hit element is removed once per gesture.

- [ ] **Step 6: Implement eraser**

Delete the first reverse-order hit and suppress repeated deletion during the same gesture.

- [ ] **Step 7: Run interaction tests**

Expected: PASS.

### Task 6: Undo, redo, and clear confirmation

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/canvas_node_editor.dart`
- Test: `test/features/mindmap/presentation/canvas_node_editor_test.dart`

- [ ] **Step 1: Write failing history tests**

Create/move/delete/edit elements, then undo and redo each operation. Assert new mutations clear redo history.

- [ ] **Step 2: Implement history operations**

Push previous committed payload once per mutation, cap history to a reasonable fixed count, and clear selection when target element disappears.

- [ ] **Step 3: Write failing clear test**

Tap Clear, cancel confirmation, then confirm. Assert cancel preserves elements and confirm clears all elements with one undo entry.

- [ ] **Step 4: Implement clear confirmation**

Use a Material confirmation dialog and disable Clear for empty documents.

- [ ] **Step 5: Run history tests**

Expected: PASS.

### Task 7: Collapsed thumbnail preview

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Write failing preview test**

Render a collapsed structured Canvas with every element family. Assert preview key, background, bounded element statistics, thumbnail renderer, Open canvas quick action where supported, and no rendering overflow.

- [ ] **Step 2: Implement bounded Canvas details**

Replace generic Canvas details with non-interactive shared renderer, compact counts, background badge, and optional Open action without capturing node drag gestures.

- [ ] **Step 3: Add small-size gesture safety test**

Assert dragging the thumbnail area still moves/selects the node rather than drawing.

- [ ] **Step 4: Run preview tests**

Run: `flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name "canvas preview" -r expanded`
Expected: PASS.

### Task 8: Fixed expanded sizing and resize behavior

**Files:**
- Modify: `lib/features/mindmap/domain/inline_node_workspace_policy.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Write failing fixed-size policy test**

Assert Canvas expanded policy returns the same large workspace size regardless of element count.

- [ ] **Step 2: Write failing resize tests**

Assert expanded Canvas ignores persisted custom dimensions and exposes no resize handles. Assert collapsed Canvas keeps manual resize callback and handles.

- [ ] **Step 3: Implement Canvas policy and expanded branches**

Add Canvas fixed workspace size to `expandedSizeForNode`, fixed-policy size branches, and expanded NodeShell no-resize condition. Leave collapsed behavior unchanged.

- [ ] **Step 4: Run sizing tests**

Expected: PASS.

### Task 9: Verification

**Files:**
- Verify all modified Canvas files.

- [ ] **Step 1: Format safe Dart files**

Run `dart format` on domain, new renderer/editor files, knowledge editor, and tests. Do not format the full `mindmap_canvas.dart`; patch it with bounded streaming replacement.

- [ ] **Step 2: Run all focused Canvas tests**

Run domain, renderer, editor, preview, sizing, and resize tests. Expected: PASS.

- [ ] **Step 3: Run targeted analyzer**

Analyze all modified Canvas files and tests. Expected: no new issues.

- [ ] **Step 4: Check whitespace**

Run `git diff --check -- <modified files>`. Expected: no whitespace errors; existing LF/CRLF warnings are informational.

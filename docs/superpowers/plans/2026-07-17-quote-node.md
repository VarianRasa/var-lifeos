# Quote Node Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a collection-focused Quote node with structured metadata, tag management, favorite and copy actions, adaptive collapsed preview, autosave, and fixed expanded sizing.

**Architecture:** Extend existing `QuotePayload` additively, keep all draft persistence through `applyNodeTypeInlineDraft`, enhance existing knowledge editor, and render collapsed actions through `_QuoteNodeDetails`. Reuse Flutter clipboard, Material controls, and existing node sizing policy.

**Tech Stack:** Flutter, Dart, Material 3, existing inline autosave pipeline, `flutter_test`.

---

### Task 1: Quote payload

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart`

- [ ] Add failing round-trip test for collection, normalized tags, favorite, and foreign-key preservation.
- [ ] Extend `QuotePayload` fields, `fromNode`, `copyWith`, and `toData`.
- [ ] Run focused payload test.

### Task 2: Quote editor

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`

- [ ] Add failing editor test for author, source, collection, tags, favorite, and copy.
- [ ] Add collection field, tag chip add/edit/remove, favorite toggle, and clipboard action.
- [ ] Keep fields inside normal `EditableText` shortcut flow.
- [ ] Run focused editor test.

### Task 3: Quote sizing and collapsed preview

**Files:**
- Modify: `lib/features/mindmap/domain/inline_node_workspace_policy.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] Add failing auto-size and collapsed overflow tests.
- [ ] Add Quote-specific expanded size and disable expanded resize.
- [ ] Replace broken quote glyph strings with valid Unicode.
- [ ] Render adaptive metadata, tags, favorite, and copy action.
- [ ] Run focused canvas tests.

### Task 4: Validation

**Files:**
- Verify all modified files.

- [ ] Run `dart format` on modified Dart files.
- [ ] Run focused Quote tests.
- [ ] Run analyzer on modified Dart files.
- [ ] Record unrelated failures without changing them.
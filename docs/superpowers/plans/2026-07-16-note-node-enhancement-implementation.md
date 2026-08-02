# Knowledge Note Node Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a responsive Markdown knowledge-note workspace with sources, attachments, metadata, search, and polished collapsed rendering.

**Architecture:** Store note-only metadata in a versioned `NotePayload`, while title/body/tags/pin/relations remain first-class `MindmapNode` fields. Route note nodes through a dedicated editor using `flutter_markdown_plus`; reuse existing attachment and node mutation callbacks.

**Tech Stack:** Flutter Material 3, Dart 3.11, `flutter_markdown_plus`, `url_launcher`, Flutter widget tests.

---

### Task 1: Add Markdown dependency and note payload
- [ ] Add `flutter_markdown_plus` dependency.
- [ ] Add `NoteSourceLink` and `NotePayload` with safe parsing and validation.
- [ ] Route inline draft creation/application through `NotePayload`.
- [ ] Add payload regression tests.

### Task 2: Build responsive knowledge-note editor
- [ ] Create dedicated note editor with wide split and narrow toggle layouts.
- [ ] Add Markdown toolbar, preview, counts, search, and table of contents.
- [ ] Add pin, color, tags, source CRUD/open, attachment callbacks, and related-node summary.
- [ ] Route `NodeType.note` to the editor.

### Task 3: Polish collapsed note and sizing
- [ ] Add Markdown-derived excerpt and metadata indicators.
- [ ] Increase expanded note policy for split workspace.
- [ ] Verify standard collapsed size has no overflow.

### Task 4: Validate
- [ ] Run formatter, focused tests, analyzer, and diff checks.
# Live Board Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add eight built-in board templates and source-linked user templates that accelerate project and nested-board creation.

**Architecture:** Persist only user-template metadata and resolve source boards live. Reuse one pure clone/remap helper for template instantiation and nested selection copy, then connect gallery and management UI to Riverpod providers and existing atomic board writes.

**Tech Stack:** Flutter, Dart 3.11.4, Riverpod, Sembast, existing UUID and canvas infrastructure.

## Global Constraints

- No new package or generated-file edits.
- User templates reference active project boards in one workspace.
- Board-reference objects never enter instantiated content.
- Invalid connectors and parent relationships are removed safely.
- Source Trash/deletion removes template from available results.
- No partial board writes.
- No commits unless user explicitly requests one.

---

### Task 1: Shared Object Clone Helper

**Files:**
- Create: `lib/features/mindmap/domain/canvas_object_clone.dart`
- Modify: `lib/features/mindmap/application/nested_board_service.dart`
- Create: `test/features/mindmap/domain/canvas_object_clone_test.dart`

**Interfaces:**
- Produces: `cloneCanvasObjects(Iterable<CanvasObject>, {required String Function() idFactory, required DateTime now, bool excludeBoardReferences = false})`.

- [ ] Write failing tests for ID remap, frame/column parents, ordered children, connector endpoints, board-reference exclusion, and orphan connector removal.
- [ ] Run `flutter test test/features/mindmap/domain/canvas_object_clone_test.dart`; expect missing helper failure.
- [ ] Implement pure two-pass clone and cleanup.
- [ ] Replace private nested-board clone logic with helper.
- [ ] Run clone and nested-board service tests; expect PASS.

### Task 2: Template Metadata and Built-ins

**Files:**
- Create: `lib/features/mindmap/domain/canvas_board_template.dart`
- Modify: `lib/features/mindmap/domain/canvas_board.dart`
- Create: `test/features/mindmap/domain/canvas_board_template_test.dart`
- Modify: `test/features/mindmap/domain/canvas_board_test.dart`

**Interfaces:**
- Produces: `CanvasBoardTemplate`, `BuiltInCanvasBoardTemplate`, `builtInCanvasBoardTemplates`, and all eight `CanvasProjectTemplate` values.

- [ ] Write failing codec, validation, eight-definition, and template-object tests.
- [ ] Run domain tests; expect missing symbols/enum values.
- [ ] Implement immutable metadata and eight minimal built-in layouts using existing canvas objects.
- [ ] Run domain tests; expect PASS.

### Task 3: Template Repository

**Files:**
- Create: `lib/features/mindmap/domain/canvas_board_template_repository.dart`
- Create: `lib/features/mindmap/data/canvas_board_template_repositories.dart`
- Create: `test/features/mindmap/data/canvas_board_template_repositories_test.dart`

**Interfaces:**
- Produces: `listTemplates`, `saveTemplate`, `deleteTemplate` for memory and Sembast repositories.

- [ ] Write shared repository contract for save, rename replacement, delete, deterministic ordering, and malformed records.
- [ ] Run repository test; expect missing repository failure.
- [ ] Implement memory map and Sembast `canvas_board_templates` store.
- [ ] Run repository test; expect PASS.

### Task 4: Live Template Service

**Files:**
- Create: `lib/features/mindmap/application/board_template_service.dart`
- Modify: `lib/features/mindmap/application/nested_board_service.dart`
- Create: `test/features/mindmap/application/board_template_service_test.dart`

**Interfaces:**
- Produces: `availableUserTemplates`, `saveSourceAsTemplate`, `renameTemplate`, `deleteTemplate`, `instantiateUserTemplate`, `instantiateBuiltInTemplate`.

- [ ] Write failing tests for active-source save, live updates, Trash/deletion filtering, rename/delete, clone cleanup, and failed-source no-write behavior.
- [ ] Run service test; expect missing service failure.
- [ ] Implement validation and live board resolution.
- [ ] Add template-object input to nested creation while preserving atomic parent/child save.
- [ ] Run service and nested-board tests; expect PASS.

### Task 5: Providers

**Files:**
- Modify: `lib/features/mindmap/application/mindmap_providers.dart`
- Test: `test/features/mindmap/application/mindmap_providers_test.dart`

**Interfaces:**
- Produces: `canvasBoardTemplateRepositoryProvider`, `boardTemplateServiceProvider`, and workspace-family available-template provider.

- [ ] Write provider override/invalidation test.
- [ ] Run provider test; expect missing provider failure.
- [ ] Wire Sembast repository and service using existing database/board providers.
- [ ] Run provider test; expect PASS.

### Task 6: Creation Gallery

**Files:**
- Modify: `lib/features/workspace/workspace_detail_page.dart`
- Modify: `test/features/workspace/workspace_detail_page_test.dart`

**Interfaces:**
- Consumes providers and service from Tasks 4–5.

- [ ] Write widget tests for eight built-ins, search, user template preview, selection, source-unavailable error, and nested creation.
- [ ] Run workspace test; expect missing gallery behavior.
- [ ] Replace hardcoded Project Plan choice with searchable gallery and existing preview painter.
- [ ] Invalidate board/template providers after successful creation.
- [ ] Run workspace test; expect PASS.

### Task 7: Settings Management

**Files:**
- Modify: `lib/features/settings/settings_page.dart`
- Modify: `test/features/settings/settings_page_test.dart`

**Interfaces:**
- Consumes template providers and workspace board list.

- [ ] Write widget tests for save board as template, rename, delete, search, and source Trash disappearance.
- [ ] Run settings test; expect missing board-template management.
- [ ] Add board-template subsection using existing card/dialog patterns and accessible labels.
- [ ] Run settings test; expect PASS.

### Task 8: Verification

- [ ] Run targeted domain, data, application, workspace, and settings tests.
- [ ] Run `dart format --set-exit-if-changed .`.
- [ ] Run `flutter analyze`.
- [ ] Run `flutter test`; record any verified baseline failures separately.

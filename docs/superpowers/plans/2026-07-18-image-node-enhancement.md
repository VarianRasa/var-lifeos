# Image Node Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Build a complete image-node workflow with metadata, transforms, annotations, derived attachment save, and polished collapsed preview.

**Architecture:** Extend ImagePayload with normalized edit state and annotations. Keep raster rendering in a focused image renderer, route persistence through existing media actions and attachment repository, and reuse ImageNodePreview for editor and collapsed rendering.

**Tech Stack:** Flutter, Dart, Riverpod, dart:ui image codecs and PictureRecorder, existing node attachment repository.

---

### Task 1: Image Payload Model

**Files:**
- Modify: lib/features/mindmap/domain/node_type_payloads.dart
- Test: test/features/mindmap/domain/node_type_payloads_test.dart

- [ ] Add immutable ImageAnnotation, ImageCrop, ImageAdjustments, and image filter values using normalized coordinates.
- [ ] Extend ImagePayload parsing, copyWith, serialization, equality support, and validation.
- [ ] Add round-trip, clamping, malformed annotation, and restore-source tests.
- [ ] Run flutter test test/features/mindmap/domain/node_type_payloads_test.dart.

### Task 2: Raster Rendering

**Files:**
- Create: lib/features/mindmap/presentation/node_editors/image_edit_renderer.dart
- Test: test/features/mindmap/presentation/image_edit_renderer_test.dart

- [ ] Decode input bytes with ui.instantiateImageCodec.
- [ ] Apply crop, quarter-turn rotation, flips, brightness, contrast, saturation, and annotation paint operations.
- [ ] Encode final output as PNG bytes and return dimensions.
- [ ] Add tiny-image render tests covering transform and annotations.

### Task 3: Persistence Actions

**Files:**
- Modify: lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart
- Modify: lib/features/calendar/day_page.dart
- Modify: lib/features/mindmap/presentation/mindmap_canvas.dart
- Test: test/features/mindmap/presentation/image_node_editor_test.dart

- [ ] Add save-derived, remove, restore, copy, external-open, and lightbox actions.
- [ ] Persist rendered bytes as a new attachment before switching active attachment ID.
- [ ] Preserve originalAttachmentId and leave current payload unchanged when saving fails.
- [ ] Add callback tests for every action.

### Task 4: Image Editor UI

**Files:**
- Modify: lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart
- Test: test/features/mindmap/presentation/image_node_editor_test.dart

- [ ] Add metadata fields for source URL, caption, alt text, and editable tag chips.
- [ ] Add transform controls for crop preset, rotate, flip, brightness, contrast, saturation, and filters.
- [ ] Add annotation toolbar for text, arrow, rectangle, freehand, colors, thickness, select, delete, undo, and redo.
- [ ] Add before-after preview and save-as-new-image progress state.
- [ ] Keep expanded editor content-sized and non-resizable through existing node presentation policy.

### Task 5: Preview and Lightbox

**Files:**
- Modify: lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart
- Modify: lib/features/mindmap/presentation/mindmap_canvas.dart
- Test: test/features/mindmap/presentation/image_node_editor_test.dart
- Test: test/features/mindmap/presentation/mindmap_canvas_test.dart

- [ ] Render transforms and focal-point alignment in ImageNodePreview.
- [ ] Show caption and at most three tags in collapsed mode.
- [ ] Open a zoomable and pannable lightbox when preview is tapped.
- [ ] Preserve retry and missing-attachment feedback.

### Task 6: Platform Actions

**Files:**
- Create: lib/features/mindmap/presentation/node_editors/image_platform_actions.dart
- Create: lib/features/mindmap/presentation/node_editors/image_platform_actions_io.dart
- Create: lib/features/mindmap/presentation/node_editors/image_platform_actions_web.dart
- Test: test/features/mindmap/presentation/image_platform_actions_io_test.dart

- [ ] Export, copy, and external-open active image using platform-safe adapters.
- [ ] Return explicit unsupported errors instead of silent failures.
- [ ] Verify Windows export and external-open paths.

### Task 7: Verification

**Files:**
- Modify: docs/superpowers/specs/2026-07-18-image-node-enhancement-design.md only if implementation constraints require clarification.

- [ ] Run dart format on changed files.
- [ ] Run flutter analyze and require no issues.
- [ ] Run payload, renderer, editor, canvas, and platform tests.
- [ ] Run flutter build windows.
- [ ] Manually smoke import, edit, annotate, save as new, restore original, export, and collapsed lightbox on Windows.

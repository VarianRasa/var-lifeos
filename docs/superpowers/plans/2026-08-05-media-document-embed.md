# Media and Document Embed Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Milanote-style media and document embed cards with quick drop auto-classification.

**Architecture:** Extend `NodeType` enum with `media` and `document`, add domain payloads `MediaPayload` & `DocumentPayload`, update drop classifier, and render canvas card widgets.

**Tech Stack:** Dart, Flutter, Riverpod, Sembast.

---

### Task 1: Update NodeType Enum & Domain Payloads

**Files:**
- Modify: `lib/core/constants/app_constants.dart`
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Test: `test/features/mindmap/domain/mindmap_node_data_test.dart`

- [ ] **Step 1: Write failing test for MediaPayload & DocumentPayload**

```dart
// test/features/mindmap/domain/mindmap_node_data_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';

void main() {
  test('MediaPayload serializes to and from node data', () {
    final payload = MediaPayload(
      urlOrPath: 'assets/video.mp4',
      mimeType: 'video/mp4',
      fileName: 'video.mp4',
      fileSize: 1024,
    );
    final data = payload.toData();
    final reconstructed = MediaPayload.fromData(data);
    expect(reconstructed.fileName, 'video.mp4');
    expect(reconstructed.mimeType, 'video/mp4');
  });

  test('DocumentPayload serializes to and from node data', () {
    final payload = DocumentPayload(
      urlOrPath: 'docs/paper.pdf',
      mimeType: 'application/pdf',
      fileName: 'paper.pdf',
      fileSize: 2048,
    );
    final data = payload.toData();
    final reconstructed = DocumentPayload.fromData(data);
    expect(reconstructed.fileName, 'paper.pdf');
    expect(reconstructed.mimeType, 'application/pdf');
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/mindmap/domain/mindmap_node_data_test.dart`

- [ ] **Step 3: Implement Enum & Payloads**

Add `media` and `document` to `NodeType` in `lib/core/constants/app_constants.dart`.
Add `MediaPayload` and `DocumentPayload` classes to `lib/features/mindmap/domain/node_type_payloads.dart`.

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/mindmap/domain/mindmap_node_data_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/core/constants/app_constants.dart lib/features/mindmap/domain/node_type_payloads.dart test/features/mindmap/domain/mindmap_node_data_test.dart
git commit -m "feat: add media and document NodeType and payloads"
```

---

### Task 2: Quick Drop File Classifier Update

**Files:**
- Modify: `lib/features/mindmap/application/canvas_file_drop_handler.dart`
- Test: `test/features/mindmap/application/canvas_quick_drop_test.dart`

- [ ] **Step 1: Write failing test for media and document classification**

```dart
test('classifies media and document files correctly', () {
  expect(classifyCanvasQuickDropContent(fileName: 'demo.mp4'), QuickDropKind.media);
  expect(classifyCanvasQuickDropContent(fileName: 'song.mp3'), QuickDropKind.media);
  expect(classifyCanvasQuickDropContent(fileName: 'report.pdf'), QuickDropKind.document);
  expect(classifyCanvasQuickDropContent(fileName: 'notes.docx'), QuickDropKind.document);
});
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/mindmap/application/canvas_quick_drop_test.dart`

- [ ] **Step 3: Implement QuickDropKind & Classification**

Update `QuickDropKind` enum and `classifyCanvasQuickDropContent` in `canvas_file_drop_handler.dart`.

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/mindmap/application/canvas_quick_drop_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/application/canvas_file_drop_handler.dart test/features/mindmap/application/canvas_quick_drop_test.dart
git commit -m "feat: support media and document file classification"
```

---

### Task 3: System Enum Compatibility & UI Card Rendering

**Files:**
- Modify: `lib/core/theme/node_visuals.dart`
- Modify: `lib/features/mindmap/domain/node_presentation.dart`
- Modify: `lib/features/mindmap/domain/inline_node_workspace_policy.dart`
- Modify: `lib/features/mindmap/presentation/add_node_dialog.dart`
- Modify: `lib/features/mindmap/application/inline_node_workspace_controller.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Fix all exhaustive switch-case lint errors**

Update all switch-cases across visual, presentation, policy, and controller files to support `NodeType.media` & `NodeType.document`.

- [ ] **Step 2: Render Media & Document Cards in MindmapCanvas**

Add `_MediaNodeCard` and `_DocumentNodeCard` widgets inside `lib/features/mindmap/presentation/mindmap_canvas.dart`.

- [ ] **Step 3: Verify with tests and analyzer**

Run: `flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart`
Run: `flutter analyze`

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "feat: render media and document embed cards and fix exhaustive enum handling"
```

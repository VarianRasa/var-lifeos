# Sticky Notes & Canvas Quick Drop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `NodeType.sticky` (square pastel notes) and smart drag-and-drop / paste classification (URLs to Link, images to Image, text to Sticky) on `MindmapCanvas`.

**Architecture:** Add `NodeType.sticky` to constants/payloads, build `StickyPayload` and `StickyNodeCard` presentation, and wire smart dropped content classifier in `lib/features/mindmap/application/canvas_file_drop_handler.dart` and `lib/features/mindmap/presentation/mindmap_canvas.dart`.

**Tech Stack:** Flutter, Dart, Riverpod.

## Global Constraints
- Target SDK/Platform: Flutter Desktop / Web / Mobile.
- Quality: All new code must pass `flutter analyze` and unit/widget tests.

---

### Task 1: Add `NodeType.sticky` and `StickyPayload` Domain Model

**Files:**
- Modify: `lib/core/constants/app_constants.dart`
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Test: `test/features/mindmap/domain/mindmap_node_data_test.dart`

**Interfaces:**
- Produces: `NodeType.sticky` enum, `StickyPayload` class, `stickyPayloadFromData(...)`, and `dataWithStickyPayload(...)`.

- [ ] **Step 1: Write failing domain unit test for StickyPayload**

```dart
test('StickyPayload parses defaults and custom values', () {
  final empty = stickyPayloadFromData({});
  expect(empty.color, equals('yellow'));
  expect(empty.fontSize, equals('medium'));

  final custom = stickyPayloadFromData({'color': 'pink', 'fontSize': 'large'});
  expect(custom.color, equals('pink'));
  expect(custom.fontSize, equals('large'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/mindmap/domain/mindmap_node_data_test.dart --name "StickyPayload"`
Expected: FAIL (unresolved identifier)

- [ ] **Step 3: Implement `NodeType.sticky` and `StickyPayload`**

Add `sticky` to `NodeType` enum and implement `StickyPayload` data helpers.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/domain/mindmap_node_data_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/constants/app_constants.dart lib/features/mindmap/domain/node_type_payloads.dart test/features/mindmap/domain/mindmap_node_data_test.dart
git commit -m "feat(mindmap): add NodeType.sticky and StickyPayload domain model"
```

---

### Task 2: Smart Canvas Quick Drop Classifier Logic

**Files:**
- Modify: `lib/features/mindmap/application/canvas_file_drop_handler.dart`
- Create: `test/features/mindmap/application/canvas_quick_drop_test.dart`

**Interfaces:**
- Produces: `classifyCanvasQuickDropContent(String input)` returning `NodeType.link`, `NodeType.image`, or `NodeType.sticky`.

- [ ] **Step 1: Write failing unit test for content classification**

```dart
test('classifyCanvasQuickDropContent classifies URLs, images, and text correctly', () {
  expect(classifyCanvasQuickDropContent('https://example.com'), equals(NodeType.link));
  expect(classifyCanvasQuickDropContent('photo.png'), equals(NodeType.image));
  expect(classifyCanvasQuickDropContent('Meeting notes for today'), equals(NodeType.sticky));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/mindmap/application/canvas_quick_drop_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement content classifier function**

Implement `classifyCanvasQuickDropContent` logic in `canvas_file_drop_handler.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/application/canvas_quick_drop_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/application/canvas_file_drop_handler.dart test/features/mindmap/application/canvas_quick_drop_test.dart
git commit -m "feat(mindmap): add smart canvas quick drop content classifier"
```

---

### Task 3: Render `NodeType.sticky` Card and Canvas Integration

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

**Interfaces:**
- Consumes: `NodeType.sticky` and `StickyPayload` from Task 1, content classifier from Task 2.

- [ ] **Step 1: Write failing widget test for sticky note rendering on canvas**

```dart
testWidgets('MindmapCanvas renders sticky note card with pastel color', (tester) async {
  // Test rendering of sticky node
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart --name "sticky note"`
Expected: FAIL

- [ ] **Step 3: Implement sticky note rendering and drag-drop auto-node creation in MindmapCanvas**

Add sticky node widget rendering with pastel backgrounds (`yellow`, `pink`, `mint`, `sky`, `purple`, `orange`) and connect clipboard/drop listeners to paste/drop as sticky notes or detected URLs/images.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/presentation/mindmap_canvas_test.dart
git commit -m "feat(mindmap): render sticky note cards and integrate smart canvas drop"
```

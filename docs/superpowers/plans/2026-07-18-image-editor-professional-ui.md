# Image Editor Professional UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert expanded image-node editor into a polished fixed-size two-column studio with grouped inspector sections, responsive fallback, and persistent actions.

**Architecture:** Keep image behavior inside existing `_ImageEditor` state and add small private presentation widgets in the same editor file. Use `LayoutBuilder` for two-column versus stacked layout, keep footer outside scrolling content, and change only expanded-size policy plus tests.

**Tech Stack:** Flutter Material 3, Dart, existing `ImagePayload` and media action callbacks, Flutter widget tests.

---

### Task 1: Lock Professional Workspace Size

**Files:**
- Modify: `lib/features/mindmap/domain/inline_node_workspace_policy.dart`
- Test: `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`

- [ ] **Step 1: Change image policy test to 900 by 820**

```dart
expect(
  InlineNodeWorkspacePolicy.expandedSizeForNode(node),
  const InlineNodeWorkspaceSize(900, 820),
);
```

- [ ] **Step 2: Run policy test and verify failure**

Run: `flutter test test/features/mindmap/domain/inline_node_workspace_policy_test.dart --name "image editor uses fixed size"`

Expected: FAIL because current image size is 760 by 1040.

- [ ] **Step 3: Update image workspace constant**

```dart
static const InlineNodeWorkspaceSize image = InlineNodeWorkspaceSize(
  900,
  820,
);
```

- [ ] **Step 4: Run policy and fixed resize tests**

Run:

```powershell
flutter test test/features/mindmap/domain/inline_node_workspace_policy_test.dart --name "image editor uses fixed size"
flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart --name "expanded image uses fixed content size"
```

Expected: both PASS.

### Task 2: Add Responsive Studio Layout Tests

**Files:**
- Modify: `test/features/mindmap/presentation/image_node_editor_test.dart`

- [ ] **Step 1: Add wide studio structure test**

```dart
testWidgets('image editor uses professional two-column studio', (tester) async {
  await tester.pumpWidget(
    _appAtSize(
      buildNodeTypeInlineEditor(_context(<Object>[], <Object>[])),
      const Size(900, 820),
    ),
  );

  expect(find.byKey(const ValueKey('image-editor-two-column')), findsOneWidget);
  expect(find.byKey(const ValueKey('image-preview-panel')), findsOneWidget);
  expect(find.byKey(const ValueKey('image-inspector-source')), findsOneWidget);
  expect(find.byKey(const ValueKey('image-inspector-details')), findsOneWidget);
  expect(find.byKey(const ValueKey('image-inspector-adjustments')), findsOneWidget);
  expect(find.byKey(const ValueKey('image-inspector-annotations')), findsOneWidget);
  expect(find.byKey(const ValueKey('image-editor-footer')), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Add narrow fallback test**

```dart
testWidgets('image editor stacks without overflow on narrow width', (tester) async {
  await tester.pumpWidget(
    _appAtSize(
      buildNodeTypeInlineEditor(_context(<Object>[], <Object>[])),
      const Size(640, 820),
    ),
  );

  expect(find.byKey(const ValueKey('image-editor-stacked')), findsOneWidget);
  expect(find.byKey(const ValueKey('image-editor-footer')), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 3: Add sized test scaffold helper**

```dart
Widget _appAtSize(Widget child, Size size) => MaterialApp(
  home: Scaffold(body: SizedBox.fromSize(size: size, child: child)),
);
```

- [ ] **Step 4: Run new tests and verify failure**

Run: `flutter test test/features/mindmap/presentation/image_node_editor_test.dart --name "professional two-column studio|stacks without overflow"`

Expected: FAIL because layout keys and section widgets do not exist.

### Task 3: Build Studio Panels and Inspector Sections

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart`

- [ ] **Step 1: Replace preset-only layout decision with constraints**

```dart
return LayoutBuilder(
  builder: (context, constraints) {
    final useTwoColumns = constraints.maxWidth >= 720;
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: useTwoColumns
                ? _buildTwoColumnStudio(...)
                : _buildStackedStudio(...),
          ),
          const SizedBox(height: 12),
          _ImageEditorFooter(...),
        ],
      ),
    );
  },
);
```

- [ ] **Step 2: Build preview panel**

Add `_ImagePreviewPanel` with:

```dart
DecoratedBox(
  key: const ValueKey('image-preview-panel'),
  decoration: BoxDecoration(
    color: colors.surfaceContainerLow,
    border: Border.all(color: colors.outlineVariant),
    borderRadius: BorderRadius.circular(16),
  ),
  child: Column(
    children: [
      Expanded(child: preview),
      sourceStatus,
      transformToolbar,
    ],
  ),
);
```

Toolbar contains fit dropdown, rotate, flip, undo, and redo with tooltips and 40-pixel targets.

- [ ] **Step 3: Build reusable inspector section**

```dart
class _ImageInspectorSection extends StatelessWidget {
  const _ImageInspectorSection({
    required this.sectionKey,
    required this.icon,
    required this.title,
    required this.children,
  });

  final Key sectionKey;
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: sectionKey,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(title)]),
          const SizedBox(height: 12),
          ...children,
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: Group existing controls without behavior changes**

Create section keys:

```dart
const ValueKey('image-inspector-source')
const ValueKey('image-inspector-details')
const ValueKey('image-inspector-adjustments')
const ValueKey('image-inspector-annotations')
```

Move existing fields and callbacks into these groups. Preserve current field keys, `_emit` calls, dropdown values, sliders, annotation creation, and semantic draft synchronization.

- [ ] **Step 5: Polish tag input and annotation tools**

Add tag submit suffix button:

```dart
suffixIcon: IconButton(
  tooltip: 'Add tag',
  onPressed: () => _addTag(_tagController.text),
  icon: const Icon(Icons.add_rounded),
),
```

Use icon-plus-label annotation buttons while preserving keys `image-annotation-add-<type>`.

- [ ] **Step 6: Run image editor tests**

Run: `flutter test test/features/mindmap/presentation/image_node_editor_test.dart`

Expected: all tests PASS.

### Task 4: Polish Adjustments and Footer

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart`
- Test: `test/features/mindmap/presentation/image_node_editor_test.dart`

- [ ] **Step 1: Upgrade adjustment slider header**

Update `_ImageAdjustmentSlider` to show label, reset button, and one-decimal value above slider. Reset calls `onChanged(0)` and disables itself when value is zero.

- [ ] **Step 2: Build sticky footer**

Add `_ImageEditorFooter` with key `image-editor-footer`, top divider, grouped actions, filled primary save action, and error-colored outlined remove action. Preserve every current callback and conditional action.

- [ ] **Step 3: Verify action behavior remains intact**

Run: `flutter test test/features/mindmap/presentation/image_node_editor_test.dart --name "emits media actions|remote editor emits open action|autosaves tags"`

Expected: all selected tests PASS.

### Task 5: Final Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Format files**

Run:

```powershell
dart format lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart lib/features/mindmap/domain/inline_node_workspace_policy.dart test/features/mindmap/presentation/image_node_editor_test.dart test/features/mindmap/domain/inline_node_workspace_policy_test.dart
```

- [ ] **Step 2: Run targeted tests**

```powershell
flutter test test/features/mindmap/presentation/image_node_editor_test.dart
flutter test test/features/mindmap/domain/inline_node_workspace_policy_test.dart --name "image editor uses fixed size"
flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart --name "expanded image uses fixed content size"
```

Expected: all PASS with no layout exceptions.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4: Build Windows release**

Run: `flutter build windows`

Expected: `Built build\windows\x64\runner\Release\var_app.exe`

## Execution Choice

Use inline execution in this session. Subagent execution is not used because no delegation was requested.

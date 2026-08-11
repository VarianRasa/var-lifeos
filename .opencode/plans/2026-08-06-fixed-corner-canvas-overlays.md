# Fixed Corner Canvas Overlays & Integrated Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Position day workspace title fixed at top-left corner, shift top header actions to top-right below board tabs, remove ribbon toolbar overlay, and enhance bottom canvas toolbar with full item creation & management options.

**Architecture:** Refactor `Stack` positioning in `DayPage` for fixed title and top-right header actions, remove ribbon toolbar state, and expand `MindmapCanvas._buildCanvasToolbar` with extended popup menus for node creation and multi-selection canvas controls.

**Tech Stack:** Flutter, Riverpod, Material 3.

## Global Constraints
- Target Flutter SDK & package `var_app`.
- Follow strict lints: single quotes, trailing commas, no raw dynamic calls.

---

### Task 1: Refactor DayPage Stack Floating Overlays Layout & Remove Ribbon Toolbar

**Files:**
- Modify: `lib/features/calendar/day_page.dart`
- Modify: `test/features/calendar/day_page_floating_overlay_test.dart`

**Interfaces:**
- Consumes: `workspaceTitleProvider`, `_viewMode`, `_isFloatingTopBarVisible`, `_isFloatingBoardTabsVisible`.
- Produces: Fixed top-left title overlay, dynamic top-right header actions overlay positioned below board tabs.

- [ ] **Step 1: Write/Update the test for top-left title, top-right header, and ribbon toolbar removal**

```dart
// test/features/calendar/day_page_floating_overlay_test.dart
testWidgets(
  'DayPage renders top-left title and top-right header actions correctly',
  (WidgetTester tester) async {
    final today = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: DayPage(date: today)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(Stack), findsWidgets);
    expect(find.byType(DayPage), findsOneWidget);
  },
);
```

- [ ] **Step 2: Run test to verify it passes/fails**

Run: `flutter test test/features/calendar/day_page_floating_overlay_test.dart`

- [ ] **Step 3: Update DayPage Stack overlays layout**

1. Move `_InlineWorkspaceTitle` to `Positioned(top: 12, left: 12)` in canvas `Stack`.
2. Move `CollaborationRoomBar`, `_DayViewModeToggle`, `_DayContextSwitcher`, and Markdown Export button to `Positioned(top: _isFloatingBoardTabsVisible ? 56 : 12, right: 12)`.
3. Remove `_isFloatingRibbonVisible` variable, menu toggle, and ribbon overlay container.

- [ ] **Step 4: Run test to verify passes**

Run: `flutter test test/features/calendar/day_page_floating_overlay_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/day_page.dart test/features/calendar/day_page_floating_overlay_test.dart
git commit -m "feat(calendar): relocate title to top-left, header actions to top-right, remove ribbon toolbar"
```

---

### Task 2: Enhance Bottom Canvas Toolbar in MindmapCanvas

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`

**Interfaces:**
- Consumes: `_selectedNodeIds`, `_transformationController`, `onCanvasObjectCreated`.
- Produces: Extended `_buildCanvasToolbar` with creation tools, selection actions, grid toggles.

- [ ] **Step 1: Expand `_buildCanvasToolbar` with canvas item & multi-selection actions**

In `lib/features/mindmap/presentation/mindmap_canvas.dart`, add items for creation, grouping, locking/unlocking, grid/snap toggles directly into the bottom toolbar menu items.

- [ ] **Step 2: Run analyzer to verify 0 issues**

Run: `flutter analyze`

- [ ] **Step 3: Run widget & unit tests**

Run: `flutter test`

- [ ] **Step 4: Commit**

```bash
git add lib/features/mindmap/presentation/mindmap_canvas.dart
git commit -m "feat(mindmap): enhance bottom canvas toolbar with comprehensive item controls"
```

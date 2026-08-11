# DayPage Modular Floating Canvas Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `DayPage` canvas controls to overlay as 3 stacked modular floating bars over a 100% full-screen canvas, with individual collapse handles and Desktop `View` menu integration.

**Architecture:** Wrap the canvas and floating control bars in a `Stack` within `DayPage`. Manage state for individual floating bar visibilities (`isFloatingTopBarVisible`, `isFloatingRibbonVisible`, `isFloatingBoardTabsVisible`). Integrate menu toggles into `App` menu system.

**Tech Stack:** Flutter, Riverpod, Material 3.

## Global Constraints
- Material 3 dark-first styling.
- Non-blocking overlay touch/gesture pass-through for canvas areas outside floating bars.
- Zero `flutter analyze` errors or warnings.

---

### Task 1: Add Floating Overlay State & Layout Shell in DayPage

**Files:**
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/calendar/day_page_floating_overlay_test.dart`

**Interfaces:**
- Consumes: Existing `DayCanvasTabHeader`, `_MindmapDocumentCanvasToolbar`, `_DayToolsBar`, and `MindmapCanvas`.
- Produces: Floating stack layout for canvas mode and state fields `_isFloatingTopBarVisible`, `_isFloatingRibbonVisible`, `_isFloatingBoardTabsVisible`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/calendar/day_page_floating_overlay_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:var_app/features/calendar/day_page.dart';

void main() {
  testWidgets('DayPage renders canvas as stack background with floating controls overlay', (WidgetTester tester) async {
    final today = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DayPage(day: today),
        ),
      ),
    );
    await tester.pumpAndSettle();
    
    expect(find.byType(Stack), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails/passes**

Run: `flutter test test/features/calendar/day_page_floating_overlay_test.dart`

- [ ] **Step 3: Refactor DayPage canvas layout into Stack with modular floating containers**

In `lib/features/calendar/day_page.dart`:
Add state variables:
```dart
bool _isFloatingTopBarVisible = true;
bool _isFloatingRibbonVisible = true;
bool _isFloatingBoardTabsVisible = true;
```
Wrap canvas body and toolbars in a `Stack` overlay layout when `_viewMode == _DayViewMode.canvas`, styled with `Card`/`Container` translucent surface decoration (`Theme.of(context).colorScheme.surface.withValues(alpha: 0.85)`), blur/shadow, and individual hide/show mini floating handles.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/calendar/day_page_floating_overlay_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/day_page.dart test/features/calendar/day_page_floating_overlay_test.dart
git commit -m "feat(calendar): implement modular floating canvas overlay stack in DayPage"
```

---

### Task 2: Add Desktop View Menu Toggles for Floating Canvas Controls

**Files:**
- Modify: `lib/app.dart` or desktop platform menu integration files
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/calendar/day_page_floating_overlay_test.dart`

- [ ] **Step 1: Write test for menu toggle actions**

Add test cases in `test/features/calendar/day_page_floating_overlay_test.dart` to verify floating bar visibility toggle handlers work correctly.

- [ ] **Step 2: Implement keyboard shortcuts and Desktop View menu items**

Add `CallbackShortcuts` / `PlatformMenuBar` menu items for `View`:
- `Toggle Top Header Bar` (`Ctrl+Alt+1`)
- `Toggle Ribbon Toolbar` (`Ctrl+Alt+2`)
- `Toggle Board Tabs` (`Ctrl+Alt+3`)
- `Hide/Show All Canvas Controls` (`Ctrl+Shift+H`)

- [ ] **Step 3: Run flutter analyze and tests**

Run: `flutter analyze`
Run: `flutter test`

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "feat(calendar): add View menu shortcuts & toggles for floating canvas controls"
```

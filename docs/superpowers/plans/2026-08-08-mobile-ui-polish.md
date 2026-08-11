# Mobile UI Polish & Compact Header Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean up the stacked headers on compact mobile screens (< 600px width) by introducing a compact top header bar and a unified mobile tools bottom sheet.

**Architecture:** Conditional rendering in `day_page.dart` depending on `MediaQuery.sizeOf(context).width < 600`. Static header stack (`_DayToolsBar`, `_MindmapMobileToolbar`) will be replaced on compact screens with a single-line compact header bar that triggers a unified `_showMobileToolsSheet`.

**Tech Stack:** Flutter, Riverpod, Material 3.

## Global Constraints
- Target mobile screen width threshold: `MediaQuery.sizeOf(context).width < 600`.
- Maintain dark-first M3 visual style (`AppColors`, `AppDesignTokens`).
- All existing tests in `test/features/calendar/day_page_test.dart` and `test/features/calendar/day_canvas_tab_header_test.dart` must pass.

---

### Task 1: Compact Mobile Top Header Component & Layout Refactor

**Files:**
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/calendar/day_page_mobile_layout_test.dart`

**Interfaces:**
- Consumes: `MindmapNode? selectedNode`, `_DailyMissionStats stats`, `List<DayMiniInsight> miniInsights`, `DateTime normalizedDate`
- Produces: `_MobileCompactHeader` widget rendering a single row top bar on compact screens.

- [ ] **Step 1: Write failing test for compact mobile layout**

Create `test/features/calendar/day_page_mobile_layout_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:var_app/features/calendar/day_page.dart';

void main() {
  testWidgets('renders compact top header when screen width < 600', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DayPage(day: DateTime(2026, 8, 8)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobile-compact-header')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/calendar/day_page_mobile_layout_test.dart`
Expected: FAIL with "Key mobile-compact-header not found"

- [ ] **Step 3: Implement `_MobileCompactHeader` & update `day_page.dart` conditional rendering**

In `lib/features/calendar/day_page.dart`, define `_MobileCompactHeader` and conditionally render it when `MediaQuery.sizeOf(context).width < 600`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/calendar/day_page_mobile_layout_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/day_page.dart test/features/calendar/day_page_mobile_layout_test.dart
git commit -m "feat(calendar): add compact mobile top header layout"
```

---

### Task 2: Unified Mobile Tools Sheet Integration

**Files:**
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/calendar/day_page_mobile_layout_test.dart`

**Interfaces:**
- Consumes: `_showMobileToolsSheet` callback in `_MobileCompactHeader`
- Produces: Enhanced Modal Bottom Sheet displaying Day Status, Pulse, Focus mode toggle, Inbox count, and Mindmap tools.

- [ ] **Step 1: Write failing test for mobile tools sheet opening**

In `test/features/calendar/day_page_mobile_layout_test.dart`, add:
```dart
testWidgets('opens mobile tools sheet when tapping Tools button', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: DayPage(day: DateTime(2026, 8, 8)),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final toolsButton = find.byKey(const Key('mobile-tools-button'));
  await tester.tap(toolsButton);
  await tester.pumpAndSettle();

  expect(find.text('Day Tools & Status'), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/calendar/day_page_mobile_layout_test.dart`
Expected: FAIL with "Key mobile-tools-button not found" or "Day Tools & Status not found"

- [ ] **Step 3: Update `_showMobileToolsSheet` in `day_page.dart`**

Enhance `_showMobileToolsSheet` to include sections for Day Status (Board %, Pulse score, Focus Mode, Inbox count, Quick Capture) and Mindmap tools.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/calendar/day_page_mobile_layout_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/calendar/day_page.dart test/features/calendar/day_page_mobile_layout_test.dart
git commit -m "feat(calendar): integrate day status into mobile tools sheet"
```

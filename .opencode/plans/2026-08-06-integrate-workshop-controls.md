# Integrate Workshop Controls Into Board Tab Header Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move floating workshop controls (`groups` icon button & popup menu) from individual floating position to be neatly integrated inside `DayCanvasTabHeader` alongside AI Assistant, Voting, Templates, History, and Export icons.

**Architecture:** Update `DayCanvasTabHeader` to render the workshop popup menu and timer when active, using `activeCanvasBoard.workshopSession`. Remove the standalone floating Positioned workshop menu card in `DayPage`.

**Tech Stack:** Flutter, Material 3, Riverpod.

## Global Constraints
- Target Flutter SDK & package `var_app`.
- Follow strict lints: single quotes, trailing commas, no raw dynamic calls.

---

### Task 1: Integrate Workshop Popup Menu & Active Session Timer into DayCanvasTabHeader

**Files:**
- Modify: `lib/features/calendar/widgets/day_canvas_tab_header.dart`
- Modify: `lib/features/calendar/day_page.dart`
- Modify: `test/features/calendar/day_page_floating_overlay_test.dart`

**Interfaces:**
- Consumes: `CanvasBoard.workshopSession`, `onWorkshopActionSelected`.
- Produces: Integrated `groups` PopupMenuButton in `DayCanvasTabHeader`.

- [ ] **Step 1: Update `DayCanvasTabHeader` parameters to accept workshop action callbacks and session state**

Pass `workshopSession`, `onWorkshopAction` to `DayCanvasTabHeader` so it can render the `PopupMenuButton<String>` with icon `Icons.groups` (or `Icons.groups_outlined` when inactive) and display timer when `workshopSession.isActive`.

- [ ] **Step 2: Remove standalone floating `Positioned` workshop card in `DayPage`**

Remove lines in `DayPage` (`Positioned(top: 16, right: ...)`) that render standalone workshop controls popup.

- [ ] **Step 3: Run `flutter analyze` & `flutter test` to verify zero issues**

Run: `flutter analyze`
Run: `flutter test test/features/calendar/day_page_floating_overlay_test.dart`

- [ ] **Step 4: Commit**

```bash
git add lib/features/calendar/widgets/day_canvas_tab_header.dart lib/features/calendar/day_page.dart test/features/calendar/day_page_floating_overlay_test.dart
git commit -m "feat(calendar): integrate workshop controls and timer into board tab header"
```

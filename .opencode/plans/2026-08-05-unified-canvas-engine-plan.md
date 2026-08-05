# Unified Canvas Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify all canvas workspace features (Workshop Sessions, Live Voting, Realtime Collab / Board Room, Templates, Multi-Board switching) into DayPage while transforming WorkspaceDetailPage into a Project Directory that routes to DayPage.

**Architecture:** Extend `CanvasBoard` repository and domain models to support multi-board queries per `dayKey` and optional `workspaceId`. Enhance `DayPage` with a multi-board tab header and full workspace action bars. Refactor `WorkspaceDetailPage` to serve as a project dashboard navigating users to DayPage boards.

**Tech Stack:** Flutter, Dart, Riverpod, Sembast, Firebase Auth / Firestore / Storage (for Collab).

## Global Constraints

- Dart SDK: `^3.11.4`
- Follow strict typing and single quote formatting
- All tests run via `flutter test`
- Maintain Material 3 dark-first visual style

---

### Task 1: Update `CanvasBoard` Domain Model & Repository Query Interface

**Files:**
- Modify: `lib/features/mindmap/domain/canvas_board.dart`
- Modify: `lib/features/mindmap/domain/canvas_board_repository.dart`
- Modify: `lib/features/mindmap/data/canvas_board_repositories.dart`
- Test: `test/features/mindmap/domain/canvas_board_test.dart`

**Interfaces:**
- Consumes: `CanvasBoard` entity
- Produces: `CanvasBoard.copyWith` with `isPrimaryDayBoard` flag, `getBoardsForDay(String dayKey)` repository method

- [ ] **Step 1: Write the failing unit test for `getBoardsForDay` repository method**

```dart
test('getBoardsForDay returns all boards for a given dayKey sorted by createdAt', () async {
  final repo = InMemoryCanvasBoardRepository();
  final board1 = CanvasBoard(id: 'b1', title: 'Main', dayKey: '2026-08-05', isPrimaryDayBoard: true, createdAt: DateTime(2026, 8, 5, 10));
  final board2 = CanvasBoard(id: 'b2', title: 'Brainstorm', dayKey: '2026-08-05', isPrimaryDayBoard: false, createdAt: DateTime(2026, 8, 5, 11));
  await repo.saveBoard(board1);
  await repo.saveBoard(board2);

  final boards = await repo.getBoardsForDay('2026-08-05');
  expect(boards.length, equals(2));
  expect(boards.first.id, equals('b1'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/mindmap/domain/canvas_board_test.dart`
Expected: FAIL (method `getBoardsForDay` not defined on `CanvasBoardRepository`)

- [ ] **Step 3: Implement domain & repository changes**

Update `CanvasBoard` to include `isPrimaryDayBoard` field and update `CanvasBoardRepository` interface & Sembast implementation with `getBoardsForDay(String dayKey)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/domain/canvas_board_test.dart`
Expected: PASS

---

### Task 2: Implement DayPage Multi-Board Header & Tab Switching

**Files:**
- Create: `lib/features/calendar/widgets/day_canvas_tab_header.dart`
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/calendar/day_canvas_tab_header_test.dart`

**Interfaces:**
- Consumes: `getBoardsForDay`, `saveBoard`
- Produces: `DayCanvasTabHeader` widget triggering `onSelectBoard` and `onAddBoard`

- [ ] **Step 1: Write failing widget test for `DayCanvasTabHeader`**

```dart
testWidgets('DayCanvasTabHeader renders tabs and calls onSelectBoard', (tester) async {
  var selectedId = 'b1';
  final boards = [
    CanvasBoard(id: 'b1', title: 'Main Canvas', dayKey: '2026-08-05', isPrimaryDayBoard: true),
    CanvasBoard(id: 'b2', title: 'Project Board', dayKey: '2026-08-05', isPrimaryDayBoard: false),
  ];

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DayCanvasTabHeader(
        boards: boards,
        activeBoardId: selectedId,
        onSelectBoard: (id) => selectedId = id,
        onAddBoard: () {},
      ),
    ),
  ));

  expect(find.text('Main Canvas'), findsOneWidget);
  expect(find.text('Project Board'), findsOneWidget);

  await tester.tap(find.text('Project Board'));
  expect(selectedId, equals('b2'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/calendar/day_canvas_tab_header_test.dart`
Expected: FAIL (widget `DayCanvasTabHeader` missing)

- [ ] **Step 3: Implement `DayCanvasTabHeader` widget and integrate into `DayPage`**

Create `DayCanvasTabHeader` with clean Material 3 tab styling and wire active board state in `DayPage`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/calendar/day_canvas_tab_header_test.dart`
Expected: PASS

---

### Task 3: Expose Full Workspace Toolbars (Workshop, Voting, Collab) in DayPage

**Files:**
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/calendar/day_page_workspace_actions_test.dart`

**Interfaces:**
- Consumes: `MindmapCanvas` with full parameters (`collaborationState`, `workshopSession`, `votingParticipantId`)
- Produces: Action bar icons on DayPage top bar for Workshop, Voting, and Collab Room

- [ ] **Step 1: Write failing widget test for DayPage workspace toolbar buttons**

```dart
testWidgets('DayPage top bar displays Workshop, Voting, and Collab action buttons', (tester) async {
  await tester.pumpWidget(ProviderScope(child: MaterialApp(home: DayPage(initialDate: DateTime(2026, 8, 5)))));
  await tester.pumpAndSettle();

  expect(find.byIcon(Icons.video_call_outlined), findsOneWidget); // Collab/Room
  expect(find.byIcon(Icons.how_to_vote_outlined), findsOneWidget); // Voting
  expect(find.byIcon(Icons.present_to_all_outlined), findsOneWidget); // Workshop
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/calendar/day_page_workspace_actions_test.dart`
Expected: FAIL (icons missing or not present in DayPage top bar)

- [ ] **Step 3: Connect workspace toolbars and dialog triggers into `DayPage`**

Wire collaboration notifier, voting outbox, and workshop controller into `DayPage` state and render action buttons in top bar.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/calendar/day_page_workspace_actions_test.dart`
Expected: PASS

---

### Task 4: Refactor WorkspaceDetailPage into Project Directory & Navigator

**Files:**
- Modify: `lib/features/workspace/workspace_detail_page.dart`
- Test: `test/features/workspace/workspace_detail_page_test.dart`

**Interfaces:**
- Consumes: Workspace boards list
- Produces: Project dashboard displaying metadata and navigation cards to DayPage

- [ ] **Step 1: Write failing test for WorkspaceDetailPage board card navigation**

```dart
testWidgets('Tapping board card in WorkspaceDetailPage routes to DayPage with activeBoardId', (tester) async {
  // Test navigation route push to DayPage with activeBoardId parameter
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/workspace/workspace_detail_page_test.dart`
Expected: FAIL

- [ ] **Step 3: Refactor `WorkspaceDetailPage` body to render project dashboard & board cards**

Update `WorkspaceDetailPage` layout to display workspace header, overview metrics, and board list with click-to-navigate action to DayPage.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/workspace/workspace_detail_page_test.dart`
Expected: PASS

---

### Task 5: Final Verification & Preflight Checks

- [ ] **Step 1: Run `flutter analyze`**
- [ ] **Step 2: Run `flutter test`**

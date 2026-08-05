# DayPage Canvas Tab Rename and Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to rename and delete canvas tabs on `DayPage` canvas tab header.

**Architecture:** `DayCanvasTabHeader` will expose `onRenameBoard` and `onDeleteBoard` callbacks and trigger a context menu via long-press or secondary tap. `DayPage` handles rename/delete dialogs, repository mutation, provider invalidation, and active tab fallback.

**Tech Stack:** Flutter, Riverpod, Sembast (`CanvasBoardRepository`).

## Global Constraints
- `always_declare_return_types`, `avoid_dynamic_calls`, `prefer_single_quotes`, `require_trailing_commas`, `unawaited_futures`.
- Material 3 styling adhering to `app_colors.dart` and `app_theme.dart`.

---

### Task 1: Add Rename & Delete Callbacks and Context Menu to `DayCanvasTabHeader`

**Files:**
- Modify: `lib/features/calendar/widgets/day_canvas_tab_header.dart`
- Modify/Test: `test/features/calendar/day_canvas_tab_header_test.dart`

**Interfaces:**
- Consumes: `CanvasBoard` from `lib/features/mindmap/domain/canvas_board.dart`
- Produces: `DayCanvasTabHeader` constructor accepts optional `ValueChanged<CanvasBoard>? onRenameBoard` and `ValueChanged<CanvasBoard>? onDeleteBoard`.

- [ ] **Step 1: Write failing widget test for rename & delete context menu callbacks**

Modify `test/features/calendar/day_canvas_tab_header_test.dart`:
```dart
testWidgets('DayCanvasTabHeader triggers onRenameBoard and onDeleteBoard from menu', (WidgetTester tester) async {
  CanvasBoard? renamedBoard;
  CanvasBoard? deletedBoard;

  final primaryBoard = CanvasBoard(
    id: 'day-2026-08-05',
    title: '2026-08-05',
    kind: CanvasBoardKind.daily,
    day: DateTime(2026, 8, 5),
    createdAt: DateTime(2026, 8, 5),
    updatedAt: DateTime(2026, 8, 5),
  );
  final subBoard = CanvasBoard(
    id: 'sub-1',
    title: 'Sub Board',
    kind: CanvasBoardKind.daily,
    day: DateTime(2026, 8, 5),
    createdAt: DateTime(2026, 8, 5),
    updatedAt: DateTime(2026, 8, 5),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DayCanvasTabHeader(
          boards: [primaryBoard, subBoard],
          activeBoardId: subBoard.id,
          onSelectBoard: (_) {},
          onAddBoard: () {},
          onRenameBoard: (b) => renamedBoard = b,
          onDeleteBoard: (b) => deletedBoard = b,
        ),
      ),
    ),
  );

  // Long press subBoard chip to trigger context menu
  await tester.longPress(find.text('Sub Board'));
  await tester.pumpAndSettle();

  expect(find.text('Rename'), findsOneWidget);
  expect(find.text('Delete'), findsOneWidget);

  await tester.tap(find.text('Rename'));
  await tester.pumpAndSettle();
  expect(renamedBoard?.id, equals('sub-1'));

  // Test delete on subBoard
  await tester.longPress(find.text('Sub Board'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
  expect(deletedBoard?.id, equals('sub-1'));

  // Primary board should only have Rename
  await tester.longPress(find.text('2026-08-05'));
  await tester.pumpAndSettle();
  expect(find.text('Rename'), findsOneWidget);
  expect(find.text('Delete'), findsNothing);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/calendar/day_canvas_tab_header_test.dart`
Expected: FAIL due to missing parameter / menu options.

- [ ] **Step 3: Update `DayCanvasTabHeader` implementation**

In `lib/features/calendar/widgets/day_canvas_tab_header.dart`:
Add parameters:
```dart
final ValueChanged<CanvasBoard>? onRenameBoard;
final ValueChanged<CanvasBoard>? onDeleteBoard;
```
Wrap `ChoiceChip` with a `GestureDetector` handling `onLongPress` and `onSecondaryTapDown`:
```dart
void _showTabMenu(BuildContext context, TapDownDetails? details, CanvasBoard board) {
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final position = details != null
      ? RelativeRect.fromRect(
          details.globalPosition & const Size(40, 40),
          Offset.zero & overlay.size,
        )
      : RelativeRect.fromRect(
          Offset.zero & const Size(40, 40),
          Offset.zero & overlay.size,
        );

  final isPrimary = board.isPrimaryDayBoard(board.day);

  showMenu<String>(
    context: context,
    position: position,
    items: [
      const PopupMenuItem(
        value: 'rename',
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 18),
            SizedBox(width: 8),
            Text('Rename'),
          ],
        ),
      ),
      if (!isPrimary)
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
    ],
  ).then((value) {
    if (value == 'rename') {
      onRenameBoard?.call(board);
    } else if (value == 'delete') {
      onDeleteBoard?.call(board);
    }
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/calendar/day_canvas_tab_header_test.dart`
Expected: PASS

- [ ] **Step 5: Commit Task 1**

```bash
git add lib/features/calendar/widgets/day_canvas_tab_header.dart test/features/calendar/day_canvas_tab_header_test.dart
git commit -m "feat(calendar): add rename and delete callbacks and context menu to DayCanvasTabHeader"
```

---

### Task 2: Implement Rename & Delete Dialog Handlers in `DayPage`

**Files:**
- Modify: `lib/features/calendar/day_page.dart`
- Modify/Test: `test/features/calendar/day_page_workspace_actions_test.dart`

**Interfaces:**
- Consumes: `onRenameBoard` and `onDeleteBoard` from `DayCanvasTabHeader`.
- Produces: `_renameDailyBoard` and `_deleteDailyBoard` methods in `_DayPageState`.

- [ ] **Step 1: Write failing widget test for rename & delete in `DayPage`**

In `test/features/calendar/day_page_workspace_actions_test.dart` or a new test file:
```dart
testWidgets('DayPage renames and deletes sub-boards', (WidgetTester tester) async {
  // Setup DayPage with mock boards and verify rename dialog updates board title
  // and delete dialog removes board and switches active board
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/calendar/day_page_workspace_actions_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement `_renameDailyBoard` and `_deleteDailyBoard` in `DayPage`**

In `lib/features/calendar/day_page.dart`:
```dart
Future<void> _renameDailyBoard(CanvasBoard board) async {
  final controller = TextEditingController(text: board.title);
  final newTitle = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename Board'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Board Title',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (newTitle == null || newTitle.isEmpty || newTitle == board.title) return;

  final updatedBoard = board.copyWith(
    title: newTitle,
    updatedAt: DateTime.now(),
  );
  await ref.read(canvasBoardRepositoryProvider).saveBoard(updatedBoard);
  ref.invalidate(dailyCanvasBoardsProvider(board.day.dateOnly));
  _showSnackBar('Board renamed to "$newTitle"');
}

Future<void> _deleteDailyBoard(CanvasBoard board) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Board'),
      content: Text('Are you sure you want to delete "${board.title}"? This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  await ref.read(canvasBoardRepositoryProvider).deleteBoard(board.id);
  ref.invalidate(dailyCanvasBoardsProvider(board.day.dateOnly));

  if (_activeBoardId == board.id) {
    final primaryId = 'day-${board.day.dateOnly.toIso8601String().split('T').first}';
    setState(() {
      _activeBoardId = primaryId;
    });
  }
  _showSnackBar('Board deleted');
}
```

Connect `onRenameBoard` and `onDeleteBoard` in `DayCanvasTabHeader` instantiation inside `day_page.dart`.

- [ ] **Step 4: Run tests & static analysis**

Run: `dart format . && flutter analyze && flutter test`
Expected: 0 issues, all tests PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add lib/features/calendar/day_page.dart test/features/calendar/day_page_workspace_actions_test.dart
git commit -m "feat(calendar): implement board rename and delete dialogs on DayPage"
```

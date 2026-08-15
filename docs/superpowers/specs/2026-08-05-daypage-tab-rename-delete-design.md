# Tab Rename and Delete in DayPage Canvas Design Spec

## Overview
Enable renaming and deleting canvas tabs on the `DayPage` canvas tab header. 

## Rules & Constraints
- **Primary Board (Date Board)**: Can be renamed, but CANNOT be deleted.
- **Sub-Boards (Added via `+`)**: Can be renamed AND deleted.
- **Active Board Fallback**: If an active sub-board is deleted, active board falls back to the primary board for that day.

## Component Changes

### 1. `DayCanvasTabHeader` (`lib/features/calendar/widgets/day_canvas_tab_header.dart`)
- Add callback parameters:
  - `onRenameBoard?: ValueChanged<CanvasBoard>`
  - `onDeleteBoard?: ValueChanged<CanvasBoard>`
- Add context menu trigger (`onSecondaryTapDown` / `onLongPress` / gesture) on each tab chip.
- Display `PopupMenuButton` or `showMenu` with options:
  - **Rename Board**: Available for all boards.
  - **Delete Board**: Available only for non-primary boards (`!board.isPrimaryDayBoard(activeDate)` or when not primary).

### 2. `DayPage` State & Persistence Handlers (`lib/features/calendar/day_page.dart`)
- `_renameDailyBoard(CanvasBoard board)`:
  - Opens `AlertDialog` with a text field populated with `board.title`.
  - On save: updates board `title` and `updatedAt`, calls `canvasBoardRepositoryProvider.saveBoard(updatedBoard)`, invalidates `dailyCanvasBoardsProvider(normalizedDate)`.
- `_deleteDailyBoard(CanvasBoard board)`:
  - Opens confirmation dialog (`AlertDialog`).
  - On confirm: calls `canvasBoardRepositoryProvider.deleteBoard(board.id)`.
  - If `board.id == _activeBoardId`, resets `_activeBoardId` to the primary board ID for `normalizedDate`.
  - Invalidates `dailyCanvasBoardsProvider(normalizedDate)`.

## Testing Plan
- Test `DayCanvasTabHeader` widget tests for context menu options on primary vs sub-boards.
- Test board deletion & fallback tab selection behavior.

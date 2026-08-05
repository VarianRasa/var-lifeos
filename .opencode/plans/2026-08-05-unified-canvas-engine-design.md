# Unified Canvas Engine Design (DayPage & Workspace Unification)

**Date**: 2026-08-05  
**Status**: Approved  
**Target Package**: `var_app`

---

## 1. Executive Summary

`var_app` currently uses the single reusable `MindmapCanvas` widget (`lib/features/mindmap/presentation/mindmap_canvas.dart`) for both **DayPage** (calendar daily notes) and **WorkspaceDetailPage** (long-term project boards). However, advanced project features (Workshop Session, Voting, Realtime Collaboration / Board Room, Templates, Multi-Board switching) are predominantly wired in `WorkspaceDetailPage`, while `DayPage` runs a constrained single-board instance per day.

This design unifies all canvas capabilities into a **Unified Board Engine centered at DayPage**. DayPage becomes the primary workspace canvas host supporting multi-board tabs per day and full project feature sets. `WorkspaceDetailPage` transitions into a **Project & Canvas Directory / Dashboard**, routing users directly to the specific board instance on DayPage.

---

## 2. Architecture & Data Model

### 2.1 Domain Model Update (`CanvasBoard`)
File: `lib/features/mindmap/domain/canvas_board.dart`

`CanvasBoard` model retains universal identification:
- `dayKey` (`String?`, format `YYYY-MM-DD`): Associates board with a specific day.
- `workspaceId` (`String?`): Associates board with a specific workspace/project.
- `isPrimaryDayBoard` (`bool`): Identifies default main canvas for a given `dayKey`.

All canvas instances support:
1. **Workshop Sessions**: Host/Viewer, timer, presenter view.
2. **Voting Engine**: Outbox, voting overlays, participant state.
3. **Realtime Collaboration (Board Room)**: Live cursors, ping pointers, canvas comments, role permissions.
4. **Templates & AI Assistant**: Board templates, quick creation, AI canvas preview.

---

## 3. UI/UX Changes

### 3.1 DayPage Canvas Multi-Board Header & Controls
File: `lib/features/calendar/day_page.dart`

1. **Board Selector Bar**:
   - Tab switcher at top of DayPage canvas: `[Main Canvas (Default)] [+] [Board Tab 2]`.
   - Add Board button (`[+]`): Creates blank board or instantiates from `CanvasBoardTemplate`.
2. **Full Workspace Toolbars**:
   - Top action bar exposes:
     - Workshop Controls (Host, Presenter Mode, Timer).
     - Live Voting panel.
     - Realtime Collab / Board Room controls (Share link, Live cursors, Ping pointer, Comments).
     - AI Assistant & Export dialogs.

### 3.2 WorkspaceDetailPage Transformation
File: `lib/features/workspace/workspace_detail_page.dart`

- Converts into **Project Directory & Overview Dashboard**.
- Displays workspace metadata, timeline, members, and a card list of all associated `CanvasBoard`s.
- Clicking a board card navigates directly to `DayPage(dayKey: board.dayKey, activeBoardId: board.id)`.

---

## 4. Verification Plan

1. **Unit & Integration Tests**:
   - `CanvasBoard` query tests for combined `dayKey` and `workspaceId` persistence.
   - DayPage multi-board tab creation and state switching tests.
   - Collaboration & Workshop session state preservation across board tab switches.
2. **Automated Preflight Commands**:
   - `flutter analyze`
   - `flutter test`

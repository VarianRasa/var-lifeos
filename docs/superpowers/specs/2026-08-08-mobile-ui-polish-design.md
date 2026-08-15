# Design Spec: Mobile UI Polish & Compact Header Layout

## Context & Problem
On mobile screens (`width < 600px`), the calendar day page (`day_page.dart`) currently stacks multiple headers and toolbars vertically:
1. `_DayToolsBar` (Board status %, Pulse, Focus mode, Inbox, Auto Time-Block)
2. `_MindmapMobileToolbar` ("Mindmap tools" text header + "Tools" button)
3. Board canvas toolbar (Board, Table, Context: All, grid view options)
4. Floating board tabs header (`DayCanvasTabHeader`)

This vertical stacking consumes over 35% of the screen height, leaving a tiny viewport for the mindmap canvas. Floating controls at the bottom also suffer from tight margins.

## Proposed Solution: Compact Mobile Top Header + Single Floating Sheet

### 1. Unified Mobile Top Header (`< 600px`)
- Replace the multi-stacked header with a single compact bar (38-44px high).
- Displays canvas sub-board selector / tabs and essential quick actions (View Mode switcher, Quick Capture, and a consolidated "Tools" button).
- Hide static `_DayToolsBar` and redundant `_MindmapMobileToolbar` bar on compact screens.

### 2. Comprehensive Mobile Tools Sheet (`_showMobileToolsSheet`)
- When the user taps "Tools" in the top bar, display a unified modal Bottom Sheet.
- Divided into clear sections:
  1. **Day Status & Pulse**: Board completion %, 7-day Pulse score, Focus toggle, Auto Time-Block trigger, and Inbox.
  2. **Mindmap View & Tools**: Context filter (All/Active), layout reset, import/export, and template actions.

### 3. Floating Bottom Controls Polish
- Update layout constraints and padding around bottom floating controls (zoom pill `100%`, canvas mini-map, and FAB `+`).
- Ensure proper `SafeArea` padding to avoid overlapping OS navigation bars.

## File Changes
- `lib/features/calendar/day_page.dart`: Refactor mobile conditional header rendering and integrate tools into bottom sheet.
- `lib/features/calendar/widgets/day_canvas_tab_header.dart`: Ensure compact styling without overflowing on small viewports.

## Testing & Verification
- Test on compact screens (`width < 600px`) and wide screens (`width >= 600px`).
- Run `flutter analyze` and `flutter test`.

# DayPage Floating Modular Canvas Controls Design

## Overview
Transform `DayPage` canvas controls from a static top bar into stacked modular floating overlay bars over a full-screen canvas. Users gain maximum canvas vertical area while retaining full control over individual toolbar visibility via floating handles and Desktop `View` menu settings.

## Architecture & Layout
- Re-architect `DayPage` canvas view using a Flutter `Stack`.
- `MindmapCanvas` takes full 100% height and width of the viewport.
- Three modular floating bars hover at the top of the canvas in a vertical stack with top padding:
  1. **Top Header Floating Pill**: Date display, Collab Mode status, View Mode selector (`Canvas`, `Timeline`, `Board`, `Table`), Context filter, Share & Canvas Settings actions, and collapse toggle.
  2. **Ribbon Toolbar Floating Bar**: Action tabs (`Home`, `Insert`, `Node`, `Canvas`, `View`) and corresponding tool buttons.
  3. **Day Sub-Board Tabs Floating Bar**: Daily canvas tabs and creation/management buttons.

## Visual Design
- Floating containers feature Material 3 elevation, translucent blur background (`BackdropFilter` or semi-transparent surface container), subtle border, and rounded corners (`BorderRadius.circular(12)` to `16`).
- Floating bars do not block canvas gestures underneath outside their bounds.

## State & Visibility Control
- State managed per modular bar:
  - `isFloatingTopBarVisible` (default `true`)
  - `isFloatingRibbonVisible` (default `true`)
  - `isFloatingBoardTabsVisible` (default `true`)
- Mini floating handle / icon toggles on each bar allow instant individual collapse/expand.
- Quick global toggle `isAllCanvasControlsVisible` to hide/show all bars at once.

## Desktop Menu Integration (`View` Menu)
- Update desktop menu bar entries under `View`:
  - `View` -> `Show Top Header Bar` (`Ctrl+Alt+1` / `Cmd+Option+1`)
  - `View` -> `Show Ribbon Toolbar` (`Ctrl+Alt+2` / `Cmd+Option+2`)
  - `View` -> `Show Board Tabs` (`Ctrl+Alt+3` / `Cmd+Option+3`)
  - `View` -> `Hide/Show All Canvas Controls` (`Ctrl+Shift+H` / `Cmd+Shift+H`)

## Verification Strategy
- Widget tests for `DayPage` floating overlay rendering and visibility state toggles.
- Verification via `flutter analyze` and `flutter test`.

# Canvas Node Enhancement Design

**Date:** 2026-07-16
**Status:** Approved design, pending written-spec review

## Goal

Turn Canvas nodes into lightweight visual workspaces that support drawing, text, sticky notes, shapes, and arrows directly inside the expanded node while preserving a larger sub-canvas action.

## Scope

Canvas version one includes:

- selection tool
- freehand pen
- eraser
- text labels
- sticky notes
- rectangles
- ellipses
- arrows
- pen color and thickness controls
- plain, grid, and dots backgrounds
- element selection, movement, and deletion
- undo and redo
- clear canvas with confirmation
- structured persistence with legacy stroke compatibility
- non-interactive collapsed thumbnail
- expanded fixed workspace without resize
- collapsed manual resize
- Open canvas action for a larger workspace

Version one excludes images, frames/groups, snapping, connector routing, internal zoom/pan, pressure sensitivity, real-time collaboration, and export.

## Domain Model

### CanvasPayload

`CanvasPayload` becomes the typed document payload for `NodeType.canvas`:

- `schemaVersion`: integer, initially `1`
- `background`: one of `plain`, `grid`, `dots`
- `elements`: ordered list of `CanvasElement`
- `activeTool`: last selected tool for editor continuity
- `penColor`: supported color token
- `penWidth`: positive finite width

Unknown root keys and unknown keys inside the nested `canvas` map are preserved.

### CanvasPoint

Each point contains finite normalized coordinates:

- `x`
- `y`

Coordinates are normalized to the workspace dimensions in the range `0..1`. Rendering converts them to local pixels, allowing the same document to work in expanded workspace and collapsed thumbnail.

### CanvasElement Types

Every element has:

- stable `id`
- `type`
- `color`
- optional creation/update metadata only when already available locally

Supported element records:

#### CanvasStroke

- ordered `points`
- positive `width`

#### CanvasText

- `position`
- `text`
- `fontSize`

#### CanvasSticky

- `position`
- normalized `width` and `height`
- `text`
- background color token

#### CanvasShape

- `shape`: `rectangle` or `ellipse`
- normalized start/end bounds
- stroke width
- optional fill color token

#### CanvasArrow

- normalized `start`
- normalized `end`
- stroke width

Element ordering is painter order. Newly created elements append to the end.

## Compatibility

Legacy top-level keys remain readable:

- `strokes: List<String>`
- `background: String`

Legacy stroke strings are parsed using the existing point encoding when possible. Malformed stroke records are ignored rather than crashing. When no structured document exists, parsed legacy strokes become `CanvasStroke` elements with deterministic IDs.

Writes store the authoritative nested `canvas` map and retain legacy summary keys:

- `strokes`: serialized freehand strokes
- `background`: selected background

This keeps existing preview and readers functional during migration.

## Editor State and History

Canvas editing uses local state inside the Canvas editor:

- current payload
- selected element ID
- active gesture draft
- undo stack
- redo stack

Each completed mutation pushes the previous payload to undo history:

- add element
- move element
- delete element
- erase element
- edit text/sticky content
- change persistent element properties
- clear canvas

Pointer movement during one drag does not create repeated history entries. One completed gesture equals one undo step. New mutations clear redo history. History is session-local and not persisted.

## Toolbar

Toolbar is compact and wraps on narrow widths.

Tools:

- Select
- Pen
- Eraser
- Text
- Sticky
- Rectangle
- Ellipse
- Arrow

Controls:

- pen color choices from existing theme-compatible tokens
- pen width continuous slider
- background segmented control: Plain, Grid, Dots
- Undo
- Redo
- Delete selected
- Clear
- Open canvas

Disabled actions communicate state:

- Undo disabled with empty undo stack
- Redo disabled with empty redo stack
- Delete disabled without selection
- Clear disabled with no elements

Clear requires confirmation because it deletes all Canvas elements.

## Gesture Rules

### Select

- tap element selects it
- selected element shows a visible outline/handles
- drag selected element moves it within normalized `0..1` bounds
- tapping empty workspace clears selection
- Delete action removes selected element

Selection hit testing runs from last element to first, matching painter order.

### Pen

- pointer down starts a stroke
- pointer movement appends normalized points
- pointer up commits one `CanvasStroke`
- strokes with fewer than two distinct points are discarded

### Eraser

- pointer contact finds the topmost hit element
- the element is removed once per gesture
- erasing does not split strokes in version one

### Rectangle, Ellipse, Arrow

- pointer down stores normalized start
- drag updates temporary preview
- pointer up commits element
- zero-size or negligible elements are discarded

### Text and Sticky

- tap workspace location opens a small input dialog
- non-empty submission creates the element
- tapping an existing text/sticky element while selected opens edit input
- cancel leaves payload unchanged

## Rendering

A shared Canvas renderer paints both expanded workspace and collapsed preview:

1. background
2. elements in order
3. active gesture preview when editing
4. selected element decoration when editing

Background behavior:

- plain: solid surface
- grid: evenly spaced horizontal and vertical lines
- dots: evenly spaced point pattern

Renderer clips to workspace bounds.

## Expanded Workspace

Expanded Canvas uses a fixed workspace size from `InlineNodeWorkspacePolicy` and ignores persisted custom dimensions. Resize handles are absent.

Expanded layout:

- Title and Content fields
- Canvas toolbar
- large interactive workspace
- concise element count/status row

The workspace itself is not internally scrollable. The outer inline editor may scroll if viewport height is smaller than the fixed workspace.

## Collapsed Preview

Collapsed Canvas remains manually resizable and gesture-safe.

Preview contains:

- non-interactive rendered thumbnail
- current background
- total element count
- compact counts for drawings, text/stickies, and shapes
- Open canvas quick action when callback exists

Preview must not capture drag gestures used to move or resize the node. It limits labels and statistics to prevent overflow in small custom sizes.

## Open Canvas Action

Existing `OpenSubCanvasAction(node.id)` remains the integration boundary. Direct expanded editing and larger sub-canvas editing operate on the same `CanvasPayload` document.

No duplicate storage model is introduced.

## Validation

Validation errors include:

- unsupported schema version
- unsupported background or active tool
- unsupported color token
- non-finite or non-positive pen width
- duplicate or empty element IDs
- unsupported element type
- non-finite or out-of-range normalized coordinates
- empty text/sticky content
- non-positive text size or element dimensions
- stroke with fewer than two valid points
- unsupported shape type

Title validation remains unchanged.

## Tests

### Domain

- structured round-trip and nested unknown-key preservation
- legacy stroke migration
- malformed legacy stroke safety
- element ordering
- validation boundaries
- legacy summary writes

### Editor

- toolbar and background controls
- pen gesture creates one stroke and one undo entry
- shape and arrow drag creation
- text and sticky add/edit flows
- select and move
- delete selected
- eraser removes topmost element
- undo and redo
- clear confirmation
- pen width slider continuous drag
- reconstructed payload updates do not interrupt active gesture
- Open canvas callback action

### Canvas and Sizing

- collapsed thumbnail renders structured elements
- collapsed preview does not capture node drag
- preview statistics bounded without overflow
- expanded fixed policy size
- expanded resize handles absent
- collapsed resize handles remain

## Deliberate Simplifications

- Eraser removes whole elements; add partial stroke erasing only if users need precision editing.
- Text uses one font family and basic size; add rich typography only after real use.
- Shapes use simple stroke/fill; add rotation and resize handles later.
- History is session-local; add persistent history only if cross-session undo becomes necessary.
- Internal zoom/pan is excluded; use Open canvas for larger workspace navigation.

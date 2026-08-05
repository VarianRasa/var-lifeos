# Design Spec: Sticky Notes & Smart Canvas Quick Drop

## Overview
Integrates `NodeType.sticky` (colorful square visual note cards) and smart canvas drag-and-drop / paste content auto-detection (URLs, images, and text) into the `MindmapCanvas` for `var_app`.

## 1. Domain & Model (`NodeType.sticky`)
- Enum addition: `NodeType.sticky` in `lib/core/constants/app_constants.dart`.
- **Payload Schema (`StickyPayload`)**:
  - `color`: Pastel color tokens (`yellow`, `pink`, `mint`, `sky`, `purple`, `orange`).
  - `fontSize`: `small`, `medium`, `large`.
  - `text`: Main sticky note text body.
- **Visual Presentation**:
  - Distinctive square aspect ratio container with soft shadow and pastel background fill.
  - Quick inline color picker in floating popover/toolbar.

## 2. Smart Quick Drop & Paste Handler
- Integrated into `MindmapCanvas` keyboard listeners and `DropTarget` handlers.
- **Content Classification Rules**:
  1. **URL Link**: String matching `http://` or `https://` -> creates `NodeType.link`.
  2. **Image File**: File dropped with extension `.png`, `.jpg`, `.jpeg`, `.webp` -> creates `NodeType.image` with stored local attachment ID.
  3. **Plain Text**: Raw pasted text -> creates `NodeType.sticky` containing the text.
- **Position Calculation**: Nodes are placed precisely at the mouse cursor / drop coordinates on the canvas offset.

## 3. Verification & Testing
- Domain unit tests for `StickyPayload` parsing and metadata serialization.
- Unit tests for canvas content type classifier logic.
- Widget tests for sticky note rendering and drag-drop handling on `MindmapCanvas`.

# Image Annotation (Pins & Freehand Sketching) Design

## Goal

Enable users to annotate image nodes directly on the canvas using numbered comment pins and non-destructive freehand drawings, with all pin text discoverable via global offline search.

## Core Requirements

1. **Non-Destructive Annotations:**
   - Store pins and freehand strokes as normalized relative coordinates `(xRatio, yRatio)` from `0.0` to `1.0` inside `MindmapNode.data['annotations']`.
   - Never modify or replace original source image files.
2. **Interactive Annotation Modes:**
   - **View Mode:** Display overlay of numbered pins and sketch paths over the image. Tapping a pin opens a comment popover.
   - **Annotate Mode:** Activated from node toolbar. Captures gestures over the image node:
     - **Pin Tool:** Tapping image places a numbered pin and opens inline text editor.
     - **Pen Tool:** Draw smooth freehand paths with configurable color and width.
     - **Eraser Tool:** Clear individual strokes or delete pins.
3. **Search FTS Integration:**
   - `SearchDocumentProjector` projects pin comment text into searchable search documents associated with the parent image node.

## Data Model

```json
{
  "annotations": {
    "pins": [
      {
        "id": "pin-1722700000",
        "xRatio": 0.45,
        "yRatio": 0.30,
        "text": "Adjust contrast and lighting here",
        "createdAt": "2026-08-04T10:00:00Z"
      }
    ],
    "strokes": [
      {
        "color": 4294901760,
        "strokeWidth": 3.0,
        "points": [
          {"xRatio": 0.1, "yRatio": 0.2},
          {"xRatio": 0.15, "yRatio": 0.25}
        ]
      }
    ]
  }
}
```

## Architecture

### 1. `ImageAnnotationController` (`lib/features/mindmap/application/image_annotation_controller.dart`)
- Handles adding, editing, and deleting pins.
- Manages drawing stroke vectors and history (undo/redo).
- Persists changes back to `MindmapRepository` and triggers `SearchIndexCoordinator`.

### 2. `ImageAnnotationOverlay` (`lib/features/mindmap/presentation/image_annotation_overlay.dart`)
- `CustomPainter` renders responsive vector strokes and numbered pin badges over `ImageNode`.
- Handles relative coordinate conversion regardless of canvas zoom or node resize.

## Testing Strategy

- **Unit Tests:** `ImageAnnotationController` pin addition, relative coordinate calculations, stroke parsing, and FTS document projection.
- **Widget Tests:** `ImageAnnotationOverlay` rendering pins, popover comment editing, and gesture switching between canvas pan and drawing.

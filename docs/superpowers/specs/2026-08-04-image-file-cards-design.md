# Design Spec: Image & File Cards on Canvas

Date: 2026-08-04  
Status: Approved  

## Overview
Enable Milanote-style file dropping directly onto the Var mindmap canvas. Dropping images, video, audio, or document files creates appropriate mindmap nodes at the drop position. Generic files receive a dedicated `FileCardWidget` showing icon, filename, and file size badge.

---

## 1. Canvas File Drop Pipeline (`CanvasFileDropHandler`)

Location: `lib/features/mindmap/application/canvas_file_drop_handler.dart`

```dart
class CanvasFileDropHandler {
  final NodeAttachmentRepository repository;

  const CanvasFileDropHandler({required this.repository});

  Future<MindmapNode> processDroppedFile({
    required String filePath,
    required List<int> bytes,
    required CanvasPosition position,
    required String dayKey,
  }) async {
    // 1. Detect file type by extension & magic bytes
    // 2. Import into NodeAttachmentRepository
    // 3. Create & return MindmapNode with matching payload
    //    - image -> NodeType.image with ImagePayload
    //    - audio -> NodeType.audio with AudioPayload
    //    - video -> NodeType.video with VideoPayload
    //    - generic -> NodeType.link with file attachment metadata
  }
}
```

---

## 2. Canvas Integration (`mindmap_canvas.dart`)

Wrap canvas stack with `CanvasDropzoneOverlay`:
- `onFilesDropped(filePaths, screenOffset)`:
  1. Map `screenOffset` to canvas coordinates (accounting for zoom & origin).
  2. For each dropped file path, read bytes & invoke `CanvasFileDropHandler`.
  3. Emit created node via `onNodeCreated` callback (or append to draft nodes).

---

## 3. Generic File Card Widget (`FileCardWidget`)

Location: `lib/features/mindmap/presentation/widgets/file_card_widget.dart`

Visual UI for non-media file nodes (`NodeType.link` with file attachment):
- Icon: Extension-based (e.g. PDF → red document icon, ZIP → archive icon, code → code icon).
- Filename: Truncated title with full name tooltip.
- File Size Badge: Formatted string (e.g., `1.2 MB`, `450 KB`).
- Action: Click to open/export file via `NodeAttachmentRepository.readBytes`.

---

## 4. Testing Plan
- `test/features/mindmap/application/canvas_file_drop_handler_test.dart`: Test file type detection & node creation from dropped bytes.
- `test/features/mindmap/presentation/widgets/file_card_widget_test.dart`: Widget test for file card rendering & file size formatting.

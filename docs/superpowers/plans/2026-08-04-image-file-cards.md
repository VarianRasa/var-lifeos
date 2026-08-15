# Image & File Cards on Canvas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to drag-and-drop any file onto the canvas to automatically import it and create an image, audio, video, or generic file node at the drop position.

**Architecture:** Create `CanvasFileDropHandler` to classify dropped files by MIME/extension, import bytes via `NodeAttachmentRepository`, and build typed `MindmapNode` instances. Build `FileCardWidget` for generic document/archive nodes. Wrap `mindmap_canvas.dart` with `CanvasDropzoneOverlay` and link dropped files to `CanvasFileDropHandler`.

**Tech Stack:** Dart 3, Flutter, Material 3, Sembast.

## Global Constraints
- SDK: Dart `^3.11.4`, Flutter 3.x
- Style: Material 3 dark-first visual style, colors in `lib/core/theme/app_colors.dart`
- Analyzer: Clean `flutter analyze` with strict lints

---

### Task 1: CanvasFileDropHandler Service

**Files:**
- Create: `lib/features/mindmap/application/canvas_file_drop_handler.dart`
- Test: `test/features/mindmap/application/canvas_file_drop_handler_test.dart`

**Interfaces:**
- Produces: `CanvasFileDropHandler` with `processDroppedFile` method

- [ ] **Step 1: Write failing test**

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/canvas_file_drop_handler.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/core/constants/app_constants.dart';

void main() {
  test('CanvasFileDropHandler classifies PNG bytes as image node', () async {
    final handler = CanvasFileDropHandler();
    final pngHeader = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0]);
    final node = await handler.processDroppedFile(
      fileName: 'photo.png',
      bytes: pngHeader,
      position: const CanvasPosition(x: 100, y: 200),
      dayKey: '2026-08-04',
    );

    expect(node.type, NodeType.image);
    expect(node.position.x, 100);
    expect(node.position.y, 200);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/mindmap/application/canvas_file_drop_handler_test.dart`  
Expected: FAIL (file missing)

- [ ] **Step 3: Implement `CanvasFileDropHandler`**

Create `lib/features/mindmap/application/canvas_file_drop_handler.dart`:

```dart
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../domain/canvas_position.dart';
import '../domain/mindmap_node.dart';
import '../domain/node_type_payloads.dart';

class CanvasFileDropHandler {
  const CanvasFileDropHandler();

  Future<MindmapNode> processDroppedFile({
    required String fileName,
    required Uint8List bytes,
    required CanvasPosition position,
    required String dayKey,
  }) async {
    final ext = p.extension(fileName).toLowerCase();
    final id = const Uuid().v4();

    NodeType type;
    Map<String, Object?> data = {};

    if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(ext)) {
      type = NodeType.image;
      data = ImagePayload(
        fileName: fileName,
        byteLength: bytes.length,
        url: '',
      ).toData();
    } else if (['.mp3', '.wav', '.aac', '.m4a', '.ogg'].contains(ext)) {
      type = NodeType.audio;
      data = AudioPayload(
        fileName: fileName,
        sizeBytes: bytes.length,
      ).toData();
    } else if (['.mp4', '.mov', '.webm'].contains(ext)) {
      type = NodeType.video;
      data = VideoPayload(
        fileName: fileName,
      ).toData();
    } else {
      type = NodeType.link;
      data = {
        'title': fileName,
        'fileSize': bytes.length,
        'fileExtension': ext.replaceFirst('.', ''),
        'isLocalFile': true,
      };
    }

    return MindmapNode(
      id: id,
      dayKey: dayKey,
      type: type,
      title: fileName,
      position: position,
      data: data,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/application/canvas_file_drop_handler_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/application/canvas_file_drop_handler.dart test/features/mindmap/application/canvas_file_drop_handler_test.dart
git commit -m "feat: add CanvasFileDropHandler service"
```

---

### Task 2: FileCardWidget for Generic File Nodes

**Files:**
- Create: `lib/features/mindmap/presentation/widgets/file_card_widget.dart`
- Test: `test/features/mindmap/presentation/widgets/file_card_widget_test.dart`

**Interfaces:**
- Consumes: `fileName`, `fileSize`, `fileExtension`

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/presentation/widgets/file_card_widget.dart';

void main() {
  testWidgets('FileCardWidget displays filename, icon, and formatted size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FileCardWidget(
            fileName: 'document.pdf',
            fileSize: 2450000,
            fileExtension: 'pdf',
          ),
        ),
      ),
    );

    expect(find.text('document.pdf'), findsOneWidget);
    expect(find.text('2.3 MB'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/mindmap/presentation/widgets/file_card_widget_test.dart`  
Expected: FAIL (file missing)

- [ ] **Step 3: Implement `FileCardWidget`**

Create `lib/features/mindmap/presentation/widgets/file_card_widget.dart`:

```dart
import 'package:flutter/material.dart';

class FileCardWidget extends StatelessWidget {
  final String fileName;
  final int fileSize;
  final String fileExtension;

  const FileCardWidget({
    super.key,
    required this.fileName,
    required this.fileSize,
    required this.fileExtension,
  });

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconForExtension(String ext) {
    return switch (ext.toLowerCase()) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'zip' || 'tar' || 'gz' || '7z' || 'rar' => Icons.folder_zip_outlined,
      'txt' || 'md' || 'doc' || 'docx' => Icons.description_outlined,
      'xls' || 'xlsx' || 'csv' => Icons.table_chart_outlined,
      'ppt' || 'pptx' => Icons.slideshow_outlined,
      'dart' || 'js' || 'ts' || 'py' || 'html' || 'css' || 'json' => Icons.code_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _iconForExtension(fileExtension),
              color: colorScheme.onPrimaryContainer,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatSize(fileSize),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/presentation/widgets/file_card_widget_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/presentation/widgets/file_card_widget.dart test/features/mindmap/presentation/widgets/file_card_widget_test.dart
git commit -m "feat: add FileCardWidget for generic file nodes"
```

---

### Task 3: Canvas Dropzone Integration

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`

- [ ] **Step 1: Check baseline health**

Run: `flutter analyze`  
Expected: 0 issues

- [ ] **Step 2: Wrap Canvas stack with `CanvasDropzoneOverlay`**

In `mindmap_canvas.dart`:
1. Import `CanvasDropzoneOverlay` and `CanvasFileDropHandler`.
2. Wrap top canvas stack with `CanvasDropzoneOverlay`.
3. Inside `onFilesDropped`: Convert screen drop offset to canvas position using viewport transform. Call `CanvasFileDropHandler` for each file. Emit node via `widget.onNodeCreated` or draft append.

- [ ] **Step 3: Run analyze & test suite**

Run: `flutter analyze`  
Run: `flutter test`  
Expected: All tests PASS, clean analyze.

- [ ] **Step 4: Commit**

```bash
git add lib/features/mindmap/presentation/mindmap_canvas.dart
git commit -m "feat: wrap canvas with CanvasDropzoneOverlay and handle file drops"
```

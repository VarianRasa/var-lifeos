# Document & Media Embed Card Design Spec

## Overview
Menambahkan node tipe `media` dan `document` ke canvas mindmap Milanote-style. Pengguna dapat mengunggah atau men-drag-drop file audio/video/dokumen ke canvas untuk secara otomatis membuat card embed interaktif.

## 1. Domain Layer
### Enum Additions (`lib/core/constants/app_constants.dart`)
```dart
enum NodeType {
  // ... existing types
  media,
  document,
}
```

### Payloads (`lib/features/mindmap/domain/node_type_payloads.dart`)
- `MediaPayload`:
  - `urlOrPath`: String
  - `mimeType`: String
  - `fileName`: String
  - `fileSize`: int?
  - `durationMs`: int?
- `DocumentPayload`:
  - `urlOrPath`: String
  - `mimeType`: String
  - `fileName`: String
  - `fileSize`: int?
  - `pageCount`: int?

## 2. Quick Drop Integration (`lib/features/mindmap/application/canvas_file_drop_handler.dart`)
Klasifikasi ekstensi file saat drop:
- Video (`.mp4`, `.mov`, `.mkv`, `.webm`) -> `NodeType.media`
- Audio (`.mp3`, `.wav`, `.m4a`, `.aac`, `.flac`) -> `NodeType.media`
- Document (`.pdf`, `.doc`, `.docx`, `.xls`, `.xlsx`, `.ppt`, `.pptx`, `.txt`, `.csv`) -> `NodeType.document`

## 3. UI Presentation (`lib/features/mindmap/presentation/mindmap_canvas.dart`)
- `NodeType.media`: Card memuat icon play/video/audio, nama file, ukuran, dan preview indicator.
- `NodeType.document`: Card memuat badge tipe file (misal PDF/DOCX), nama file, ukuran file, dan tombol aksi (open/download).

## 4. System Compatibility Updates
Meliputi perbaikan exhaustive enum checks pada:
- `lib/core/theme/node_visuals.dart`
- `lib/features/mindmap/domain/node_presentation.dart`
- `lib/features/mindmap/domain/inline_node_workspace_policy.dart`
- `lib/features/mindmap/presentation/add_node_dialog.dart`
- `lib/features/mindmap/application/inline_node_workspace_controller.dart`

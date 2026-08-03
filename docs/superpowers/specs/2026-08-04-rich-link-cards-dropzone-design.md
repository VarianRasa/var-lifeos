# Rich Link Preview Cards & Canvas File Dropzone Design Spec

> **Date:** 2026-08-04  
> **Status:** Approved  
> **Target:** Var App (`var_app`)

## Overview

Adds two Milanote-style visual canvas capabilities to Var app:
1. **Rich Link Preview Cards:** Client-side OpenGraph metadata scraper (HTML parser) with a zero-backend CORS web fallback to render visual link cards (cover image, favicon, domain, title, description).
2. **Canvas File Drag-and-Drop Dropzone:** Desktop and Web canvas drop target for files (images, PDFs, documents) mapped directly to canvas spatial cursor coordinates.

---

## 1. Rich Link Preview Cards

### 1.1 Architecture & Domain Model

**File:** `lib/features/mindmap/domain/link_metadata.dart`

```dart
class LinkMetadata {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? faviconUrl;
  final DateTime fetchedAt;

  const LinkMetadata({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.faviconUrl,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson();
  factory LinkMetadata.fromJson(Map<String, dynamic> json);
}
```

### 1.2 OpenGraph Metadata Scraper Service

**File:** `lib/core/services/url_metadata_scraper_service.dart`

- Performs HTTP GET with browser `User-Agent`.
- Parses HTML `<meta property="og:title">`, `og:image`, `og:description`, `og:site_name`.
- Favicon fallback: `https://www.google.com/s2/favicons?domain=<host>&sz=64`.
- **CORS / Web Fallback (Zero Backend):** If HTTP GET fails due to CORS (in web browser) or network error, catches exception and returns fallback `LinkMetadata`:
  - `title`: domain name or URL
  - `faviconUrl`: Google favicon service URL
  - `imageUrl`: null
  - `description`: null
- **Caching:** Cache scraped `LinkMetadata` in Sembast key-value store to prevent re-fetching on canvas re-renders.

### 1.3 Presentation Widget

**File:** `lib/features/mindmap/presentation/widgets/link_preview_card_widget.dart`

- Rendered inside `link` nodes or canvas `linkPreview` objects.
- Visual layout:
  - Top: AspectRatio cover image (if `imageUrl` present).
  - Bottom content block:
    - Favicon image (16x16) + Site Name / Host domain text.
    - Title text (bold, max 2 lines).
    - Description text (muted, max 2 lines).
- Loading state: Skeleton loader shimmer while scraping.

---

## 2. Canvas File Drag-and-Drop Dropzone

### 2.1 Component Architecture

**File:** `lib/features/mindmap/presentation/widgets/canvas_dropzone_overlay.dart`

- Wraps `MindmapCanvas` with `DropTarget` (via `desktop_drop` or HTML drag-drop).
- **Drag Events:**
  - `onDragEntered`: Displays dashed accent overlay border across canvas with upload icon indicator.
  - `onDragExited`: Hides overlay.
  - `onDone(detail)`:
    1. Obtains screen drop coordinate `detail.offset`.
    2. Converts screen coordinate to spatial canvas position: `viewportController.screenToCanvas(detail.offset)`.
    3. Iterates dropped files (`detail.files`):
       - Image extension (`.png`, `.jpg`, `.jpeg`, `.webp`, `.svg`, `.gif`): Creates `NodeType.image` at target canvas coordinates.
       - Document extension (`.pdf`, `.txt`, `.md`, `.doc`, `.docx`): Creates `NodeType.resource` / `NodeType.note` at target canvas coordinates.
    4. Saves attachments via `NodeAttachmentRepository` and invalidates mindmap providers.

---

## 3. Testing Strategy

- `test/core/services/url_metadata_scraper_service_test.dart`:
  - Unit test parsing sample HTML with OG meta tags.
  - Unit test fallback metadata generation on network/CORS error.
- `test/features/mindmap/presentation/canvas_dropzone_overlay_test.dart`:
  - Widget test verifying dropzone overlay visibility toggle on drag enter/exit.
  - Spatial coordinate translation check.

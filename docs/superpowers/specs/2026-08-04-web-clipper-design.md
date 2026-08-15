# Web Clipper Browser Extension Design

## Goal

Provide a cross-browser extension (Manifest V3) for Chrome, Edge, Firefox, and Brave that lets users capture full articles, selections, bookmarks, and screenshots directly into Var app via a secure local HTTP server.

## Core Requirements

1. **Manifest V3 Extension Architecture:**
   - Universal extension build compatible with Chrome Web Store and Firefox Add-ons.
   - Popup interface with mode switcher: **Full Article**, **Selection**, **Bookmark**, and **Screenshot**.
   - Destination picker fetching recent boards from Var's local API; mandatory destination selection before save.
2. **Local HTTP Clipper API Server:**
   - Var app starts a background server listening on `http://127.0.0.1:18420/v1/capture`.
   - Secured with local token authentication (`Authorization: Bearer <local_token>`) configurable in Var Settings.
   - Accepts JSON payload, validates inputs using `CaptureValidator`, passes payload to `CaptureService`, and triggers background search indexing.
3. **Clip Modes & Content Processing:**
   - **Full Article:** Extracts clean readable body text and main images using Readability algorithms for offline storage.
   - **Selection:** Captures user-highlighted text and inline images.
   - **Bookmark:** Stores canonical URL, metadata title, og:image preview, and description.
   - **Screenshot:** Encodes canvas/viewport area capture into base64/PNG payload.

## Architecture

### 1. Local Server (`lib/core/services/local_clipper_server.dart`)
- Listens on `http://127.0.0.1:18420`.
- Endpoints:
  - `GET /v1/boards`: Returns available workspaces and destination boards for picker.
  - `POST /v1/capture`: Validates authorization header, parses `CapturePayload`, calls `CaptureService.saveCapture()`.

### 2. Web Extension Popup (`extensions/web_clipper/`)
- `manifest.json`: Manifest V3 config with activeTab, storage, and host permissions for `http://127.0.0.1:18420/*`.
- `popup.html` / `popup.js`: Mode selection UI, destination dropdown, status indicator, and API token configuration.
- `content_script.js`: DOM reader for readability extraction, selection capture, and screenshot bounds.

## Testing Strategy

- **Unit Tests:** `LocalClipperServer` endpoint routing, token authorization verification, and `CapturePayload` parsing.
- **Integration Tests:** HTTP POST requests to `127.0.0.1:18420/v1/capture` verifying atomic storage in `MindmapRepository` and search indexing.
- **Contract Tests:** Extension message payload format compatibility tests.

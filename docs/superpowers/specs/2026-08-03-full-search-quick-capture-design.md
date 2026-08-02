# Full Search and Quick Capture Design

## Goal

Make every stored item discoverable offline and let users quickly capture mixed content into a chosen board. Search covers node text, comments, metadata, attachments, document text, image OCR, and audio/video transcripts.

## Delivery Order

1. Build unified global search and extraction indexing.
2. Add in-app quick capture.
3. Add Android, iOS, macOS, and Windows share targets.
4. Add browser extension and web clipper.

Each stage uses same capture, extraction, duplicate-detection, and indexing services.

## Search Scope

Index searchable content from:

- Node titles, bodies, tags, types, statuses, dates, creators, and other user-facing metadata.
- Board and workspace names.
- Board and node comments.
- Attachment names, MIME types, URLs, and extracted document text.
- OCR text and regions from images.
- Transcripts and timestamps from audio and video.
- Captured article snapshots and bookmark previews.

Source records remain authoritative. Search documents are derived data and can be rebuilt.

## Architecture

### Search Index

`SearchIndexRepository` owns a local SQLite full-text index. Each search document references its source, workspace, board, node, creator, type, status, source revision, extraction state, timestamps, and optional location metadata such as transcript timestamp or OCR region.

Index writes are incremental and idempotent. Source creation or mutation upserts affected documents. Source deletion removes all derived documents. Startup reconciliation repairs missed updates without rebuilding healthy entries.

### Content Extraction

`ContentExtractionPipeline` processes content in background:

1. Extract text locally when platform support exists.
2. Use local parsers for supported documents.
3. Run local OCR or transcription when available.
4. Fall back to configured cloud extraction only when user enabled cloud processing and item is not marked local-only.
5. Store normalized extraction results and searchable text locally.

Extraction states are `queued`, `processing`, `ready`, `partial`, and `failed`. Failure never rolls back source capture. Metadata remains searchable while extraction can be retried.

`CloudExtractionService` is provider-neutral at domain boundary. Provider configuration stays in data/application layers. Temporary uploads and files are deleted after processing.

### Search Service

`SearchService` queries local index and applies:

- Full-text relevance.
- Recency boost.
- Active workspace boost.
- Explicit filters for date, type, workspace, board, creator, and status.

Filters are hard constraints and always override boosts. Stable tie-breaking uses last-edited time then source ID.

### Capture Service

`CaptureService` accepts one mixed payload containing text, URLs, images, files, and clipboard content. It validates trust-boundary input, normalizes content, detects duplicates, stores source items, and queues extraction/indexing.

Capture and indexing are separate transactions: durable source storage must succeed before background processing starts.

## Quick Capture Flow

1. User opens capture from app, OS share target, or browser extension.
2. Input parser shows detected text, URLs, images, and files before saving.
3. Duplicate detection compares canonical URL and content hash.
4. When match exists, user sees prior item and chooses open existing or create copy.
5. Destination picker requires explicit selection and offers recent boards, board search, and create board.
6. Capture stores source content atomically in selected board.
7. Extraction and indexing continue in background with visible per-item status.

Last destination may be highlighted but never submitted automatically.

## URL Capture

URL classification is automatic:

- Article-like pages store canonical URL, metadata, readable snapshot, and required local assets for offline reading.
- Other pages store bookmark metadata and preview.
- Classification or snapshot failure falls back to bookmark capture rather than failing whole operation.
- Canonical URL drives duplicate detection; user can still create a copy.

Remote content is treated as untrusted. HTML is sanitized before local display, executable content is discarded, redirects are bounded, and private/local network fetches are rejected.

## Search Experience

### Command Palette

`Ctrl/Cmd+K` provides fast global results, keyboard navigation, recent queries, filter shortcuts, and direct navigation to source node or attachment context.

### Search Page

Dedicated Search page provides:

- Full previews and match highlighting.
- Date, type, workspace, board, creator, and status filters.
- OCR region or transcript timestamp when available.
- Extraction state and retry action for partial or failed items.
- Direct opening of parent node with matching attachment or comment highlighted.

Both surfaces use same query and ranking service.

## Offline and Sync

After first successful processing, extracted text and index remain available offline. Search does not require network access.

Sync transfers authoritative source content using existing sync rules. Extracted documents may sync only when encryption, permissions, provider policy, and schema compatibility permit it; otherwise each device rebuilds missing derived data. Search results must never expose content unavailable to current workspace permissions.

## Privacy and Settings

Cloud OCR/transcription is disabled by default. Settings provides one explicit opt-in that shows:

- Content categories eligible for upload.
- Estimated upload size before each queued batch.
- Active provider and processing status.
- Option to mark individual content local-only.
- Action to delete locally stored cloud-derived results and request provider-side deletion where supported.

Disabling cloud processing stops new uploads but preserves local results until user deletes them.

## Limits and Failure Handling

- Validate allowed types, file signatures, size, count, and destination permissions.
- Enforce extraction timeouts, cancellation, bounded retries with backoff, and concurrency limits.
- Hash streaming avoids loading large files wholly into memory.
- Capture remains usable when extractor, cloud provider, or index is unavailable.
- Partial mixed captures report failed members and preserve successfully stored members only after user confirms partial save.
- Index corruption triggers safe rebuild from authoritative local sources.
- Temporary files are cleaned after success, failure, cancellation, and startup recovery.

## Testing

- Search document codecs, source references, incremental upsert/delete, reconciliation, and corruption rebuild.
- Ranking relevance, recency, active-workspace boost, stable ties, and every filter.
- Node, metadata, comment, attachment, document, OCR, transcript, snapshot, and bookmark indexing.
- Offline search after restart and network removal.
- Local-first extraction, cloud permission gate, local-only override, upload estimate, cancellation, retry, and deletion.
- Mixed capture parsing, validation, atomic storage, partial-save confirmation, and destination permissions.
- Canonical URL and content-hash duplicate flows, including explicit copy creation.
- Article classification, sanitized snapshot, bookmark fallback, redirect bounds, and private-network rejection.
- Command palette keyboard flow and Search page filtering, previews, highlights, source navigation, OCR regions, and transcript timestamps.
- Workspace permission isolation and deletion propagation.
- Android, iOS, macOS, and Windows share-target contract tests before each platform stage.
- Browser extension message validation and capture contract tests before web-clipper release.

## Deliberate Limits

- No semantic/vector search in first release; add only when full-text metrics show clear missed-query demand.
- No automatic destination selection.
- No automatic duplicate merging.
- No mandatory cloud processing.
- No cross-workspace result leakage, even for duplicate detection.
- No background website recrawling; snapshots update only through explicit recapture.
- Platform share targets and browser extension ship after in-app capture proves shared service contracts.

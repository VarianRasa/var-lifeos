# Resource Node Enhancement Design

**Date:** 2026-07-17
**Status:** Approved design, awaiting written-spec review

## Goal

Turn Resource nodes into structured asset records for one primary local file or URL, related assets, adaptive previews, and a three-level folder hierarchy. Expanded nodes size themselves from content without manual resize. Collapsed nodes remain manually resizable and show a bounded preview.

## Scope

Version one includes:

- dedicated `ResourcePayload`
- one primary file or URL asset
- multiple related file or URL assets
- adaptive preview by asset type
- folder path with at most three levels
- editable tags
- summary/description and long-form node content
- add, replace, edit label, open, copy location, and remove actions
- legacy Resource migration
- content-driven expanded sizing without resize handles
- bounded collapsed preview with manual resize
- validation and missing-file states

Version one excludes:

- automatic website metadata scraping
- website content downloads
- global folder database
- bulk folder rename across nodes
- unrestricted folder depth
- internal file editing
- cloud upload changes beyond existing attachment infrastructure
- automatic duplicate detection
- drag reordering of related assets

## Domain Model

### ResourcePayload

`ResourcePayload` is specific to `NodeType.resource` and no longer shares editing behavior with Link or Bookmark. It contains:

- `schemaVersion`: integer, initially `1`
- `primaryAsset`: nullable `ResourceAsset`
- `relatedAssets`: ordered list of `ResourceAsset`
- `folderPath`: ordered list of one to three folder names
- `description`: short asset summary
- `tags`: node tags exposed through the typed payload

Unknown Resource keys and unrelated node data remain preserved during reads and writes.

### ResourceAsset

Each asset contains:

- `id`: stable local identifier
- `kind`: `file` or `url`
- `label`: editable display label
- `location`: URL for URL assets; optional original file location metadata for local files
- `attachmentId`: attachment reference for managed local files
- `mimeType`: normalized MIME type when known
- `sizeBytes`: non-negative byte count when known
- `fileName`: original or inferred file name
- `extension`: normalized extension when known

A file asset uses the existing node attachment repository. Payload data does not embed file bytes. A URL asset accepts only absolute `http` or `https` URLs.

## Compatibility and Migration

Legacy Resource keys remain readable:

- `source`
- `category`
- `description`
- `links`
- node tags

When no structured Resource section exists:

- non-empty `source` becomes `primaryAsset`
- an HTTP or HTTPS source becomes a URL asset
- any other source remains a safe legacy location record and is not opened automatically as an arbitrary path
- each valid legacy link becomes a related URL asset
- non-empty `category` becomes the first folder segment
- `description` and node tags remain unchanged

Writes store the authoritative structured Resource section while retaining legacy summary keys for compatibility. Stable generated IDs make migration deterministic. Malformed legacy values are ignored instead of crashing.

## Folder Model

A Resource stores its folder as a path directly on the node:

```text
Research / Flutter / Rendering
```

Rules:

- zero to three segments
- trimmed, non-empty segment names
- path separator characters are rejected
- repeated adjacent segments are rejected
- folder suggestions are derived from paths used by other Resource nodes
- no separate folder table or global folder mutation exists in version one

The editor allows adding, renaming, and removing segments. Removing a parent also removes its descendants from that Resource path.

## Expanded Editor

The existing title and content fields remain. Content serves as long-form notes. Resource-specific controls appear below them.

### Primary Asset

The primary asset card provides:

- `Choose file`
- `Paste URL`
- adaptive preview
- asset label editing
- `Open`
- `Copy location`
- `Replace`
- `Remove`

Replacing the primary asset updates one payload entry and does not alter related assets.

### Adaptive Preview

Preview behavior:

- managed local images show a thumbnail
- image URLs may show a thumbnail when the URL is directly renderable, with a safe fallback card
- generic URLs show host/domain and external-link styling
- documents show file type, name, and size
- audio and video show media type, name, and size
- unknown types show a generic file card
- missing or unreadable local files show `Unavailable`

Preview failure never blocks editing or saving.

### Related Assets

Related assets appear as bounded cards. Each supports:

- file or URL creation
- label editing
- preview/type icon
- open
- copy location
- remove

Version one preserves insertion order and does not add drag reordering.

### Folder and Tags

Folder uses an editable breadcrumb with no more than three levels. Tags use chips with explicit add, edit, and remove actions. Empty values are never persisted.

### Sizing

Expanded Resource nodes:

- use a comfortable fixed width
- calculate height from preview, folder controls, tags, description, and related asset count
- ignore persisted custom dimensions
- expose no resize handles
- rely on the outer inline workspace scroll when the viewport is smaller

Collapsed Resource nodes keep persisted/manual dimensions and resize handles.

## Collapsed Preview

Collapsed Resource details are non-interactive so node drag and resize gestures remain available. The preview shows, within available space:

- primary thumbnail or asset icon
- primary label or domain
- type and size metadata when available
- folder breadcrumb, truncated safely
- related asset count
- up to a bounded number of tags

Small custom sizes use fewer labels rather than overflowing. Missing files show an unavailable indicator without exceptions.

## Persistence and Attachment Behavior

Local file selection uses existing attachment import and storage services. `ResourcePayload` references the resulting attachment ID. URL assets store only validated URLs and display metadata.

Removing an asset removes its Resource reference. Physical attachment cleanup must use existing reference-safe cleanup behavior; version one does not directly delete shared bytes from the editor.

Every payload mutation flows through the existing inline draft/update path so normal autosave and mindmap invalidation remain intact.

## Validation

Validation reports clear field-level errors for:

- unsupported schema version
- unsupported asset kind
- duplicate or empty asset IDs
- URL assets without valid HTTP/HTTPS URLs
- file assets without a usable attachment or safe legacy record
- negative file sizes
- malformed MIME type or extension values
- empty labels when no file name/domain fallback exists
- more than three folder segments
- empty or invalid folder names
- duplicate adjacent folder segments
- empty tags

Invalid drafts remain editable. Saving preserves last valid data and never discards unrelated node keys.

## Error Handling

- file picker cancellation makes no change
- attachment import failure displays an inline or snackbar error
- URL validation failure keeps entered text available for correction
- open failure displays feedback instead of throwing
- unavailable local files retain metadata and can be replaced or removed
- preview loading failure falls back to a generic asset card

## Testing

### Domain

- structured payload round trip
- unknown key preservation
- deterministic legacy migration
- URL and file validation
- folder depth and segment validation
- duplicate asset ID rejection
- node tag synchronization

### Editor

- choose/cancel local file
- add valid and invalid URL
- replace/remove primary asset
- add/edit/remove related assets
- folder segment add/edit/remove at three-level limit
- tag add/edit/remove
- adaptive preview and unavailable fallback
- open/copy callbacks
- no overflow at supported widths

### Canvas Integration

- collapsed preview is bounded and non-interactive
- expanded Resource ignores persisted custom size
- expanded Resource has no resize handles
- collapsed Resource retains resize handles
- expanded height grows with related asset count
- legacy Resource still renders

## Deliberate Simplifications

- Folder paths live on Resource nodes; add a global folder entity only when cross-node rename and folder management become required.
- URL previews use stored URL information; add metadata scraping only through an explicit backend or cache.
- Related assets preserve insertion order; add drag ordering only after users need manual ranking.
- Physical attachment deletion stays reference-safe and outside the editor; add explicit storage cleanup tooling separately.

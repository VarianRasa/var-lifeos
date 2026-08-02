# Complete Backend and Media Integration Design

## Goal

Complete remaining online and platform integrations for mindmap attachments without changing local-first node persistence or embedding binary data in node records.

The implementation adds:

- Firebase Storage as the default online attachment backend.
- An HTTP attachment adapter selected through `VAR_SYNC_ENDPOINT` when the server advertises attachment capability.
- Durable browser attachment storage.
- Local Image and Video file picking.
- Native video playback where the selected package supports the platform.
- Safe fallbacks on unsupported platforms.

## Existing Boundaries

- `MindmapNode.data` stores attachment metadata only.
- `NodeAttachmentRepository` owns local binary persistence.
- `AttachmentSyncPlanner` creates separate attachment work items.
- Normal node sync payloads never contain attachment bytes or local filesystem paths.
- Portable backup already encrypts attachment payloads through the existing AES-GCM/PBKDF2 envelope.
- Firebase Auth, Firestore, and a Firebase Storage bucket are configured for Web, Android, iOS, and macOS Firebase targets.
- `VAR_SYNC_ENDPOINT` selects optional HTTP sync adapters.

## Remote Attachment Architecture

### Contracts

Add a remote attachment contract separate from node metadata sync:

```dart
abstract interface class RemoteAttachmentStore {
  AttachmentSyncCapability get capability;

  Future<RemoteAttachmentMetadata?> head(String attachmentId);

  Future<void> upload({
    required NodeAttachment metadata,
    required Stream<List<int>> bytes,
  });

  Future<RemoteAttachmentDownload> download(String attachmentId);

  Future<void> delete({
    required String attachmentId,
    required String tombstoneVersion,
  });
}
```

The adapter validates attachment IDs, canonical remote keys, MIME, size, and SHA-256 before committing data locally or remotely.

### Adapter Selection

Selection order:

1. Use the HTTP attachment adapter when `VAR_SYNC_ENDPOINT` exists and `/capabilities` explicitly advertises attachment support.
2. Otherwise use Firebase Storage when Firebase is initialized, a user is authenticated, and the platform supports the adapter.
3. Otherwise report `localOnly` and keep attachment operations local.

Capability fallback never blocks existing node metadata sync.

### Canonical Remote Key

Firebase Storage objects use:

```text
attachments/{userId}/{attachmentId}
```

The HTTP contract exposes attachment IDs in routes and maps them to its own server-side namespace. Clients never submit arbitrary paths.

## Firebase Storage Adapter

- Add `firebase_storage` after confirming current FlutterFire compatibility.
- Require Firebase Auth identity before remote operations.
- Upload metadata includes attachment ID, SHA-256, byte length, MIME, normalized filename, and schema version.
- Download validates server metadata, byte count, and checksum before local import.
- Firebase Storage Security Rules restrict objects to the authenticated user namespace.
- Windows and Linux use another supported adapter or local-only fallback when FlutterFire Storage support is unavailable.

## HTTP Attachment Contract

The app implements a client adapter only. No server implementation is added to this repository.

### Capability

```http
GET /capabilities
```

Expected attachment response fields:

```json
{
  attachments: {
    version: 1,
    upload: true,
    download: true,
    delete: true,
    maxBytes: 104857600
  }
}
```

Missing, malformed, or unsupported capability leaves node metadata sync operational and selects Firebase Storage or local-only fallback.

### Routes

```text
HEAD   /attachments/{attachmentId}
PUT    /attachments/{attachmentId}
GET    /attachments/{attachmentId}
DELETE /attachments/{attachmentId}
```

Upload headers carry schema version, MIME, normalized filename, byte length, and SHA-256. Delete requires an explicit tombstone/version token. Authentication uses the existing HTTP sync authentication boundary; no private service credentials are stored in the Flutter client.

## Sync Execution

`AttachmentSyncPlanner` remains responsible for planning. Add an executor that:

- Runs attachment work separately from node metadata work.
- Uploads local-only referenced attachments.
- Downloads remote-only referenced attachments.
- Reports conflicts when local and remote metadata differ.
- Never automatically overwrites conflicts without a resolution policy.
- Retries idempotent operations with bounded backoff.
- Persists progress so interrupted sync can resume.
- Applies downloads through `NodeAttachmentRepository` only after complete validation.

Delete remains disabled until a tombstone owned by the current user/device is available.

## Durable Web Attachment Storage

Replace the bounded in-memory Web adapter with IndexedDB-backed blob persistence.

- Store metadata and bytes in separate object stores.
- Keep the existing repository contract.
- Use a transaction for metadata and byte writes.
- Verify checksum and length on read.
- Recover incomplete writes during initialization.
- Preserve the memory adapter only as a test adapter, not production Web storage.

OPFS can be added later only if browser support and migration requirements justify it.

## File Picker Integration

- Add `file_picker` after checking support for Android, iOS, Web, Windows, macOS, and Linux.
- Image accepts the existing concrete image MIME allowlist.
- Video accepts the existing concrete video MIME allowlist.
- Reject empty, oversized, extension/MIME-mismatched, or malformed files before import.
- Import bytes through `NodeAttachmentRepository`.
- Save only attachment metadata in `MindmapNode.data`.
- Replace actions preserve captions, alt text, playback position, fit, and unrelated payload fields.
- URL import and clipboard image URL remain available.

## Video Playback

- Prefer `video_player` if its supported platform matrix covers the current target sufficiently.
- Platforms unsupported by the selected player keep poster, resume position, export, and Open externally.
- Playback is wrapped behind a small presentation adapter so unsupported platforms compile without player-specific calls.
- Playback position writes use the existing debounced controller.
- Flush on pause, editor close, node switch, and app lifecycle pause.
- Never persist on every frame.
- Player errors are contained and surfaced as fallback UI.

## Security and Data Integrity

- Validate UUID attachment IDs at every trust boundary.
- Accept only canonical SHA-256 values.
- Validate concrete MIME types and byte limits.
- Never accept client-controlled remote object paths.
- Verify checksum and length after every download.
- Do not expose local paths in sync metadata.
- Do not place Firebase service credentials or HTTP secrets in the client.
- Keep Firebase Storage rules least-privilege by authenticated user namespace.
- Preserve valid local data if remote operations fail.

## Offline and Conflict Behavior

- Local imports succeed while offline.
- Pending upload/download work persists for later execution.
- Node metadata sync remains independent from attachment transfer failure.
- Missing remote blobs produce explicit warnings without deleting node metadata.
- Local/remote metadata mismatch creates a conflict; no automatic overwrite.
- Download failure never replaces a valid local attachment.

## Testing

### Unit

- Firebase and HTTP capability selection.
- HTTP request paths, headers, validation, and unsupported fallback.
- Firebase remote key ownership and metadata validation.
- Sync executor retries, resume state, conflicts, and idempotency.
- IndexedDB repository round-trip and transaction recovery.
- File picker validation and metadata-only node updates.
- Video adapter support/fallback and playback-position flush.

### Integration

- Local file import to local repository and node metadata.
- Local attachment upload, remote manifest planning, clean second sync.
- Remote-only attachment download and checksum validation.
- Offline import followed by reconnect upload.
- HTTP unsupported capability falling back to Firebase Storage.
- Conflict leaves both local data and remote object unchanged.
- Web reload preserves attachment bytes.

### Release Gates

```bash
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release --dart-define=VAR_DEMO_SEED=false
```

Run platform builds for targets affected by picker and playback integration where build tooling is available.

## Completion Criteria

- A user can select a local Image or Video file and reopen it after app restart.
- Web attachments survive browser reload.
- Referenced attachments upload through HTTP when capability exists, otherwise Firebase Storage when available.
- Remote-only referenced attachments download and validate locally.
- Metadata sync continues when attachment sync is unavailable.
- Supported platforms play Video nodes natively; unsupported platforms use the documented fallback.
- Backup/restore, sync conflicts, and offline behavior remain data-loss safe.
- Full tests, analyzer, formatting, and Web release build pass.

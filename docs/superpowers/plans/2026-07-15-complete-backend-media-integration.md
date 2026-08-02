# Complete Backend and Media Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete online attachment transfer, durable Web storage, local media picking, and native Video playback while preserving local-first node persistence and metadata-only node records.

**Architecture:** Keep `NodeAttachmentRepository` as local source of truth and add a separate `RemoteAttachmentStore` boundary. Capability selection prefers a capable HTTP server, falls back to authenticated Firebase Storage, then local-only behavior; IndexedDB, file picking, and video playback remain platform adapters behind conditional imports.

**Tech Stack:** Flutter 3.41, Dart 3.11, Riverpod, Sembast/IndexedDB, Firebase Auth/Storage, HTTP, file_picker, video_player, cryptography.

---

## File Structure

### Create

- `lib/features/sync/domain/remote_attachment_store.dart`: remote attachment metadata, transfer contract, capability result, and validation.
- `lib/features/sync/data/firebase_remote_attachment_store.dart`: authenticated Firebase Storage adapter.
- `lib/features/sync/data/http_remote_attachment_store.dart`: capability-aware HTTP adapter.
- `lib/features/sync/data/remote_attachment_store_stub.dart`: unsupported-platform fallback.
- `lib/features/sync/application/attachment_sync_executor.dart`: retryable upload/download execution and persisted progress.
- `lib/features/mindmap/data/indexeddb_node_attachment_repository_web.dart`: durable Web repository.
- `lib/features/mindmap/application/media_file_import_service.dart`: picker validation and repository import orchestration.
- `lib/features/mindmap/presentation/video_playback_adapter.dart`: platform-neutral player interface.
- `lib/features/mindmap/presentation/video_playback_adapter_supported.dart`: video_player implementation.
- `lib/features/mindmap/presentation/video_playback_adapter_stub.dart`: poster/external-open fallback.
- `storage.rules`: least-privilege Firebase Storage rules.
- Matching tests under `test/features/sync/` and `test/features/mindmap/`.

### Modify

- `pubspec.yaml`: add compatible `firebase_storage`, `file_picker`, and `video_player` packages.
- `firebase.json`: register Storage rules.
- `lib/features/sync/application/sync_providers.dart`: capability selection and executor providers.
- `lib/features/sync/application/sync_controller.dart`: execute attachment work after metadata planning without blocking metadata success.
- `lib/features/sync/domain/attachment_sync.dart`: expose execution-ready work and conflicts without local paths.
- `lib/features/mindmap/data/local_node_attachment_repository_web.dart`: route production Web to IndexedDB and retain memory repository for tests.
- `lib/features/calendar/day_page.dart`: enable local Image/Video picker actions.
- `lib/features/mindmap/presentation/mindmap_canvas.dart`: provide player and import/export states to media nodes.
- `lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart`: native player surface with fallback.
- `docs/release/beta_release_checklist.md`: add online attachment, Web reload, picker, and playback smoke tests.

---

### Task 1: Add remote attachment domain contract

**Files:**
- Create: `lib/features/sync/domain/remote_attachment_store.dart`
- Modify: `lib/features/sync/domain/attachment_sync.dart`
- Test: `test/features/sync/domain/remote_attachment_store_test.dart`

- [ ] **Step 1: Write failing contract tests**

Test canonical attachment IDs, SHA-256, MIME, size, `attachments/{userId}/{attachmentId}` Firebase keys, HTTP route IDs, and metadata equality.

```dart
test('rejects client controlled remote paths', () {
  expect(
    () => RemoteAttachmentMetadata(
      attachmentId: validId,
      checksum: validChecksum,
      byteLength: 42,
      mimeType: 'image/png',
      fileName: 'image.png',
      remoteObjectKey: '../private/file',
    ),
    throwsFormatException,
  );
});
```

- [ ] **Step 2: Run test and confirm failure**

Run: `flutter test test/features/sync/domain/remote_attachment_store_test.dart`

Expected: compile failure because the contract does not exist.

- [ ] **Step 3: Implement minimal contract**

Define `RemoteAttachmentStore`, `RemoteAttachmentMetadata`, `RemoteAttachmentDownload`, transfer exceptions, and capability values. Upload accepts bytes or a bounded stream; download returns metadata plus verified bytes. Delete requires a tombstone version but remains unused until Task 5 provides ownership data.

- [ ] **Step 4: Run domain tests**

Run:

```bash
flutter test test/features/sync/domain/remote_attachment_store_test.dart
flutter test test/features/sync/domain/attachment_sync_test.dart
```

Expected: tests pass and normal node work items still contain no bytes or local paths.

### Task 2: Add dependencies and Firebase Storage rules

**Files:**
- Modify: `pubspec.yaml`
- Create: `storage.rules`
- Modify: `firebase.json`
- Test: `test/features/sync/data/firebase_remote_attachment_store_test.dart`

- [ ] **Step 1: Resolve compatible packages**

Run:

```bash
flutter pub add firebase_storage file_picker video_player
```

Expected: Pub resolves versions compatible with Flutter 3.41/Dart 3.11. Do not force a version that downgrades existing FlutterFire packages.

- [ ] **Step 2: Add Storage rules**

Use authenticated user ownership:

```text
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /attachments/{userId}/{attachmentId} {
      allow read, write: if request.auth != null
        && request.auth.uid == userId
        && attachmentId.matches('^[0-9a-fA-F-]{36}$');
    }
  }
}
```

Register `storage.rules` in `firebase.json`. Client validation remains mandatory; rules are defense in depth.

- [ ] **Step 3: Add Firebase adapter tests with a fake gateway**

Do not require a live Firebase project in unit tests. Inject a small gateway that records path, metadata, bytes, and auth UID.

- [ ] **Step 4: Run dependency and test checks**

Run:

```bash
flutter pub get
flutter test test/features/sync/data/firebase_remote_attachment_store_test.dart
flutter analyze pubspec.yaml lib/features/sync
```

### Task 3: Implement Firebase Storage adapter

**Files:**
- Create: `lib/features/sync/data/firebase_remote_attachment_store.dart`
- Create: `lib/features/sync/data/remote_attachment_store_stub.dart`
- Modify: `lib/features/sync/application/sync_providers.dart`
- Test: `test/features/sync/data/firebase_remote_attachment_store_test.dart`
- Test: `test/features/sync/application/sync_providers_test.dart`

- [ ] **Step 1: Write failing upload/download tests**

Cover authenticated key ownership, unauthenticated rejection, upload metadata, checksum validation, corrupt download rejection, missing object, and unsupported-platform fallback.

- [ ] **Step 2: Implement adapter**

Use Firebase Storage references under `attachments/{uid}/{attachmentId}`. Store metadata keys `schemaVersion`, `attachmentId`, `checksum`, `byteLength`, `mimeType`, and `fileName`. Verify downloaded bytes before returning them.

- [ ] **Step 3: Add provider fallback**

Firebase adapter is eligible only when Firebase is initialized, Auth has a user, and platform support is available. Otherwise return `localOnly` without throwing during app boot.

- [ ] **Step 4: Run focused tests**

Run:

```bash
flutter test test/features/sync/data/firebase_remote_attachment_store_test.dart
flutter test test/features/sync/application/sync_providers_test.dart
```

### Task 4: Implement HTTP capability and attachment adapter

**Files:**
- Create: `lib/features/sync/data/http_remote_attachment_store.dart`
- Modify: `lib/features/sync/application/sync_providers.dart`
- Test: `test/features/sync/data/http_remote_attachment_store_test.dart`

- [ ] **Step 1: Write capability tests**

Cover valid `/capabilities`, missing attachment section, malformed JSON, unsupported version, server limits, authentication headers, and fallback to Firebase/local.

- [ ] **Step 2: Write route tests**

Assert exact requests:

```text
HEAD /attachments/{id}
PUT /attachments/{id}
GET /attachments/{id}
DELETE /attachments/{id}
```

Reject redirects to another host, oversized downloads, mismatched metadata, unsafe IDs, and non-success status codes.

- [ ] **Step 3: Implement adapter**

Use the existing HTTP client/auth boundary. Capability must be fetched before attachment work. Missing support does not affect node metadata sync.

- [ ] **Step 4: Run tests**

Run:

```bash
flutter test test/features/sync/data/http_remote_attachment_store_test.dart
flutter test test/features/sync/application/sync_providers_test.dart
```

### Task 5: Execute and persist attachment sync work

**Files:**
- Create: `lib/features/sync/application/attachment_sync_executor.dart`
- Modify: `lib/features/sync/application/sync_controller.dart`
- Modify: sync state storage models discovered in `lib/features/sync/domain/` and `lib/features/sync/data/`
- Test: `test/features/sync/application/attachment_sync_executor_test.dart`
- Test: `test/features/sync/application/sync_controller_test.dart`

- [ ] **Step 1: Write executor tests**

Cover upload, download, retry, resume after interruption, idempotent second run, conflict no-op, corrupt download, remote unavailable, and metadata sync success despite attachment failure.

- [ ] **Step 2: Implement progress model**

Persist attachment ID, direction, remote store kind, attempt count, next retry time, and last error. Never persist bytes or local paths.

- [ ] **Step 3: Implement execution**

Uploads read verified local bytes immediately before transfer. Downloads verify metadata and bytes, then import through `NodeAttachmentRepository` with stable ID. Use bounded exponential backoff. Do not execute delete work until tombstone ownership exists.

- [ ] **Step 4: Integrate after metadata sync**

Metadata sync result remains successful when attachment capability is unavailable. Report attachment warnings separately in sync status/activity.

- [ ] **Step 5: Run sync suites**

Run:

```bash
flutter test test/features/sync/application/attachment_sync_executor_test.dart
flutter test test/features/sync/application/sync_controller_test.dart
flutter test test/features/sync
```

### Task 6: Replace Web memory storage with IndexedDB

**Files:**
- Create: `lib/features/mindmap/data/indexeddb_node_attachment_repository_web.dart`
- Modify: `lib/features/mindmap/data/local_node_attachment_repository_web.dart`
- Test: `test/features/mindmap/data/indexeddb_node_attachment_repository_web_test.dart`

- [ ] **Step 1: Write browser repository contract tests**

Run tests on Chrome. Cover import, reload/reopen, read, export, delete, manifest, corrupt transaction recovery, checksum, quota error, and concurrent writes.

- [ ] **Step 2: Implement IndexedDB stores**

Use one database with `metadata` and `blobs` object stores. Write both in one transaction. Store raw bytes as browser-supported binary data, not Base64.

- [ ] **Step 3: Add initialization recovery**

Remove metadata without blobs, blobs without metadata, and incomplete transaction markers without touching valid entries.

- [ ] **Step 4: Route production Web adapter**

Keep the bounded memory repository injectable for tests only. Production Web must open IndexedDB.

- [ ] **Step 5: Run Web tests**

Run:

```bash
flutter test -d chrome test/features/mindmap/data/indexeddb_node_attachment_repository_web_test.dart
flutter build web --release --dart-define=VAR_DEMO_SEED=false
```

### Task 7: Enable local Image and Video file picking

**Files:**
- Create: `lib/features/mindmap/application/media_file_import_service.dart`
- Modify: `lib/features/calendar/day_page.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/application/media_file_import_service_test.dart`
- Test: `test/features/calendar/day_page_test.dart`

- [ ] **Step 1: Write validation tests**

Cover cancel, empty bytes, oversized bytes, unsupported MIME, extension mismatch, picker path-only results, Web in-memory bytes, and preserved unrelated payload fields during Replace.

- [ ] **Step 2: Implement import service**

The service receives picker output, derives bytes without exposing local paths to node data, validates through attachment constants, imports through `NodeAttachmentRepository`, and returns an `ImagePayload` or `VideoPayload` metadata patch.

- [ ] **Step 3: Enable visible picker actions**

Replace the disabled local option with working Image/Video pick actions. Keep URL import. Show contained errors and leave the previous attachment unchanged when import fails.

- [ ] **Step 4: Run picker tests**

Run:

```bash
flutter test test/features/mindmap/application/media_file_import_service_test.dart
flutter test test/features/calendar/day_page_test.dart --name Image|Video|Replace
```

### Task 8: Add native Video playback adapter

**Files:**
- Create: `lib/features/mindmap/presentation/video_playback_adapter.dart`
- Create: `lib/features/mindmap/presentation/video_playback_adapter_supported.dart`
- Create: `lib/features/mindmap/presentation/video_playback_adapter_stub.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/video_playback_adapter_test.dart`
- Test: `test/features/mindmap/presentation/video_node_editor_test.dart`

- [ ] **Step 1: Write adapter lifecycle tests**

Cover initialize, play, pause, seek, mute, error fallback, node/source switch, dispose, lifecycle pause, and position persistence debounce.

- [ ] **Step 2: Implement supported adapter**

Wrap `video_player` behind the neutral interface. Network sources accept only valid HTTP(S). Local attachment playback uses a platform-safe temporary/export URI only where supported; Web uses a Blob URL with explicit revoke on dispose.

- [ ] **Step 3: Implement unsupported fallback**

Compile-safe fallback exposes poster, resume position, export, and Open externally without presenting fake playback controls.

- [ ] **Step 4: Integrate editor**

Large/Wide nodes show the native surface when adapter initialization succeeds. Compact/Standard keep bounded poster views. Reuse the existing `VideoPlaybackDraftController` for throttled position persistence.

- [ ] **Step 5: Run playback tests**

Run:

```bash
flutter test test/features/mindmap/presentation/video_playback_adapter_test.dart
flutter test test/features/mindmap/presentation/video_node_editor_test.dart
```

### Task 9: End-to-end integration and release verification

**Files:**
- Modify: `docs/release/beta_release_checklist.md`
- Test: integration tests under `test/features/sync/` and `test/features/mindmap/`

- [ ] **Step 1: Add end-to-end tests**

Test local picker import, offline queue, Firebase upload, HTTP capability fallback, remote download, Web reopen, conflict preservation, backup round-trip, and playback fallback.

- [ ] **Step 2: Update manual checklist**

Add Firebase Storage rules deployment, HTTP capability smoke, local file picker on mobile/desktop/Web, Web reload persistence, remote conflict, and native/fallback playback checks.

- [ ] **Step 3: Run focused verification**

```bash
flutter test test/features/mindmap
flutter test test/features/sync
flutter test test/features/calendar/day_page_test.dart
flutter analyze
```

- [ ] **Step 4: Run beta preflight**

```bash
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release --dart-define=VAR_DEMO_SEED=false
```

- [ ] **Step 5: Run available platform builds**

```bash
flutter build apk
flutter build windows
```

Run iOS/macOS/Linux builds only on hosts with their required toolchains. A platform build failure caused by unavailable host tooling must be documented; code/test failures must be fixed.

---

## Execution Order

1. Tasks 1-5 complete remote transfer and capability selection.
2. Task 6 makes Web attachments durable.
3. Task 7 exposes local binary import.
4. Task 8 adds native playback with safe fallback.
5. Task 9 verifies offline, backend, Web, picker, playback, backup, and release behavior together.

Do not start attachment execution before both remote adapters pass contract tests. Do not remove existing local-only or poster fallbacks until every supported platform has a verified replacement.

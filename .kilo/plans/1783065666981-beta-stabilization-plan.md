# Beta stabilization plan: Firebase Auth + Firestore sync

## Goal

Stabilize Var beta by replacing placeholder/local sync auth with required Firebase Auth, moving cloud sync to Firestore per-node storage, preserving local-first behavior, and fixing the known `NodeEditorPanel` test timeout.

## Confirmed decisions

- Firebase project: create new project `var-app-prod` with display name `Var`.
- Firebase is required for beta cloud sync/auth.
- Beta platform scope: Web + Android.
- Auth scope: full auth flow.
  - Sign in with email/password.
  - Register with email/password.
  - Reset password.
  - Sign out.
  - Persist/auth state handling.
- Cloud sync storage: Firestore.
- Firestore model: per-node documents, not one large backup document.
- First Firebase login behavior: merge local + cloud data; do not delete local data automatically.
- Portable encrypted backup remains for offline export/import/restore.
- Also fix current test timeout in `test/features/mindmap/presentation/node_editor_panel_test.dart`.

## Current repo state

- No Firebase config found:
  - no `firebase.json`
  - no `lib/firebase_options.dart`
  - no `google-services.json`
  - no `GoogleService-Info.plist`
  - no `firebase_core`, `firebase_auth`, `cloud_firestore` deps
- Android package/application id: `com.varapp.dev` in `android/app/build.gradle.kts`.
- Web app metadata already uses `Var`.
- Current sync auth abstractions:
  - `lib/features/sync/domain/sync_account.dart`
  - `SyncAuthGateway.signIn({email, displayName})`
  - local fallback via `SembastSyncAuthGateway`
  - REST auth via `HttpSyncAuthGateway`
- Current cloud sync remote model:
  - `SyncRemoteBackupStore`
  - `MindmapBackupDocument` containing all nodes
  - HTTP store at `HttpSyncRemoteBackupStore`
- Current backup doc is full-document based and can exceed Firestore 1 MiB if stored as one doc.

## Implementation phases

### Phase 1 — Firebase setup

1. Create Firebase project:
   - projectId: `var-app-prod`
   - displayName: `Var`
   - if unavailable, use unique suffix and update all config references.
2. Enable Firebase products:
   - Authentication: Email/password provider.
   - Cloud Firestore.
3. Register apps:
   - Web app: `Var Web`.
   - Android app: package `com.varapp.dev`.
4. Add FlutterFire config:
   - `lib/firebase_options.dart`
   - `android/app/google-services.json`
   - web config embedded via `firebase_options.dart`.
5. Add dependencies to `pubspec.yaml`:
   - `firebase_core`
   - `firebase_auth`
   - `cloud_firestore`
6. Android Gradle changes:
   - add Google services plugin as required by FlutterFire.
   - ensure Android build remains valid.
7. App bootstrap:
   - initialize Firebase before `runApp` in `lib/main.dart`.
   - use `DefaultFirebaseOptions.currentPlatform`.

### Phase 2 — Auth domain refactor

1. Update `SyncAuthGateway` contract in `lib/features/sync/domain/sync_account.dart`:
   - `signIn({required String email, required String password})`
   - add `register({required String email, required String password})`
   - add `sendPasswordResetEmail(String email)`
   - keep `signOut()` and `currentState()`.
2. Keep `SyncUser` as app-level user projection:
   - id = Firebase UID
   - email = Firebase email
   - displayName optional if later supported.
3. Implement `FirebaseSyncAuthGateway`:
   - wraps `FirebaseAuth.instance`
   - maps `User` to `SyncAuthState.signedIn`
   - includes `accessToken` from `getIdToken()` if still needed by legacy HTTP paths/tests.
   - handles auth errors with user-safe messages.
4. Decide legacy gateways:
   - Update `LocalSyncAuthGateway`/`SembastSyncAuthGateway` signatures for tests only, or remove provider use from production.
   - Keep in-memory/local versions for unit/widget tests.
5. Update tests for auth contract.

### Phase 3 — Auth UI in Settings

1. Replace hardcoded `_toggleSignIn()` using `local@var.app` in `lib/features/settings/settings_page.dart`.
2. Add auth dialog/card:
   - email field
   - password field
   - sign in action
   - create account/register action
   - reset password action
   - loading/error/success states
3. Validation:
   - email nonempty and basic format
   - password nonempty for sign-in
   - password min length for registration, matching Firebase requirements.
4. Preserve existing sync card metrics, activity log, restore points, and conflict queue.
5. On sign-in success:
   - trigger load/sync state refresh.
   - run first-login merge flow or prompt-free merge according to confirmed decision.
6. On sign-out:
   - keep local data.
   - clear remote auth state.

### Phase 4 — Firestore per-node sync store

1. Introduce Firestore sync adapter, likely new file:
   - `lib/features/sync/data/firestore_sync_remote_node_store.dart`
2. Firestore path:
   - `users/{uid}/nodes/{nodeId}`
   - optional metadata: `users/{uid}/sync/state/latest`
3. Node document fields:
   - all `MindmapNode.toJson()` data
   - `updatedAt`
   - `deletedAt` for tombstones if needed
   - `schemaVersion`
   - `sourceDevice`
4. Avoid single Firestore backup doc.
5. Support fetch latest cloud state:
   - fetch all user node docs or paginated batches.
   - convert docs into `MindmapNode` list and tombstone list.
6. Support upload merged local state:
   - batch writes with Firestore batch limit safety.
   - delete/tombstone handling.
7. Keep `MindmapBackupDocument` for portable offline backup only.
8. Existing `CloudSyncService` can be adapted in either of two ways:
   - Preferred: introduce a new `SyncRemoteNodeStore` contract and update cloud service to sync nodes/tombstones per node.
   - Faster transitional approach: implement a Firestore adapter that reconstructs `MindmapBackupDocument` from per-node docs while storing documents per-node under the hood.
9. Conflict behavior:
   - reuse `MindmapSyncPlanner` per node.
   - conflict summaries stay in Settings.
10. Baseline:
   - keep local `SyncStateStore` baseline per user.
   - baseline user id must be Firebase UID.

### Phase 5 — Provider wiring

1. Update `lib/features/sync/application/sync_providers.dart`:
   - use `FirebaseSyncAuthGateway` for production.
   - use Firestore remote store instead of HTTP remote store.
2. Runtime config changes:
   - `VAR_SYNC_ENDPOINT` becomes legacy/out-of-scope for beta, or retained only for tests/dev if needed.
   - document Firebase-required behavior.
3. Tests should override providers with in-memory/local adapters.

### Phase 6 — Firestore security rules

Add Firestore rules equivalent to:

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

Recommended validation additions:
- `schemaVersion` required for node writes.
- deny cross-user writes.
- optionally restrict max node doc size/fields.

### Phase 7 — Local/cloud merge behavior

On first sign-in:
1. Load local nodes.
2. Load Firestore nodes for UID.
3. Load local baseline for UID if any.
4. Run merge:
   - no cloud data → upload local nodes.
   - no local data → import cloud nodes.
   - both present → use `MindmapSyncPlanner` with baseline if available.
5. If conflicts:
   - keep local data unchanged until resolved.
   - show conflict queue.
6. If no conflicts:
   - save merged nodes locally.
   - write merged state to Firestore.
   - update baseline.

### Phase 8 — Fix NodeEditorPanel test timeout

Current log:
- `flutter_test_object_panel.log`
- failing test: `NodeEditorPanel shows object properties and copies wiki link`
- timeout after `tester.pumpAndSettle()` around copy/snackbar.

Plan:
1. Run targeted test:
   - `flutter test test/features/mindmap/presentation/node_editor_panel_test.dart -r expanded`
2. Replace fragile `pumpAndSettle()` in that test with deterministic pumps:
   - after widget mount: `await tester.pump()` / finite duration
   - after snackbar: `await tester.pump()` or `await tester.pump(const Duration(milliseconds: 100))`
3. If widget has infinite transient animation, identify source via test binding transient callbacks.
4. Keep assertion:
   - clipboard = `[[Health Goal]]`
   - snackbar text visible.
5. Run full file test.

### Phase 9 — Tests

Add/update tests:
- `firebase_sync_auth_gateway_test.dart` with fake/mocked Firebase if feasible; otherwise provider-level adapter tests behind abstractions.
- `firestore_sync_remote_node_store_test.dart` using fake/emulator if available, or abstraction-level fake.
- `sync_providers_test.dart` updated for Firebase/Firestore production wiring and provider overrides.
- `settings_page_test.dart` for:
  - sign-in dialog
  - register flow
  - reset password flow
  - sign-out keeps local data
  - invalid credential error state
  - first login merge behavior
- `cloud_sync_service_test.dart` or new sync service tests for per-node Firestore model.
- Keep existing portable backup tests unchanged unless contract requires.

### Phase 10 — Validation commands

Run after implementation:

```powershell
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release --dart-define=VAR_DEMO_SEED=false
```

Targeted tests during work:

```powershell
flutter test test/features/mindmap/presentation/node_editor_panel_test.dart -r expanded
flutter test test/features/settings/settings_page_test.dart -r expanded
flutter test test/features/sync -r expanded
```

Android smoke after Firebase config:

```powershell
flutter build apk --debug
```

## Risks / caveats

- Creating a new Firebase project is an external action; confirm before actual creation.
- `var-app-prod` projectId may be unavailable; use suffix if needed.
- Web + Android only for beta. iOS/macOS/Windows need separate Firebase config/support decisions later.
- Firestore per-node sync is larger than simply replacing auth; do it behind tests and keep portable backup stable.
- Firestore offline cache plus local Sembast can create two local stores; app source of truth should remain Sembast, with Firestore only as cloud sync backend.
- Firestore write costs scale with node count; batch and debounce future real-time sync.
- Avoid logging Firebase tokens/passwords.

## Definition of done

- Firebase initializes on Web and Android.
- User can register, sign in, reset password, sign out.
- Local data remains intact through auth state changes.
- First login merges local/cloud data.
- Sync stores nodes in Firestore per user/per node.
- Conflict queue still works for edit/edit and delete/edit cases.
- Portable encrypted backup still works.
- `NodeEditorPanel` timeout fixed.
- Format/analyze/tests/web build pass.

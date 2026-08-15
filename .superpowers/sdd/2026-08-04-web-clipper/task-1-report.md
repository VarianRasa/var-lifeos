# Task 1 Report: Local Clipper HTTP Server & Auth Token Manager

## Status: DONE

## Commit
`40340c6` — `feat: add LocalClipperServer for Web Clipper API communication`

## Files Created
- `lib/core/services/local_clipper_server.dart`
- `test/core/services/local_clipper_server_test.dart`

## Implementation Summary

### LocalClipperServer
- Binds to `127.0.0.1:18420` (loopback only)
- `Authorization: Bearer <token>` required on all endpoints; returns 401 JSON if missing/invalid
- `GET /v1/boards` → 200 with `{"boards": [...]}`
- `POST /v1/capture` → 200 with `{"status": "success", "nodeId": "..."}` or 400 on error
- Unknown routes → 404
- All responses are JSON with proper `Content-Type`
- `localClipperServerProvider` Riverpod provider wired to `captureServiceProvider`

### Tests (4/4 pass)
1. `rejects requests without valid authorization token` — verifies 401
2. `returns boards list when authorized` — verifies 200 + JSON boards array
3. `captures payload when authorized` — verifies 200 + success status + nodeId
4. `returns 404 for unknown endpoints` — verifies 404

### TDD Compliance
- RED: Test written first, confirmed compilation failure (no implementation file)
- GREEN: Implementation written, all 4 tests pass
- `flutter analyze` — no issues found

## Deviations from Brief
- Added `captures payload when authorized` and `returns 404 for unknown endpoints` tests (brief only had 2; these cover the remaining endpoints)
- `_handleRequest` uses `Future<void>` return type with `await request.response.close()` instead of sync `void` with `..close()` cascade — avoids potential unawaited-futures lint
- `localClipperServerProvider` uses `captureServiceProvider.valueOrNull` since upstream is `FutureProvider<CaptureService>`, not `Provider<CaptureService>`

## Review Fixes

### Status: DONE

- Malformed JSON and request decoding errors now return 400 JSON with a closed response.
- Request bodies are capped at 1 MiB, enforced for known and streamed content lengths.
- Server exposes its actual bound `port`; tests use OS-assigned port `0` to avoid collisions.
- Hardcoded provider token retains plan behavior with a `ponytail` upgrade-path comment.
- Added malformed JSON regression coverage.

### Verification

- `flutter test test/core/services/local_clipper_server_test.dart` — 5/5 passed
- `flutter analyze lib/core/services/local_clipper_server.dart test/core/services/local_clipper_server_test.dart` — no issues found

### Fix Commit

`fix: address review findings for LocalClipperServer`

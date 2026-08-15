# Audio Node Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-first Audio node with recording, file import, HTTPS playback, timestamped manual/AI transcripts, compact collapsed controls, and free-only OpenRouter transcription through Cloudflare Worker.

**Architecture:** Extend the pure Dart payload first, reuse `NodeAttachmentRepository` for app-owned audio, isolate plugin playback/recording behind presentation/application boundaries, and add a separate HTTP transcription repository. Cloudflare Worker owns the OpenRouter secret and rejects paid model routes.

**Tech Stack:** Flutter, Riverpod, Sembast attachment storage, `file_picker`, `record`, `just_audio`, `http`, Cloudflare Workers TypeScript, Vitest.

---

### Task 1: Audio Payload and Validation

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart`

- [ ] Add failing tests for legacy migration, attachment/URL sources, timestamp segment ordering, 25 MB limit, and data round-trip.
- [ ] Run `flutter test test/features/mindmap/domain/node_type_payloads_test.dart` and confirm new tests fail.
- [ ] Add `AudioSourceType`, `AudioTranscriptSegment`, enriched `AudioPayload`, compatibility fields, `copyWith`, serialization, and validation.
- [ ] Re-run focused domain tests and confirm pass.

### Task 2: Audio File Import

**Files:**
- Modify: `lib/features/mindmap/application/media_file_import_service.dart`
- Test: `test/features/mindmap/application/media_file_import_service_test.dart`

- [ ] Add failing tests for valid audio import, cancellation, empty file, bad extension/MIME, magic-byte mismatch, and 25 MB rejection.
- [ ] Run focused import tests and confirm failure.
- [ ] Add `MediaFileKind.audio`, audio extension/MIME validation, and `pickAudio()` returning attachment metadata in `AudioPayload`.
- [ ] Re-run focused import tests and confirm pass.

### Task 3: Runtime Transcription Contract

**Files:**
- Modify: `lib/core/config/runtime_config.dart`
- Create: `lib/features/mindmap/domain/audio_transcription.dart`
- Create: `lib/features/mindmap/data/http_audio_transcription_repository.dart`
- Test: `test/core/config/runtime_config_test.dart`
- Create: `test/features/mindmap/data/http_audio_transcription_repository_test.dart`

- [ ] Add failing tests for `VAR_AUDIO_TRANSCRIPTION_ENDPOINT`, normalized timestamp segments, unavailable-free-model errors, HTTP failures, and malformed responses.
- [ ] Run focused config/repository tests and confirm failure.
- [ ] Add endpoint config, repository interface, result/error types, multipart HTTP adapter, and atomic response validation.
- [ ] Re-run focused tests and confirm pass.

### Task 4: Cloudflare Free-Only Worker

**Files:**
- Create: `workers/audio-transcription/package.json`
- Create: `workers/audio-transcription/tsconfig.json`
- Create: `workers/audio-transcription/wrangler.toml`
- Create: `workers/audio-transcription/src/index.ts`
- Create: `workers/audio-transcription/test/index.test.ts`

- [ ] Add failing Vitest cases for method/content validation, 25 MB limit, missing secret, free-model unavailability, paid-route rejection, timestamp normalization, and upstream errors.
- [ ] Run `npm test` in `workers/audio-transcription` and confirm failure.
- [ ] Implement stateless multipart proxy using `OPENROUTER_API_KEY`, explicit free-model allowlist, no persistence, structured JSON errors, and normalized segments.
- [ ] Re-run Worker tests and confirm pass.

### Task 5: Real Audio Editor and Preview

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/features/mindmap/presentation/node_editors/audio_node_editor.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Modify: `lib/features/mindmap/presentation/inline_node_workspace.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Modify: `lib/features/mindmap/domain/inline_node_workspace_policy.dart`
- Modify platform permission files only where required by `record`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`
- Test: `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`

- [ ] Add failing widget/policy tests for three source actions, editable transcript, draggable seek slider, timestamp seek, no expanded resize, bounded collapsed preview, and canvas dragging outside controls.
- [ ] Run focused widget/policy tests and confirm failure.
- [ ] Add `record` and `just_audio`; run `flutter pub get`.
- [ ] Implement dedicated editor with record/pause/resume/stop, picker action, HTTPS input, player controls, manual transcript, AI state, and segment list.
- [ ] Replace fake `_AudioNodeDetails` toggle with real compact player and bounded transcript preview.
- [ ] Add content-derived expanded sizing and disable Audio expanded resize while preserving collapsed resize policy if currently supported.
- [ ] Re-run focused widget/policy tests and confirm pass.

### Task 6: Formatting and Verification

**Files:**
- Modify: `docs/superpowers/specs/2026-07-17-audio-node-enhancement-design.md` only if implementation constraints require an explicit correction.

- [ ] Run `dart format` on edited Dart files.
- [ ] Run focused Audio tests.
- [ ] Run `flutter analyze` and report unrelated existing failures separately.
- [ ] Run `flutter test` if focused tests and analyzer permit.
- [ ] Run Worker `npm test`.
- [ ] Check `git diff --check` and inspect changed-file list for unrelated edits.

No commits are created unless explicitly requested.

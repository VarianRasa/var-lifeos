# Audio Node Enhancement Design

Date: 2026-07-17
Status: Approved design, pending implementation plan

## Goal

Turn Audio nodes into local-first audio workspaces that can record audio, import a file, or stream an online URL. Provide real playback, timestamped transcripts, and safe free-only AI transcription without exposing API secrets in Flutter.

## Product Decisions

- Support three mutually exclusive source modes: recording, imported file, and online URL.
- Limit recordings to 10 minutes.
- Limit imported or transcribed audio to 25 MB.
- Copy recordings and selected files into the existing node attachment repository.
- Keep online sources as HTTPS URLs.
- Keep manual transcript editing available regardless of AI availability.
- Use free OpenRouter transcription models only. Never fall back to a paid model.
- Store the OpenRouter key only as a Cloudflare Worker secret.
- Expanded Audio nodes size to their content and do not expose manual resize handles.
- Collapsed Audio nodes provide a compact player and useful transcript preview.

## User Experience

### Empty State

The editor presents three primary actions:

1. Record audio
2. Choose audio file
3. Add online URL

The transcript area remains available for manual entry before a source is selected.

### Recording

- Request microphone permission only when recording starts.
- Show elapsed time and the 10-minute limit.
- Provide pause, resume, stop, and cancel controls.
- Require confirmation before discarding a non-empty recording.
- Stop automatically at 10 minutes and preserve the completed recording.
- Import the completed recording into the attachment repository before updating node payload.
- Preserve the prior source if recording or import fails.

### File Import

- Use the existing file picker and attachment repository.
- Accept common audio MIME types and extensions supported by the playback plugin.
- Reject empty files and files larger than 25 MB.
- Copy bytes into app-owned attachment storage so playback survives movement or deletion of the original file.
- Display file name, size, and resolved duration when available.

### Online URL

- Accept only valid HTTPS URLs.
- Validate syntax immediately and surface playback errors without clearing the URL.
- Do not download the whole remote file into attachment storage unless the user explicitly replaces it with an imported copy in a future feature.
- Disable AI transcription when the remote host cannot be fetched safely by the Worker.

### Player

- Play and pause real audio.
- Seek continuously with a draggable slider.
- Display current position and total duration.
- Provide mute/volume control and playback speeds from 0.75x through 2x.
- Keep a single active player per Audio node editor or collapsed preview.
- Dispose player and recording resources when widgets leave the tree.
- Clicking a transcript segment seeks to its start timestamp.

### Transcript

- Store editable plain transcript text plus ordered timestamp segments.
- Each segment contains stable ID, start milliseconds, end milliseconds, and text.
- AI transcription shows progress, cancel-safe error state, and retry.
- Successful AI output replaces segments only after a complete valid response is received.
- Manual edits never disappear after network or model failure.
- If the free model returns text without timestamps, store one segment covering the full known duration and explain reduced timestamp precision.

### Collapsed Node

- Show compact play/pause, seek position, duration, source name, and up to three transcript segments.
- Keep controls usable without opening the editor.
- Truncate long segment text with an explicit overflow indicator.
- Size the node from bounded content rather than an internal scrolling Column.
- Preserve normal canvas dragging outside interactive player controls.

### Expanded Node

- Show full source card, player, transcript segments, and transcription actions.
- Let node height follow bounded editor content.
- Use a bounded transcript viewport only after the transcript exceeds the defined preview ceiling.
- Do not show manual resize handles in expanded mode.

## Data Model

Extend `AudioPayload` while continuing to read legacy fields:

- `sourceType`: `none`, `attachment`, or `url`
- `attachmentId`
- `fileName`
- `mimeType`
- `sizeBytes`
- `remoteUrl`
- `durationMilliseconds`
- `transcriptText`
- `transcriptSegments`
- `transcriptionStatus`: `idle`, `processing`, `complete`, or `failed`
- `transcriptionError`

Legacy migration rules:

- Read `audioPath` as a URL when it is a valid HTTPS URL.
- Otherwise retain it as display-only legacy source text until replaced.
- Parse `audioDuration` when possible, but never discard the original value on parse failure.
- Read `audioTranscript` into `transcriptText`.
- Continue writing legacy summary fields during this feature cycle for compatibility with existing previews and backups.

## Architecture

### Domain

- Keep payload objects and validation pure Dart.
- Add immutable transcript segment and source-type value objects.
- Validate duration, byte size, URL scheme, segment ordering, and non-negative timestamps.

### Application

- Add an Audio source import service using `NodeAttachmentRepository`.
- Add a recording coordinator behind an interface so widget tests use fakes.
- Add an audio playback controller behind an interface so editor and preview share behavior without embedding plugin calls in domain code.
- Add an HTTP transcription repository configured from a new runtime flag.

### Presentation

- Replace generic audio text fields with a dedicated stateful Audio editor.
- Keep title and content editing in the existing inline workspace.
- Route file picking, recording, playback, and transcription through injected callbacks or providers.
- Protect canvas drag gestures by reserving pointer handling only for active media controls.

### Backend

Create a separate Cloudflare Worker under `workers/audio-transcription/`.

- Runtime secret: `OPENROUTER_API_KEY`
- Flutter runtime endpoint: `VAR_AUDIO_TRANSCRIPTION_ENDPOINT`
- Accept multipart audio input plus MIME type and optional language hint.
- Reject payloads over 25 MB before forwarding.
- Reject unsupported content types and non-audio bodies.
- Use a configured allowlist of free transcription-capable OpenRouter models.
- Never select a paid route.
- Normalize provider output into transcript text and timestamp segments.
- Return structured error codes for unavailable free model, invalid audio, upstream rate limit, and provider failure.
- Do not persist uploaded audio or transcript data.

## Dependencies

- Add `record` for microphone recording.
- Add `just_audio` for file and URL playback.
- Reuse installed `file_picker`, `http`, `path_provider`, and attachment infrastructure.
- Add platform setup only where plugin requirements demand it.

Linux may require a platform playback implementation or system package. Unsupported runtime capability must disable the affected action with an explanation rather than crash.

## Failure Handling

- Missing microphone permission leaves existing source untouched.
- Picker cancellation changes nothing.
- Attachment import failure leaves existing source untouched.
- Playback errors preserve source metadata and expose retry.
- AI endpoint absence disables AI transcription but not recording, import, playback, or manual transcript editing.
- No free model returns a clear free-model-unavailable state and never incurs paid usage.
- Worker or network failure preserves prior transcript and segments.
- Node save writes only complete source metadata; partial recordings remain temporary until imported successfully.

## Layout Safety

- Avoid fixed heights around content-driven Columns.
- Measure node height from source card, controls, and bounded transcript preview.
- Clamp transcript preview lines and segment count in collapsed mode.
- Use `mainAxisSize: MainAxisSize.min` for content-driven sections.
- Reserve a small layout tolerance for fractional pixels and text scaling.
- Test narrow widths, large text scale, missing duration, long file names, long URLs, and long transcript segments.

## Accessibility

- Give record, play, pause, seek, speed, source selection, transcription, and delete controls semantic labels.
- Preserve keyboard focus order and Space/Enter activation on desktop and web.
- Expose current position and duration to assistive technology.
- Do not rely on color alone for recording, processing, or failure state.

## Testing

### Domain Tests

- Legacy payload migration
- JSON/data round trip
- URL and size validation
- Timestamp ordering and normalization
- Free-only transcription error mapping

### Application Tests

- Recording stops at 10 minutes
- Cancel and permission denial preserve prior source
- Imported bytes enter attachment repository
- AI success atomically replaces transcript segments
- AI failure preserves manual transcript

### Widget Tests

- Three source actions appear
- Recording state transitions render correctly
- Seek slider supports drag updates
- Transcript segment tap seeks player
- Expanded node has no resize affordance
- Collapsed preview remains bounded and draggable
- Long content and large text scale produce no RenderFlex overflow

### Worker Tests

- Reject oversized and non-audio uploads
- Reject requests when no free model is available
- Never route to a paid model
- Normalize timestamped and text-only responses
- Map OpenRouter rate and provider errors

## Acceptance Criteria

- User can record up to 10 minutes, pause/resume, save, and play recording.
- User can choose an audio file and keep using it after the original file moves.
- User can add and play a valid HTTPS audio URL.
- Player seek slider drags smoothly.
- AI transcription uses only free OpenRouter models through the Worker.
- Timestamped segments seek playback when selected.
- Manual transcript remains editable and survives AI failures.
- Collapsed and expanded modes show useful audio controls without RenderFlex overflow.
- Expanded Audio nodes auto-size and cannot be manually resized.
- Audio node remains movable on the canvas outside interactive controls.

## Out of Scope

- Paid transcription fallback
- Cloud storage of raw recordings
- Waveform generation
- Audio editing, trimming, noise removal, or format conversion
- Speaker diarization guarantees
- Background recording
- Batch transcription

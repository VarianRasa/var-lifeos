# Node Inline Editor Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build type-specific inline editing, automatic/manual node sizing, attachment-backed Image and Video nodes, and a structured Itinerary node while preserving local-first persistence, backup, and sync compatibility.

**Architecture:** Add typed presentation and payload codecs in the mindmap domain, then route all node rendering through a shared shell that owns sizing, resize, edit sessions, validation, and autosave. Existing and new node types provide focused renderer/editor modules; binary attachments remain behind an adapter and never enter Sembast node records.

**Tech Stack:** Flutter, Dart 3.11, Riverpod, Sembast, shared_preferences, existing sync/backup adapters, Flutter widget/unit tests.

---

## File Structure

### Create

- `lib/features/mindmap/domain/node_presentation.dart`: presets, effective dimensions, clamp rules, and `NodePresentationSpec`.
- `lib/features/mindmap/domain/node_ui_state_codec.dart`: typed read/write access for UI state stored in `MindmapNode.data`.
- `lib/features/mindmap/domain/node_type_payloads.dart`: typed payload readers/writers for all type-specific data, including itinerary/image/video.
- `lib/features/mindmap/domain/node_validation.dart`: field validation shared by inline editors.
- `lib/features/mindmap/domain/node_attachment.dart`: attachment metadata and repository contract.
- `lib/features/mindmap/data/local_node_attachment_repository.dart`: local attachment persistence adapter.
- `lib/features/mindmap/application/node_inline_edit_controller.dart`: draft session, debounce autosave, retry, and flush.
- `lib/features/mindmap/presentation/node_shell.dart`: selection, resize, presets, edit-state chrome, and palette-aware shell.
- `lib/features/mindmap/presentation/node_type_content.dart`: dispatch read-only content by `NodeType`.
- `lib/features/mindmap/presentation/node_type_inline_editor.dart`: dispatch editor by `NodeType`.
- `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart`: Task, Kanban, Plan, Note, Habit, Goal, Routine, Checklist, Timer.
- `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`: Journal, Link, Bookmark, Resource, Idea, Question, Decision, Quote, Audio, Canvas.
- `lib/features/mindmap/presentation/node_editors/life_data_node_editors.dart`: Event, Contact, Metric, Expense, Mood, Weather, Fit, Empty.
- `lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart`: Itinerary, Image, Video.
- Matching tests under `test/features/mindmap/...`.

### Modify

- `lib/core/constants/app_constants.dart`: add new `NodeType` values and labels.
- `lib/features/mindmap/domain/mindmap_node.dart`: expose typed copy helpers without changing storage format.
- `lib/features/mindmap/presentation/mindmap_canvas.dart`: effective geometry, shared shell, resize interaction, inline editor dispatch.
- `lib/features/calendar/day_page.dart`: create-node gallery, contextual ribbon presets, attachment import actions.
- `lib/features/mindmap/application/mindmap_providers.dart`: attachment and edit-session providers.
- `lib/features/sync/domain/...`: preserve attachment manifest seam without embedding binary payloads.
- Backup implementation files discovered during Task 12.

---

## Phase 1: Shared Foundation

### Task 1: Add new node types

**Files:**
- Modify: `lib/core/constants/app_constants.dart`
- Modify: all exhaustive `NodeType` switches reported by analyzer
- Test: `test/core/constants/app_constants_test.dart`

- [ ] **Step 1: Write failing enum coverage test**

```dart
test('media and travel node types expose stable labels', () {
  expect(NodeType.itinerary.label, 'Itinerary');
  expect(NodeType.image.label, 'Image');
  expect(NodeType.video.label, 'Video');
});
```

- [ ] **Step 2: Run test and confirm compile failure**

Run: `flutter test test/core/constants/app_constants_test.dart`

Expected: compile failure because new enum values do not exist.

- [ ] **Step 3: Add enum values and labels**

```dart
enum NodeType {
  // Existing values remain unchanged.
  itinerary,
  image,
  video,
}
```

Add `label`, icon, color, compatibility, create-gallery category, filtering, serialization, and exhaustive switch cases. Do not reorder existing values if persisted data depends on names or ordinals.

- [ ] **Step 4: Run focused test and analyzer**

Run:

```bash
flutter test test/core/constants/app_constants_test.dart
flutter analyze lib test
```

Expected: test passes; analyzer identifies no missing switch branches.

### Task 2: Build presentation sizing domain

**Files:**
- Create: `lib/features/mindmap/domain/node_presentation.dart`
- Test: `test/features/mindmap/domain/node_presentation_test.dart`

- [ ] **Step 1: Write failing sizing tests**

```dart
test('manual dimensions become custom and clamp to type bounds', () {
  final spec = NodePresentationSpec.forType(NodeType.task);
  final state = spec.resolve(
    preset: NodeSizePreset.standard,
    customWidth: 9999,
    customHeight: 1,
  );

  expect(state.preset, NodeSizePreset.custom);
  expect(state.width, spec.maxWidth);
  expect(state.height, spec.minHeight);
});

test('kanban itinerary and video default to wide', () {
  expect(NodePresentationSpec.forType(NodeType.kanban).defaultPreset,
      NodeSizePreset.wide);
  expect(NodePresentationSpec.forType(NodeType.itinerary).defaultPreset,
      NodeSizePreset.wide);
  expect(NodePresentationSpec.forType(NodeType.video).defaultPreset,
      NodeSizePreset.wide);
});
```

- [ ] **Step 2: Implement immutable sizing values**

```dart
enum NodeSizePreset { auto, compact, standard, large, wide, custom }

final class NodePresentationState {
  const NodePresentationState({
    required this.preset,
    required this.width,
    required this.height,
  });

  final NodeSizePreset preset;
  final double width;
  final double height;
}
```

Implement `NodePresentationSpec.forType`, preset dimensions, type limits, finite-value checks, and clamping. Keep this file pure Dart except for `Size` only if existing domain conventions allow `dart:ui`; otherwise store doubles.

- [ ] **Step 3: Run domain tests**

Run: `flutter test test/features/mindmap/domain/node_presentation_test.dart`

Expected: all sizing tests pass.

### Task 3: Add typed UI-state codec

**Files:**
- Create: `lib/features/mindmap/domain/node_ui_state_codec.dart`
- Modify: `lib/features/mindmap/domain/mindmap_node.dart`
- Test: `test/features/mindmap/domain/node_ui_state_codec_test.dart`

- [ ] **Step 1: Write legacy and round-trip tests**

```dart
test('legacy node resolves automatic type defaults', () {
  final node = MindmapNode.create(
    id: 'legacy',
    type: NodeType.note,
    title: 'Legacy',
    day: DateTime(2026, 7, 13),
  );

  final state = NodeUiStateCodec.read(node);
  expect(state.preset, NodeSizePreset.auto);
  expect(state.effective.width, greaterThan(0));
});

test('codec preserves unrelated data', () {
  final data = NodeUiStateCodec.write(
    {'domainKey': 'keep'},
    preset: NodeSizePreset.custom,
    width: 420,
    height: 280,
    collapsedSections: const {'metadata'},
  );
  expect(data['domainKey'], 'keep');
  expect(data['uiWidth'], 420);
});
```

- [ ] **Step 2: Implement reserved-key codec**

Use exact keys from spec: `uiSizePreset`, `uiWidth`, `uiHeight`, `uiCollapsedSections`, `uiEditorVersion`. Reject non-finite numbers, unknown presets, malformed lists, and dimensions outside the type spec.

- [ ] **Step 3: Add node copy helper**

```dart
MindmapNode copyWithUiState(NodeUiState state) => copyWith(
  data: NodeUiStateCodec.writeState(data, type: type, state: state),
  updatedAt: DateTime.now(),
);
```

- [ ] **Step 4: Run codec and existing entity tests**

Run:

```bash
flutter test test/features/mindmap/domain/node_ui_state_codec_test.dart
flutter test test/features/mindmap/domain/mindmap_node_test.dart
```

Expected: new and existing tests pass.

### Task 4: Make canvas geometry size-aware

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Add failing geometry tests**

Add tests proving a custom-sized node affects rendered `SizedBox`, lasso selection bounds, connection port placement, and layout spacing.

```dart
final resized = node.copyWith(
  data: NodeUiStateCodec.write(
    node.data,
    preset: NodeSizePreset.custom,
    width: 520,
    height: 260,
  ),
);
expect(tester.getSize(find.byKey(const ValueKey('mindmap-node-resized'))),
    const Size(520, 260));
```

- [ ] **Step 2: Replace static size lookups**

Create one `_effectiveNodeSize(MindmapNode node)` function backed by `NodeUiStateCodec`. Use it for rendering, overlap checks, drag-select, viewport focus, connection ports, groups, layout algorithms, minimap, and export.

- [ ] **Step 3: Run full canvas tests**

Run: `flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart`

Expected: all existing tests and new geometry tests pass.

### Task 5: Add shared resizable node shell

**Files:**
- Create: `lib/features/mindmap/presentation/node_shell.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/node_shell_test.dart`

- [ ] **Step 1: Write interaction tests**

Test hover-only resize handles, selected-state handles, preset menu, keyboard resize, pointer resize, Custom transition, minimum/maximum clamp, and palette shape.

- [ ] **Step 2: Implement shell API**

```dart
class MindmapNodeShell extends StatelessWidget {
  const MindmapNodeShell({
    required this.node,
    required this.presentation,
    required this.selected,
    required this.editing,
    required this.saveState,
    required this.onResize,
    required this.onPresetChanged,
    required this.child,
    super.key,
  });
}
```

Use four corner handles only on large pointer devices; provide preset and keyboard alternatives for touch/accessibility. Graphite Fuchsia stays rectangular and decoration-free.

- [ ] **Step 3: Replace `_DoodleNodeShell` usage**

Keep palette path generation in the shared shell. Remove duplicate node-shell painting only after parity tests pass.

- [ ] **Step 4: Run shell and canvas tests**

Run:

```bash
flutter test test/features/mindmap/presentation/node_shell_test.dart
flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart
```

Expected: resize and existing canvas interactions pass.

### Task 6: Add inline edit session controller

**Files:**
- Create: `lib/features/mindmap/application/node_inline_edit_controller.dart`
- Modify: `lib/features/mindmap/application/mindmap_providers.dart`
- Test: `test/features/mindmap/application/node_inline_edit_controller_test.dart`

- [ ] **Step 1: Write fake-clock autosave tests**

Cover debounce, immediate `Ctrl+Enter` save, focus-loss flush, cancel restore, failed-save draft retention, retry, and one undo snapshot per session.

```dart
test('failed save keeps draft and retry persists it', () async {
  repository.failNextSave = true;
  controller.begin(node);
  controller.updateTitle('Draft');
  await controller.flush();
  expect(controller.state.draft.title, 'Draft');
  expect(controller.state.saveStatus, NodeSaveStatus.error);

  await controller.retry();
  expect(controller.state.saveStatus, NodeSaveStatus.saved);
});
```

- [ ] **Step 2: Implement controller state**

```dart
enum NodeSaveStatus { idle, dirty, saving, saved, error }

final class NodeInlineEditState {
  const NodeInlineEditState({
    required this.persisted,
    required this.draft,
    required this.saveStatus,
    this.errorMessage,
  });
}
```

Use one timer per active node session. Save through `mindmapMutationController`; invalidate through existing mutation paths. Cancel timers in `dispose` and flush valid drafts before explicit close.

- [ ] **Step 3: Run controller tests**

Run: `flutter test test/features/mindmap/application/node_inline_edit_controller_test.dart`

Expected: all edit-session tests pass without real delays.

## Phase 2: Existing Type Modules

### Task 7: Add typed payload and validation layer

**Files:**
- Create: `lib/features/mindmap/domain/node_type_payloads.dart`
- Create: `lib/features/mindmap/domain/node_validation.dart`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart`
- Test: `test/features/mindmap/domain/node_validation_test.dart`

- [ ] **Step 1: Inventory existing data keys**

Use `rg node.data|data\[' lib/features/mindmap lib/features/calendar` and record every key in typed payload classes. Preserve current serialization names.

- [ ] **Step 2: Write round-trip tests for each existing type family**

At minimum cover task/checklist, kanban, plan, goal, habit/routine, calendar/event, contact/metric/expense, mood/weather/fit, links/resources, timer/audio/canvas.

- [ ] **Step 3: Implement typed payload readers/writers**

Each payload exposes `fromNode`, `toData(existingData)`, and `validate`. Writers merge unrelated keys instead of replacing `data`.

- [ ] **Step 4: Run payload and validation tests**

Run:

```bash
flutter test test/features/mindmap/domain/node_type_payloads_test.dart
flutter test test/features/mindmap/domain/node_validation_test.dart
```

Expected: every payload round-trips and invalid trust-boundary input is rejected.

### Task 8: Implement productivity editors

**Files:**
- Create: `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart`
- Create: `lib/features/mindmap/presentation/node_type_content.dart`
- Create: `lib/features/mindmap/presentation/node_type_inline_editor.dart`
- Test: `test/features/mindmap/presentation/productivity_node_editors_test.dart`

- [ ] **Step 1: Write editor behavior tests**

Test Compact, Standard, Large, and Wide content for Task, Kanban, Plan, Note, Habit, Goal, Routine, Checklist, and Timer. Verify editing invokes draft callbacks rather than repositories directly.

- [ ] **Step 2: Implement dispatcher interfaces**

```dart
Widget buildNodeTypeContent(NodeRenderContext context);
Widget buildNodeTypeInlineEditor(NodeEditContext context);
```

`NodeEditContext` contains node, typed draft, effective preset, validation errors, and callbacks. It does not expose `WidgetRef` or repository access.

- [ ] **Step 3: Implement productivity layouts**

Use existing quick-action domain helpers. Preserve Kanban card advancement, habit completion, goal milestones, plan steps, and checklist behavior.

- [ ] **Step 4: Run editor and canvas tests**

Run:

```bash
flutter test test/features/mindmap/presentation/productivity_node_editors_test.dart
flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart
```

Expected: type editors and existing quick actions pass.

### Task 9: Implement knowledge and thinking editors

**Files:**
- Create: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`

- [ ] **Step 1: Add tests for Journal, Link, Bookmark, Resource, Idea, Question, Decision, Quote, Audio, and Canvas**

Verify URL validation, long-text layout thresholds, decision options, quote attribution, audio fallback action, and sub-canvas open action.

- [ ] **Step 2: Implement layouts using typed payloads**

Use plain multiline text fields; do not add a rich-text dependency. Use existing URL launching or external-open adapters where available.

- [ ] **Step 3: Run focused tests**

Run: `flutter test test/features/mindmap/presentation/knowledge_node_editors_test.dart`

Expected: all knowledge editor tests pass.

### Task 10: Implement life and data editors

**Files:**
- Create: `lib/features/mindmap/presentation/node_editors/life_data_node_editors.dart`
- Test: `test/features/mindmap/presentation/life_data_node_editors_test.dart`

- [ ] **Step 1: Add tests for Event, Contact, Metric, Expense, Mood, Weather, Fit, and Empty**

Verify date/time validation, finite numeric values, currency/category handling, mood ranges, units, and placeholder conversion.

- [ ] **Step 2: Implement layouts**

Reuse date normalization helpers and existing calendar payload codecs. Keep date comparisons local-day based.

- [ ] **Step 3: Run focused tests**

Run: `flutter test test/features/mindmap/presentation/life_data_node_editors_test.dart`

Expected: all life/data editor tests pass.

## Phase 3: Itinerary and Media

### Task 11: Implement Itinerary payload and editor

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Create: `lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart`
- Test: `test/features/mindmap/domain/itinerary_payload_test.dart`
- Test: `test/features/mindmap/presentation/itinerary_node_editor_test.dart`

- [ ] **Step 1: Write agenda round-trip and validation tests**

```dart
final itinerary = ItineraryPayload(
  destination: 'Kyoto',
  startDate: DateTime(2026, 10, 2),
  endDate: DateTime(2026, 10, 6),
  timezone: 'Asia/Tokyo',
  agenda: const [
    ItineraryAgendaItem(
      id: 'day-1-temple',
      title: 'Kiyomizu-dera',
      startMinutes: 540,
      durationMinutes: 120,
    ),
  ],
);
expect(ItineraryPayload.fromData(itinerary.toData()).agenda.single.id,
    'day-1-temple');
```

Reject end dates before start, negative costs/durations, duplicate agenda IDs, and minute values outside a day.

- [ ] **Step 2: Implement itinerary editor**

Compact shows destination, date range, and next agenda. Wide shows reorderable timeline, completion toggles, budget summary, and conversion callbacks for Task/Event creation.

- [ ] **Step 3: Run itinerary tests**

Run:

```bash
flutter test test/features/mindmap/domain/itinerary_payload_test.dart
flutter test test/features/mindmap/presentation/itinerary_node_editor_test.dart
```

Expected: payload and editor tests pass.

### Task 12: Add attachment repository

**Files:**
- Create: `lib/features/mindmap/domain/node_attachment.dart`
- Create: `lib/features/mindmap/data/local_node_attachment_repository.dart`
- Modify: `lib/features/mindmap/application/mindmap_providers.dart`
- Test: `test/features/mindmap/data/local_node_attachment_repository_test.dart`

- [ ] **Step 1: Write repository contract tests**

Test byte import, MIME allowlist, resolve, export, delete, reference safety, filename normalization, and manifest round-trip using a temporary directory or in-memory adapter.

- [ ] **Step 2: Define attachment contract**

```dart
abstract interface class NodeAttachmentRepository {
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  });
  Future<List<int>?> readBytes(String attachmentId);
  Future<void> delete(String attachmentId);
  Future<List<NodeAttachmentManifestEntry>> buildManifest();
}
```

Validate IDs and paths before file operations. Keep writes atomic using temporary file plus rename where supported.

- [ ] **Step 3: Implement provider and lifecycle**

Provide platform-aware local implementation. Web may use an existing browser storage adapter or a bounded in-memory fallback until durable blob storage is available; document the fallback in code with a `ponytail:` comment and upgrade path.

- [ ] **Step 4: Run attachment tests**

Run: `flutter test test/features/mindmap/data/local_node_attachment_repository_test.dart`

Expected: repository contract passes without writing outside test directories.

### Task 13: Implement Image node

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart`
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/mindmap/presentation/image_node_editor_test.dart`

- [ ] **Step 1: Write payload and UI tests**

Cover local attachment, portable URL, invalid scheme, thumbnail/preview thresholds, fit modes, caption, alt-text warning, replace, and export actions.

- [ ] **Step 2: Implement import entry points**

Use existing clipboard and drag/drop seams. Validate MIME as `image/*`, enforce configured byte limits, store binary through `NodeAttachmentRepository`, and save only metadata in node data.

- [ ] **Step 3: Implement renderer/editor**

Compact uses a thumbnail with semantic alt label. Large/Wide uses `Image.memory`, local resolved bytes, or network provider according to source. Failed loads show retry and Open externally.

- [ ] **Step 4: Run image tests**

Run: `flutter test test/features/mindmap/presentation/image_node_editor_test.dart`

Expected: image source and accessibility states pass.

### Task 14: Implement Video node

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart`
- Test: `test/features/mindmap/presentation/video_node_editor_test.dart`

- [ ] **Step 1: Write payload and fallback tests**

Cover attachment/URL source, duration, thumbnail, playback position clamp, mute state, invalid MIME, and unsupported-platform external-open fallback.

- [ ] **Step 2: Reuse installed playback capability if present**

Inspect `pubspec.yaml`. If a compatible video dependency already exists, wrap it behind a small presentation adapter. Do not add a new package until platform support and bundle impact are confirmed. Without a compatible dependency, ship thumbnail plus Open externally and mark the ceiling with a `ponytail:` comment.

- [ ] **Step 3: Implement editor and playback state persistence**

Debounce playback-position writes separately from text autosave. Never write on every frame. Flush on pause, close, or app lifecycle pause.

- [ ] **Step 4: Run video tests**

Run: `flutter test test/features/mindmap/presentation/video_node_editor_test.dart`

Expected: playback adapter or fallback behavior passes.

## Phase 4: Integration, Backup, and Release Safety

### Task 15: Add contextual Node ribbon controls

**Files:**
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/calendar/day_page_test.dart`

- [ ] **Step 1: Add failing ribbon tests**

Verify selected node exposes Auto/Compact/Standard/Large/Wide presets, current save status, Edit/Done action, and attachment actions only for Image/Video.

- [ ] **Step 2: Implement contextual controls**

Use existing automatic contextual Node tab behavior. Preset changes save typed UI state through mutation controller. Do not duplicate inline fields in ribbon.

- [ ] **Step 3: Run DayPage tests**

Run: `flutter test test/features/calendar/day_page_test.dart --name ribbon|node`

Expected: contextual ribbon tests pass.

### Task 16: Extend backup and restore for attachments

**Files:**
- Modify: backup files discovered with `rg -n backup|restore|archive lib/features/sync lib/features/settings`
- Test: matching backup/restore tests

- [ ] **Step 1: Identify current portable backup boundary**

Document exact manifest/encryption pipeline in test comments. Preserve current cryptography and failure semantics.

- [ ] **Step 2: Write failing backup tests**

Create node plus image attachment, export backup, restore into empty repositories, then assert node metadata and bytes match. Add missing-attachment and corrupted-entry tests that fail safely without discarding valid node data.

- [ ] **Step 3: Add attachment manifest entries**

Store attachment metadata and encrypted file payloads beside node data using versioned manifest entries. Restore validates path, checksum, MIME, and size before commit.

- [ ] **Step 4: Run backup tests**

Run focused tests identified in Step 1.

Expected: attachment round-trip passes; corrupted data reports error without partial destructive restore.

### Task 17: Add sync attachment seam

**Files:**
- Modify: `lib/features/sync/domain/` planning models
- Modify: sync adapters selected by `VAR_SYNC_ENDPOINT`
- Test: sync planning and adapter tests

- [ ] **Step 1: Write sync planning tests**

Verify node metadata sync remains unchanged, attachment upload/download work is represented separately, local-only paths are excluded, and missing endpoint keeps local fallback behavior.

- [ ] **Step 2: Add attachment work items**

Define attachment hash, size, MIME, and remote object key. Do not embed bytes in normal node mutation payloads.

- [ ] **Step 3: Implement adapter capability boundary**

If HTTP endpoint lacks attachment routes, return explicit unsupported capability while preserving node metadata sync. Do not invent undocumented endpoints.

- [ ] **Step 4: Run sync tests**

Run: `flutter test test/features/sync`

Expected: metadata sync remains green; attachment capability behavior is deterministic.

### Task 18: Accessibility, performance, and full verification

**Files:**
- Modify: affected presentation files
- Modify: `docs/release/beta_release_checklist.md` only if new manual media checks are needed
- Test: all focused and full suites

- [ ] **Step 1: Add semantics and keyboard tests**

Verify resize handles, preset menu, inline edit controls, image alt labels, and video controls expose semantics and keyboard activation.

- [ ] **Step 2: Add performance guards**

Ensure typing rebuilds only the edited node, image decoding uses bounded dimensions, video position saves are throttled, and canvas layout does not parse payload maps repeatedly in paint loops.

- [ ] **Step 3: Run focused verification**

```bash
dart format --set-exit-if-changed lib test
flutter analyze
flutter test test/features/mindmap
flutter test test/features/calendar/day_page_test.dart
flutter test test/features/sync
```

Expected: no analyzer issues and all focused suites pass.

- [ ] **Step 4: Run beta preflight**

```bash
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release --dart-define=VAR_DEMO_SEED=false
```

Expected: all commands succeed. If Windows file locking blocks a build, stop the running app and rerun; do not delete build output recursively without verified workspace paths.

---

## Execution Order and Checkpoints

1. Tasks 1-6 produce reusable sizing/editing foundation with existing nodes still functional.
2. Tasks 7-10 migrate all existing types to typed payloads and inline editors.
3. Tasks 11-14 add Itinerary, attachment storage, Image, and Video.
4. Tasks 15-17 integrate ribbon, backup, and sync seams.
5. Task 18 performs accessibility, performance, and release verification.

After each phase, run all tests for files touched in that phase before continuing. Do not start media attachment work until effective-size canvas geometry and autosave are stable.

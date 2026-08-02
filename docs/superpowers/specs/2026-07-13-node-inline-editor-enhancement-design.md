# Node Inline Editor Enhancement Design

## Goal

Upgrade every mindmap node into a type-specific inline workspace with professional UI, automatic and manual sizing, reliable autosave, and local-first persistence. Add itinerary, image, and video node types without breaking existing nodes, backup, or sync behavior.

## Scope

This design covers:

- Shared node shell and sizing behavior.
- Type-specific read and edit layouts for every node type.
- Inline editing, validation, autosave, retry, and undo behavior.
- Persistence and sync metadata changes.
- New itinerary, image, and video node types.
- Attachment storage boundary for image and video files.

This design does not add rich-text collaboration, binary storage inside Sembast records, image manipulation, video transcoding, or a new remote sync protocol.

## Architecture

### Shared contracts

`NodePresentationSpec` defines:

- Automatic default size.
- Minimum and maximum dimensions.
- Supported presets.
- Preferred aspect ratio.
- Compact, standard, large, and wide presentation thresholds.

`NodeInlineEditorSpec` defines:

- Fields and sections for one `NodeType`.
- Validation rules.
- Read-only and editing layouts.
- Type-specific actions.
- Serialization through typed codecs.

`MindmapNodeShell` owns shared behavior:

- Selection and hover state.
- Drag and resize interaction.
- Preset selection.
- Focus and keyboard handling.
- Saving, saved, error, and retry states.
- Palette-specific card shape and styling.

`NodeTypeContent` renders type-specific read-only content. `NodeTypeInlineEditor` renders type-specific editing controls. Both use typed helpers instead of reading `MindmapNode.data` directly.

### File direction

Keep feature-first layering:

- `domain/`: presentation size values, typed node payload codecs, validation, attachment metadata.
- `application/`: inline edit session, debounce autosave, retry, mutation orchestration.
- `data/`: attachment adapters and existing node repository integration.
- `presentation/`: shared shell, resize handles, preset menu, type renderers, type editors.

No generated Riverpod annotations are required unless existing controller style makes them necessary.

## Interaction Design

### Editing

- Single click selects a node and activates contextual Node ribbon.
- Double click or `Enter` starts inline editing.
- `Escape` cancels unsaved edits and restores persisted values.
- `Ctrl+Enter` saves immediately.
- Losing focus flushes the latest valid draft.
- Autosave runs after a short per-node debounce.
- Save failure keeps the draft visible and exposes retry.
- Undo records one edit session, not every keystroke.

### Sizing

Supported presets:

- `Auto`
- `Compact`
- `Standard`
- `Large`
- `Wide`
- `Custom`

`Auto` selects dimensions from type, content amount, and presentation thresholds. Manual resizing changes the preset to `Custom`. Resize handles appear only while hovered or selected. Dimensions are clamped to each type specification.

Compact mode shows the smallest useful type-specific summary. Standard mode exposes the primary workflow. Large and Wide modes expose the complete inline editor for that type.

The node anchor remains stable during resize. Hit testing, selection bounds, connection ports, lasso selection, minimap rendering, export, grouping, and layout algorithms must use the persisted effective node size.

### Visual language

- Graphite Fuchsia: rectangular, 6px radius, thin border, restrained type accent, no paper decoration.
- Blueprint: technical rectangular shell.
- Midnight: soft modern rounded shell.
- Schoolboard: restrained chalk shell.
- Blackboard: organic doodle shell.
- Cardboard: paper/torn shell.

All palettes share interaction behavior and information hierarchy.

## Persistence

UI state remains inside `MindmapNode.data` for compatibility with current repositories, backup, and sync payloads.

Reserved keys:

- `uiSizePreset`
- `uiWidth`
- `uiHeight`
- `uiCollapsedSections`
- `uiEditorVersion`

Typed codecs validate enum names, numeric bounds, and section IDs. Old nodes without these keys resolve lazily to type defaults. No bulk migration or rewrite occurs.

Autosave uses `mindmapMutationController` and existing invalidation helpers. A failed write never discards the local draft. Successful writes update `updatedAt` and participate in existing sync conflict handling.

## Attachment Boundary

Image and video binary data must not be stored directly inside `MindmapNode.data`.

Define an attachment adapter with operations to:

- Import local bytes or a supported local file.
- Resolve a stored attachment for display.
- Delete an unreferenced attachment.
- Export attachment files.
- Produce and restore backup manifest entries.

Node data stores attachment ID, media metadata, optional portable URL, caption, and display settings. Local file paths are device-local hints and cannot be treated as portable sync identifiers.

Remote sync of binary attachments remains an adapter seam. Metadata node sync continues through the existing payload. Unsupported platforms fall back to URL previews or external opening.

## Type Layouts

### Productivity

- Task: completion, title, priority, due date, checklist, progress.
- Kanban: columns, cards, WIP summary, card movement; default Wide.
- Plan: ordered steps, active step, schedule, progress.
- Note: title, long body, tags, links.
- Habit: frequency, streak, today completion, recent history.
- Goal: target, milestones, deadline, progress.
- Routine: recurrence, steps, completion state, next run.
- Checklist: editable items, completion count, progress.
- Timer: duration, elapsed state, linked task, start/stop/reset.

### Knowledge and Thinking

- Journal: entry date, mood, prompts, long-form body.
- Link: URL, title, preview metadata, open action.
- Bookmark: URL, collection, tags, preview.
- Resource: source, category, description, links.
- Idea: description, maturity status, evidence, next action.
- Question: question, investigation status, answer, evidence.
- Decision: options, criteria, selected outcome, rationale.
- Quote: quote, author, source.
- Audio: source, duration, playback, transcript note.
- Canvas: embedded sub-canvas summary and open action.

### Life and Data

- Event: date, start/end time, location, reminder.
- Contact: identity, organization, communication fields, relationship notes.
- Metric: value, unit, target, trend.
- Expense: amount, category, payment method, date.
- Mood: mood score, energy, note, contributing factors.
- Weather: condition, temperature, location, observation date.
- Fit: activity, duration, distance or repetitions, intensity.
- Empty/Placeholder: intended type, title, convert action.

## New Node Types

### Itinerary

Default size is Wide.

Fields:

- Trip name and destinations.
- Start/end date and timezone.
- Budget and status.
- Ordered agenda items containing time, location, activity, duration, cost, and notes.

Actions:

- Add, edit, delete, and reorder agenda items.
- Mark agenda item complete.
- Open a location externally.
- Convert an agenda item to Task or Event.

Compact mode shows destination, dates, and next agenda. Large/Wide mode shows the travel timeline.

### Image

Default size is Standard with Large and Wide support.

Sources:

- Local file.
- Clipboard.
- Drag and drop.
- Portable URL.

Fields:

- Attachment ID or URL.
- Caption and alt text.
- Tags and source URL.
- Width, height, MIME type, and display fit mode.

Actions:

- Preview, replace, change fit mode, export, and open externally.

Compact mode shows a thumbnail. Large/Wide shows a larger preview. Missing alt text produces a non-blocking accessibility warning.

### Video

Default size is Wide.

Sources:

- Local attachment.
- Portable URL.

Fields:

- Attachment ID or URL.
- Title, caption, tags.
- Duration, thumbnail, MIME type.
- Last playback position and mute state.

Actions:

- Play, pause, seek, mute, fullscreen, replace, and open externally.

Compact mode shows thumbnail and duration. Large/Wide mode shows an inline player. Platforms without supported playback use thumbnail plus Open externally.

## Validation

Validation remains type-specific and protects trust boundaries:

- URLs must use supported schemes.
- Numeric values must be finite and within type limits.
- Dates and time ranges must be valid.
- Media metadata must match supported MIME families.
- Dimensions must remain within presentation limits.
- Required titles cannot become empty.

Validation errors remain inline and prevent invalid persistence, but drafts remain available for correction.

## Accessibility

- Resize handles have semantic labels and keyboard alternatives.
- Editing order follows a predictable focus sequence.
- All actions expose tooltips and semantics.
- Color never carries status alone.
- Image nodes surface alt-text status.
- Video controls are keyboard accessible.
- Compact nodes preserve readable text and minimum pointer targets.

## Rollout

### Phase 1: Foundation

- Shared presentation spec and typed UI state codec.
- Shared node shell, presets, resize, autosave, retry, and undo session.
- Effective-size integration with canvas geometry.

### Phase 2: Existing type modules

- Implement all existing node type renderers and inline editors using shared contracts.
- Preserve current type-specific quick actions.

### Phase 3: New types

- Add itinerary and its typed payload.
- Add attachment adapter.
- Add image node.
- Add video node with platform fallback.

### Phase 4: Backup, sync, and polish

- Attachment backup manifest and restore.
- Attachment sync seam and conflict behavior.
- Performance, accessibility, responsive, and cross-platform verification.

## Testing

- Domain tests for size clamping, presets, codecs, validation, and new payloads.
- Repository tests proving new `data` fields round-trip unchanged.
- Widget tests for edit, cancel, autosave, retry, resize, presets, and palette shapes.
- Canvas tests for effective geometry, ports, lasso, grouping, minimap, export, and layouts.
- Type-specific widget tests for every editor module.
- Attachment adapter tests with in-memory files or bytes.
- Backup/restore tests including attachment manifests.
- Platform fallback tests for unsupported media playback.

## Success Criteria

- Every node type has a purpose-built inline read and edit layout.
- Nodes support Auto, Compact, Standard, Large, Wide, and Custom sizing.
- Resizing persists and all canvas geometry uses effective dimensions.
- Autosave cannot lose a valid local draft after a failed write.
- Existing nodes load without migration errors.
- Itinerary, Image, and Video work through typed payloads.
- Binary media remains outside Sembast node records.
- Existing backup and sync metadata remain compatible.
- Focused analyzer and test suites pass before broader preflight.

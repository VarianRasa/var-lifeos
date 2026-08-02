# Knowledge Note Node Enhancement Design

## Goal

Turn `NodeType.note` into a focused knowledge-note workspace with Markdown authoring, rendered preview, sources, attachments, tags, pinning, related-node context, and useful collapsed summaries.

## Scope

- Dedicated versioned `NotePayload` stored under `MindmapNode.data['note']`.
- Responsive split Markdown editor and preview.
- Compact Edit/Preview toggle when split layout cannot fit.
- Formatting toolbar, search, counts, and heading table of contents.
- Pin, color, tags, sources, attachments, and related-node summary.
- Collapsed rendered excerpt and knowledge metadata.
- Backward compatibility with existing title/body note nodes.
- Focused domain, editor, collapsed-view, and sizing tests.

## Dependency

Use `flutter_markdown` for Markdown rendering. Lock a package version compatible with current Flutter and Dart SDK constraints. Use existing Flutter link-launching patterns; do not add a second URL launcher abstraction.

## Data Model

Add `NotePayload` with:

- `version`: current schema version.
- `color`: stable color token key, not a raw runtime `Color` value.
- `sourceLinks`: ordered `NoteSourceLink` values containing `id`, `label`, and normalized `url`.
- `attachments`: ordered existing attachment references supported by current mindmap storage flow.

Title and Markdown content remain authoritative in `MindmapNode.title` and `MindmapNode.body`. Pin state remains `MindmapNode.isPinned`. Tags remain `MindmapNode.tags`. Relationships remain `MindmapNode.relatedNodeIds`.

`NotePayload.fromNode` returns defaults when `data['note']` is absent. `toData` preserves unrelated data and writes only the note section. Malformed source links and attachments are skipped safely.

## Markdown Editor

Large layout uses two equal panes:

- Left: multiline Markdown editor.
- Right: rendered `MarkdownBody` preview.

Small layout uses an Edit/Preview segmented control and one pane. Editor mode is local UI state and is not persisted.

Toolbar actions insert or wrap Markdown syntax at the current text selection:

- Heading.
- Bold.
- Italic.
- Quote.
- Bullet list.
- Numbered list.
- Checklist item.
- Link.
- Inline code.
- Code block.

Toolbar preserves selection where practical and never deletes selected text. Undo/redo remains native `TextEditingController` behavior.

## Search and Navigation

Search field highlights or selects the next case-insensitive match in the editor. Empty search performs no mutation. A result count shows total matches.

Table of contents parses Markdown heading lines (`#` through `######`) and displays their text and level. Selecting an entry moves the editor selection to that heading and scrolls it into view when editor mode is visible.

Word and character counts update from the live draft.

## Knowledge Metadata

- Pin toggle updates `MindmapNode.isPinned` through the node-draft callback.
- Color selector writes a stable token into `NotePayload`.
- Tags reuse the existing node tag list and editing callback.
- Source links support add, open, edit, and delete with URL validation.
- Attachments reuse existing attachment add/open/remove callbacks and storage types.
- Related nodes display existing relationship IDs/count and use current connection/navigation affordances; the note editor does not create a second graph relationship model.

## Collapsed View

Collapsed note content shows:

- A short plain-text excerpt derived from Markdown.
- Pin and color indicators.
- Up to three tags.
- Source and attachment counts.
- Related-node count when non-zero.

Collapsed rendering does not expose a full Markdown document or internal scroll. Long content truncates safely.

## Sizing and Scrolling

Expanded note width supports split view. Height uses a bounded workspace policy. Editor and preview panes scroll independently inside the bounded content region. Metadata sections remain visible below or beside the editor according to available width.

Collapsed node sizing remains user-configurable and must not overflow at standard `340×320` size.

## Validation

- Note title remains required.
- Source URLs must parse as absolute HTTP or HTTPS URLs.
- Source labels trim whitespace and fall back to the URL host when empty.
- Color values outside supported tokens decode to default.
- Attachment metadata uses current attachment validation.
- Markdown content remains plain local text; no HTML execution.

## Tests

- `NotePayload` default, round trip, malformed-data handling, and unrelated-data preservation.
- Markdown toolbar insertion and selection wrapping.
- Split layout at wide width and toggle layout at narrow width.
- Search result count and next-match selection.
- Heading table of contents extraction and navigation.
- Pin, color, tags, source CRUD, and attachment callbacks.
- Collapsed excerpt and metadata indicators.
- Expanded bounded scrolling and collapsed no-overflow behavior.
- Existing note data without `data['note']` remains editable.

## Non-Goals

- Collaborative real-time editing.
- WYSIWYG rich-text storage.
- Embedded remote web pages.
- Automatic backlink creation from arbitrary text.
- OCR, audio transcription, or AI summarization.
- Nested notes or folder hierarchy inside a note.
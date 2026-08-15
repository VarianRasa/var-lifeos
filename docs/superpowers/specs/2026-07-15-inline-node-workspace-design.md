# Inline Node Workspace Design

**Date:** 2026-07-15  
**Status:** Approved design  
**Approach:** A — expand selected node in place on mindmap canvas

## Goal

Turn each mindmap node into an inline workspace. Selecting or explicitly opening a node expands its existing canvas card in place, exposes its full type-specific editor, and keeps canvas context visible. Only one node may be expanded. Unselected nodes automatically collapse.

## Interaction Model

- Selection remains source of truth through `expandedNodeId`.
- Selecting a collapsed node selects and expands it.
- Selecting another node flushes pending edits from current node, collapses it, then expands new node.
- Clearing selection flushes pending edits and collapses expanded node.
- Re-selecting expanded node does not recreate draft or editor state.
- Keyboard, Life Explorer, search, context menu, connection navigation, and programmatic highlight use same selection/expansion path.
- Old node-detail URLs redirect to day canvas, highlight target node, select it, center it, and expand it.
- Missing or inaccessible route targets return to day canvas with contained status message; no standalone detail surface opens.

## Layout

Expanded node keeps same canvas position and connection identity. Expansion changes card bounds using type family defaults:

| Size | Dimensions | Node types |
| --- | --- | --- |
| Small | 280 × 180 | placeholder, bookmark, resource, question, idea |
| Standard | 360 × 280 | task, note, journal, event, decision, reminder |
| Large | 440 × 360 | plan, goal, habit, metric, expense, contact, location |
| Wide | 560 × 380 | kanban, itinerary, image, video |

Types not explicitly listed use existing `NodePresentationSpec` default, clamped to at least Standard editor space when expanded.

Expanded card structure:

1. **Header:** type icon, title, save status, compact actions, collapse/close control.
2. **Body:** existing type-specific editor from `node_editors`, wrapped in internal scrolling.
3. **Footer:** validation/status summary and type-relevant primary actions.
4. **Ports:** input/output connection ports remain anchored to vertical card center and stay usable while expanded.

Body scrolls internally; canvas does not grow to fit editor content. Header and footer remain visible. Card must not overflow its resolved bounds at minimum supported canvas zoom.

## State Model

### Ephemeral State

- `expandedNodeId`: sole expanded-node identifier, derived from active selection.
- Per-node draft map: editor draft, dirty state, validation state, debounce timer, and save generation.
- Expansion transition state: flush-in-progress and requested next selection.
- Scroll position may remain ephemeral for active session.

Only one editor widget is active at a time, but draft entries may survive temporary rebuilds. Drafts are removed after successful flush and collapse, node deletion, or confirmed replacement by newer repository state.

### Persisted State

Persist only UI state relevant across sessions:

- existing size preset/custom size when user explicitly resizes;
- existing collapsed editor sections;
- editor schema version already owned by `NodeUiStateCodec`.

Do not persist `expandedNodeId`, hover, focus, scroll offset, transient validation, save status, selection animation, or debounce state.

## Editing and Autosave

- Reuse existing `node_editors`; do not create duplicate type editors.
- Every editor mutation updates per-node draft immediately.
- Autosave uses debounce after last valid change.
- Save reads latest repository node, merges draft-owned fields only, preserves unrelated payload and concurrent updates, then saves through `mindmapMutationControllerProvider`.
- Save completion is generation-checked so stale async completion cannot overwrite newer draft status.
- Invalid drafts remain local and display contained validation; they do not replace valid repository state.
- Save errors keep draft dirty and expose retry status without collapsing editor.

Flush is mandatory before:

- switching expanded node;
- clearing selection;
- route/navigation away from day canvas;
- deleting, archiving, duplicating, or moving active node;
- app lifecycle pause where existing platform lifecycle permits;
- backup/export operations that require current edits.

If flush fails validation or persistence, switch/navigation is blocked and current node remains expanded. Destructive actions require existing confirmation behavior.

## Canvas Integration

Expansion must preserve existing canvas systems:

- connections and relation labels;
- connection creation, relink, and port hit-testing;
- node drag and persisted position;
- node resize and preset selection;
- minimap bounds and viewport fitting;
- zoom, pan, keyboard navigation, lasso, multi-selection, and focus mode;
- undo/redo history;
- collaboration selection/cursor signals;
- backup, restore, local persistence, sync planning, and attachment references.

Expanded bounds participate in overlap, selection, minimap, fit, group frame, and connection endpoint calculations. Drag starts only from header/drag-safe area; editor controls, text selection, scrolling, media controls, and form gestures must not move canvas node.

Undo records committed node mutations, not every draft keystroke. One debounced save produces one logical undo entry. Expansion/collapse alone creates no undo entry.

## Routing and Migration

`NodeDetailPage` becomes compatibility-only during migration:

1. Existing `/calendar/:day/node/:nodeId` route resolves day and node.
2. Router redirects to day canvas with `highlightNodeId`/equivalent route state.
3. Day canvas selects, centers, highlights, and expands target after node data loads.
4. Deep links, bookmarks, and notifications retain functional destination semantics.

After route redirect coverage and analytics confirm no remaining direct dependency, remove `NodeDetailPage`, its standalone layout, duplicate editor wiring, and tests that assert separate detail rendering. Keep route redirect permanently for backward-compatible links.

No node-data migration is required. Existing node payload, attachment IDs, UI size state, relationships, backup format, and sync format remain valid.

## Accessibility and Input

- Expanded card exposes clear semantic label: node type, title, expanded state, and save state.
- Collapse, save retry, type actions, and ports remain keyboard reachable.
- Focus moves into editor only after explicit expansion; switching restores predictable focus.
- Escape flushes valid draft then collapses; validation failure keeps editor open.
- Internal scrolling supports wheel, trackpad, touch, Page Up/Down, and keyboard focus traversal.
- Minimum touch targets and existing contrast tokens remain unchanged.

## Error and Race Handling

- Selection changes are serialized; latest requested selection wins after successful flush.
- Repository node deletion during edit closes draft safely and reports missing node.
- Concurrent external updates merge against latest node at commit; draft-owned fields win only where user changed them.
- Node type changes invalidate incompatible draft/editor state and rebuild from latest payload.
- Attachment imports retain existing ownership cleanup rules: newly imported uncommitted attachment is removed; old attachments remain for retention-based garbage collection.
- Provider invalidation follows existing `invalidateMindmapState` boundary after committed mutation.

## Testing

### Type Coverage

- Parameterized render and edit smoke tests for every `NodeType`.
- Verify each type selects correct expanded size family or fallback.
- Verify existing `node_editors` load and emit payload without losing unrelated data.
- Explicit minimum-size and overflow tests for Image, Video, Itinerary, Kanban, and dense payload editors.

### Selection and Drafts

- Only one node expanded.
- Unselected node auto-collapses.
- Draft survives harmless rebuild.
- Switch flushes current draft before expanding next node.
- Failed validation/save blocks switch and preserves draft.
- Latest rapid selection wins.

### Autosave

- Debounce coalesces sequential edits.
- Stale save completion cannot clear newer dirty state.
- Latest repository merge preserves concurrent unrelated fields.
- Lifecycle/navigation/backup flush paths persist valid draft.
- Undo groups one debounced commit as one mutation.

### Routing

- Old detail route redirects to correct day.
- Target node is highlighted, centered, selected, and expanded.
- Missing node produces contained canvas status.
- Browser back/forward and deep links remain stable.

### Canvas Behavior

- Connections remain centered and interactive for expanded cards.
- Connection preview and completion work while source or target is expanded.
- Drag uses header area; editor interaction does not drag node.
- Resize, minimap, fit, zoom, grouping, lasso, and multi-selection use expanded bounds.
- Compact and collapsed cards render without overflow after expansion closes.

### Data Integrity

- Payload round-trip for every type.
- Attachment IDs remain metadata-only.
- Backup/restore and sync round-trip expanded-node edits.
- Expansion state is absent from persisted node and backup data.

## Non-Goals

- Multiple expanded nodes.
- Split-pane or detached inspector editor.
- New node payload schema solely for inline expansion.
- Persisting active expansion or scroll position.
- Replacing existing node editors.
- Changing sync protocol, backup format, attachment retention policy, or collaboration protocol.
- Deleting old attachments from UI replace flow.
- Mobile-specific full-screen editor redesign; compact screens may use existing adaptive canvas constraints while preserving same state model.

## Acceptance Criteria

- Every supported `NodeType` can be edited inline without opening standalone detail UI.
- Exactly one selected node is expanded; deselection collapses it.
- Autosave and mandatory flush prevent silent edit loss.
- Concurrent unrelated payload updates survive commit.
- Existing detail links redirect and expand correct canvas node.
- Expanded cards preserve connection, drag, resize, minimap, zoom, undo, backup, and sync behavior.
- Minimum-size and overflow tests pass for dense editors.
- `NodeDetailPage` has documented compatibility removal path and no new feature dependency.

# Quote Node Design

## Goal

Turn Quote nodes into useful local quote-collection cards with reliable editing, autosave, rich collapsed previews, and backward-compatible stored data.

## Scope

- Use node body as quote text.
- Keep title as card label.
- Add structured author, source, collection, tags, and favorite fields.
- Add copy action that copies quote text with optional author attribution.
- Show quote details and actions in collapsed mode.
- Auto-size expanded Quote nodes and disable manual resize.
- Preserve existing `author` and `quoteSource` data.
- Repair mojibake defaults or rendering that currently displays broken quote characters.

## Data Model

Extend `QuotePayload` with:

- `author: String`
- `source: String`
- `collection: String`
- `tags: List<String>`
- `isFavorite: bool`

Storage keys remain additive. Existing `author` and `quoteSource` keys stay unchanged. New keys use `collection`, `tags`, and `isFavorite`. Unknown data keys remain preserved by `toData`.

Tags are trimmed, empty entries are removed, and duplicate tags are removed case-insensitively while retaining first-entry spelling.

## Expanded Editor

Expanded editor contains:

1. Existing title field.
2. Existing content field as multiline quote text.
3. Author field.
4. Source field.
5. Collection field.
6. Tag chips with add, edit, and remove actions.
7. Favorite toggle.
8. Copy Quote action.

All text fields use normal `EditableText` behavior, including external paste and URL/symbol input. Draft changes flow through existing inline autosave pipeline. Expanded Quote node size follows `InlineNodeWorkspacePolicy`; resize handles are hidden.

## Collapsed Preview

Collapsed card shows:

- Favorite state.
- Quote text with typographic quote styling.
- Author attribution when present.
- Source and collection when present.
- Tag chips within available width.
- Copy Quote action.

Preview adapts content to available node size without `RenderFlex` overflow. It limits secondary metadata before truncating primary quote text. Existing node movement remains available outside interactive controls.

## Copy Behavior

Copied text format:

- Quote only: `Quote text`
- Quote plus author: `“Quote text” — Author`

Source, collection, and tags are not copied.

## Compatibility

- Existing Quote nodes load without migration.
- Missing new fields use empty values or `false`.
- Existing author/source tests continue passing.
- Unknown node data remains untouched.

## Validation

Add focused tests for:

- Payload round trip and unknown-key preservation.
- Tag normalization.
- Editing author, source, collection, tags, and favorite.
- Copy output.
- Autosave integration.
- Expanded fixed auto-size without resize controls.
- Collapsed preview at narrow and short sizes without overflow.
- Legacy Quote node compatibility.

## Deliberate Limits

No rating, quote usage history, remote metadata lookup, citation verification, or nested collections. Add only when product usage proves need.
# Image Editor Professional UI Design

## Goal

Polish expanded image-node editor into a professional desktop editing workspace. Improve hierarchy, spacing, scanability, and action clarity without changing autosave, attachment persistence, image rendering, or editing behavior.

## Chosen Direction

Use a balanced two-column studio layout at a fixed expanded size of 900 by 820 logical pixels.

- Left column: visual preview and direct image transforms.
- Right column: metadata, adjustments, and annotations.
- Bottom: persistent action footer.
- Narrow constraints: fall back to a vertical layout without overflow.

## Layout

### Workspace

- Expanded image nodes always use 900 by 820 logical pixels.
- Manual resize controls are disabled while expanded.
- Outer padding is 16 pixels.
- Main content uses a 16-pixel gap between columns.
- Left column uses approximately 42 percent of available width.
- Right column uses remaining width and owns vertical scrolling when content exceeds available height.
- Footer stays visible and does not scroll with inspector content.

### Left Preview Column

- Put image inside a bordered preview card using surface-container colors.
- Keep preview aspect area visually dominant and centered.
- Show compact source state below preview: local file, remote URL, loading, or missing source.
- Group fit, rotate, flip, undo, and redo inside one transform toolbar.
- Use icon buttons with tooltips and consistent 40-pixel targets.
- Keep lightbox behavior on preview.

### Right Inspector Column

Use four visually separated sections:

1. **Source**
   - Image URL.
   - Source URL.
   - Tag input and removable chips.
2. **Details**
   - Caption.
   - Required alt text.
   - Accessibility helper or error state.
3. **Adjustments**
   - Filter selector.
   - Brightness, contrast, and saturation sliders.
   - Numeric value display and reset action per slider.
4. **Annotations**
   - Text, arrow, rectangle, and freehand tool buttons.
   - Existing annotation rows with delete action.

Each section uses:

- Small icon and title header.
- Surface-container-low background.
- Subtle outline and 12-pixel radius.
- 12-pixel internal padding.
- 10 to 12 pixels between controls.

## Field Styling

- Use outlined, dense fields with consistent labels.
- Keep URL keyboard type for URL fields.
- Preserve text selection, paste, slash, query strings, fragments, and autosave focus.
- Do not recreate field keys during autosave echo rebuilds.
- Alt-text validation stays visible but uses concise helper spacing.
- Tag input provides a clear submit affordance in addition to keyboard submission.

## Adjustment Controls

- Slider label, reset icon, and numeric value share one header row.
- Slider occupies full section width below header.
- Reset button is disabled when value is zero.
- Existing value ranges and payload behavior remain unchanged.
- Filter selection remains a dropdown but uses the same dense inspector styling.

## Annotation Controls

- Tool buttons use icon plus label instead of text-only controls.
- Selected or active tool styling is reserved for future interactive canvas work; current add-on-click behavior remains.
- Existing annotations display in compact rows with type, text summary, and delete action.
- Empty annotation state shows a short instruction rather than blank space.

## Footer Actions

- Footer has top divider and surface-container background.
- Left group: Replace and Export.
- Right group: Remove from node and Save as new image.
- Save as new image is primary filled action.
- Remove from node uses error-color styling but stays outlined.
- Buttons wrap only on narrow fallback layouts.
- Retry and Open externally remain available in contextually appropriate groups.

## Responsive Behavior

- At 720 logical pixels or wider, use two columns.
- Below 720 pixels, use one vertically scrolling inspector with preview first.
- Footer remains outside scrolling content in both modes.
- No RenderFlex overflow is acceptable at supported widths.

## Accessibility

- Every icon-only action keeps a tooltip.
- Touch and pointer targets remain at least 40 logical pixels.
- Section headings use semantic text hierarchy.
- Destructive action remains visually distinct from primary save action.
- Alt-text validation remains prominent and readable.

## Behavior Preservation

- No payload schema changes.
- No new dependencies.
- Keep autosave and semantic draft comparison.
- Keep attachment replace, export, retry, save-as-new, restore-original, remove, and external-open callbacks.
- Keep filters, transforms, tags, annotations, undo, redo, and lightbox behavior.

## Testing

- Existing image editor behavior tests remain green.
- Add layout tests for two-column and narrow fallback modes.
- Assert section labels and primary/destructive actions.
- Assert fixed expanded size remains 900 by 820 and resize handles stay absent.
- Assert no overflow exceptions at desktop and narrow test surfaces.
- Run targeted image tests, Flutter analyzer, and Windows release build.

## Deliberate Limits

- No new crop or annotation geometry behavior in this polish pass.
- No drag-and-drop or clipboard image import changes.
- No payload migration.
- No changes to collapsed image-node design beyond compatibility fixes required by shared widgets.

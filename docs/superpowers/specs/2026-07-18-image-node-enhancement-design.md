# Image Node Enhancement Design

## Goal

Turn image nodes into a balanced photo, reference, and asset workflow. Users can import, inspect, edit, annotate, export, and restore images without losing the original attachment.

## Scope

### Sources

- Import a local GIF, JPG, PNG, or WebP file up to 100 MB.
- Accept an HTTPS image URL.
- Accept drag-and-drop and clipboard image paste where the platform supports them.
- Keep existing replace and retry flows.

### Metadata

- Caption.
- Required accessibility alt text.
- Optional source URL.
- Editable tags.
- Read-only file name, MIME type, byte size, dimensions, and modified time when available.

### Viewer

- Render local attachment or remote URL with loading, retry, and missing-image states.
- Zoom and pan.
- Fit modes: contain and cover.
- Editable focal point for cover mode.
- Lightbox from the collapsed node preview.
- Before/after comparison while editing.

### Transform Editor

- Free crop and preset aspect ratios: original, square, 4:3, 16:9, and portrait.
- Rotate left/right in 90-degree steps.
- Horizontal and vertical flip.
- Brightness, contrast, and saturation controls.
- Small built-in filter set implemented from the same adjustment values.
- Reset individual controls and reset all.

### Annotation Editor

- Text, arrow, rectangle, and freehand tools.
- Stroke color, fill color where relevant, and thickness.
- Select, move, resize, and delete annotations.
- Undo and redo for annotation and transform operations.
- Annotation coordinates remain normalized to image dimensions.

### Save Model

- Editing is non-destructive until save.
- Save as new image renders the current transform and annotations to a new PNG or JPEG attachment.
- Original attachment remains referenced as the restore source.
- Active node switches to the newly rendered attachment only after persistence succeeds.
- Failed rendering or persistence leaves the current image unchanged and removes temporary output.
- Restore original switches back to the original attachment without deleting derived files automatically.

### Actions

- Replace image.
- Remove active image with confirmation.
- Export active image.
- Copy active image to clipboard where supported.
- Open active image externally where supported.
- Save edited image as new attachment.
- Restore original.

### Collapsed Node

- Use most available node space for image preview.
- Show caption and up to three tags without covering important image content.
- Respect contain/cover and focal point settings.
- Clicking preview opens lightbox.
- Keep loading, retry, and missing-image feedback visible.

## Data Model

Extend ImagePayload with source URL, tags, original attachment ID, dimensions, transform values, focal point, adjustment values, filter, and annotations. Existing attachmentId remains active attachment.

Each annotation stores a stable ID, tool type, normalized geometry, text when applicable, colors, and stroke width.

## Architecture

- Domain payload and validation stay in node_type_payloads.dart.
- Editor UI and preview stay in media_travel_node_editors.dart unless size requires one focused image editor file.
- Raster rendering uses Flutter image APIs and ui.PictureRecorder; no new package.
- Attachment reads and writes use existing node attachment repository and media action callback boundary.
- Platform clipboard and external-open behavior uses existing conditional adapters or small conditional files.

## Validation

- Alt text required when an image source exists.
- HTTPS required for remote URLs.
- Imported MIME must be GIF, JPEG, PNG, or WebP.
- Import size must not exceed 100 MB.
- Crop and focal coordinates must remain between zero and one.
- Adjustment values are clamped to documented ranges.
- Empty annotations and invalid geometry are rejected during payload normalization.

## Testing

- Payload serialization, normalization, copy, and validation tests.
- Crop, focal, and annotation coordinate tests.
- Raster output smoke test with a tiny fixture image.
- Editor tests for tags, adjustments, annotation undo and redo, save, restore, remove, and action callbacks.
- Collapsed preview tests for local bytes, URL state, caption, tags, fit, and lightbox action.
- Overflow tests across compact, standard, large, and wide presets.
- Full flutter analyze, targeted tests, and Windows build.

## Deliberate Limits

- No AI image generation or AI alt-text generation.
- No layer masks, blend modes, perspective transform, or arbitrary-angle rotation.
- No automatic deletion of derived attachments; attachment garbage collection remains separate work.
- GIF edits export a still image from the currently decoded frame.

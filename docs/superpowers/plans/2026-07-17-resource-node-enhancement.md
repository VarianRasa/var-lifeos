# Resource Node Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a structured Resource node with one primary file or URL, related assets, adaptive previews, three-level folders, editable tags, content-driven expanded sizing, and legacy migration.

**Architecture:** Add `ResourcePayload` and `ResourceAsset` beside existing typed node payloads, while leaving Link and Bookmark on `LinkResourcePayload`. Put Resource-specific UI in one focused editor/preview file, reuse existing node attachment repository and file picker path, and keep `mindmap_canvas.dart` changes limited to payload routing, attachment loading, collapsed preview, and sizing behavior.

**Tech Stack:** Flutter, Dart 3.11, Material 3, Riverpod, `file_picker`, existing `NodeAttachmentRepository`, `url_launcher`, Flutter widget tests.

**Execution note:** Do not create commits unless the user explicitly requests them.

---

## File Map

- Modify `lib/features/mindmap/domain/node_type_payloads.dart`: define `ResourceAsset`, `ResourcePayload`, migration, persistence, and validation.
- Modify `lib/features/mindmap/presentation/node_type_inline_editor.dart`: route Resource drafts through `ResourcePayload`.
- Modify `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart`: add Resource attachment callbacks to `NodeEditContext`.
- Create `lib/features/mindmap/presentation/node_editors/resource_node_editor.dart`: Resource editor, dialogs, folder/tags, asset cards, and shared adaptive preview.
- Modify `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`: delegate Resource rendering/editing to the new Resource widgets.
- Modify `lib/features/mindmap/presentation/mindmap_canvas.dart`: load primary attachment bytes, connect file/open actions, route collapsed Resource preview, and disable expanded resize.
- Modify `lib/features/mindmap/domain/inline_node_workspace_policy.dart`: calculate expanded Resource height from structured content.
- Modify focused tests under `test/features/mindmap/` for domain, editor, attachment integration, preview, and sizing.

---

### Task 1: Resource domain model and legacy migration

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart`

- [ ] **Step 1: Write failing structured round-trip test**

Add a test named `resource payload round trips assets folders and unknown keys` that constructs:

```dart
const payload = ResourcePayload(
  primaryAsset: ResourceAsset(
    id: 'primary',
    kind: 'file',
    label: 'Architecture PDF',
    attachmentId: 'attachment-1',
    mimeType: 'application/pdf',
    sizeBytes: 2048,
    fileName: 'architecture.pdf',
    extension: 'pdf',
  ),
  relatedAssets: <ResourceAsset>[
    ResourceAsset(
      id: 'related-1',
      kind: 'url',
      label: 'Reference',
      location: 'https://example.com/reference',
    ),
  ],
  folderPath: <String>['Research', 'Flutter', 'Rendering'],
  description: 'Rendering architecture reference.',
  tags: <String>['flutter', 'graphics'],
);
```

Assert `toData` stores a nested `resource` map, retains a foreign root key, and `ResourcePayload.fromNode` restores every field and node tag.

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart --name "resource payload round trips" -r expanded
```

Expected: FAIL because `ResourcePayload` and `ResourceAsset` do not exist.

- [ ] **Step 3: Add immutable Resource types**

Implement these public shapes in `node_type_payloads.dart`:

```dart
final class ResourceAsset {
  const ResourceAsset({
    required this.id,
    required this.kind,
    this.label = '',
    this.location = '',
    this.attachmentId = '',
    this.mimeType = '',
    this.sizeBytes,
    this.fileName = '',
    this.extension = '',
  });

  final String id;
  final String kind;
  final String label;
  final String location;
  final String attachmentId;
  final String mimeType;
  final int? sizeBytes;
  final String fileName;
  final String extension;

  String get displayName;
  bool get isFile;
  bool get isUrl;
  bool get isImage;
  ResourceAsset copyWith({
    String? label,
    String? location,
    String? attachmentId,
    String? mimeType,
    int? sizeBytes,
    String? fileName,
    String? extension,
  });
  Map<String, Object?> toJson();
  static ResourceAsset? fromJson(Object? value);
}

final class ResourcePayload {
  const ResourcePayload({
    this.schemaVersion = 1,
    this.primaryAsset,
    this.relatedAssets = const <ResourceAsset>[],
    this.folderPath = const <String>[],
    this.description = '',
    this.tags = const <String>[],
  });

  final int schemaVersion;
  final ResourceAsset? primaryAsset;
  final List<ResourceAsset> relatedAssets;
  final List<String> folderPath;
  final String description;
  final List<String> tags;

  factory ResourcePayload.fromNode(MindmapNode node);
  ResourcePayload copyWith({
    ResourceAsset? primaryAsset,
    bool clearPrimaryAsset = false,
    List<ResourceAsset>? relatedAssets,
    List<String>? folderPath,
    String? description,
    List<String>? tags,
  });
  Map<String, Object?> toData(Map<String, Object?> data);
  MindmapNode toNode(MindmapNode node);
  List<String> validate({required String title});
}
```

Use the existing nested-section merge pattern so unknown nested `resource` keys and unrelated root keys survive writes. `toNode` writes `tags` back to the node.

- [ ] **Step 4: Add deterministic legacy migration test**

Create a Resource node with:

```dart
const <String, Object?>{
  'source': 'https://example.com/manual.pdf',
  'category': 'Research',
  'description': 'Legacy summary',
  'links': <String>['https://example.com/a', 'invalid'],
  'foreign': true,
}
```

Assert:

- primary asset ID is `legacy-primary`
- primary kind is `url`
- only the valid HTTP link becomes `legacy-related-1`
- folder path is `['Research']`
- description and foreign key survive
- repeated reads produce identical IDs

- [ ] **Step 5: Implement legacy migration and summary writes**

When no nested structured Resource exists:

```dart
final source = _text(node.data['source']).trim();
final category = _text(node.data['category']).trim();
final links = _strings(node.data['links']);
```

Map HTTP/HTTPS sources to URL assets. Map non-URL sources to a file-kind safe legacy record with `location` only and no `attachmentId`. Map valid legacy links in original order. On writes, keep compatibility summaries:

```dart
result
  ..['source'] = primaryAsset?.location ?? primaryAsset?.fileName ?? ''
  ..['category'] = folderPath.firstOrNull ?? ''
  ..['description'] = description
  ..['links'] = relatedAssets
      .where((asset) => asset.isUrl)
      .map((asset) => asset.location)
      .toList(growable: false);
```

- [ ] **Step 6: Add validation tests**

Assert exact validation messages for:

- unsupported schema version
- unsupported kind
- duplicate and empty IDs
- URL without absolute HTTP/HTTPS location
- missing primary asset
- file without attachment ID or safe legacy location
- negative size
- empty fallback display name
- more than three folder levels
- empty folder segment
- `/` or `\\` inside a folder segment
- repeated adjacent folder segment
- empty tag

- [ ] **Step 7: Implement validation**

Use existing `NodeValidation.requiredTitle(title)` plus Resource-specific checks. Validation must return errors without throwing and must not mutate the payload.

- [ ] **Step 8: Run domain tests**

Run:

```powershell
flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart --name "resource" -r expanded
```

Expected: PASS.

---

### Task 2: Typed draft routing without changing Link or Bookmark

**Files:**
- Modify: `lib/features/mindmap/presentation/node_type_inline_editor.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`

- [ ] **Step 1: Write failing Resource draft routing test**

Create a Resource node with a structured payload, call `nodeTypeInlineDraftFor`, then call `applyNodeTypeInlineDraft` with an updated description. Assert the draft is `ResourcePayload`, data is saved, and tags update on the node. Also assert Link and Bookmark still return `LinkResourcePayload`.

- [ ] **Step 2: Run routing test and verify failure**

Run:

```powershell
flutter test --no-pub test/features/mindmap/presentation/knowledge_node_editors_test.dart --name "resource typed draft" -r expanded
```

Expected: FAIL because Resource still routes through `LinkResourcePayload`.

- [ ] **Step 3: Split Resource routing**

Change `nodeTypeInlineDraftFor` to:

```dart
NodeType.link || NodeType.bookmark => LinkResourcePayload.fromNode(node),
NodeType.resource => ResourcePayload.fromNode(node),
```

Change `applyNodeTypeInlineDraft` to accept `(NodeType.resource, ResourcePayload)` and call `value.toNode(node)`. Keep Link and Bookmark branches unchanged.

In `mindmap_canvas.dart`, change `_typedPayloadForNode`, `_payloadFor`, validation, and typed-draft equality branches so Resource uses `ResourcePayload`. Compare all Resource fields, including asset lists, folder path, description, and tags.

- [ ] **Step 4: Run routing test**

Run the command from Step 2.

Expected: PASS.

---

### Task 3: Resource attachment callbacks and generic file import

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Add failing callback integration test**

Pump `buildProductionNodeInlineEditorForTest` for a Resource node with overridden in-memory attachment repository. Trigger the Resource `Choose file` action through a fake callback seam. Assert the returned asset contains attachment ID, file name, MIME type, byte length, and normalized extension.

- [ ] **Step 2: Run integration test and verify failure**

Run:

```powershell
flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name "resource imports primary file" -r expanded
```

Expected: FAIL because Resource callbacks are not available.

- [ ] **Step 3: Add Resource callback types**

In `productivity_node_editors.dart`, add:

```dart
typedef ResourceAssetAddCallback = Future<ResourceAsset?> Function();
typedef ResourceAssetOpenCallback = Future<void> Function(
  ResourceAsset asset,
);
```

Add optional `onResourceAssetAdd` and `onResourceAssetOpen` fields plus `List<List<String>> resourceFolderSuggestions` to `NodeEditContext`.

- [ ] **Step 4: Reuse existing safe attachment import path**

In `_ProductionNodeInlineEditorState`, implement `_addResourceAsset()` by calling the existing generic attachment picker/import logic used by task attachments and mapping the result:

```dart
return ResourceAsset(
  id: 'asset-${const Uuid().v4()}',
  kind: 'file',
  label: attachment.fileName,
  attachmentId: attachment.id,
  mimeType: attachment.mimeType,
  sizeBytes: attachment.byteLength,
  fileName: attachment.fileName,
  extension: _normalizedExtension(attachment.fileName),
);
```

Do not delete physical bytes when a Resource reference is removed. Keep repository cleanup outside the editor.

Implement `_openResourceAsset`:

- URL assets call the existing validated external-open path.
- File image assets open the existing memory image dialog.
- Other file assets export/read bytes through the existing attachment repository and report `Unavailable` when missing.

Pass both callbacks into `NodeEditContext`. Watch `nodesForDayProvider(widget.node.day)`, parse only Resource nodes, deduplicate non-empty `folderPath` values, and pass the resulting paths through `resourceFolderSuggestions`.

- [ ] **Step 5: Run integration test**

Run the command from Step 2.

Expected: PASS.

---

### Task 4: Shared adaptive Resource preview

**Files:**
- Create: `lib/features/mindmap/presentation/node_editors/resource_node_editor.dart`
- Create: `test/features/mindmap/presentation/resource_node_editor_test.dart`

- [ ] **Step 1: Write failing preview matrix test**

Pump `ResourceAssetPreview` for:

- local image with bytes
- direct image URL
- generic URL
- PDF/document
- audio
- video
- unknown binary
- unavailable local attachment

Assert stable keys:

```dart
const ValueKey<String>('resource-preview-image');
const ValueKey<String>('resource-preview-url');
const ValueKey<String>('resource-preview-document');
const ValueKey<String>('resource-preview-audio');
const ValueKey<String>('resource-preview-video');
const ValueKey<String>('resource-preview-generic');
const ValueKey<String>('resource-preview-unavailable');
```

Assert every case renders without overflow at widths 280, 640, and 760.

- [ ] **Step 2: Run preview test and verify failure**

Run:

```powershell
flutter test --no-pub test/features/mindmap/presentation/resource_node_editor_test.dart --name "resource preview" -r expanded
```

Expected: FAIL because preview widget does not exist.

- [ ] **Step 3: Implement `ResourceAssetPreview`**

Create a stateless widget with this interface:

```dart
class ResourceAssetPreview extends StatelessWidget {
  const ResourceAssetPreview({
    required this.asset,
    this.bytes,
    this.loading = false,
    this.error,
    this.compact = false,
    super.key,
  });

  final ResourceAsset asset;
  final Uint8List? bytes;
  final bool loading;
  final String? error;
  final bool compact;
}
```

Use `Image.memory` for managed local image bytes and `Image.network` only for direct HTTP/HTTPS image URLs, with `errorBuilder` falling back to a generic URL card. Use bounded `AspectRatio`, `maxLines`, and `TextOverflow.ellipsis`. Never place `Expanded` under an unbounded scroll constraint.

Also define the shared node-level preview used by expanded content and collapsed cards:

```dart
class ResourceNodePreview extends StatelessWidget {
  const ResourceNodePreview({
    required this.payload,
    this.primaryBytes,
    this.primaryLoading = false,
    this.primaryError,
    this.compact = false,
    super.key,
  });

  final ResourcePayload payload;
  final Uint8List? primaryBytes;
  final bool primaryLoading;
  final String? primaryError;
  final bool compact;
}
```

`ResourceNodePreview` composes `ResourceAssetPreview`, folder breadcrumb, related count, description, and bounded tags. Empty Resource state renders a clear `No asset selected` card.

- [ ] **Step 4: Add metadata formatting helpers**

Add pure helpers in the same file:

```dart
String resourceAssetTypeLabel(ResourceAsset asset);
String resourceFileSizeLabel(int? bytes);
String resourceUrlHost(String location);
IconData resourceAssetIcon(ResourceAsset asset);
```

Cover these helpers in the preview test.

- [ ] **Step 5: Run preview tests**

Run the command from Step 2.

Expected: PASS.

---

### Task 5: Full Resource editor interactions

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/resource_node_editor.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/resource_node_editor_test.dart`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`

- [ ] **Step 1: Write failing primary asset tests**

Pump `ResourceNodeEditor` with recording callbacks. Verify:

- empty state exposes `resource-primary-choose-file` and `resource-primary-paste-url`
- cancelled file callback leaves payload unchanged
- successful file callback sets primary asset
- valid URL dialog creates URL asset
- invalid URL remains in dialog with `Use an absolute HTTP or HTTPS URL.`
- replace updates only primary asset
- remove clears only primary asset
- open and copy actions emit the correct target

- [ ] **Step 2: Write failing related asset tests**

Verify add file, add URL, edit label, open, copy, and remove. Assert insertion order remains stable and related mutations never replace the primary asset.

- [ ] **Step 3: Write failing folder and tag tests**

Verify:

- folder segment add/edit/remove
- existing folder paths appear as deduplicated suggestions
- fourth segment control is disabled
- removing segment two removes segments two and three
- invalid separator displays local error
- tags can add, edit, and remove
- empty tags are rejected

- [ ] **Step 4: Run editor tests and verify failure**

Run:

```powershell
flutter test --no-pub test/features/mindmap/presentation/resource_node_editor_test.dart -r expanded
```

Expected: FAIL because editor interactions are not implemented.

- [ ] **Step 5: Implement `ResourceNodeEditor`**

Use this interface:

```dart
class ResourceNodeEditor extends StatefulWidget {
  const ResourceNodeEditor({
    required this.payload,
    required this.onChanged,
    this.primaryBytes,
    this.primaryLoading = false,
    this.primaryError,
    this.onChooseFile,
    this.onOpenAsset,
    this.folderSuggestions = const <List<String>>[],
    super.key,
  });

  final ResourcePayload payload;
  final ValueChanged<ResourcePayload> onChanged;
  final Uint8List? primaryBytes;
  final bool primaryLoading;
  final String? primaryError;
  final ResourceAssetAddCallback? onChooseFile;
  final ResourceAssetOpenCallback? onOpenAsset;
  final List<List<String>> folderSuggestions;
}
```

Use small dialogs with `TextFormField(initialValue:)` and local draft strings; do not manually dispose dialog controllers during route closing animations. Use `Clipboard.setData` for copy actions and show local feedback only after success.

- [ ] **Step 6: Add bounded asset cards and controls**

Use `Wrap` for toolbar actions, `Column(mainAxisSize: MainAxisSize.min)` for lists, and fixed/limited preview height. Keys must include asset IDs so tests and accessibility can target each item.

- [ ] **Step 7: Delegate Resource from knowledge editor**

Change the switch to:

```dart
NodeType.link || NodeType.bookmark => _linkFields(),
NodeType.resource => _resourceFields(buildContext),
```

Return `ResourceNodeEditor` from `_resourceFields`, passing Resource payload, preview bytes/loading/error, and Resource callbacks from `NodeEditContext`. Remove old Source/Category/Description/Links fields only for Resource; Link and Bookmark remain unchanged.

- [ ] **Step 8: Run editor and knowledge tests**

Run:

```powershell
flutter test --no-pub test/features/mindmap/presentation/resource_node_editor_test.dart test/features/mindmap/presentation/knowledge_node_editors_test.dart --name "resource" -r expanded
```

Expected: PASS.

---

### Task 6: Production attachment loading and Resource content rendering

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Write failing primary image loading test**

Create a Resource with a local image primary asset, override `nodeAttachmentRepositoryProvider`, and pump production content/editor. Assert bytes reach `ResourceAssetPreview` and render `resource-preview-image`.

- [ ] **Step 2: Run loading test and verify failure**

Run:

```powershell
flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name "resource loads primary image attachment" -r expanded
```

Expected: FAIL because Resource is not part of production attachment loading.

- [ ] **Step 3: Extend production source revision and load logic**

Extend `_mediaSourceFor`, `_dataRevision`, `_load`, and payload synchronization so a Resource primary attachment ID triggers repository loading. Clear stale bytes when primary asset changes from file to URL or is removed. Preserve generation checks so late reads cannot overwrite newer drafts.

- [ ] **Step 4: Render Resource through knowledge content**

In `_KnowledgeContent`, branch Resource to a `ResourceNodePreview` from `resource_node_editor.dart`. Pass `NodeRenderContext.attachmentBytes`, loading, and error. Show primary preview, folder breadcrumb, related count, description, and bounded tags for compact/standard/large/wide presets.

- [ ] **Step 5: Route Resource through production content wrapper**

In `_NodeTypeSpecificContent`, route `NodeType.resource` through `_ProductionNodeTypeContent` so attachment bytes are available. Remove Resource from `_NoteNodeSource` routing.

- [ ] **Step 6: Run loading and preset tests**

Run:

```powershell
flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name "resource loads primary image attachment" -r expanded
flutter test --no-pub test/features/mindmap/presentation/knowledge_node_editors_test.dart --name "resource renders" -r expanded
```

Expected: PASS.

---

### Task 7: Collapsed preview gesture safety

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/resource_node_editor.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Write failing collapsed preview test**

Render a collapsed Resource with a primary document, three-level folder, three tags, and two related assets. Assert:

- `resource-collapsed-preview` exists
- primary label and type appear
- folder breadcrumb truncates safely
- related count appears
- no rendering exception at a 280 by 220 custom size

- [ ] **Step 2: Write failing gesture safety test**

Drag over the preview area and assert the node movement callback receives the drag. The preview must not open, select text, or capture asset actions.

- [ ] **Step 3: Implement bounded non-interactive preview**

Wrap collapsed `ResourceNodePreview` in `IgnorePointer`. Limit tags and metadata based on available width. Use `Flexible` with loose fit or fixed preview bounds under any scrollable parent; never use non-zero flex with unbounded height.

- [ ] **Step 4: Run collapsed tests**

Run:

```powershell
flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name "resource collapsed" -r expanded
```

Expected: PASS.

---

### Task 8: Content-driven expanded size and resize behavior

**Files:**
- Modify: `lib/features/mindmap/domain/inline_node_workspace_policy.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Write failing size policy test**

Create a compact Resource and another with primary preview, three folders, tags, long description, and six related assets. Assert both widths equal `760`, detailed height exceeds compact height, and the height formula is deterministic.

- [ ] **Step 2: Implement Resource expanded policy**

Add a stable base size and an early Resource branch:

```dart
static const InlineNodeWorkspaceSize resource = InlineNodeWorkspaceSize(
  760,
  780,
);

if (node.type == NodeType.resource) {
  final payload = ResourcePayload.fromNode(node);
  final descriptionLines = _workspaceTextLines(
    payload.description,
    min: 2,
    max: 6,
  );
  final primaryHeight = payload.primaryAsset == null ? 120.0 : 280.0;
  final folderHeight = payload.folderPath.isEmpty ? 56.0 : 88.0;
  final tagHeight = payload.tags.isEmpty ? 56.0 : 96.0;
  final relatedHeight = payload.relatedAssets.length * 84.0;
  return InlineNodeWorkspaceSize(
    760,
    520 +
        primaryHeight +
        folderHeight +
        tagHeight +
        descriptionLines * 20 +
        relatedHeight,
  );
}
```

Change `expandedSizeFor(NodeType.resource)` and the design-family test to return `InlineNodeWorkspacePolicy.resource`. `expandedSizeForNode` remains authoritative for content-driven height.

- [ ] **Step 3: Write failing resize behavior tests**

Assert expanded Resource ignores persisted custom width/height and `NodeShell.onResizeChanged` is null. Assert collapsed highlighted Resource retains callback and bottom-right resize handle.

- [ ] **Step 4: Add Resource to fixed expanded branches**

Add `NodeType.resource` beside Task/Canvas/Idea/Question/Decision in:

- `_effectiveNodeSizes`
- `_nodeSizeFor`
- expanded `NodeShell.onResizeChanged` condition

Leave collapsed `NodeShell` behavior unchanged.

- [ ] **Step 5: Run sizing tests**

Run:

```powershell
flutter test --no-pub test/features/mindmap/domain/inline_node_workspace_policy_test.dart --name "resource expanded size" -r expanded
flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name "expanded resource|collapsed resource" -r expanded
```

Expected: PASS.

---

### Task 9: Validation, formatting, and focused regression suite

**Files:**
- Verify all files listed above.

- [ ] **Step 1: Format only edited Dart files**

Run `dart format` on the focused Resource/domain/editor/test files. Do not run whole-file formatting on `mindmap_canvas.dart`; preserve its historical encoding and use bounded edits only.

- [ ] **Step 2: Run focused Resource tests**

Run:

```powershell
flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart --name "resource" -r expanded
flutter test --no-pub test/features/mindmap/domain/inline_node_workspace_policy_test.dart --name "resource" -r expanded
flutter test --no-pub test/features/mindmap/presentation/resource_node_editor_test.dart -r expanded
flutter test --no-pub test/features/mindmap/presentation/knowledge_node_editors_test.dart --name "resource" -r expanded
flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name "resource" -r expanded
```

Expected: all selected tests PASS with zero Flutter exceptions.

- [ ] **Step 3: Run targeted analyzer**

Run:

```powershell
flutter analyze lib/features/mindmap/domain/node_type_payloads.dart lib/features/mindmap/domain/inline_node_workspace_policy.dart lib/features/mindmap/presentation/node_type_inline_editor.dart lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart lib/features/mindmap/presentation/node_editors/resource_node_editor.dart lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/domain/inline_node_workspace_policy_test.dart test/features/mindmap/presentation/resource_node_editor_test.dart test/features/mindmap/presentation/knowledge_node_editors_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Check whitespace and unintended files**

Run:

```powershell
git diff --check -- lib/features/mindmap/domain/node_type_payloads.dart lib/features/mindmap/domain/inline_node_workspace_policy.dart lib/features/mindmap/presentation/node_type_inline_editor.dart lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart lib/features/mindmap/presentation/node_editors/resource_node_editor.dart lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/domain/inline_node_workspace_policy_test.dart test/features/mindmap/presentation/resource_node_editor_test.dart test/features/mindmap/presentation/knowledge_node_editors_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart
```

Expected: exit code `0` and no whitespace errors.

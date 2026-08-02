# Inline Node Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace standalone node-detail editing with one autosaving, single-expanded inline workspace on the mindmap canvas while preserving all canvas, persistence, backup, and sync behavior.

**Architecture:** Add pure domain policy for expanded sizes and draft patches, then one Riverpod application controller that owns `expandedNodeId`, per-node drafts, debounce, latest-node merge, and mandatory flush transitions. Extract reusable editor chrome from `NodeEditorPanel`/`NodeDetailPage`, render it inside `MindmapCanvas`, redirect legacy detail URLs to highlighted day canvas, then remove dead standalone detail code after exhaustive type and regression coverage passes.

**Tech Stack:** Flutter 3.41, Dart 3.11, Riverpod, Material 3, go_router, existing `MindmapRepository`, `MindmapMutationController`, `NodeUiStateCodec`, node editor modules, Flutter widget/unit tests.

---

## File Structure

### Create

- `lib/features/mindmap/domain/inline_node_workspace_policy.dart`: exhaustive expanded-size policy, persisted-state boundary, and draft-owned patch merge contract.
- `lib/features/mindmap/application/inline_node_workspace_controller.dart`: single-expanded selection state, per-node drafts, debounce generations, latest-node merge, flush, and transition serialization.
- `lib/features/mindmap/presentation/inline_node_workspace.dart`: reusable header/body/footer workspace that hosts existing type editors with internal scrolling.
- `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`: exhaustive `NodeType` size and non-persistence tests.
- `test/features/mindmap/application/inline_node_workspace_controller_test.dart`: autosave, race, flush, validation, deletion, and latest-merge tests.
- `test/features/mindmap/presentation/inline_node_workspace_test.dart`: editor chrome, scrolling, semantics, action routing, and all-type rendering tests.

### Modify

- `lib/features/mindmap/presentation/node_editor_panel.dart`: extract reusable editor body/actions and delegate to `InlineNodeWorkspace` without duplicating editor logic.
- `lib/features/mindmap/presentation/node_type_inline_editor.dart`: expose complete type-editor dispatcher used by inline workspace.
- `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart`: keep productivity editor actions surface-neutral.
- `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`: keep knowledge editor actions surface-neutral.
- `lib/features/mindmap/presentation/node_editors/life_data_node_editors.dart`: keep life/data editor actions surface-neutral.
- `lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart`: keep media/travel editor actions surface-neutral.
- `lib/features/mindmap/presentation/mindmap_canvas.dart`: render one expanded workspace, use expanded bounds for ports/minimap/layout, and isolate editor gestures from node drag.
- `lib/features/calendar/day_page.dart`: make selection drive expansion, flush before transitions/actions, wire undo and lifecycle boundaries, remove sheet/detail opening behavior.
- `lib/core/router/app_router.dart`: redirect legacy node-detail route to day route with `highlight` query.
- `lib/features/mindmap/presentation/node_detail_page.dart`: remove standalone page after migration coverage passes.
- `test/features/mindmap/presentation/node_editor_panel_test.dart`: preserve extracted editor behavior tests.
- `test/features/mindmap/presentation/mindmap_canvas_test.dart`: expanded geometry, connections, drag, resize, minimap, zoom, performance, and overflow tests.
- `test/features/calendar/day_page_test.dart`: single-expanded selection, flush transitions, route highlight, undo, and destructive-action tests.
- `test/core/router/app_router_test.dart`: legacy URL redirect and browser navigation tests; create file if absent.
- `test/features/mindmap/presentation/node_detail_page_test.dart`: migrate useful editor assertions, then delete file.
- `test/features/mindmap/presentation/habit_heatmap_test.dart`: move standalone-page assertions to inline workspace harness.
- `test/features/sync/application/portable_backup_codec_test.dart`: prove expansion/draft state is absent from backup.
- `test/features/sync/application/sync_controller_test.dart`: prove committed inline edits sync through unchanged node schema.

## Type Consistency

Current `NodeType` has no separate `placeholder`, `reminder`, or `location` enum values. Implement policy without adding schema types:

- `NodeType.empty` uses Placeholder/Small behavior.
- `NodeType.event` is current reminder-capable calendar type and uses Standard behavior.
- Location data remains part of `NodeType.itinerary`; Itinerary stays Wide.
- Explicitly listed design types use required family sizes.
- Remaining current types (`link`, `routine`, `mood`, `timer`, `quote`, `audio`, `checklist`, `canvas`, `weather`, `fit`) use existing `NodePresentationSpec` defaults clamped to at least 360 × 280 while expanded.

---

### Task 1: Inline Workspace State and Size Policy

**Files:**
- Create: `lib/features/mindmap/domain/inline_node_workspace_policy.dart`
- Create: `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`
- Modify: `lib/features/mindmap/domain/node_ui_state_codec.dart`
- Test: `test/features/mindmap/domain/node_ui_state_codec_test.dart`

- [ ] **Step 1: Write exhaustive failing size-policy tests**

Add parameterized tests covering every `NodeType.values` entry and required families:

```dart
test('expanded size policy covers every NodeType', () {
  for (final type in NodeType.values) {
    final size = InlineNodeWorkspacePolicy.expandedSizeFor(type);
    expect(size.width, greaterThanOrEqualTo(280));
    expect(size.height, greaterThanOrEqualTo(180));
  }
});

test('design families resolve exact expanded sizes', () {
  expect(
    InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.empty),
    const Size(280, 180),
  );
  expect(
    InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.task),
    const Size(360, 280),
  );
  expect(
    InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.goal),
    const Size(440, 360),
  );
  expect(
    InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.kanban),
    const Size(560, 380),
  );
});
```

- [ ] **Step 2: Run policy test and verify red state**

Run: `flutter test test/features/mindmap/domain/inline_node_workspace_policy_test.dart`

Expected: FAIL because `InlineNodeWorkspacePolicy` does not exist.

- [ ] **Step 3: Implement exhaustive pure-Dart policy**

Create:

```dart
abstract final class InlineNodeWorkspacePolicy {
  static const small = Size(280, 180);
  static const standard = Size(360, 280);
  static const large = Size(440, 360);
  static const wide = Size(560, 380);

  static Size expandedSizeFor(NodeType type) => switch (type) {
    NodeType.empty ||
    NodeType.bookmark ||
    NodeType.resource ||
    NodeType.question ||
    NodeType.idea => small,
    NodeType.task ||
    NodeType.note ||
    NodeType.journal ||
    NodeType.event ||
    NodeType.decision => standard,
    NodeType.plan ||
    NodeType.goal ||
    NodeType.habit ||
    NodeType.metric ||
    NodeType.expense ||
    NodeType.contact => large,
    NodeType.kanban ||
    NodeType.itinerary ||
    NodeType.image ||
    NodeType.video => wide,
    _ => _clampedExistingDefault(type),
  };
}
```

Implement `_clampedExistingDefault` using `NodePresentationSpec.forType(type).resolve()` and `max(width, 360)`, `max(height, 280)`.

- [ ] **Step 4: Define draft-owned patch contract**

Add immutable `InlineNodeDraftPatch` with:

```dart
final class InlineNodeDraftPatch {
  const InlineNodeDraftPatch({
    this.title,
    this.body,
    this.priority,
    this.tags,
    this.dataFields = const {},
  });

  final String? title;
  final String? body;
  final NodePriority? priority;
  final List<String>? tags;
  final Map<String, Object?> dataFields;

  MindmapNode mergeInto(MindmapNode latest, DateTime now) {
    return latest.copyWith(
      title: title ?? latest.title,
      body: body ?? latest.body,
      priority: priority ?? latest.priority,
      tags: tags ?? latest.tags,
      data: <String, Object?>{...latest.data, ...dataFields},
      updatedAt: now,
    );
  }
}
```

`mergeInto` must copy latest node, replace only non-null scalar fields, merge `dataFields` over `latest.data`, preserve attachment IDs and unrelated keys, and set `updatedAt: now`.

- [ ] **Step 5: Test persistence boundary**

Add tests proving `NodeUiStateCodec.write` stores only explicit preset/custom size, collapsed sections, and editor version; it must not store `expandedNodeId`, draft, dirty, save status, scroll, or debounce keys.

Run: `flutter test test/features/mindmap/domain/inline_node_workspace_policy_test.dart test/features/mindmap/domain/node_ui_state_codec_test.dart`

Expected: PASS; every `NodeType` has one deterministic expanded size and no ephemeral state enters node data.

---

### Task 2: Extract Reusable Workspace Editor

**Files:**
- Create: `lib/features/mindmap/presentation/inline_node_workspace.dart`
- Create: `test/features/mindmap/presentation/inline_node_workspace_test.dart`
- Modify: `lib/features/mindmap/presentation/node_editor_panel.dart`
- Modify: `lib/features/mindmap/presentation/node_type_inline_editor.dart`
- Test: `test/features/mindmap/presentation/node_editor_panel_test.dart`

- [ ] **Step 1: Write failing workspace chrome test**

Build `InlineNodeWorkspace` with a Note node and assert:

```dart
expect(find.byKey(const ValueKey('inline-workspace-header-note-1')), findsOneWidget);
expect(find.byKey(const ValueKey('inline-workspace-scroll-note-1')), findsOneWidget);
expect(find.byKey(const ValueKey('inline-workspace-footer-note-1')), findsOneWidget);
expect(find.text('Note'), findsWidgets);
expect(tester.takeException(), isNull);
```

Also assert semantics include title, type, `expanded`, and current save state.

- [ ] **Step 2: Run new test and verify red state**

Run: `flutter test test/features/mindmap/presentation/inline_node_workspace_test.dart`

Expected: FAIL because widget does not exist.

- [ ] **Step 3: Extract editor surface from `NodeEditorPanel`**

Create `InlineNodeWorkspace` parameters:

```dart
const InlineNodeWorkspace({
  required MindmapNode node,
  required NodeEditContext editContext,
  required InlineNodeSaveStatus saveStatus,
  required VoidCallback onCollapse,
  required VoidCallback onRetrySave,
  required ValueChanged<InlineNodeDraftPatch> onDraftChanged,
  super.key,
});
```

Structure widget as fixed `Column`: header, `Expanded(SingleChildScrollView(...buildNodeTypeInlineEditor(editContext)))`, footer. Keep connection ports outside this widget in canvas node shell.

- [ ] **Step 4: Make existing editor dispatch complete and surface-neutral**

Update `buildNodeTypeInlineEditor(NodeEditContext context)` to reach all existing editor chains without route or dialog assumptions. Move shared templates/action builders from private `NodeEditorPanel` methods into reusable top-level/private-library helpers only where both panel and workspace need them.

Do not copy type editor implementations into new file.

- [ ] **Step 5: Preserve existing panel behavior during migration**

Make `NodeEditorPanel` compose extracted workspace/editor body while retaining current sheet/dialog wrapper until Task 6 removes its entry points.

Run:

```bash
flutter test test/features/mindmap/presentation/inline_node_workspace_test.dart
flutter test test/features/mindmap/presentation/node_editor_panel_test.dart
flutter test test/features/mindmap/presentation/productivity_node_editors_test.dart
flutter test test/features/mindmap/presentation/knowledge_node_editors_test.dart
flutter test test/features/mindmap/presentation/life_data_node_editors_test.dart
```

Expected: PASS; same editors render in reusable workspace and old panel behavior remains intact temporarily.

---

### Task 3: Single Expanded Canvas Node and Adaptive Geometry

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`
- Test: `test/features/calendar/day_page_test.dart`

- [ ] **Step 1: Write failing single-expanded tests**

Add widget tests:

```dart
expect(find.byKey(const ValueKey('inline-workspace-node-a')), findsOneWidget);
await selectNode('node-b');
expect(find.byKey(const ValueKey('inline-workspace-node-a')), findsNothing);
expect(find.byKey(const ValueKey('inline-workspace-node-b')), findsOneWidget);
```

Assert clearing selection removes workspace, while selection remains canvas source of truth.

- [ ] **Step 2: Write failing geometry/scroll/port tests**

For Small, Standard, Large, and Wide nodes, assert expanded rendered size equals policy; body scrolls internally; header/footer remain visible; connection port centers equal expanded card center; minimap uses expanded rectangle.

Run: `flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart --name 'expanded|workspace|port|minimap'`

Expected: FAIL because canvas has no expanded workspace branch.

- [ ] **Step 3: Add expansion inputs to `MindmapCanvas`**

Add fields:

```dart
final String? expandedNodeId;
final Widget Function(MindmapNode node)? expandedNodeBuilder;
final Future<bool> Function(String? nextNodeId)? onExpandedSelectionChanging;
```

Resolve `_nodeSizeFor(node)` to `InlineNodeWorkspacePolicy.expandedSizeFor(node.type)` when `node.id == expandedNodeId`; otherwise keep existing `NodeUiStateCodec` geometry.

- [ ] **Step 4: Render workspace inside existing node shell**

In `_MindmapNodeCard`, branch before compact/full card body:

```dart
if (widget.node.id == expandedNodeId) {
  return NodeShell(
    size: expandedSize,
    preset: widget.preset,
    child: expandedNodeBuilder(widget.node),
  );
}
```

Keep ports positioned from effective size center. Expanded node remains same node ID, canvas position, relation identity, and selection identity.

- [ ] **Step 5: Isolate editor gestures from canvas movement**

Extend `_NodePointerSurface.shouldIgnoreDrag` to treat workspace body, form controls, scrollbars, media controls, selection, and footer buttons as non-drag regions. Permit drag only from header drag-safe region and existing external shell handles.

- [ ] **Step 6: Connect DayPage selection to expansion**

Use `_selectedNodeId` as `expandedNodeId`; remove any second expansion state. Pass `expandedNodeBuilder` that reads the node’s draft/edit context and returns `InlineNodeWorkspace`.

Run:

```bash
flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart --name 'expanded|workspace|port|minimap|drag'
flutter test test/features/calendar/day_page_test.dart --name 'expanded|selection|collapse'
```

Expected: PASS; exactly one selected node expands, unselected nodes collapse, and expanded geometry drives ports/minimap without editor drag leakage.

---

### Task 4: Autosave Drafts, Latest Merge, and Flush Transitions

**Files:**
- Create: `lib/features/mindmap/application/inline_node_workspace_controller.dart`
- Create: `test/features/mindmap/application/inline_node_workspace_controller_test.dart`
- Modify: `lib/features/mindmap/application/mindmap_mutation_controller.dart`
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/mindmap/application/mindmap_mutation_controller_test.dart`
- Test: `test/features/calendar/day_page_test.dart`

- [ ] **Step 1: Write failing controller state tests**

Cover `expandedNodeId`, per-node draft retention, dirty/saving/saved/error status, and only-one-expanded invariant.

```dart
await controller.requestExpansion('a');
controller.updateDraft('a', patchA);
await controller.requestExpansion('b');
expect(controller.state.expandedNodeId, 'b');
expect(repository.savedIds, ['a']);
```

- [ ] **Step 2: Write failing debounce and stale completion tests**

Inject clock/timer seam and repository gates. Assert sequential edits produce one save, and completion for generation 1 cannot mark generation 2 clean.

Run: `flutter test test/features/mindmap/application/inline_node_workspace_controller_test.dart`

Expected: FAIL because controller does not exist.

- [ ] **Step 3: Implement controller state and providers**

Define:

```dart
final inlineNodeWorkspaceControllerProvider =
    NotifierProvider<InlineNodeWorkspaceController, InlineNodeWorkspaceState>(
      InlineNodeWorkspaceController.new,
    );
```

State contains `expandedNodeId`, immutable draft/status map, transition generation, and flush flag. Controller methods:

```dart
Future<bool> requestExpansion(String? nodeId);
void updateDraft(String nodeId, InlineNodeDraftPatch patch);
Future<bool> flushNode(String nodeId);
Future<bool> flushExpanded();
void discardMissingNode(String nodeId);
```

- [ ] **Step 4: Implement latest-node merge save**

`flushNode` must:

1. read latest node from `mindmapRepositoryProvider`;
2. stop safely if missing;
3. validate current draft;
4. call `InlineNodeDraftPatch.mergeInto(latest, now)`;
5. save through `mindmapMutationControllerProvider`;
6. generation-check completion;
7. keep draft dirty on error.

- [ ] **Step 5: Serialize switch and clear transitions**

`requestExpansion(next)` flushes current first. Failed validation/save returns `false` and keeps current expanded. Rapid calls use generation; latest requested selection wins after successful flush.

- [ ] **Step 6: Wire mandatory flush boundaries in DayPage**

Before selection switch, clear, route away, delete, archive, duplicate, move-day, backup/export, and supported lifecycle pause, call `flushExpanded()`. Continue action only when it returns `true`.

Run:

```bash
flutter test test/features/mindmap/application/inline_node_workspace_controller_test.dart
flutter test test/features/calendar/day_page_test.dart --name 'autosave|flush|selection|delete|archive|backup'
flutter test test/features/mindmap/application/mindmap_mutation_controller_test.dart
```

Expected: PASS; no valid edit is lost, invalid/error drafts block transitions, unrelated concurrent payload fields survive.

---

### Task 5: Migrate Every NodeType and Type-Specific Actions

**Files:**
- Modify: `lib/features/mindmap/presentation/inline_node_workspace.dart`
- Modify: `lib/features/mindmap/presentation/node_type_inline_editor.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/life_data_node_editors.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/media_travel_node_editors.dart`
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/mindmap/presentation/inline_node_workspace_test.dart`
- Test: `test/features/mindmap/presentation/productivity_node_editors_test.dart`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`
- Test: `test/features/mindmap/presentation/life_data_node_editors_test.dart`
- Test: `test/features/mindmap/presentation/video_node_editor_test.dart`

- [ ] **Step 1: Add exhaustive all-type render test**

For every `NodeType.values`, create valid minimum payload fixture, render expanded workspace at policy size, and assert no exception/overflow and editor dispatcher returns non-empty content.

- [ ] **Step 2: Add payload round-trip action tests**

Cover task checklist, kanban advance, plan step, goal milestone, habit completion, media replace/export/open, itinerary agenda, metric/expense/contact fields, journal/note text, and fallback editors. Verify unrelated payload keys and attachment IDs survive draft merge.

- [ ] **Step 3: Run tests red**

Run: `flutter test test/features/mindmap/presentation/inline_node_workspace_test.dart --name 'NodeType|payload|action|overflow'`

Expected: FAIL listing editor actions still coupled to panel/detail context.

- [ ] **Step 4: Move action callbacks into `NodeEditContext`**

Expand `NodeEditContext` with explicit optional callbacks for all current actions. `InlineNodeWorkspace` receives callbacks from DayPage/controller; editor modules call context callbacks and never navigate to `NodeDetailPage`.

- [ ] **Step 5: Apply type family sizes and dense editor constraints**

Use policy size for each type. Wrap Kanban, Itinerary, Image, Video, and dense Large types in bounded internal scroll/layout. Do not increase canvas card beyond policy solely for content.

Run:

```bash
flutter test test/features/mindmap/presentation/inline_node_workspace_test.dart
flutter test test/features/mindmap/presentation/productivity_node_editors_test.dart
flutter test test/features/mindmap/presentation/knowledge_node_editors_test.dart
flutter test test/features/mindmap/presentation/life_data_node_editors_test.dart
flutter test test/features/mindmap/presentation/video_node_editor_test.dart
```

Expected: PASS for every `NodeType`, payload round-trip, minimum size, media metadata, and action callback.

---

### Task 6: Remove Page Entry Actions and Redirect Legacy Route

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/calendar/day_page.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Create or modify: `test/core/router/app_router_test.dart`
- Modify: `test/features/calendar/day_page_test.dart`
- Modify: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Write failing legacy redirect tests**

Navigate to `/calendar/2026-07-15/node/node-1` and assert final location is `/calendar/2026-07-15?highlight=node-1`; DayPage highlights, centers, selects, and expands node after load.

Add missing-node test expecting day canvas plus contained status, not standalone page.

- [ ] **Step 2: Run route tests red**

Run: `flutter test test/core/router/app_router_test.dart`

Expected: FAIL because route still builds `NodeDetailPage`.

- [ ] **Step 3: Replace nested route builder with redirect**

Implement:

```dart
redirect: (context, state) {
  final date = state.pathParameters['date']!;
  final nodeId = Uri.encodeQueryComponent(state.pathParameters['nodeId']!);
  return '/calendar/$date?highlight=$nodeId';
},
```

Keep route name for compatibility if existing callers use it.

- [ ] **Step 4: Remove standalone open buttons and sheet entry points**

Replace node “open full page”, `_showNodeEditorSheet`, and route pushes with selection + center + expansion. Keep collapse/clear controls inside inline workspace.

- [ ] **Step 5: Test browser/deep-link behavior**

Run:

```bash
flutter test test/core/router/app_router_test.dart
flutter test test/features/calendar/day_page_test.dart --name 'highlight|legacy|expanded'
flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart --name 'open|selection|focus'
```

Expected: PASS; no UI action opens detail page, old URL remains functional, back/forward location is stable.

---

### Task 7: Preserve Canvas Systems, Accessibility, Undo, and Performance

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Modify: `lib/features/mindmap/presentation/inline_node_workspace.dart`
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`
- Test: `test/features/calendar/day_page_test.dart`
- Test: `test/features/mindmap/presentation/node_shell_test.dart`

- [ ] **Step 1: Add expanded connection and geometry tests**

Assert source/target ports center on expanded height, connection preview/completion works, group bounds enclose expanded card, minimap and fit use expanded dimensions, and resize returns to user-selected collapsed size after collapse.

- [ ] **Step 2: Add input isolation tests**

Assert header drag moves node; typing, selecting text, wheel scrolling, slider/media interaction, and footer buttons do not move node. Escape flushes and collapses only on valid save.

- [ ] **Step 3: Add undo grouping tests**

Three edits inside one debounce window create one save and one undo entry. Expansion/collapse creates no undo entry. Undo restores committed payload without changing expansion identity unexpectedly.

- [ ] **Step 4: Add accessibility tests**

Assert semantics include type/title/expanded/save state; collapse/retry/ports are keyboard reachable; focus enters editor only after expansion and restores after collapse.

- [ ] **Step 5: Add rebuild/performance tests**

Use existing `onNodeCardBuilt` harness. Typing in expanded node must not rebuild unrelated cards. Stale save/attachment completions must not mutate current workspace.

- [ ] **Step 6: Run canvas regression files**

Run:

```bash
flutter test test/features/mindmap/presentation/node_shell_test.dart
flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart
flutter test test/features/calendar/day_page_test.dart
```

Expected: PASS; drag/connect/resize/zoom/minimap/group/undo/accessibility behavior remains intact and unrelated card build counts remain stable.

---

### Task 8: Remove Dead NodeDetailPage Code and Tests

**Files:**
- Delete: `lib/features/mindmap/presentation/node_detail_page.dart`
- Delete: `test/features/mindmap/presentation/node_detail_page_test.dart`
- Modify: `test/features/mindmap/presentation/habit_heatmap_test.dart`
- Modify: imports in `lib/core/router/app_router.dart` and any files returned by search.
- Test: `test/features/mindmap/presentation/inline_node_workspace_test.dart`
- Test: `test/core/router/app_router_test.dart`

- [ ] **Step 1: Inventory remaining detail-page dependencies**

Run: `rg -n 'NodeDetailPage|node_detail_page|node_detail' lib test`

Expected before deletion: only route compatibility references, old page file/tests, and assertions scheduled for migration.

- [ ] **Step 2: Move unique useful tests before deletion**

Move Habit heatmap and any unique type editor assertions into `inline_node_workspace_test.dart` or existing type editor tests. Run migrated tests and require PASS before deleting source.

- [ ] **Step 3: Delete standalone page and obsolete tests**

Delete page and page-only tests. Remove import from router. Keep legacy route name/path redirect from Task 6.

- [ ] **Step 4: Scan for dead references**

Run: `rg -n 'NodeDetailPage|node_detail_page' lib test`

Expected: no matches.

Run:

```bash
flutter test test/features/mindmap/presentation/inline_node_workspace_test.dart
flutter test test/features/mindmap/presentation/habit_heatmap_test.dart
flutter test test/core/router/app_router_test.dart
```

Expected: PASS; all former page behavior is covered by inline editor or redirect tests.

---

### Task 9: Full Regression and Release Preflight

**Files:**
- Modify only failing feature files proven related to inline workspace.
- Test: `test/features/sync/application/portable_backup_codec_test.dart`
- Test: `test/features/sync/application/sync_controller_test.dart`
- Test: all Flutter tests.

- [ ] **Step 1: Add backup non-persistence regression**

Create expanded workspace/draft in provider state, encode backup, and assert serialized node contains committed payload and allowed `NodeUiStateCodec` fields only; no `expandedNodeId`, draft, dirty, save generation, scroll, or debounce data.

- [ ] **Step 2: Add sync committed-edit regression**

Flush inline draft, run sync planning/controller, and assert unchanged `MindmapNode` schema carries committed edit while ephemeral workspace state is absent.

- [ ] **Step 3: Run focused integration suite**

Run:

```bash
flutter test test/features/mindmap/domain/inline_node_workspace_policy_test.dart
flutter test test/features/mindmap/application/inline_node_workspace_controller_test.dart
flutter test test/features/mindmap/presentation/inline_node_workspace_test.dart
flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart
flutter test test/features/calendar/day_page_test.dart
flutter test test/core/router/app_router_test.dart
flutter test test/features/sync/application/portable_backup_codec_test.dart
flutter test test/features/sync/application/sync_controller_test.dart
```

Expected: all focused tests pass with no overflow, uncaught async error, stale-save mutation, or route regression.

- [ ] **Step 4: Run project preflight**

Run:

```bash
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release --dart-define=VAR_DEMO_SEED=false
```

Expected:

- dependencies resolve;
- formatter reports zero changed files;
- analyzer reports `No issues found`;
- full test suite passes;
- Web release build succeeds.

- [ ] **Step 5: Run platform builds required by project release checklist**

Run:

```bash
flutter build apk
flutter build windows
```

Expected: Android APK and Windows release builds succeed without missing editor/plugin symbols.

- [ ] **Step 6: Run final consistency scans**

Run:

```bash
rg -n 'TO[D]O|TB[D]|FIXM[E]' docs/superpowers/plans/2026-07-15-inline-node-workspace.md lib/features/mindmap lib/features/calendar/day_page.dart
rg -n 'NodeDetailPage|node_detail_page' lib test
rg -n 'expandedNodeId|draft|debounce|saveGeneration' lib/features/mindmap/domain lib/features/sync
```

Expected:

- no plan placeholders;
- no standalone detail-page references;
- ephemeral workspace identifiers exist only in application/presentation code and tests, never persisted domain serialization, backup, or sync payload code.

## Completion Criteria

- Every current `NodeType` renders and edits inside one expanded canvas workspace.
- Selection is sole expansion source; only one node expands and unselected nodes collapse.
- Debounced autosave merges draft-owned fields into latest repository node.
- Mandatory flush blocks unsafe transitions on validation/save failure.
- Legacy detail URLs redirect, highlight, center, select, and expand target node.
- Connections, drag, resize, minimap, zoom, grouping, undo, accessibility, backup, and sync regressions pass.
- `NodeDetailPage` implementation and standalone tests are removed while compatibility route remains.
- Full preflight and platform builds pass.

# Material 3 Adaptive Canvas Final Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish mindmap and graph canvas chrome, then close final accessibility, responsive, RTL, text-scaling, reduced-motion, and raw-style gaps without changing canvas behavior or domain logic.

**Architecture:** Keep canvas engines opaque and unchanged. Restrict production edits to Flutter chrome around canvases: tool popovers, search/filter overlays, selection bars, minimap container/semantics, node editor shell, graph page controls/panels, and graph physics canvas chrome. Reuse `ThemeData`, `AppSemanticColors`, and `AppDesignTokens`; verify behavior with focused widget tests before full repository gates.

**Tech Stack:** Flutter, Dart 3.11.4, Material 3, Riverpod, `flutter_test`.

## Global Constraints

- Preserve all seven Astryx color/font variants and light/dark modes.
- Add no shadcn web dependency, CSS token tree, duplicate theme runtime, or `Shadcn*` widget family.
- Material components provide behavior, semantics, focus, and platform adaptation.
- Interactive targets remain at least 44 logical pixels.
- System text scaling remains enabled; truncation requires full content through tooltip, detail view, expansion, or accessible label.
- Layout responds to available space: compact at 320, medium at 768, expanded at 1024 and 1440 logical pixels.
- Status and errors never rely on color alone; focus remains visible.
- Reduced motion uses `AppDesignTokens.effectiveDuration(context, duration)`.
- Do not modify painters, transforms, hit-testing, physics, gestures, connectors, canvas coordinates, selection geometry, domain logic, persistence, routes, synchronization, or backup behavior.
- Specifically do not edit painter classes or paint methods in `lib/features/mindmap/presentation/mindmap_canvas.dart`, `lib/features/mindmap/presentation/mindmap_connection_painter.dart`, `lib/features/mindmap/presentation/widgets/canvas_minimap_widget.dart`, `lib/features/graph/graph_page.dart`, or `lib/features/graph/presentation/graph_physics_canvas.dart`.
- Do not bulk replace raw styles. Classify each match as structural chrome, data accent, persisted canvas identity, or painter geometry before editing.
- Keep existing uncommitted work out of every commit. Before each commit run `git diff -- <task paths>` and stage only listed files.

## Planned File Map

- Modify `lib/features/mindmap/presentation/canvas_tool_popover.dart`: tokenized popover surface, adaptive width, semantic color choices, 44-pixel targets.
- Modify `lib/features/mindmap/presentation/widgets/multi_select_action_bar.dart`: responsive selection actions with Material surface and semantics.
- Modify `lib/features/mindmap/presentation/widgets/canvas_minimap_widget.dart`: chrome and semantics only; `_MinimapPainter` stays byte-for-byte unchanged.
- Modify `lib/features/mindmap/presentation/mindmap_canvas.dart`: overlay/search/toolbar chrome only; canvas listeners, `InteractiveViewer`, painters, transforms, and interaction callbacks stay unchanged.
- Modify `lib/features/mindmap/presentation/node_editor_panel.dart`: adaptive editor shell, focus order, scalable tabs/actions; save/delete/editor logic stays unchanged.
- Modify `lib/features/graph/graph_page.dart`: adaptive app bar, filter/dashboard/list/detail chrome, semantics, reduced-motion durations; `VisualGraphView` transform/gesture/painter code stays unchanged.
- Modify `lib/features/graph/presentation/graph_physics_canvas.dart`: optional semantic wrapper and surrounding controls only; simulation, ticker, `InteractiveViewer`, and `_GraphPhysicsPainter` stay unchanged.
- Modify focused tests under `test/features/mindmap/presentation/` and `test/features/graph/`.
- Create `test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart`: cross-cutting 320/768/1024/1440, text scale, RTL, and reduced-motion coverage.

---

### Task 1: Lock Scope with Raw-Style Audit and Baseline Tests

**Files:**
- Inspect: `lib/features/mindmap/presentation/**/*.dart`
- Inspect: `lib/features/graph/**/*.dart`
- Inspect: `test/features/mindmap/presentation/**/*.dart`
- Inspect: `test/features/graph/**/*.dart`
- No production file changes

**Interfaces:**
- Consumes: semantic roles from `Theme.of(context).colorScheme`, `AppSemanticColors.of(context)`, geometry/motion from `AppDesignTokens.of(context)`.
- Produces: classified audit output used to select only chrome edits in Tasks 2-7.

- [ ] **Step 1: Capture clean scope and focused baseline**

Run:

```bash
git status --short
flutter test test/features/mindmap/presentation/canvas_tool_popover_test.dart test/features/mindmap/presentation/canvas_milanote_features_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart test/features/mindmap/presentation/node_editor_panel_test.dart test/features/graph/graph_page_test.dart
```

Expected: current worktree state recorded; focused suite exits `0`. If baseline fails, record exact failing test and stop rather than folding unrelated fixes into this plan.

- [ ] **Step 2: Generate exact raw-style inventory**

Run:

```bash
rg -n "Colors\.|Color\(0x|fontSize:|BorderRadius\.circular\(|Radius\.circular\(|BoxShadow\(|Duration\(milliseconds:" lib/features/mindmap/presentation lib/features/graph --glob "*.dart"
```

Expected: inventory includes known chrome candidates such as `canvas_tool_popover.dart:18-24`, `multi_select_action_bar.dart:25-39`, `mindmap_canvas.dart:11262-11293`, `mindmap_canvas.dart:11432-11527`, `mindmap_canvas.dart:11847-11943`, and `graph_page.dart:907-915`; it also includes excluded data/painter values.

- [ ] **Step 3: Classify every candidate before editing**

Use these exact rules:

```text
EDIT: surface/background/border/radius/elevation/spacing/type role owned by widget chrome.
KEEP: node-type colors, persisted canvas color payloads, annotation stroke colors, media colors, chart marks, connection identity colors.
KEEP: values inside CustomPainter.paint, canvas geometry, hit regions, transforms, InteractiveViewer bounds/scales, gesture thresholds, physics constants.
EDIT DURATION ONLY: chrome reveal/collapse transition; route through AppDesignTokens.effectiveDuration.
KEEP DURATION: double-click, pointer throttle, debounce, autosave, physics tick, or domain timing.
```

Expected: no ambiguous match proceeds to implementation. When unsure, keep value unchanged.

- [ ] **Step 4: Verify protected code has test coverage before chrome edits**

Run:

```bash
flutter test test/features/mindmap/presentation/canvas_board_integration_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart test/features/graph/domain/graph_physics_simulation_test.dart test/features/graph/graph_page_test.dart
```

Expected: PASS. This test set remains regression guard after each relevant task.

No commit: audit is read-only.

### Task 2: Polish Canvas Tool Popover and Color Choices

**Files:**
- Modify: `lib/features/mindmap/presentation/canvas_tool_popover.dart:3-109`
- Test: `test/features/mindmap/presentation/canvas_tool_popover_test.dart`

**Interfaces:**
- Consumes: `AppDesignTokens.of(context)`, `Theme.of(context).colorScheme`, existing `title`, `onClose`, `child`, `selected`, and `onSelected` parameters.
- Produces: same public constructors; `ValueKey('canvas-tool-popover')`, `ValueKey('canvas-tool-popover-close')`, and `ValueKey('canvas-color-$hex')` remain stable.

- [ ] **Step 1: Write failing compact-width, target-size, and color-semantics tests**

Append tests that pump `CanvasToolPopover` at width `320`, text scale `2.0`, and assert no exception plus bounded width; pump `CanvasColorChoices` and assert selected semantics and minimum target:

```dart
testWidgets('tool popover fits compact width at 200 percent text scale', (
  tester,
) async {
  await tester.binding.setSurfaceSize(const Size(320, 568));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: CanvasToolPopover(
              title: 'Connector appearance settings',
              onClose: () {},
              child: const Text('Choose connector appearance'),
            ),
          ),
        ),
      ),
    ),
  );
  expect(tester.takeException(), isNull);
  expect(
    tester.getSize(find.byKey(const ValueKey('canvas-tool-popover'))).width,
    lessThanOrEqualTo(320),
  );
  expect(
    tester.getSize(find.byKey(const ValueKey('canvas-tool-popover-close'))),
    const Size(44, 44),
  );
});

testWidgets('canvas color choices expose selected labels and 44 pixel targets', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CanvasColorChoices(selected: '#4F7CFF', onSelected: (_) {}),
      ),
    ),
  );
  final choice = find.byKey(const ValueKey('canvas-color-#4F7CFF'));
  expect(tester.getSize(choice), const Size(44, 44));
  expect(
    tester.getSemantics(find.bySemanticsLabel('Color #4F7CFF, selected')),
    matchesSemantics(
      label: 'Color #4F7CFF, selected',
      isButton: true,
      isSelected: true,
      hasSelectedState: true,
      hasTapAction: true,
    ),
  );
});
```

- [ ] **Step 2: Run tests and confirm red state**

Run:

```bash
flutter test test/features/mindmap/presentation/canvas_tool_popover_test.dart
```

Expected: FAIL because current close and color targets are below `44`, current semantic label lacks selected text, or compact text scaling overflows.

- [ ] **Step 3: Apply minimal tokenized chrome**

Import `../../../core/theme/app_design_tokens.dart`. Replace fixed elevation/radius with `tokens.shadowMedium`, `tokens.radiusContainer`, border-first `ShapeDecoration`, and width derived from `LayoutBuilder`:

```dart
final tokens = AppDesignTokens.of(context);
final colorScheme = Theme.of(context).colorScheme;
return LayoutBuilder(
  builder: (context, constraints) => ConstrainedBox(
    constraints: BoxConstraints(
      minWidth: math.min(240, constraints.maxWidth),
      maxWidth: math.min(320, constraints.maxWidth),
    ),
    child: DecoratedBox(
      decoration: ShapeDecoration(
        color: colorScheme.surfaceContainerHigh,
        shadows: tokens.shadowMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusContainer),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [header, const SizedBox(height: 8), child],
        ),
      ),
    ),
  ),
);
```

Add `import 'dart:math' as math;`. Use `IconButton` with `constraints: BoxConstraints.tightFor(width: tokens.minimumTarget, height: tokens.minimumTarget)` and visible `tooltip: 'Close tool settings'`; remove redundant outer `Semantics` if native `IconButton` semantics now match. Wrap each swatch in `SizedBox.square(dimension: tokens.minimumTarget)`, center a `30`-pixel visual circle, use `InkResponse(customBorder: const CircleBorder())`, and label selected choice exactly `Color ${entry.key}, selected`; unselected label remains `Color ${entry.key}`. Keep raw map colors because they are persisted canvas identities, not structural chrome.

- [ ] **Step 4: Verify green state and format**

Run:

```bash
dart format lib/features/mindmap/presentation/canvas_tool_popover.dart test/features/mindmap/presentation/canvas_tool_popover_test.dart
flutter test test/features/mindmap/presentation/canvas_tool_popover_test.dart
```

Expected: PASS with no overflow or semantics exception.

- [ ] **Step 5: Commit focused change**

```bash
git diff -- lib/features/mindmap/presentation/canvas_tool_popover.dart test/features/mindmap/presentation/canvas_tool_popover_test.dart
git add lib/features/mindmap/presentation/canvas_tool_popover.dart test/features/mindmap/presentation/canvas_tool_popover_test.dart
git commit -m "fix(mindmap): polish canvas tool popover accessibility"
```

### Task 3: Make Selection Bar and Minimap Chrome Adaptive

**Files:**
- Modify: `lib/features/mindmap/presentation/widgets/multi_select_action_bar.dart:3-75`
- Modify: `lib/features/mindmap/presentation/widgets/canvas_minimap_widget.dart:15-53`
- Test: `test/features/mindmap/presentation/canvas_milanote_features_test.dart`
- Test: `test/features/mindmap/presentation/canvas_scale_navigation_test.dart`

**Interfaces:**
- Consumes: existing callback API and `MinimapNodeDot`/`viewportRect` values.
- Produces: same public API; add `ValueKey('multi-select-action-bar')`; preserve `ValueKey('mindmap-minimap-semantics')` supplied by caller and do not alter `_MinimapPainter`.

- [ ] **Step 1: Write failing selection-bar compact/RTL/semantics tests**

Add test using `Size(320, 568)`, `TextDirection.rtl`, `TextScaler.linear(2)`, all callbacks non-null. Assert no exception, width `<= 320`, `find.byTooltip('Delete selected')`, and a live-region label `4 items selected`. Assert each enabled `IconButton` size has width and height `>= 44`.

```dart
expect(find.bySemanticsLabel('4 items selected'), findsOneWidget);
for (final element in find.descendant(
  of: find.byKey(const ValueKey('multi-select-action-bar')),
  matching: find.byType(IconButton),
).evaluate()) {
  final size = tester.getSize(find.byWidget(element.widget));
  expect(size.width, greaterThanOrEqualTo(44));
  expect(size.height, greaterThanOrEqualTo(44));
}
```

- [ ] **Step 2: Write failing minimap structural-semantics test**

In `canvas_scale_navigation_test.dart`, retain existing painter-size assertions and add an assertion that interactive minimap semantics expose button/tap action and descriptive label containing object count and navigation instruction. Do not assert paint pixels.

```dart
final semantics = tester.getSemantics(
  find.byKey(const ValueKey('mindmap-minimap-semantics')),
);
expect(semantics.label, contains('canvas objects'));
expect(semantics.label, contains('Tap to move viewport'));
expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
```

- [ ] **Step 3: Run tests and confirm red state**

Run:

```bash
flutter test test/features/mindmap/presentation/canvas_milanote_features_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart
```

Expected: FAIL on compact selection layout and incomplete minimap semantics.

- [ ] **Step 4: Implement adaptive selection chrome**

Use `LayoutBuilder`; at `maxWidth < 480`, render count as flexible text plus `MenuAnchor` containing `MenuItemButton`s for Group into frame, Change color, Delete selected, and Clear selection. At wider widths retain icon buttons. Use sentence-case tooltips, `AppDesignTokens.minimumTarget`, `tokens.radiusContainer`, `tokens.shadowMedium`, `colorScheme.surfaceContainerHigh`, and one-pixel `outlineVariant` border. Wrap count in `Semantics(liveRegion: true, label: '$selectedCount items selected', excludeSemantics: true)`.

- [ ] **Step 5: Implement minimap chrome without painter changes**

Replace container radius/border with `AppDesignTokens.radiusElement` and semantic colors. Wrap existing `GestureDetector` in `Semantics(button: onTapMinimap != null, label: '${nodeDots.length} canvas objects. Tap to move viewport')`. Leave lines `55-98`, including `_MinimapPainter.paint` and `shouldRepaint`, unchanged.

- [ ] **Step 6: Verify tests and protected diff**

Run:

```bash
dart format lib/features/mindmap/presentation/widgets/multi_select_action_bar.dart lib/features/mindmap/presentation/widgets/canvas_minimap_widget.dart test/features/mindmap/presentation/canvas_milanote_features_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart
flutter test test/features/mindmap/presentation/canvas_milanote_features_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart
git diff --word-diff=porcelain -- lib/features/mindmap/presentation/widgets/canvas_minimap_widget.dart
```

Expected: tests PASS; diff contains no changes inside `_MinimapPainter`.

- [ ] **Step 7: Commit focused change**

```bash
git add lib/features/mindmap/presentation/widgets/multi_select_action_bar.dart lib/features/mindmap/presentation/widgets/canvas_minimap_widget.dart test/features/mindmap/presentation/canvas_milanote_features_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart
git commit -m "fix(mindmap): adapt canvas selection and minimap chrome"
```

### Task 4: Polish Mindmap Search, Empty, and Overlay Chrome

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart:11138-11945`
- Create: `test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

**Interfaces:**
- Consumes: current private `_OverlayPanel`, `_CanvasSearchOverlay`, `_CanvasFilterPill`, `_CanvasSearchEmptyState`, `_CanvasEmptyHint`, and existing callbacks/keys.
- Produces: same callbacks and keys; only chrome layout and semantics change. `InteractiveViewer`, listeners, transforms, painter construction, gesture thresholds, and canvas models remain untouched.

- [ ] **Step 1: Create reusable test harness in new test file**

Define local helper with exact signature:

```dart
Future<void> pumpCanvas(
  WidgetTester tester, {
  required Size size,
  TextDirection textDirection = TextDirection.ltr,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: textScaler,
          disableAnimations: disableAnimations,
        ),
        child: Directionality(
          textDirection: textDirection,
          child: const Scaffold(body: MindmapCanvas(nodes: <MindmapNode>[])),
        ),
      ),
    ),
  );
  await tester.pump();
}
```

- [ ] **Step 2: Write failing representative-width tests**

Add one parameterized widget test looping over exact sizes:

```dart
for (final width in <double>[320, 768, 1024, 1440]) {
  await pumpCanvas(tester, size: Size(width, 900));
  expect(find.byKey(const ValueKey('mindmap-canvas')), findsOneWidget);
  expect(tester.takeException(), isNull, reason: 'width=$width');
}
```

At width `320`, focus search using `Ctrl+F`, assert overlay width `<= 320`, all search IconButtons have `>= 44` targets, and horizontal filter lists remain scrollable. At `768`, `1024`, and `1440`, assert overlay stays constrained to `<= 380` and does not cover full canvas width.

- [ ] **Step 3: Write failing text-scale and RTL tests**

Pump at `320x900`, `TextScaler.linear(2)`, RTL. Open search with `Ctrl+F`; enter `unmatched`; assert no overflow and clear action remains discoverable by tooltip/semantics. Assert directional placement using `AlignmentDirectional` behavior rather than fixed left/right coordinates:

```dart
expect(find.byTooltip('Clear search'), findsOneWidget);
expect(tester.takeException(), isNull);
expect(
  tester.getRect(find.byKey(const ValueKey('mindmap-search-overlay'))).right,
  lessThanOrEqualTo(320),
);
```

Add `ValueKey('mindmap-search-overlay')` to `_CanvasSearchOverlay` root for this assertion.

- [ ] **Step 4: Run tests and confirm red state**

Run:

```bash
flutter test test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart
```

Expected: FAIL from fixed-height `38/34` controls, left-only placement, raw `TextStyle(fontSize: 13)`, raw radius/shadow, or missing overlay key.

- [ ] **Step 5: Apply minimum chrome-only changes**

Within lines `11138-11945` only:

- Give `_OverlayPanel` border-first surface using `AppDesignTokens.radiusContainer`, `shadowMedium`, and semantic surface/border colors.
- Replace `_ToolbarPill` custom tappable `InkWell` with `ActionChip` or `OutlinedButton` while preserving label, tooltip, and callback.
- In `_CanvasSearchOverlay`, use `LayoutBuilder` constraints rather than global `MediaQuery` width; use `PositionedDirectional(start: leftInset, bottom: 76)`; cap width at `380`, floor only when available width permits, and add `SafeArea(minimum: EdgeInsetsDirectional.only(start: leftInset, end: 12, bottom: 12))`.
- Remove fixed `SizedBox(height: 38)` and fixed filter heights `34`; use `ConstrainedBox(minHeight: tokens.minimumTarget)` so text can grow.
- Replace `TextStyle(fontSize: 13)` with `theme.textTheme.bodyMedium` and tokenized border radius.
- Keep horizontal filter lists; do not wrap every filter into cards.
- Replace raw `Colors.transparent` with `MaterialType.transparency` where possible.
- Replace `_CanvasSearchEmptyState` raw shadow/radius with token values; add `Semantics(liveRegion: true, label: 'No canvas items match $query')` and preserve visible clear action.
- Let `_CanvasEmptyHint` wrap text without `TextOverflow.ellipsis` at high text scale.

Do not edit anything at or below `_PositionedNodeGroup`, any `CustomPainter`, any `GestureDetector`/`Listener` callback, `InteractiveViewer`, transformation controller, coordinate calculation, or hit-test code.

- [ ] **Step 6: Verify focused tests and protected canvas behavior**

Run:

```bash
dart format lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart
flutter test test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart test/features/mindmap/presentation/canvas_board_integration_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart
```

Expected: PASS.

- [ ] **Step 7: Inspect restricted diff and commit**

```bash
git diff --unified=0 -- lib/features/mindmap/presentation/mindmap_canvas.dart
git add lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart
git commit -m "fix(mindmap): polish adaptive canvas overlays"
```

Expected diff: production hunks confined to chrome classes named in this task.

### Task 5: Make Node Editor Shell Responsive and Keyboard-Safe

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editor_panel.dart`
- Test: `test/features/mindmap/presentation/node_editor_panel_test.dart`

**Interfaces:**
- Consumes: existing `NodeEditorPanel` constructor and editor state/callbacks.
- Produces: unchanged constructor and save/delete results; adaptive shell uses existing `_EditorPanelTab` values and field widgets.

- [ ] **Step 1: Write failing width matrix and text-scale tests**

Add helper that pumps same representative node at `320`, `768`, `1024`, and `1440` widths. At every width assert title field, tab controls, save and close actions remain reachable and `tester.takeException()` is null. Repeat `320` at `TextScaler.linear(2)` and RTL. Do not assert internal form data changes.

```dart
for (final width in <double>[320, 768, 1024, 1440]) {
  await pumpEditor(tester, width: width);
  expect(find.byKey(const ValueKey('node-editor-title')), findsOneWidget);
  expect(find.byTooltip('Close editor'), findsOneWidget);
  expect(tester.takeException(), isNull, reason: 'width=$width');
}
```

Use existing keys where present; if title/close keys are absent, add stable keys in production and use exact names above.

- [ ] **Step 2: Write failing focus restoration/order test**

Pump editor with a `FocusNode`-backed button immediately before it. Send Tab through header controls and tabs; assert each visible action receives focus in visual order. Trigger close and assert caller-owned launcher regains focus by requesting it in harness callback. This verifies shell behavior without changing editor logic.

- [ ] **Step 3: Run red tests**

Run:

```bash
flutter test test/features/mindmap/presentation/node_editor_panel_test.dart
```

Expected: FAIL on compact/high-scale overflow, inaccessible header action, or non-directional layout.

- [ ] **Step 4: Implement adaptive shell only**

At `NodeEditorPanel.build`, use `LayoutBuilder` with these behavior thresholds:

```dart
final compact = constraints.maxWidth < 600;
final expanded = constraints.maxWidth >= 1024;
```

- Compact: header actions wrap or move secondary actions into `MenuAnchor`; editor remains single-column and scrollable; use `SafeArea`.
- Medium: single-column content with constrained readable width.
- Expanded: keep current panel composition; do not invent inspector/domain split.
- Use `TabBar(isScrollable: compact)` or existing Material segmented control if already present; do not clip labels.
- Use `EdgeInsetsDirectional`; remove shell-only fixed widths that exceed constraints.
- Ensure header IconButtons use tooltips and `AppDesignTokens.minimumTarget`.
- Use theme text roles instead of shell-local font sizes.
- Keep all controllers, validation, `_save`, `_delete`, hydration, collaboration status, and type-specific editor code unchanged.

- [ ] **Step 5: Verify tests and editor behavior**

Run:

```bash
dart format lib/features/mindmap/presentation/node_editor_panel.dart test/features/mindmap/presentation/node_editor_panel_test.dart
flutter test test/features/mindmap/presentation/node_editor_panel_test.dart test/features/mindmap/presentation/inline_node_workspace_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit focused change**

```bash
git diff -- lib/features/mindmap/presentation/node_editor_panel.dart test/features/mindmap/presentation/node_editor_panel_test.dart
git add lib/features/mindmap/presentation/node_editor_panel.dart test/features/mindmap/presentation/node_editor_panel_test.dart
git commit -m "fix(mindmap): adapt node editor shell"
```

### Task 6: Adapt Graph Page Chrome at 320/768/1024/1440

**Files:**
- Modify: `lib/features/graph/graph_page.dart:37-2604`
- Test: `test/features/graph/graph_page_test.dart`

**Interfaces:**
- Consumes: existing providers, `_GraphBody` callbacks, graph query/filter state, and `VisualGraphView` public constructor.
- Produces: unchanged graph state and navigation behavior; stable existing keys/tooltips plus new `ValueKey('graph-page-body')` and `ValueKey('graph-search-action')` if needed for tests.

- [ ] **Step 1: Add graph test harness for exact widths**

Refactor test setup to a helper that sets `tester.view.physicalSize = Size(width, 900)` and pumps `ProviderScope` with `InMemoryMindmapRepository`. Preserve `SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty()`.

- [ ] **Step 2: Write failing width matrix tests**

For `320`, `768`, `1024`, `1440`, pump seeded graph and assert:

```dart
expect(find.byKey(const ValueKey('graph-page-body')), findsOneWidget);
expect(find.text('Graph'), findsOneWidget);
expect(find.byTooltip('Switch to 2D Physics Force-Directed View'), findsOneWidget);
expect(tester.takeException(), isNull, reason: 'width=$width');
```

At `320`, expect search exposed through `IconButton`/dialog or compact field without AppBar overflow. At `768`, search and filter toggle remain reachable. At `1024/1440`, persistent search field remains visible. Open overview, diagnostics, filters, visual controls, and detail drawer at each relevant width; assert no horizontal overflow.

- [ ] **Step 3: Write failing 200-percent text-scale and RTL tests**

Pump width `320` with `MediaQueryData(textScaler: TextScaler.linear(2))` and `TextDirection.rtl`; open filters and graph controls. Assert tooltips/actions remain discoverable and `tester.takeException()` is null. Verify labels are not used as coordinate-sensitive expectations.

- [ ] **Step 4: Run graph tests and confirm red state**

Run:

```bash
flutter test test/features/graph/graph_page_test.dart
```

Expected: FAIL because AppBar always embeds search, `_GraphBody` uses fixed `600` tab view height, cards use fixed widths `156/320`, and some rows do not adapt at compact/high-scale sizes.

- [ ] **Step 5: Implement compact, medium, expanded graph chrome**

Use `LayoutBuilder` at page/body boundaries:

```dart
final compact = constraints.maxWidth < 600;
final expanded = constraints.maxWidth >= 1024;
```

- Compact `AppBar`: title plus physics toggle and search action. Search action opens Material full-width dialog/bottom sheet containing existing `SearchField`; after dismissal, restore focus to search action.
- Medium/expanded `AppBar`: retain inline `SearchField`, constrained to available width.
- Replace fixed diagnostic/overview card widths with `ConstrainedBox` and `LayoutBuilder`: one column at `320`, two flexible columns when space permits, existing wider wrap at `1024/1440`.
- Replace fixed `SizedBox(height: 600)` with available-height-aware minimum that remains scrollable; do not change `VisualGraphView` transforms, gesture handling, hit testing, painter, or node placement.
- Keep filters collapsed by default. Ensure toggle, chips, saved-filter menu, tabs, guidance actions, and detail drawer use Material controls and `>=44` targets.
- Use `EdgeInsetsDirectional` where placement is directional.
- Preserve list/table semantics; do not convert every row into a card.
- Use semantic colors/tokens for dashboard/filter/list/detail chrome only. Keep node colors and painter contrast colors unchanged.

- [ ] **Step 6: Verify graph behavior and domain isolation**

Run:

```bash
dart format lib/features/graph/graph_page.dart test/features/graph/graph_page_test.dart
flutter test test/features/graph/graph_page_test.dart test/features/graph/graph_helpers_test.dart test/features/graph/graph_overview_test.dart test/features/graph/domain/node_graph_explorer_test.dart test/features/graph/domain/graph_physics_simulation_test.dart
```

Expected: PASS.

- [ ] **Step 7: Inspect protected diff and commit**

```bash
git diff --unified=0 -- lib/features/graph/graph_page.dart
```

Expected: no hunks in `_VisualGraphPainter.paint`, transformation math, gesture callbacks, hit testing, or node-position calculation.

```bash
git add lib/features/graph/graph_page.dart test/features/graph/graph_page_test.dart
git commit -m "fix(graph): adapt canvas page chrome"
```

### Task 7: Complete Reduced Motion and Canvas Semantics

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart` chrome classes only
- Modify: `lib/features/graph/graph_page.dart` chrome classes only
- Modify: `lib/features/graph/presentation/graph_physics_canvas.dart:1-86` wrapper only
- Test: `test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart`
- Test: `test/features/mindmap/presentation/canvas_scale_navigation_test.dart`
- Test: `test/features/graph/graph_page_test.dart`

**Interfaces:**
- Consumes: `AppDesignTokens.effectiveDuration(BuildContext, Duration)` and existing `MediaQuery.disableAnimations`/`accessibleNavigation` behavior.
- Produces: zero-duration chrome transitions under reduced motion and descriptive semantics for visual/physics canvases; no animation-controller, simulation, transform, or painter changes.

- [ ] **Step 1: Write failing reduced-motion transition tests**

Pump mindmap and graph with both variants:

```dart
const MediaQueryData(disableAnimations: true)
const MediaQueryData(accessibleNavigation: true)
```

Open graph overview/filter panels and any mindmap chrome reveal using one `tester.pump()` rather than `pumpAndSettle`; assert final content appears immediately. Existing `canvas_scale_navigation_test.dart:525-552` remains regression coverage for viewport focus.

- [ ] **Step 2: Write failing canvas semantics tests**

Assert standard graph visual canvas exposes a concise container label such as `Graph canvas, 2 nodes and 1 link`; physics mode exposes `Physics graph canvas, 2 nodes`; mindmap canvas exposes `Mindmap canvas` plus current object/node count through semantics without exposing decorative painter children.

```dart
expect(
  find.bySemanticsLabel('Physics graph canvas, 2 nodes'),
  findsOneWidget,
);
```

- [ ] **Step 3: Run tests and confirm red state**

Run:

```bash
flutter test test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart test/features/graph/graph_page_test.dart
```

Expected: FAIL on hard-coded `Duration(milliseconds: 180)` in graph chrome or missing canvas labels.

- [ ] **Step 4: Route chrome durations through tokens**

For graph `_GraphDashboardPanelToggle` and other audited chrome-only `AnimatedSwitcher`/`AnimatedSize`, replace direct duration with:

```dart
final tokens = AppDesignTokens.of(context);
final duration = tokens.effectiveDuration(context, tokens.motionFast);
```

Apply same pattern only to mindmap overlay reveal/hide transitions found in Task 1 classification. Do not alter pointer timing, double-click threshold, hover throttle, debounce, physics ticker, focus animation internals, or domain timers.

- [ ] **Step 5: Add semantic wrappers outside canvases**

Wrap standard graph root with `Semantics(container: true, explicitChildNodes: true, label: 'Graph canvas, ${nodes.length} nodes and ${edges.length} ${edges.length == 1 ? 'link' : 'links'}')`; wrap physics root with `Semantics(container: true, explicitChildNodes: true, label: 'Physics graph canvas, ${nodes.length} nodes')`; wrap mindmap viewport with `Semantics(container: true, explicitChildNodes: true, label: 'Mindmap canvas, ${widget.nodes.length} nodes and ${widget.board?.objects.length ?? 0} canvas objects')`. In `GraphPhysicsCanvas`, wrapper may surround existing `InteractiveViewer`; leave its constructor arguments, controller, `AnimationController`, simulation update, `CustomPaint`, and `_GraphPhysicsPainter` unchanged. Use `ExcludeSemantics` only around decorative painter output when equivalent node list/details controls remain available.

- [ ] **Step 6: Verify reduced motion and protected behavior**

Run:

```bash
dart format lib/features/mindmap/presentation/mindmap_canvas.dart lib/features/graph/graph_page.dart lib/features/graph/presentation/graph_physics_canvas.dart test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart test/features/graph/graph_page_test.dart
flutter test test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart test/features/graph/graph_page_test.dart test/features/graph/domain/graph_physics_simulation_test.dart
```

Expected: PASS.

- [ ] **Step 7: Confirm protected internals unchanged and commit**

```bash
git diff --unified=0 -- lib/features/mindmap/presentation/mindmap_canvas.dart lib/features/graph/graph_page.dart lib/features/graph/presentation/graph_physics_canvas.dart
git add lib/features/mindmap/presentation/mindmap_canvas.dart lib/features/graph/graph_page.dart lib/features/graph/presentation/graph_physics_canvas.dart test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart test/features/graph/graph_page_test.dart
git commit -m "fix(canvas): honor reduced motion and semantics"
```

Expected diff: wrappers/durations only; no painter, transform, hit-test, physics, gesture, or domain hunks.

### Task 8: Final Raw-Style, Accessibility, Responsive, and Repository Gates

**Files:**
- Modify only files already listed if a test exposes a scoped chrome defect
- No new dependencies
- No new production abstractions

**Interfaces:**
- Consumes: all outputs from Tasks 2-7.
- Produces: evidence that spec acceptance criteria pass without protected behavior changes.

- [ ] **Step 1: Re-run raw-style audit and classify remaining matches**

Run:

```bash
rg -n "Colors\.|Color\(0x|fontSize:|BorderRadius\.circular\(|Radius\.circular\(|BoxShadow\(|Duration\(milliseconds:" lib/features/mindmap/presentation lib/features/graph --glob "*.dart"
```

Expected remaining matches belong only to data accents, persisted canvas identities, painter geometry/contrast, media/annotation rendering, gesture thresholds, throttles, debounce, physics, or domain timing. Any remaining structural chrome match gets one targeted test and minimal token replacement in its existing file; do not perform bulk replacement.

- [ ] **Step 2: Run exact responsive matrix**

Run:

```bash
flutter test test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart
flutter test test/features/graph/graph_page_test.dart --name "320|768|1024|1440"
```

Expected: PASS at `320`, `768`, `1024`, `1440` with no `RenderFlex overflow`, clipped actions, inaccessible search, or off-screen close controls.

- [ ] **Step 3: Run accessibility variants**

Run focused tests covering:

```text
TextScaler.linear(2) at width 320
TextDirection.rtl at widths 320 and 1024
MediaQueryData(disableAnimations: true)
MediaQueryData(accessibleNavigation: true)
keyboard-only Tab/Shift+Tab/Escape/Enter operation
pointer hover tooltips and context actions
touch targets >= 44 logical pixels
focus restoration after compact search/dialog/popover closes
semantics for minimap, visual graph, physics graph, canvas search results, selection count, empty/error/disabled/destructive states
```

Command:

```bash
flutter test test/features/mindmap/presentation/canvas_tool_popover_test.dart test/features/mindmap/presentation/canvas_milanote_features_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart test/features/mindmap/presentation/node_editor_panel_test.dart test/features/graph/graph_page_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run protected canvas regression suites**

```bash
flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart test/features/mindmap/presentation/canvas_board_integration_test.dart test/features/mindmap/presentation/mixed_selection_layout_test.dart test/features/mindmap/presentation/canvas_structural_culling_scale_test.dart test/features/graph/domain/node_graph_explorer_test.dart test/features/graph/domain/graph_physics_simulation_test.dart
```

Expected: PASS, confirming painters/transforms/hit-testing/physics/gestures/domain behavior remains intact.

- [ ] **Step 5: Run format, analyzer, and full tests**

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

Expected: all commands exit `0`.

- [ ] **Step 6: Inspect final scope**

```bash
git status --short
git diff --stat
git diff --check
git diff -- lib/features/mindmap/presentation lib/features/graph test/features/mindmap/presentation test/features/graph
```

Expected: only planned chrome/test files changed; no generated files, dependency files, painters, transforms, hit-testing, physics, gestures, or domain files changed; `git diff --check` exits `0`.

- [ ] **Step 7: Commit final scoped corrections only if Step 1-6 required edits**

```bash
git add lib/features/mindmap/presentation/canvas_tool_popover.dart lib/features/mindmap/presentation/widgets/multi_select_action_bar.dart lib/features/mindmap/presentation/widgets/canvas_minimap_widget.dart lib/features/mindmap/presentation/mindmap_canvas.dart lib/features/mindmap/presentation/node_editor_panel.dart lib/features/graph/graph_page.dart lib/features/graph/presentation/graph_physics_canvas.dart test/features/mindmap/presentation/canvas_tool_popover_test.dart test/features/mindmap/presentation/canvas_milanote_features_test.dart test/features/mindmap/presentation/canvas_scale_navigation_test.dart test/features/mindmap/presentation/canvas_adaptive_accessibility_test.dart test/features/mindmap/presentation/node_editor_panel_test.dart test/features/graph/graph_page_test.dart
git commit -m "test(canvas): complete adaptive accessibility polish"
```

Skip commit when no final corrections exist; never create empty commit.

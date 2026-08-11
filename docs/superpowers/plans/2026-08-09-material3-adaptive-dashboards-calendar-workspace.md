# Material 3 Adaptive Dashboards, Calendar, and Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Memoles Insights/Life OS, workspace lists/detail data views, Calendar, dan DayPage chrome dengan Material 3 adaptive bergaya shadcn tanpa mengubah domain, persistence, scheduling, canvas geometry, atau drag/drop.

**Architecture:** Pertahankan provider, repository, route, mutation callback, painter, dan widget canvas yang ada. Migrasi dilakukan per cohesive surface cluster: native Material controls, semantic surfaces, border-first hierarchy, `LayoutBuilder` untuk compact/medium/expanded, lalu behavior-regression tests mengunci interaksi berisiko. Jangan ekstrak logic domain atau membuat design-system runtime baru.

**Tech Stack:** Flutter Material 3, Dart 3.11.4, Riverpod, GoRouter, flutter_test.

## Global Constraints

- `ThemeData`, `AppSemanticColors`, dan `AppDesignTokens` tetap satu-satunya sumber design system global.
- Pertahankan tujuh varian warna/font Astryx dan light/dark mode; node-type colors hanya data accents.
- Jangan tambah dependency, `Shadcn*` family, CSS token tree, React runtime, atau web component layer.
- Static cards memakai zero elevation, one-pixel border, semantic surfaces, `radiusElement` untuk controls, dan `radiusContainer` untuk containers.
- Interactive target minimal 44 logical pixels; focus visible; status/error tidak boleh bergantung pada warna saja.
- Layout mengikuti available width: compact sekitar 320, medium sekitar 768, expanded 1024/1440; nested layout memakai `LayoutBuilder`.
- Pertahankan copy, routes, provider contracts, filters, sorting, exports, keyboard shortcuts, context menus, hover, long-press, and semantics kecuali test task menyatakan visual composition berubah.
- Pertahankan scheduling, date normalization, `invalidateMindmapState`, calendar drag/drop and undo, workspace reorder, Kanban drag/drop, DayPage inline-save flush, canvas transforms, canvas selection geometry, viewport persistence, hit testing, and gestures.
- Jangan mengubah painters (`_GanttChartPainter`, calendar painters), `MindmapCanvas`, canvas repositories, domain/application files, atau generated files dalam plan ini.
- Workspace sudah kotor. Sebelum setiap task, jalankan `git status --short` dan `git diff -- <task files>`; edit hanya hunk task, jangan restore/stash/reset perubahan existing, dan stage path exact saja.
- Tiap task menyentuh maksimal lima file. Jika file target berubah sejak audit, re-read section dan transplant perubahan minimal; jangan overwrite whole file.

## File Map

- `lib/features/insights/insights_page.dart`: shell Insights, adaptive dashboard flow, filters, metrics, result list, dan panel chrome.
- `lib/features/insights/presentation/executive_dashboard_panel.dart`: executive dashboard data visualization chrome tanpa mengubah summary inputs.
- `lib/features/insights/presentation/habit_matrix_heatmap.dart`: heatmap container, labels, semantics, dan horizontal adaptation.
- `test/features/insights/insights_page_test.dart`: behavior, adaptive-width, keyboard, empty/loading/error, dan dashboard hierarchy regressions.
- `test/features/insights/habit_matrix_heatmap_test.dart`: heatmap semantics dan narrow-width regressions.
- `lib/features/workspace/workspaces_page.dart`: workspace index search/filter/stats/cards/reorder surfaces.
- `test/features/workspace/workspaces_page_test.dart`: workspace index adaptive and behavior regressions.
- `lib/features/workspace/workspace_detail_page.dart`: detail header, view switcher, list, Kanban, Gantt, dan canvas chrome boundary.
- `test/features/workspace/workspace_detail_page_test.dart`: detail adaptive, data-view, Kanban drag/drop, Gantt semantics, dan canvas-preservation regressions.
- `lib/features/calendar/calendar_page.dart`: calendar app bar, controls, month/week/agenda shells, day cells, preview panel, dan calendar drag/drop boundary.
- `test/features/calendar/calendar_page_test.dart`: widths, keyboard, preview, scheduling drag/drop, and undo regressions.
- `lib/features/calendar/day_page.dart`: non-canvas header, DayPage board/table chrome, compact controls, dan strict boundary around `MindmapCanvas`.
- `lib/features/calendar/widgets/day_canvas_tab_header.dart`: daily canvas tab/header visual chrome only; callbacks remain unchanged.
- `test/features/calendar/day_page_test.dart`: DayPage data-view interactions plus canvas/geometry preservation.
- `test/features/calendar/day_page_mobile_layout_test.dart`: compact header/sheet behavior and narrow overflow checks.
- `test/features/calendar/day_canvas_tab_header_test.dart`: canvas tab callbacks, target size, semantics, and compact overflow.

---

### Task 1: Insights adaptive shell, filters, and result hierarchy

**Files:**
- Modify: `lib/features/insights/insights_page.dart:150-490,690-1180`
- Modify: `test/features/insights/insights_page_test.dart:18-201,1800-1875`

**Interfaces:**
- Consumes: `smartNodeViewsProvider`, `currentDateProvider`, existing `_InsightsBody` constructor/callbacks, `SearchField`, and `LayoutConstants`.
- Produces: same `InsightsPage({Key? key, bool initialShowDashboardPanels = false})`; stable keys `insights-search-field`, `insights-dashboard-toggle`, `insights-filter-region`, `insights-results-region`; no provider or filter-state changes.

- [ ] **Step 1: Record dirty baseline for task files**

Run:

```bash
git status --short
git diff -- lib/features/insights/insights_page.dart test/features/insights/insights_page_test.dart
```

Expected: current audit may show pre-existing edits in `insights_page.dart`; save output in execution notes and preserve those hunks.

- [ ] **Step 2: Add failing adaptive and semantics tests**

Add helper and tests to `insights_page_test.dart`:

```dart
Future<void> setInsightsSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pump();
}

testWidgets('InsightsPage keeps search and dashboard controls usable at 320', (
  tester,
) async {
  addTearDown(tester.view.resetPhysicalSize);
  await setInsightsSurface(tester, const Size(320, 900));
  final repository = InMemoryMindmapRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: InsightsPage()),
    ),
  );
  await tester.pumpAndSettle();

  expect(tester.takeException(), isNull);
  expect(find.byKey(const ValueKey('insights-dashboard-toggle')), findsOneWidget);
  expect(find.byKey(const ValueKey('insights-mobile-search')), findsOneWidget);
  expect(find.byKey(const ValueKey('insights-search-field')), findsNothing);
});

testWidgets('InsightsPage exposes filters and results as semantic regions', (
  tester,
) async {
  final semantics = tester.ensureSemantics();
  addTearDown(semantics.dispose);
  final repository = InMemoryMindmapRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: InsightsPage()),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.bySemanticsLabel('Insight filters'), findsOneWidget);
  expect(find.bySemanticsLabel('Insight results'), findsOneWidget);
});
```

- [ ] **Step 3: Run tests and verify contract failure**

Run:

```bash
flutter test test/features/insights/insights_page_test.dart --plain-name "InsightsPage keeps search and dashboard controls usable at 320"
flutter test test/features/insights/insights_page_test.dart --plain-name "InsightsPage exposes filters and results as semantic regions"
```

Expected: FAIL because compact search action and stable semantic regions do not exist.

- [ ] **Step 4: Implement minimal adaptive shell**

In `InsightsPage.build`, derive width once and retain every action callback:

```dart
final width = MediaQuery.sizeOf(context).width;
final showInlineSearch = width >= LayoutConstants.mobileBreakpoint;
```

Give dashboard button key `ValueKey('insights-dashboard-toggle')`. Render existing `SearchField` only when `showInlineSearch`; otherwise render `IconButton(key: ValueKey('insights-mobile-search'), tooltip: 'Search insights', ...)` opening an `AlertDialog` containing same controller, focus node, key, hint, and `_query` update. Do not duplicate filter state.

Wrap `_InsightRangeFilterBar`, active chips, and shortcut hint in:

```dart
Semantics(
  key: const ValueKey('insights-filter-region'),
  container: true,
  label: 'Insight filters',
  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...]),
)
```

Wrap result section label plus empty/list content in equivalent `Semantics(key: ValueKey('insights-results-region'), container: true, label: 'Insight results', ...)`. Keep result ordering, `goToDay`, keyboard shortcuts, report export, filters, loading, and retry unchanged.

Replace `_InsightsBody` root fixed `Padding + ListView` with `LayoutBuilder`; use token spacing and constrain expanded content without changing child order:

```dart
final maxWidth = constraints.maxWidth >= LayoutConstants.desktopBreakpoint
    ? 1280.0
    : double.infinity;
return Align(
  alignment: Alignment.topCenter,
  child: ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: ListView(padding: EdgeInsets.all(spacing), children: children),
  ),
);
```

- [ ] **Step 5: Run focused existing and new behavior tests**

Run:

```bash
flutter test test/features/insights/insights_page_test.dart --plain-name "InsightsPage keeps search and dashboard controls usable at 320"
flutter test test/features/insights/insights_page_test.dart --plain-name "InsightsPage exposes filters and results as semantic regions"
flutter test test/features/insights/insights_page_test.dart --plain-name "InsightsPage searches and filters nodes by metadata"
flutter test test/features/insights/insights_page_test.dart --plain-name "InsightsPage keyboard slash focuses search"
```

Expected: PASS; no overflow or changed filter result.

- [ ] **Step 6: Format, inspect diff, and commit only task files**

Run:

```bash
dart format lib/features/insights/insights_page.dart test/features/insights/insights_page_test.dart
git diff --check -- lib/features/insights/insights_page.dart test/features/insights/insights_page_test.dart
git diff -- lib/features/insights/insights_page.dart test/features/insights/insights_page_test.dart
git add -- lib/features/insights/insights_page.dart test/features/insights/insights_page_test.dart
git diff --cached --check
git commit -m "feat: adapt insights dashboard shell"
```

Expected: commit contains only these two paths and preserves baseline hunks deliberately included in same files.

### Task 2: Insights dashboard panels and chart chrome

**Files:**
- Modify: `lib/features/insights/insights_page.dart:1182-1340`
- Modify: `lib/features/insights/presentation/executive_dashboard_panel.dart`
- Modify: `lib/features/insights/presentation/habit_matrix_heatmap.dart`
- Modify: `test/features/insights/insights_page_test.dart:34-96`
- Modify: `test/features/insights/habit_matrix_heatmap_test.dart`

**Interfaces:**
- Consumes: existing `ExecutiveDashboardSummary`, `ExecutiveDashboardPanel` callbacks, `HabitMatrixHeatmap(habitNodes:)`, `_buildProductivityDistribution`, and `NodeVisuals` data colors.
- Produces: same public constructors/callbacks; responsive dashboard grids and horizontally safe heatmap; painters/calculations untouched.

- [ ] **Step 1: Capture task-file baseline**

Run:

```bash
git status --short
git diff -- lib/features/insights/insights_page.dart lib/features/insights/presentation/executive_dashboard_panel.dart lib/features/insights/presentation/habit_matrix_heatmap.dart test/features/insights/insights_page_test.dart test/features/insights/habit_matrix_heatmap_test.dart
```

Expected: no unreviewed file gets overwritten.

- [ ] **Step 2: Add failing responsive dashboard tests**

Append to `insights_page_test.dart`:

```dart
testWidgets('Insights dashboard distribution stacks at 320 without overflow', (
  tester,
) async {
  addTearDown(tester.view.resetPhysicalSize);
  tester.view.physicalSize = const Size(320, 1200);
  tester.view.devicePixelRatio = 1;
  final today = DateTime(2026, 7, 6);
  final repository = InMemoryMindmapRepository(
    seedNodes: [
      MindmapNode.create(
        id: 'task',
        type: NodeType.task,
        title: 'Task',
        day: today,
        effort: NodeEffort.thirtyMinutes,
        now: today,
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mindmapRepositoryProvider.overrideWithValue(repository),
        currentDateProvider.overrideWithValue(today),
      ],
      child: const MaterialApp(
        home: InsightsPage(initialShowDashboardPanels: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Productivity Distribution'),
    500,
    scrollable: find.byType(Scrollable).first,
  );

  expect(tester.takeException(), isNull);
  final effort = tester.getTopLeft(find.text('Effort'));
  final review = tester.getTopLeft(find.text('Review State'));
  expect(review.dy, greaterThan(effort.dy));
});
```

In `habit_matrix_heatmap_test.dart`, add a 320-width test that pumps enough habit data, calls `pumpAndSettle`, expects no exception, and expects `find.bySemanticsLabel('Habit matrix heatmap')`.

- [ ] **Step 3: Verify tests fail before implementation**

Run:

```bash
flutter test test/features/insights/insights_page_test.dart --plain-name "Insights dashboard distribution stacks at 320 without overflow"
flutter test test/features/insights/habit_matrix_heatmap_test.dart --plain-name "heatmap scrolls at narrow width with chart semantics"
```

Expected: distribution remains two `Expanded` children in one row and heatmap lacks requested semantic/adaptive wrapper.

- [ ] **Step 4: Apply border-first responsive composition**

For `_buildProductivityDistribution`, preserve effort/review counts and colors. Change `buildColumn` to return a plain constrained panel, then choose layout with `LayoutBuilder`:

```dart
final columns = <Widget>[
  buildColumn('Effort', effortRows, primary),
  buildColumn('Review State', reviewRows, secondary),
];
return constraints.maxWidth < 680
    ? Column(children: [columns.first, const SizedBox(height: 10), columns.last])
    : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: columns.first),
        const SizedBox(width: 10),
        Expanded(child: columns.last),
      ]);
```

Use `Card`/`DecoratedBox` with semantic surface, one-pixel outline, `tokens.radiusContainer`, zero elevation. Keep mini bars, labels, counts, chart values, and NodeVisual colors.

In `ExecutiveDashboardPanel`, replace local ornamental shadows/raw radii with theme `Card`, token radius, semantic foreground, and a `LayoutBuilder` grid: one column below 680, two columns from 680, existing wider hierarchy above 1024. Preserve `onAreaTap` and `onStartWeeklyReview` invocation.

In `HabitMatrixHeatmap`, wrap chart content in `Semantics(container: true, image: true, label: 'Habit matrix heatmap')`; retain labels and painter/data calculations, and use horizontal `SingleChildScrollView` with a finite minimum chart width instead of squeezing cells below readable size.

- [ ] **Step 5: Run panel and dashboard tests**

Run:

```bash
flutter test test/features/insights/insights_page_test.dart --plain-name "Insights dashboard distribution stacks at 320 without overflow"
flutter test test/features/insights/insights_page_test.dart --plain-name "InsightsPage renders productivity distribution, overdue and weekly wins"
flutter test test/features/insights/habit_matrix_heatmap_test.dart
flutter test test/features/insights/executive_dashboard_summary_test.dart
```

Expected: PASS; summary calculations and panel actions remain unchanged.

- [ ] **Step 6: Format and commit exact paths**

Run:

```bash
dart format lib/features/insights/insights_page.dart lib/features/insights/presentation/executive_dashboard_panel.dart lib/features/insights/presentation/habit_matrix_heatmap.dart test/features/insights/insights_page_test.dart test/features/insights/habit_matrix_heatmap_test.dart
git diff --check -- lib/features/insights/insights_page.dart lib/features/insights/presentation/executive_dashboard_panel.dart lib/features/insights/presentation/habit_matrix_heatmap.dart test/features/insights/insights_page_test.dart test/features/insights/habit_matrix_heatmap_test.dart
git add -- lib/features/insights/insights_page.dart lib/features/insights/presentation/executive_dashboard_panel.dart lib/features/insights/presentation/habit_matrix_heatmap.dart test/features/insights/insights_page_test.dart test/features/insights/habit_matrix_heatmap_test.dart
git diff --cached --check
git commit -m "feat: polish insights data panels"
```

Expected: one cohesive visual-only dashboard commit.

### Task 3: Workspace index adaptive list and reorder surfaces

**Files:**
- Modify: `lib/features/workspace/workspaces_page.dart:80-150,184-310,312-858,860-1362`
- Modify: `test/features/workspace/workspaces_page_test.dart`

**Interfaces:**
- Consumes: `workspaceContextsProvider`, `workspaceSortProvider`, `workspaceTitleProvider`, `_setFilter`, `ReorderableListView.builder`, route URLs, and rename gestures.
- Produces: same `WorkspacesPage`; stable keys `workspace-mobile-search`, `workspace-index-content`; exact reorder callback/order persistence and card gestures preserved.

- [ ] **Step 1: Inspect dirty task files**

Run:

```bash
git status --short
git diff -- lib/features/workspace/workspaces_page.dart test/features/workspace/workspaces_page_test.dart
```

Expected: review output before edits; no reset/stash.

- [ ] **Step 2: Add failing compact and reorder regression tests**

Add to `workspaces_page_test.dart`:

```dart
testWidgets('WorkspacesPage uses compact search action at 320', (tester) async {
  addTearDown(tester.view.resetPhysicalSize);
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  final repository = InMemoryMindmapRepository(
    seedNodes: [
      MindmapNode.create(
        id: 'alpha',
        type: NodeType.task,
        title: 'Alpha task',
        day: DateTime(2026, 6, 19),
        project: 'Alpha',
        now: DateTime(2026, 6, 19),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: WorkspacesPage()),
    ),
  );
  await tester.pumpAndSettle();

  expect(tester.takeException(), isNull);
  expect(find.byKey(const ValueKey('workspace-mobile-search')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('workspace-mobile-search')));
  await tester.pumpAndSettle();
  expect(find.text('Filter workspaces'), findsOneWidget);
});
```

Add a reorder test with two project nodes, drag `workspace-card-project-beta` before `workspace-card-project-alpha`, then read `workspaceSortProvider` and assert project order `['Beta', 'Alpha']`. Use existing in-memory shared preferences setup.

- [ ] **Step 3: Run tests to establish failure**

Run:

```bash
flutter test test/features/workspace/workspaces_page_test.dart --plain-name "WorkspacesPage uses compact search action at 320"
flutter test test/features/workspace/workspaces_page_test.dart --plain-name "WorkspacesPage preserves manual project reorder"
```

Expected: compact app bar overflows/no mobile action; reorder test protects existing behavior while visual work proceeds.

- [ ] **Step 4: Implement adaptive index without touching data logic**

Derive `showInlineSearch` from width. Keep desktop `SearchField`; compact uses `IconButton(key: ValueKey('workspace-mobile-search'), tooltip: 'Filter workspaces', ...)` opening `AlertDialog(title: Text('Filter workspaces'), content: SearchField(...same controller/callback...))`.

Wrap body content with `LayoutBuilder`, centered `ConstrainedBox(maxWidth: 1120)`, token spacing, and key `workspace-index-content`. Keep section order Projects/Areas/Dailies and keep `ReorderableListView.builder`, item keys, `onReorderItem`, provider calls, right-click, long-press, hover, rename, Insights, Graph, and open routes exact.

Restyle `_WorkspaceFilterBar`, `_WorkspaceFocusStrip`, metric pills, and `_WorkspaceContextCard` to semantic `Card`/`Material` surfaces with token radii, one-pixel borders, no scale/translate hover. Hover changes border/surface only. Keep minimum target 44 for icon actions even when visuals are compact. Replace custom hover title `OverlayEntry` with native `Tooltip(message: customTitle)` around the title/card; remove `_overlayEntry`, `_showOverlay`, and `_hideOverlay` only after rename/open behavior tests pass.

- [ ] **Step 5: Run workspace index tests**

Run:

```bash
flutter test test/features/workspace/workspaces_page_test.dart
flutter test test/features/workspace/workspace_helpers_test.dart
flutter test test/features/workspace/workspace_overview_test.dart
```

Expected: PASS; filter persistence, rename display, details expansion, stats toggle, and reorder remain intact.

- [ ] **Step 6: Format and commit scoped paths**

Run:

```bash
dart format lib/features/workspace/workspaces_page.dart test/features/workspace/workspaces_page_test.dart
git diff --check -- lib/features/workspace/workspaces_page.dart test/features/workspace/workspaces_page_test.dart
git add -- lib/features/workspace/workspaces_page.dart test/features/workspace/workspaces_page_test.dart
git diff --cached --check
git commit -m "feat: adapt workspace index surfaces"
```

Expected: no workspace detail/canvas files staged.

### Task 4: Workspace detail header, list, and view switcher

**Files:**
- Modify: `lib/features/workspace/workspace_detail_page.dart:154-285,3159-3634`
- Modify: `test/features/workspace/workspace_detail_page_test.dart:78-178,1486-1560`

**Interfaces:**
- Consumes: `_WorkspaceView`, `_WorkspaceDetailHeader`, `_WorkspaceListView`, existing `context.go`, clipboard export, `WorkspaceContext` data, and `goToDay`.
- Produces: same route/public constructor; compact view menu and medium/expanded `SegmentedButton`; stable `workspace-view-menu`, `workspace-detail-header`, and existing view labels.

- [ ] **Step 1: Audit file-local dirty changes**

Run:

```bash
git status --short
git diff -- lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart
```

Expected: preserve all unrelated canvas/workshop hunks in huge detail file.

- [ ] **Step 2: Add failing width and action-preservation tests**

Add tests:

```dart
testWidgets('compact workspace detail exposes view menu without overflow', (
  tester,
) async {
  addTearDown(tester.view.resetPhysicalSize);
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(buildPage());
  await tester.pumpAndSettle();

  expect(tester.takeException(), isNull);
  expect(find.byKey(const ValueKey('workspace-view-menu')), findsOneWidget);
  expect(find.byType(SegmentedButton), findsNothing);
  await tester.tap(find.byKey(const ValueKey('workspace-view-menu')));
  await tester.pumpAndSettle();
  expect(find.text('Kanban'), findsOneWidget);
  expect(find.text('Gantt'), findsOneWidget);
});

testWidgets('workspace detail header keeps report action at medium width', (
  tester,
) async {
  addTearDown(tester.view.resetPhysicalSize);
  tester.view.physicalSize = const Size(768, 900);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(buildPage());
  await tester.pumpAndSettle();
  await tester.tap(find.text('Kanban'));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('workspace-detail-header')), findsOneWidget);
  expect(find.text('Copy report'), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 3: Verify current layout fails**

Run:

```bash
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "compact workspace detail exposes view menu without overflow"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "workspace detail header keeps report action at medium width"
```

Expected: compact still renders app-bar segmented control; header row risks overflow.

- [ ] **Step 4: Implement adaptive header and list chrome**

In app bar, use `LayoutBuilder`/width: below 700 render `PopupMenuButton<_WorkspaceView>(key: ValueKey('workspace-view-menu'), tooltip: 'Workspace view', initialValue: _view, itemBuilder: List/Kanban/Gantt)`; at 700+ keep existing `SegmentedButton` and selection callback. Do not expose canvas in this switch because route controls canvas entry today.

Give `_WorkspaceDetailHeader` key and replace fixed header/action rows with `LayoutBuilder`: compact/medium stacks identity, chips, progress copy, and `Wrap` actions; expanded may use row. Use `Card`, semantic surfaces, token radiusContainer, no `radiusPage`, no static elevation. Keep `DateTime.now`, builders, URLs, clipboard content, and SnackBar exact.

In `_WorkspaceListView`, retain active/completed membership and order. Constrain list to max width 1120, use one border-first stats card, semantic section headings, and native `ListTile` rows. Do not convert rows into standalone oversized cards; keep every `goToDay` target.

- [ ] **Step 5: Run list/header regressions**

Run:

```bash
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "compact workspace detail exposes view menu without overflow"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "workspace detail header keeps report action at medium width"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "shows workspace title and list view by default"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "shows persisted custom workspace title"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "shows stats card in list view"
```

Expected: PASS; custom title and list membership unchanged.

- [ ] **Step 6: Format and commit only detail task paths**

Run:

```bash
dart format lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart
git diff --check -- lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart
git add -- lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart
git diff --cached --check
git commit -m "feat: adapt workspace detail data views"
```

Expected: one commit; no application/domain file staged.

### Task 5: Workspace Kanban and Gantt chrome with drag/drop lock

**Files:**
- Modify: `lib/features/workspace/workspace_detail_page.dart:3640-4391`
- Modify: `test/features/workspace/workspace_detail_page_test.dart:1486-1559`

**Interfaces:**
- Consumes: `_KanbanColumn.targetStatus`, `DragTarget<String>`, `LongPressDraggable<String>`, repository save, `invalidateMindmapState`, `_GanttChartPainter`, and Gantt semantics.
- Produces: unchanged status/progress mapping and painter inputs; compact horizontally scrollable board/table-like Gantt with semantic row labels.

- [ ] **Step 1: Inspect current task hunks**

Run:

```bash
git status --short
git diff -- lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart
```

Expected: only prior committed state plus unrelated dirty baseline, if any.

- [ ] **Step 2: Add failing/locking Kanban drag test and compact Gantt test**

Add:

```dart
testWidgets('Kanban drag preserves status and progress mutation contract', (
  tester,
) async {
  await tester.pumpWidget(buildPage());
  await tester.pumpAndSettle();
  await tester.tap(find.text('Kanban'));
  await tester.pumpAndSettle();

  final card = find.text('Design homepage');
  final doing = find.text('In Progress');
  final gesture = await tester.startGesture(tester.getCenter(card));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 200));
  await gesture.moveTo(tester.getCenter(doing));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();

  final moved = await repository.getNode('task-open');
  expect(moved?.status, NodeStatus.doing);
  expect(moved?.progress, 0.1);
});

testWidgets('Gantt remains scrollable and semantic at 320', (tester) async {
  addTearDown(tester.view.resetPhysicalSize);
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(buildPage());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('workspace-view-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Gantt').last);
  await tester.pumpAndSettle();

  expect(tester.takeException(), isNull);
  expect(find.bySemanticsLabel('Gantt chart, 3 tasks'), findsOneWidget);
  expect(find.byType(Scrollable), findsWidgets);
});
```

Import `flutter/services.dart` only if `kLongPressTimeout` is not already available through current imports; prefer existing Flutter test constant import pattern.

- [ ] **Step 3: Run focused tests before visual edits**

Run:

```bash
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "Kanban drag preserves status and progress mutation contract"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "Gantt remains scrollable and semantic at 320"
```

Expected: drag contract may PASS as characterization; Gantt compact test FAILS if view selection/layout overflows. A passing characterization test is acceptable before visual change and must remain passing.

- [ ] **Step 4: Restyle only Kanban/Gantt composition**

Keep eight `_KanbanColumn` values and exact status/progress save code. Use token radiusContainer, semantic card/surface/border roles, zero-elevation cards, restrained elevated drag feedback, 44 minimum popup target, and explicit `Semantics(button: true, label: 'Move ${node.title}, ${column.label}')` around draggable card. Keep horizontal scrolling and minimum column width 240; do not collapse columns into unrelated cards or replace drag target.

Keep Gantt `earliest`, `latest`, `totalDays`, `dayWidth`, `rowHeight`, `labelWidth`, painter, and semantic labels exact. Restyle only legend, border, background, labels, and scrollbars using theme. Ensure nested vertical/horizontal scroll remains finite at 320 and chart can scroll instead of shrinking geometry.

- [ ] **Step 5: Run all workspace data-view and canvas boundary tests**

Run:

```bash
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "Kanban drag preserves status and progress mutation contract"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "switches to Kanban view and shows columns"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "switches to Gantt view and shows legend"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "Gantt remains scrollable and semantic at 320"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "project canvas persists viewport without activity history"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "opens exact shared project canvas from route state"
```

Expected: PASS; canvas viewport and selected board unchanged despite same source file.

- [ ] **Step 6: Format and commit exact files**

Run:

```bash
dart format lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart
git diff --check -- lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart
git add -- lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart
git diff --cached --check
git commit -m "feat: polish workspace kanban and gantt"
```

Expected: no painter/domain edits beyond style arguments and wrappers.

### Task 6: Calendar adaptive header, controls, and preview surfaces

**Files:**
- Modify: `lib/features/calendar/calendar_page.dart:135-605,1676-2450`
- Modify: `test/features/calendar/calendar_page_test.dart:1-380,2103-2160`

**Interfaces:**
- Consumes: calendar providers, `_CalendarControlPanel`, `_DayPreviewPanel`, `_showCalendarControlsSheet`, `_showCalendarActionsSheet`, keyboard handler, and `goToDay`.
- Produces: same calendar modes and callbacks; stable compact actions and border-first preview/control surfaces.

- [ ] **Step 1: Capture dirty baseline**

Run:

```bash
git status --short
git diff -- lib/features/calendar/calendar_page.dart test/features/calendar/calendar_page_test.dart
```

Expected: baseline recorded; no broad rewrite.

- [ ] **Step 2: Add failing representative-width tests**

Add parameterized widget test:

```dart
for (final width in <double>[320, 768, 1024, 1440]) {
  testWidgets('CalendarPage stays usable at ${width.round()} width', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    final today = DateTime(2026, 6, 19);
    final repository = InMemoryMindmapRepository();
    await _pumpCalendar(tester, repository: repository, today: today);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('calendar-actions-menu')), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    if (width < LayoutConstants.mobileBreakpoint) {
      expect(find.byKey(const ValueKey('calendar-mobile-search')), findsOneWidget);
    } else {
      expect(find.byKey(const ValueKey('calendar-search-field')), findsOneWidget);
    }
  });
}
```

Add a preview test at 1024 that presses Space, expects inline `_DayPreviewPanel` semantics label `Day preview`, and Escape collapses/closes without route change.

- [ ] **Step 3: Run tests and capture failures**

Run:

```bash
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage stays usable at 320 width"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage stays usable at 768 width"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage keyboard preview remains inline at expanded width"
```

Expected: current compact toolbar/header or preview semantics contract fails.

- [ ] **Step 4: Implement adaptive chrome without scheduling changes**

Retain app-bar search breakpoint and callbacks. Use token spacing/radii and remove local `OutlinedButton.styleFrom` geometry for Today; rely on themed `OutlinedButton.icon` at expanded width and `IconButton` compact. Keep tool/actions sheets on non-expanded widths and persistent 260 controls only when constraints support calendar plus panel; calculate from `LayoutBuilder.constraints`, not global OS.

Replace tool row nesting with horizontal scroll that always exposes `calendar-actions-menu`; use native `SegmentedButton`/existing switch unchanged. Style `_CalendarControlPanel` and `_DayPreviewPanel` as semantic `Card`/`Material` surfaces with zero static elevation, one-pixel border, token radiusContainer, and `Semantics(container: true, label: 'Calendar controls'/'Day preview')`. Keep every callback, selected day, route, filters, and preview close/collapse behavior exact.

At 1024/1440, retain optional side preview; at 320/768 retain modal bottom sheet and `SafeArea`. Do not change `_handleDayAction`, `_showFocusedDay`, date arithmetic, mutations, undo, templates, or workload balancing.

- [ ] **Step 5: Run calendar shell regressions**

Run:

```bash
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage stays usable at 320 width"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage stays usable at 768 width"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage stays usable at 1024 width"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage stays usable at 1440 width"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage keyboard opens and closes day preview"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage keyboard shortcuts ignore text entry focus"
```

Expected: PASS; no navigation/filter regression.

- [ ] **Step 6: Format and commit exact calendar shell files**

Run:

```bash
dart format lib/features/calendar/calendar_page.dart test/features/calendar/calendar_page_test.dart
git diff --check -- lib/features/calendar/calendar_page.dart test/features/calendar/calendar_page_test.dart
git add -- lib/features/calendar/calendar_page.dart test/features/calendar/calendar_page_test.dart
git diff --cached --check
git commit -m "feat: adapt calendar controls and preview"
```

Expected: only two files staged.

### Task 7: Calendar month/week/agenda cells with scheduling drag/drop lock

**Files:**
- Modify: `lib/features/calendar/calendar_page.dart:3709-3860,5116-6100`
- Modify: `test/features/calendar/calendar_page_test.dart:410-520`

**Interfaces:**
- Consumes: `_WeekCalendarView`, `_AgendaCalendarView`, `_MonthGrid`, calendar drop keys, `_DraggableCalendarNode`, `mindmapMutationControllerProvider`, and `_showRescheduleSnackBar`.
- Produces: unchanged date targets, long-press drag payload, same-day rejection, undo, selected/focused state, and agenda semantics; visual cell hierarchy only.

- [ ] **Step 1: Inspect only calendar task diff**

Run:

```bash
git status --short
git diff -- lib/features/calendar/calendar_page.dart test/features/calendar/calendar_page_test.dart
```

Expected: understand current hunks before editing large file.

- [ ] **Step 2: Add visual-state assertions to existing drag tests**

Extend month/week drag tests before gesture:

```dart
expect(
  find.bySemanticsLabel('Move Week task from 2026-06-19'),
  findsOneWidget,
);
expect(find.byKey(const ValueKey('calendar-drop-2026-06-18')), findsOneWidget);
```

Add a 320-width month-grid test that asserts no exception, focused day semantics remain available, and cells expose selected/today state with text labels rather than color-only indicators.

- [ ] **Step 3: Run characterization and failing semantics tests**

Run:

```bash
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage week drag moves node to target day"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage month drag moves node to target day"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage month cells expose state at 320"
```

Expected: drag mutations PASS before style edits; new draggable/cell semantics may FAIL.

- [ ] **Step 4: Restyle cells while preserving drag tree**

Keep `DragTarget<MindmapNode>` as outer day-cell interaction and `LongPressDraggable<MindmapNode>` around node row. Do not move callbacks across gesture detectors. Add explicit draggable semantics label `Move ${node.title} from ${dayKey(node.day)}` and day-cell semantics containing full date plus `Today`, `Selected`, workload/count text where applicable.

Use semantic surfaces, one-pixel border, token radiusElement/container, restrained drop-target elevation only while dragging, and node type colors only for icon/dot/slim accent. Remove ornamental texture/shadow only. Preserve `calendar-drop-*`, `calendar-draggable-node-*`, `_showRescheduleSnackBar`, undo action, mutation controller, same-day no-op, month/week geometry calculations, and agenda row routes.

- [ ] **Step 5: Run exact scheduling/keyboard regressions**

Run:

```bash
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage week drag moves node to target day"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage week drag ignores same-day drop"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage month drag moves node to target day"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage agenda shift arrow moves selected node"
flutter test test/features/calendar/calendar_page_test.dart --plain-name "CalendarPage month cells expose state at 320"
```

Expected: PASS; repository day values and Undo return exact original day.

- [ ] **Step 6: Format and commit calendar cells only**

Run:

```bash
dart format lib/features/calendar/calendar_page.dart test/features/calendar/calendar_page_test.dart
git diff --check -- lib/features/calendar/calendar_page.dart test/features/calendar/calendar_page_test.dart
git add -- lib/features/calendar/calendar_page.dart test/features/calendar/calendar_page_test.dart
git diff --cached --check
git commit -m "feat: polish calendar data views"
```

Expected: no domain/application/painter files changed.

### Task 8: DayPage non-canvas adaptive header and data-view switcher

**Files:**
- Modify: `lib/features/calendar/day_page.dart:2682-2705,3960-4650,10989-11045,11460-11620`
- Modify: `test/features/calendar/day_page_mobile_layout_test.dart`
- Modify: `test/features/calendar/day_page_test.dart:680-840,2164-2225`

**Interfaces:**
- Consumes: `_setViewMode`, `_DayViewMode`, `_MobileCompactHeader`, `_DayViewModeToggle`, `_flushInlineWorkspace`, `_DayContextSwitcher`, and existing tool callbacks.
- Produces: same persisted view names (`canvas`, `timeline`, `board`, `table`), compact menu/sheet access, no inline-save loss, and unchanged canvas visibility rules.

- [ ] **Step 1: Audit huge DayPage file without touching canvas code**

Run:

```bash
git status --short
git diff -- lib/features/calendar/day_page.dart test/features/calendar/day_page_mobile_layout_test.dart test/features/calendar/day_page_test.dart
```

Expected: preserve all pre-existing DayPage hunks; restrict implementation to listed sections.

- [ ] **Step 2: Add failing compact/medium mode tests**

Add to `day_page_mobile_layout_test.dart`:

```dart
testWidgets('compact header exposes every day data view without overflow', (
  tester,
) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  final repository = InMemoryMindmapRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: DayPage(date: DateTime(2026, 8, 8))),
    ),
  );
  await tester.pumpAndSettle();

  expect(tester.takeException(), isNull);
  expect(find.byKey(const Key('mobile-compact-header')), findsOneWidget);
  expect(find.byKey(const ValueKey('day-mobile-view-menu')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('day-mobile-view-menu')));
  await tester.pumpAndSettle();
  expect(find.text('Canvas'), findsOneWidget);
  expect(find.text('Board'), findsOneWidget);
  expect(find.text('Table'), findsOneWidget);
});
```

Add to `day_page_test.dart` a 768-width test selecting Table then Board through visible controls, asserting corresponding stable keys `day-table-view` and `day-board-view`, and no exception. Add a characterization assertion that switching away from canvas and back keeps same `MindmapCanvas.board?.viewport` object/value when no canvas mutation occurs.

- [ ] **Step 3: Run focused tests before implementation**

Run:

```bash
flutter test test/features/calendar/day_page_mobile_layout_test.dart --plain-name "compact header exposes every day data view without overflow"
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage switches data views at medium width"
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage view switching preserves canvas viewport"
```

Expected: mobile stable menu/key contracts fail; viewport characterization must pass before and after.

- [ ] **Step 4: Implement adaptive mode controls and preserve flush boundary**

Use existing `_setViewMode` for every selection so shared-preference persistence remains exact. Compact `_MobileCompactHeader` gets `PopupMenuButton<_DayViewMode>(key: ValueKey('day-mobile-view-menu'))` listing Canvas/Timeline/Board/Table. Medium non-canvas app bar uses icon/menu when segmented labels do not fit; expanded keeps native `SegmentedButton`. Never assign `_viewMode` directly from new controls; call `_setViewMode` so preference behavior remains centralized.

Before navigation/day change keep existing `_flushInlineWorkspace` calls exact. Do not alter `_canvasKey`, `MindmapCanvas` constructor, board providers, geometry callbacks, selection callbacks, overlay offsets, or view-mode enum names. Replace scale-down `FittedBox` dependency where possible with width-driven action grouping and overflow menu, retaining Copy, context switcher, undo/redo, history, and settings actions.

Add keys directly on existing board/table roots; do not wrap canvas in a rebuilding key.

- [ ] **Step 5: Run header, persistence, and canvas boundary tests**

Run:

```bash
flutter test test/features/calendar/day_page_mobile_layout_test.dart
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage switches data views at medium width"
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage table project edit does not reuse disposed controller"
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage view switching preserves canvas viewport"
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage persists canvas viewport without undo activity"
```

Expected: PASS; no controller disposal, viewport, or mode persistence regression.

- [ ] **Step 6: Format and commit only three task files**

Run:

```bash
dart format lib/features/calendar/day_page.dart test/features/calendar/day_page_mobile_layout_test.dart test/features/calendar/day_page_test.dart
git diff --check -- lib/features/calendar/day_page.dart test/features/calendar/day_page_mobile_layout_test.dart test/features/calendar/day_page_test.dart
git add -- lib/features/calendar/day_page.dart test/features/calendar/day_page_mobile_layout_test.dart test/features/calendar/day_page_test.dart
git diff --cached --check
git commit -m "feat: adapt day page data view controls"
```

Expected: no mindmap implementation file staged.

### Task 9: DayPage Board and Table chrome with mutation lock

**Files:**
- Modify: `lib/features/calendar/day_page.dart:9766-10690`
- Modify: `test/features/calendar/day_page_test.dart`

**Interfaces:**
- Consumes: `_DayNodeBoardView`, `_DayBoardColumn`, `_DayBoardCard`, `_DayNodeTableView`, `InlineNodeDraftPatch`, latest-node merge callbacks supplied by parent, and `NodeUpdateCallback`.
- Produces: unchanged board status mutation, table edits/sort/filter, latest-node merge, selection, pin/archive/priority actions; stable board/table semantic regions.

- [ ] **Step 1: Review dirty Board/Table sections**

Run:

```bash
git status --short
git diff -- lib/features/calendar/day_page.dart test/features/calendar/day_page_test.dart
```

Expected: no edits outside Board/Table sections during task.

- [ ] **Step 2: Add board drag and table behavior tests**

Add tests using seeded open node:

```dart
testWidgets('DayPage board drag moves node without changing canvas geometry', (
  tester,
) async {
  final day = DateTime(2026, 8, 8);
  final source = MindmapNode.create(
    id: 'drag-task',
    type: NodeType.task,
    title: 'Drag task',
    day: day,
    status: NodeStatus.open,
    position: const CanvasPosition(120, 240),
    now: day,
  );
  final repository = InMemoryMindmapRepository(seedNodes: [source]);
  await pumpDayPage(tester, repository: repository, day: day);
  await tester.tap(find.text('Board'));
  await tester.pumpAndSettle();

  final gesture = await tester.startGesture(
    tester.getCenter(find.text('Drag task')),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  await gesture.moveTo(tester.getCenter(find.text('Doing')));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();

  final updated = await repository.getNode('drag-task');
  expect(updated?.status, NodeStatus.doing);
  expect(updated?.position, source.position);
});
```

Add table test selecting `Priority`, changing row priority via existing editor/menu, then asserting repository title/day/position unchanged and priority changed. Use actual existing test pump helper names found during execution; if helper is `_pumpDayPage`, use it exactly rather than creating a duplicate.

- [ ] **Step 3: Run characterization tests**

Run:

```bash
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage board drag moves node without changing canvas geometry"
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage table edit preserves unrelated node fields"
```

Expected: tests characterize current mutation contract; any failure must be fixed in test setup before visual implementation, not by changing domain behavior.

- [ ] **Step 4: Apply native data-view composition**

For Board, retain horizontal scroll, all `NodeStatus.values`, `DragTarget<MindmapNode>`, `LongPressDraggable<MindmapNode>`, and exact `copyWith` status/isDone/progress logic. Replace raw radii `18/14` with token radiusContainer/radiusElement, semantic surfaces, one-pixel borders, zero card elevation, restrained drag feedback elevation, 44 action target, and explicit semantic labels for column/card/move state. Add `ValueKey('day-board-view')` to root.

For Table, keep quick-view counts, `_filteredNodes`, `_sortNodes`, sort enum names, editing callbacks, and horizontally scrollable table behavior. Use one bordered surface, native `DataTable`/existing row composition, semantic column labels, compact visuals with 44 targets, and hide only optional columns at narrow nested widths; never turn each row into a card. Add `ValueKey('day-table-view')` to root.

Do not modify parent `InlineNodeDraftPatch.between(...).mergeInto(...)` save sequence.

- [ ] **Step 5: Run board/table and inline-save regressions**

Run:

```bash
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage board drag moves node without changing canvas geometry"
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage table edit preserves unrelated node fields"
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage table project edit does not reuse disposed controller"
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage direct NodeShell preset persists through canvas"
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage deletes drag-selected nodes and supports undo"
```

Expected: PASS; geometry and canvas mutation behavior unchanged.

- [ ] **Step 6: Format and commit Board/Table task**

Run:

```bash
dart format lib/features/calendar/day_page.dart test/features/calendar/day_page_test.dart
git diff --check -- lib/features/calendar/day_page.dart test/features/calendar/day_page_test.dart
git add -- lib/features/calendar/day_page.dart test/features/calendar/day_page_test.dart
git diff --cached --check
git commit -m "feat: polish day board and table views"
```

Expected: exact two paths only.

### Task 10: Daily and workspace canvas chrome boundary

**Files:**
- Modify: `lib/features/calendar/widgets/day_canvas_tab_header.dart`
- Modify: `test/features/calendar/day_canvas_tab_header_test.dart`
- Modify: `lib/features/workspace/workspace_detail_page.dart:559-3158`
- Modify: `test/features/workspace/workspace_detail_page_test.dart:180-1484`
- Modify: `test/features/calendar/day_page_test.dart:42-210`

**Interfaces:**
- Consumes: `DayCanvasTabHeader` public constructor/callbacks, workspace canvas toolbar callbacks, `MindmapCanvas`, `CanvasBoard`, canvas providers/repositories, and existing board/workshop/voting routes.
- Produces: polished tabs/toolbars/dialog chrome only; identical board IDs, viewport, object geometry, selection, collaboration, voting, and workshop operations.

- [ ] **Step 1: Audit dirty canvas-adjacent files carefully**

Run:

```bash
git status --short
git diff -- lib/features/calendar/widgets/day_canvas_tab_header.dart test/features/calendar/day_canvas_tab_header_test.dart lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart test/features/calendar/day_page_test.dart
```

Expected: identify existing canvas work and avoid replacing any callback/repository code.

- [ ] **Step 2: Add chrome-only tests and geometry characterization**

In `day_canvas_tab_header_test.dart`, add 320-width test asserting no overflow, active tab selected semantics, `onSelectBoard` fires exact ID, and all visible icon buttons have hit-test size at least 44x44.

In `workspace_detail_page_test.dart`, add test that pumps an initial board with viewport and one object geometry, toggles any polished toolbar/menu, then reads `MindmapCanvas` and repository:

```dart
expect(canvas.board?.viewport, initial.viewport);
expect(canvas.board?.objects.single.geometry, initial.objects.single.geometry);
```

In `day_page_test.dart`, extend `canvas context menu follows Astryx menu geometry` or add a companion test asserting visual chrome changes do not alter menu row `minimumTarget` nor selected board/viewport.

- [ ] **Step 3: Run characterization tests before chrome edits**

Run:

```bash
flutter test test/features/calendar/day_canvas_tab_header_test.dart
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "workspace canvas chrome preserves viewport and object geometry"
flutter test test/features/calendar/day_page_test.dart --plain-name "canvas context menu follows Astryx menu geometry"
```

Expected: compact header styling test may fail; viewport/object geometry characterizations must pass.

- [ ] **Step 4: Restyle chrome only**

For `DayCanvasTabHeader`, preserve constructor and every callback. Use `TabBar`/`Material` composition or existing tabs with theme roles, token radiusElement, border-first surface, selected/focused/hovered states, horizontal scroll at 320, and minimum target 44. Keep board IDs and action semantics.

In workspace canvas section, modify only toolbar, tab strip, board dashboard cards, dialogs, sheets, menus, and status banners. Use themed Material components, token radii, semantic surfaces, zero static elevation and restrained menu/dialog/drag elevation. Do not alter `_currentBoard`, `_selectedBoardId`, `_canvasKeys`, `_history`, repository methods, `_recordCanvasMutation`, `MindmapCanvas` arguments, viewport callbacks, object callbacks, workshop/voting state machines, nested-board operations, or collaboration permissions.

Do not edit `lib/features/mindmap/presentation/mindmap_canvas.dart`; canvas internals belong Phase 6.

- [ ] **Step 5: Run canvas preservation suite**

Run:

```bash
flutter test test/features/calendar/day_canvas_tab_header_test.dart
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "workspace canvas chrome preserves viewport and object geometry"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "project canvas persists viewport without activity history"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "opens exact shared project canvas from route state"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "project canvas manages voting session and results"
flutter test test/features/workspace/workspace_detail_page_test.dart --plain-name "project canvas runs facilitated workshop stages"
flutter test test/features/calendar/day_page_test.dart --plain-name "canvas context menu follows Astryx menu geometry"
flutter test test/features/calendar/day_page_test.dart --plain-name "DayPage persists canvas viewport without undo activity"
```

Expected: PASS; exact viewport, geometry, board ID, permissions, and workflows preserved.

- [ ] **Step 6: Format and commit five exact files**

Run:

```bash
dart format lib/features/calendar/widgets/day_canvas_tab_header.dart test/features/calendar/day_canvas_tab_header_test.dart lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart test/features/calendar/day_page_test.dart
git diff --check -- lib/features/calendar/widgets/day_canvas_tab_header.dart test/features/calendar/day_canvas_tab_header_test.dart lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart test/features/calendar/day_page_test.dart
git add -- lib/features/calendar/widgets/day_canvas_tab_header.dart test/features/calendar/day_canvas_tab_header_test.dart lib/features/workspace/workspace_detail_page.dart test/features/workspace/workspace_detail_page_test.dart test/features/calendar/day_page_test.dart
git diff --cached --check
git commit -m "feat: polish workspace canvas chrome"
```

Expected: exactly five paths; no `mindmap_canvas.dart` or domain file.

### Task 11: Cross-surface accessibility, variants, and regression gate

**Files:**
- Modify: `test/features/insights/insights_page_test.dart`
- Modify: `test/features/workspace/workspaces_page_test.dart`
- Modify: `test/features/workspace/workspace_detail_page_test.dart`
- Modify: `test/features/calendar/calendar_page_test.dart`
- Modify: `test/features/calendar/day_page_mobile_layout_test.dart`

**Interfaces:**
- Consumes: final Phase 4/5 surfaces, `AppTheme.forVariant`, `AppThemeVariant.values`, Material semantics, and all existing feature tests.
- Produces: representative width/light-dark/seven-variant/text-scale/reduced-motion regression matrix; no production change.

- [ ] **Step 1: Inspect dirty test baseline**

Run:

```bash
git status --short
git diff -- test/features/insights/insights_page_test.dart test/features/workspace/workspaces_page_test.dart test/features/workspace/workspace_detail_page_test.dart test/features/calendar/calendar_page_test.dart test/features/calendar/day_page_mobile_layout_test.dart
```

Expected: tests only in this task.

- [ ] **Step 2: Add bounded variant/accessibility matrix**

In each page test file, add one representative smoke loop rather than Cartesian explosion. Example for Calendar:

```dart
for (final variant in AppThemeVariant.values) {
  testWidgets('CalendarPage renders ${variant.name} light and dark', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final repository = InMemoryMindmapRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: AppTheme.forVariant(variant, brightness: Brightness.light),
            darkTheme: AppTheme.forVariant(variant, brightness: Brightness.dark),
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: const CalendarPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
```

Use actual `AppTheme.forVariant` signature from current theme file during execution. Across five files cover once each: 320 and 1440 widths, textScaler 2.0, `disableAnimations: true`, keyboard activation, visible semantics labels, and light/dark. Do not duplicate all dimensions on every page.

- [ ] **Step 3: Run new matrix tests**

Run each exact `--plain-name` added in Step 2, then:

```bash
flutter test test/features/insights/insights_page_test.dart test/features/workspace/workspaces_page_test.dart test/features/workspace/workspace_detail_page_test.dart test/features/calendar/calendar_page_test.dart test/features/calendar/day_page_mobile_layout_test.dart
```

Expected: PASS with no overflow, semantics exception, or animation hang.

- [ ] **Step 4: Run focused Phase 4/5 suite**

Run:

```bash
flutter test test/features/insights test/features/workspace test/features/calendar
```

Expected: all tests pass. If an unrelated pre-existing failure appears, record exact failing test and output; do not change domain behavior to make visual tests pass.

- [ ] **Step 5: Format and analyze**

Run:

```bash
dart format --set-exit-if-changed lib/features/insights lib/features/workspace lib/features/calendar test/features/insights test/features/workspace test/features/calendar
flutter analyze
```

Expected: formatter exit 0 and analyzer no new issues. Because workspace is dirty, classify analyzer diagnostics against `git diff --name-only`; do not fix unrelated files.

- [ ] **Step 6: Run full repository test gate**

Run:

```bash
flutter test
```

Expected: all pass. Existing unrelated failure must be documented with exact command/test/error and left untouched.

- [ ] **Step 7: Commit test matrix only**

Run:

```bash
git diff --check -- test/features/insights/insights_page_test.dart test/features/workspace/workspaces_page_test.dart test/features/workspace/workspace_detail_page_test.dart test/features/calendar/calendar_page_test.dart test/features/calendar/day_page_mobile_layout_test.dart
git add -- test/features/insights/insights_page_test.dart test/features/workspace/workspaces_page_test.dart test/features/workspace/workspace_detail_page_test.dart test/features/calendar/calendar_page_test.dart test/features/calendar/day_page_mobile_layout_test.dart
git diff --cached --check
git commit -m "test: cover adaptive dashboard and calendar surfaces"
```

Expected: test-only commit, maximum five files.

## Completion Checklist

- Insights dashboard, workspace index/detail, Calendar, DayPage board/table, and canvas chrome share semantic Material 3 border-first hierarchy.
- Compact, medium, expanded widths work near 320, 768, 1024, and 1440 logical pixels.
- Seven Astryx variants and both brightness modes render without changing palette/font mapping.
- Search, filters, sorting, exports, routes, keyboard shortcuts, context actions, hover, long-press, semantics, text scaling, and reduced motion remain usable.
- Calendar drag/drop moves exact node day, same-day drop remains no-op, and Undo restores original day.
- Workspace and DayPage Kanban drag/drop preserve exact status/progress rules and unrelated node fields.
- Workspace manual reorder remains persisted.
- Canvas board IDs, viewport, object geometry, selection, gestures, workshop, voting, collaboration, and repository operations remain unchanged.
- No production file outside listed task paths, no domain/application/generated file, and no dirty unrelated workspace change is staged.
- `dart format --set-exit-if-changed ...`, `flutter analyze`, focused suites, and `flutter test` pass or pre-existing unrelated failures are recorded exactly.

# Material 3 Adaptive Shell and Standard Product Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Memoles shared shell, navigation, search, settings, capture, focus, onboarding, serta sync/recovery dengan Material 3 adaptive bergaya shadcn tanpa mengubah route, domain logic, persistence, canvas behavior, atau backup semantics.

**Architecture:** `AdaptiveScaffold` tetap menjadi pemilik navigation, global shortcuts, quick capture overlay, dan desktop menu dispatch. Feature pages tetap memiliki state serta orchestration sendiri, tetapi memakai native Material surfaces dan shared behavior-rich status primitives; perubahan dipecah per cohesive surface agar setiap task dapat diuji dan direview sendiri. Foundation dari `2026-08-08-material3-adaptive-shadcn-foundation.md` harus sudah selesai sebelum plan ini dijalankan.

**Tech Stack:** Flutter Material 3, Dart 3.11.4, Riverpod, go_router, flutter_test, existing in-memory repositories.

## Global Constraints

- Pertahankan tujuh varian warna/font Astryx dan light/dark mode.
- Jangan tambah dependency, `Shadcn*` widget family, CSS, React, atau runtime web.
- Gunakan native `NavigationDrawer`, `AppBar`, `Card`, `ListTile`, `Dialog`, `TextField`, `DropdownButtonFormField`, buttons, progress indicators, `Tooltip`, dan `SnackBar`.
- Minimum target interaksi tetap 44 logical pixels; focus harus terlihat dan status/error tidak boleh bergantung pada warna saja.
- Compact mencakup lebar sampai 768; representative verification widths: 320, 768, 1024, dan 1440 logical pixels.
- Pertahankan text scaling, RTL, keyboard-only flow, pointer hover/context actions, touch safe areas, dan reduced motion.
- Jangan ubah domain logic, persistence, routes, sync/backup behavior, destructive confirmation rules, canvas coordinates, selection geometry, gestures, atau painters.
- Jangan menimpa atau membundel perubahan user yang belum di-commit. Saat audit, `lib/shared/layout/adaptive_scaffold.dart`, `lib/features/settings/settings_page.dart`, dan `test/shared/layout/adaptive_scaffold_test.dart` modified; beberapa shared/focus/capture files untracked. Re-read `git status --short` dan diff setiap file sebelum mengedit.
- Ikuti TDD ketat: tulis satu behavior test, jalankan dan lihat failure yang benar, tulis perubahan production minimal, lalu jalankan focused test sampai PASS.
- Jangan hand-edit `lib/dataconnect_generated/`.

## File Map

- `lib/shared/layout/adaptive_scaffold.dart`: shell adaptive, active destination, global shortcuts, mobile drawer, desktop/web top navigation.
- `lib/shared/layout/desktop_window_chrome.dart`: Windows title bar, native window controls, desktop menus.
- `lib/shared/widgets/animated_empty_state.dart`: shared empty composition dengan reduced-motion behavior.
- `lib/shared/widgets/error_message.dart`: shared inline error/status composition dengan semantics.
- `lib/shared/widgets/skeleton_loader.dart`: shared loading composition dengan reduced-motion behavior.
- `lib/features/search/presentation/search_page.dart`: search page structure dan async state switching.
- `lib/features/search/presentation/search_filter_bar.dart`: responsive filter controls.
- `lib/features/search/presentation/search_result_tile.dart`: semantic result row.
- `lib/features/settings/settings_page.dart`: settings page hierarchy dan existing controls/dialog entry points.
- `lib/features/capture/presentation/quick_capture_dialog.dart`: quick capture form, duplicate state, loading/error, save action.
- `lib/features/command/presentation/quick_capture_dock.dart`: shell capture presentation dan dismiss/focus behavior.
- `lib/features/focus/focus_page.dart`: adaptive focus page hierarchy.
- `lib/features/focus/widgets/focus_zen_view.dart`: focused fullscreen state dan exit behavior.
- `lib/features/onboarding/onboarding_overlay.dart`: first-launch modal surface dan focus flow.
- `lib/features/sync/presentation/recovery_center.dart`: sync/recovery status, forms, previews, confirmations, destructive actions.

---

### Task 1: Kunci adaptive shell dan navigation contract

**Files:**
- Modify: `test/shared/layout/adaptive_scaffold_test.dart:12-194`
- Modify: `lib/shared/layout/adaptive_scaffold.dart:27-593`

**Interfaces:**
- Consumes: `AppRoute`, `appRouteLocation(BuildContext, AppRoute)`, `LayoutConstants.mobileBreakpoint`, `quickCaptureVisibleProvider`, `desktopMenuController`.
- Produces: existing `AdaptiveScaffold({required Widget body, bool? windowsDesktop})`, `AstryxTopNav({required AppRoute route})`, mobile drawer keys, top-nav keys, dan unchanged shortcuts `Ctrl/Cmd+K`, `Ctrl/Cmd+Q`, `Ctrl/Cmd+T`, `Ctrl/Cmd+B`.

- [ ] **Step 1: Tambahkan failing tests untuk batas width, destination, semantics, dan text scaling**

Tambahkan `/search` ke route list test lalu tambahkan tests berikut:

```dart
testWidgets('shell switches at compact boundary without overflow', (tester) async {
  for (final width in <double>[320, 768, 769, 1024, 1440]) {
    await pumpShell(tester, width: width, location: '/search');
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('astryx-mobile-menu')),
      width <= 768 ? findsOneWidget : findsNothing,
    );
  }
});

testWidgets('drawer selection follows grouped route order', (tester) async {
  await pumpShell(tester, width: 320, location: '/settings');
  await tester.tap(find.byKey(const ValueKey('astryx-mobile-menu')));
  await tester.pumpAndSettle();
  final drawer = tester.widget<NavigationDrawer>(find.byType(NavigationDrawer));
  expect(drawer.selectedIndex, 9);
  expect(find.byKey(const ValueKey('astryx-drawer-settings')), findsOneWidget);
});

testWidgets('shell remains usable at two times text scale', (tester) async {
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await pumpShell(tester, width: 320);
  expect(find.byKey(const ValueKey('astryx-mobile-menu')), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Jalankan test untuk membuktikan failure**

Run: `flutter test test/shared/layout/adaptive_scaffold_test.dart`

Expected: FAIL karena `NavigationDrawer.selectedIndex` memakai index global `AppRoute.values`, sedangkan children memakai grouped subset; 320px dengan text scale 2 juga boleh menunjukkan overflow sebelum header disederhanakan.

- [ ] **Step 3: Implementasikan satu ordered destination list dan shell compact minimal**

Di `adaptive_scaffold.dart`, tambahkan satu list yang menjadi sumber drawer index dan children:

```dart
const _navigationRoutes = <AppRoute>[
  ..._primaryRoutes,
  ..._analysisRoutes,
  ..._systemRoutes,
];
```

Ubah drawer menjadi:

```dart
selectedIndex: _navigationRoutes.indexOf(route),
onDestinationSelected: (index) {
  Navigator.of(context).pop();
  context.go(appRouteLocation(context, _navigationRoutes[index]));
},
```

Pertahankan section labels dan keys. Pada `_MobileShellHeader`, gunakan `theme.textTheme.titleLarge`, `Flexible` untuk timer pill, dan hilangkan ukuran/font lokal; jangan hapus quick capture atau command palette actions. Pada `AstryxTopNav`, gunakan `theme.textTheme.labelLarge`/`bodySmall`, `tokens.radiusElement`, semantic surfaces/borders, dan native `Tooltip`/`InkWell`; jangan ubah menu action mapping.

- [ ] **Step 4: Jalankan focused test sampai PASS**

Run: `flutter test test/shared/layout/adaptive_scaffold_test.dart`

Expected: PASS pada 320/768/769/1024/1440, route settings terpilih, quick capture tetap toggle, dan tidak ada overflow pada text scale 2.

- [ ] **Step 5: Commit task**

```bash
git add lib/shared/layout/adaptive_scaffold.dart test/shared/layout/adaptive_scaffold_test.dart
git commit -m "feat: polish adaptive shell navigation"
```

### Task 2: Selaraskan Windows desktop chrome dengan shell contract

**Files:**
- Modify: `test/shared/layout/desktop_window_chrome_test.dart`
- Modify: `lib/shared/layout/desktop_window_chrome.dart:15-540`

**Interfaces:**
- Consumes: `DesktopWindowController`, `DesktopMenuController`, `AppSemanticColors`, `AppDesignTokens`.
- Produces: unchanged `DesktopWindowChrome`, `DesktopMenuAction`, controller callbacks, keys `windows-title-bar`, `windows-drag-region`, `windows-minimize`, `windows-maximize`, `windows-restore`, `windows-close`.

- [ ] **Step 1: Tulis failing tests untuk native controls dan keyboard-visible menus**

```dart
testWidgets('window controls keep 44 pixel targets and semantic labels', (tester) async {
  await tester.pumpWidget(testApp(enabled: true));
  await tester.pumpAndSettle();
  for (final key in <String>['windows-minimize', 'windows-maximize', 'windows-close']) {
    final finder = find.byKey(ValueKey(key));
    expect(tester.getSize(finder), const Size(44, 44));
  }
  expect(tester.getSemantics(find.byKey(const ValueKey('windows-close'))).label, 'Close');
});

testWidgets('desktop menu uses themed popup without ornamental shadow', (tester) async {
  await tester.pumpWidget(testApp(enabled: true));
  await tester.tap(find.byKey(const ValueKey('windows-menu-tools')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('windows-menu-recoveryCenter')), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

Gunakan existing `testApp`/fake controller helper di file; sesuaikan nama helper hanya bila file sudah memakai nama lain.

- [ ] **Step 2: Verifikasi RED**

Run: `flutter test test/shared/layout/desktop_window_chrome_test.dart`

Expected: FAIL pada finder semantics/size bila key berada di wrapper yang belum berukuran 44 atau popup key/casing belum sesuai contract.

- [ ] **Step 3: Terapkan styling minimal tanpa mengubah window behavior**

Gunakan `tokens.radiusInner`/`tokens.radiusElement`, `semantic.surface`, `semantic.surfaceRaised`, `semantic.border`, `semantic.focusRing`, dan theme text roles. Pertahankan restrained popup elevation dari global `MenuTheme`; hapus `fontSize`, radius literal, dan duplicate popup elevation lokal bila global theme sudah menyediakannya. Jangan ubah `_WindowManagerController` atau urutan callbacks.

- [ ] **Step 4: Verifikasi GREEN**

Run: `flutter test test/shared/layout/desktop_window_chrome_test.dart test/shared/layout/adaptive_scaffold_test.dart`

Expected: PASS; minimize/maximize/restore/close, drag, double-click, secondary click, dan menu dispatch tetap bekerja.

- [ ] **Step 5: Commit task**

```bash
git add lib/shared/layout/desktop_window_chrome.dart test/shared/layout/desktop_window_chrome_test.dart
git commit -m "feat: align desktop window chrome"
```

### Task 3: Gunakan shared loading, empty, dan error surfaces pada search

**Files:**
- Modify: `lib/shared/widgets/animated_empty_state.dart`
- Modify: `lib/shared/widgets/error_message.dart`
- Modify: `lib/features/search/presentation/search_page.dart:38-117`
- Modify: `test/features/search/presentation/search_page_test.dart`

**Interfaces:**
- Consumes: existing `AsyncValue<List<SearchResult>>`, `AnimatedEmptyState`, `ErrorMessage`, `SearchResultTile`, search provider.
- Produces: search loading key `search-loading`, empty key `search-empty`, error key `search-error`, unchanged query URL replacement dan result navigation.

- [ ] **Step 1: Tambahkan tests async-state dan semantics**

```dart
testWidgets('search exposes loading state without empty copy', (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [searchResultsProvider.overrideWith((ref, query) => Completer<List<SearchResult>>().future)],
    child: const MaterialApp(home: SearchPage(initialQuery: 'pending')),
  ));
  await tester.pump();
  expect(find.byKey(const ValueKey('search-loading')), findsOneWidget);
  expect(find.text('No results'), findsNothing);
});

testWidgets('search empty state explains how to recover', (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [searchResultsProvider.overrideWith((ref, query) async => const [])],
    child: const MaterialApp(home: SearchPage(initialQuery: 'missing')),
  ));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);
  expect(find.text('No results for “missing”'), findsOneWidget);
  expect(find.text('Try fewer words or clear filters.'), findsOneWidget);
});

testWidgets('search error state has alert semantics', (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [searchResultsProvider.overrideWith((ref, query) => Future.error(StateError('index unavailable')))],
    child: const MaterialApp(home: SearchPage()),
  ));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('search-error')), findsOneWidget);
  expect(tester.getSemantics(find.text('Search unavailable')).hasFlag(SemanticsFlag.isLiveRegion), isTrue);
});
```

Tambahkan `dart:async` import di test.

- [ ] **Step 2: Verifikasi RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart`

Expected: FAIL karena keys, recovery copy, dan live-region semantics belum ada.

- [ ] **Step 3: Implementasikan state composition minimal**

Ubah `_SearchResults` agar menerima `queryText` dan gunakan:

```dart
loading: () => const Center(
  child: Semantics(
    key: ValueKey('search-loading'),
    liveRegion: true,
    label: 'Searching',
    child: CircularProgressIndicator(),
  ),
),
error: (error, stackTrace) => ErrorMessage(
  key: const ValueKey('search-error'),
  title: 'Search unavailable',
  message: '$error',
),
data: (items) => items.isEmpty
    ? AnimatedEmptyState(
        key: const ValueKey('search-empty'),
        icon: Icons.search_off_outlined,
        title: queryText.trim().isEmpty
            ? 'Search your workspace'
            : 'No results for “${queryText.trim()}”',
        message: 'Try fewer words or clear filters.',
      )
    : ListView.builder(...),
```

Pastikan `ErrorMessage` memakai `Semantics(container: true, liveRegion: true)` dan theme roles; pastikan `AnimatedEmptyState` memakai `MediaQuery.disableAnimationsOf(context)` untuk melewati animation dan tidak memakai ornamental shadow. Pertahankan public constructor signatures yang sudah dipakai call sites; tambahkan optional parameters hanya bila diperlukan oleh code exact di atas.

- [ ] **Step 4: Verifikasi GREEN**

Run: `flutter test test/features/search/presentation/search_page_test.dart test/shared/widgets/animated_empty_state_test.dart`

Expected: PASS untuk loading, empty, error, existing filters, preview, dan extraction state.

- [ ] **Step 5: Commit task**

```bash
git add lib/shared/widgets/animated_empty_state.dart lib/shared/widgets/error_message.dart lib/features/search/presentation/search_page.dart test/features/search/presentation/search_page_test.dart
git commit -m "feat: polish search async states"
```

### Task 4: Poles search filters dan result rows secara responsive

**Files:**
- Modify: `lib/features/search/presentation/search_filter_bar.dart`
- Modify: `lib/features/search/presentation/search_result_tile.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`

**Interfaces:**
- Consumes: existing `SearchFilters`, `SearchResult`, `ValueChanged<SearchFilters>`, `VoidCallback onTap`.
- Produces: unchanged filter behavior; result rows expose button semantics dan full title through tooltip/semantic label saat visual text terpotong.

- [ ] **Step 1: Tambahkan responsive dan semantics tests**

```dart
testWidgets('search controls fit compact and expanded widths', (tester) async {
  for (final width in <double>[320, 768, 1024, 1440]) {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(_searchApp(results: const []));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
});

testWidgets('search result is one semantic button with full label', (tester) async {
  await tester.pumpWidget(_searchApp(results: [result]));
  await tester.pumpAndSettle();
  final semantics = tester.getSemantics(find.text('Launch brief'));
  expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
  expect(semantics.label, contains('Launch brief'));
  expect(semantics.label, contains('Ship global search'));
});
```

Extract `_searchApp({required List<SearchResult> results})` dan shared `result` fixture di test file agar setup tidak diduplikasi.

- [ ] **Step 2: Verifikasi RED**

Run: `flutter test test/features/search/presentation/search_page_test.dart`

Expected: FAIL pada 320px overflow atau result semantics.

- [ ] **Step 3: Implementasikan layout content-driven**

Di `SearchFilterBar`, gunakan `LayoutBuilder`: compact memakai horizontal `SingleChildScrollView` berisi `Row`; expanded memakai `Wrap(spacing: 8, runSpacing: 8)`. Jangan mengubah filter values atau callbacks. Di `SearchResultTile`, gunakan native `Card` + `ListTile`, `Semantics(button: true, label: '${document.title}. ${document.snippet}')`, `Tooltip(message: document.title)`, dan theme text roles; node-type color hanya pada icon/dot.

- [ ] **Step 4: Verifikasi GREEN**

Run: `flutter test test/features/search/presentation/search_page_test.dart`

Expected: PASS pada empat widths, filter updates tetap menghasilkan `SearchQuery`, dan result tetap membuka existing destination.

- [ ] **Step 5: Commit task**

```bash
git add lib/features/search/presentation/search_filter_bar.dart lib/features/search/presentation/search_result_tile.dart test/features/search/presentation/search_page_test.dart
git commit -m "feat: make search surfaces adaptive"
```

### Task 5: Susun hierarchy Settings tanpa memecah behavior besar

**Files:**
- Modify: `lib/features/settings/settings_page.dart:36-347`
- Modify: `test/features/settings/settings_page_test.dart`

**Interfaces:**
- Consumes: all existing Riverpod providers, existing private manager cards, dialogs, import/export/clear callbacks.
- Produces: unchanged `SettingsPage`; page key `settings-page`, constrained content max width `960`, section header semantics, responsive appearance controls, unchanged control keys.

- [ ] **Step 1: Tulis tests hierarchy, width, dan destructive styling**

```dart
testWidgets('SettingsPage is constrained and usable at representative widths', (tester) async {
  for (final width in <double>[320, 768, 1024, 1440]) {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(_settingsTestApp());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }
});

testWidgets('clear data confirmation uses destructive action color', (tester) async {
  await tester.pumpWidget(_settingsTestApp());
  await tester.pumpAndSettle();
  await _tapKey(tester, 'data-management-toggle');
  await tester.tap(find.text('Clear All Data'));
  await tester.pumpAndSettle();
  final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete Everything'));
  final foreground = button.style?.foregroundColor?.resolve(<WidgetState>{});
  expect(foreground, Theme.of(tester.element(find.byType(AlertDialog))).colorScheme.onError);
});
```

- [ ] **Step 2: Verifikasi RED**

Run: `flutter test test/features/settings/settings_page_test.dart`

Expected: FAIL karena page key/constrained adaptive layout belum ada dan clear action masih `TextButton` lokal.

- [ ] **Step 3: Terapkan page hierarchy minimal**

Bungkus list dengan `Center` + `ConstrainedBox(maxWidth: 960)` dan beri `ListView` key `settings-page`. Gunakan `LayoutBuilder` hanya untuk Appearance controls: width `< 600` memakai `Column`; selainnya `Row`. Gunakan `Card`/`ListTile` dan global theme; hapus `_settingsPanelDecoration` dari overview/managers saat native `Card` cukup, tetapi pertahankan behavior-rich private widgets dan all existing keys. Ubah clear confirmation action menjadi:

```dart
FilledButton(
  style: FilledButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.error,
    foregroundColor: Theme.of(context).colorScheme.onError,
  ),
  onPressed: () => Navigator.pop(context, true),
  child: const Text('Delete Everything'),
),
```

Jangan mengubah restore-point creation sebelum deletion, import parsing, provider invalidation, atau manager persistence.

- [ ] **Step 4: Verifikasi GREEN**

Run: `flutter test test/features/settings/settings_page_test.dart`

Expected: seluruh existing settings behavior dan tests baru PASS pada compact/expanded widths.

- [ ] **Step 5: Commit task**

```bash
git add lib/features/settings/settings_page.dart test/features/settings/settings_page_test.dart
git commit -m "feat: polish adaptive settings surfaces"
```

### Task 6: Poles quick capture dialog dan shell dock

**Files:**
- Modify: `lib/features/capture/presentation/quick_capture_dialog.dart:11-358`
- Modify: `lib/features/command/presentation/quick_capture_dock.dart`
- Modify: `test/features/capture/presentation/quick_capture_dialog_test.dart`
- Modify: `test/features/command/presentation/quick_capture_dock_test.dart`

**Interfaces:**
- Consumes: `CapturePayload`, `CaptureDestination`, `DuplicateDetector`, `CaptureService`, `quickCaptureVisibleProvider`.
- Produces: unchanged save/duplicate behavior; native `FilledButton` save action, semantic loading/error/duplicate status, Escape dismiss dan first-field focus in dock.

- [ ] **Step 1: Ubah tests untuk contract native button dan status semantics**

```dart
testWidgets('capture fits compact width and exposes progress status', (tester) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(buildTestableWidget());
  await tester.pump();
  expect(find.byKey(const Key('quick_capture_save_button')), findsOneWidget);
  expect(tester.takeException(), isNull);
});

testWidgets('duplicate warning is a live status and copy uses filled action', (tester) async {
  await mindmapRepository.saveNode(existingNode);
  await tester.pumpWidget(buildTestableWidget());
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('quick_capture_url_field')), 'https://example.com/duplicate');
  await tester.pumpAndSettle();
  expect(tester.getSemantics(find.text('Duplicate content detected')).hasFlag(SemanticsFlag.isLiveRegion), isTrue);
  expect(find.widgetWithText(FilledButton, 'Create Copy'), findsOneWidget);
});
```

Update existing `tester.widget<ElevatedButton>` assertions menjadi `tester.widget<FilledButton>`.

Di dock test tambahkan:

```dart
testWidgets('Escape closes quick capture dock and restores shell', (tester) async {
  await tester.pumpWidget(buildDockApp());
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.byType(QuickCaptureDock), findsNothing);
});
```

- [ ] **Step 2: Verifikasi RED**

Run: `flutter test test/features/capture/presentation/quick_capture_dialog_test.dart test/features/command/presentation/quick_capture_dock_test.dart`

Expected: FAIL karena save/copy masih `ElevatedButton`, duplicate state belum live region, atau Escape belum dismiss.

- [ ] **Step 3: Implementasikan native dialog/form state minimal**

Gunakan `AlertDialog` dengan constrained scrollable content dan actions; gunakan `theme.textTheme.titleLarge`, `FilledButton` untuk Save/Create Copy, `TextButton` untuk Open Existing, semantic `LinearProgressIndicator`, dan `Semantics(liveRegion: true)` untuk errors/duplicate. Gunakan `colorScheme.errorContainer` + `onErrorContainer` dan border; jangan gunakan `Colors.red`. Pertahankan keys, duplicate gate, destination requirement, attachment behavior, exception messages, dan created node result.

Di `QuickCaptureDock`, gunakan `CallbackShortcuts` untuk Escape, `FocusScope(autofocus: true)`, semantic modal container, dan existing provider toggle. Jangan menambah route atau state provider.

- [ ] **Step 4: Verifikasi GREEN**

Run: `flutter test test/features/capture/presentation/quick_capture_dialog_test.dart test/features/command/presentation/quick_capture_dock_test.dart test/shared/layout/adaptive_scaffold_test.dart`

Expected: PASS; save tetap disabled tanpa content/destination dan saat duplicate, Create Copy tetap explicit override, Escape menutup dock.

- [ ] **Step 5: Commit task**

```bash
git add lib/features/capture/presentation/quick_capture_dialog.dart lib/features/command/presentation/quick_capture_dock.dart test/features/capture/presentation/quick_capture_dialog_test.dart test/features/command/presentation/quick_capture_dock_test.dart
git commit -m "feat: polish quick capture surfaces"
```

### Task 7: Jadikan Focus page adaptive tanpa mengubah timer/audio

**Files:**
- Modify: `lib/features/focus/focus_page.dart:16-259`
- Modify: `lib/features/focus/widgets/focus_zen_view.dart`
- Modify: `test/features/focus/focus_timer_test.dart`

**Interfaces:**
- Consumes: `focusTimerProvider`, `focusAudioPlayerServiceProvider`, `allMindmapNodesProvider`, current timer/audio callbacks.
- Produces: unchanged start/pause/skip/reset/select node behavior; adaptive one-column/two-region layout dan semantic Zen exit.

- [ ] **Step 1: Tambahkan widget tests untuk widths dan Zen keyboard flow**

```dart
testWidgets('focus page fits representative widths', (tester) async {
  for (final width in <double>[320, 768, 1024, 1440]) {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(focusTestApp());
    await tester.pumpAndSettle();
    expect(find.text('Focus Mode & Pomodoro'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }
});

testWidgets('Zen mode exposes exit button and Escape returns to focus page', (tester) async {
  await tester.pumpWidget(focusTestApp());
  await tester.tap(find.byTooltip('Mode Zen Fullscreen'));
  await tester.pumpAndSettle();
  expect(find.byTooltip('Exit Zen mode'), findsOneWidget);
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.text('Focus Mode & Pomodoro'), findsOneWidget);
});
```

Tambahkan `flutter/services.dart` import dan gunakan existing provider overrides/helper di file test.

- [ ] **Step 2: Verifikasi RED**

Run: `flutter test test/features/focus/focus_timer_test.dart`

Expected: FAIL pada compact overflow atau Escape exit behavior.

- [ ] **Step 3: Implementasikan adaptive composition minimal**

Gunakan `LayoutBuilder`: `< 900` mempertahankan single column max width 560; `>= 900` memakai `Row` dengan timer/stats di satu `Expanded` dan music/task selection di `Expanded`. Gunakan native `Card` theme tanpa local elevation/color/shape; ganti local title/body styles dengan theme roles. Pertahankan semua provider calls dan callbacks.

Di `FocusZenView`, bungkus root dengan `CallbackShortcuts` untuk Escape dan tombol bertooltip `Exit Zen mode`; gunakan semantic label untuk timer state. Jangan ubah timer math, duration, audio auto-play, atau selected task behavior.

- [ ] **Step 4: Verifikasi GREEN**

Run: `flutter test test/features/focus/focus_timer_test.dart test/features/focus/ambient_sound_test.dart`

Expected: PASS pada representative widths; timer/audio tests tetap lulus.

- [ ] **Step 5: Commit task**

```bash
git add lib/features/focus/focus_page.dart lib/features/focus/widgets/focus_zen_view.dart test/features/focus/focus_timer_test.dart
git commit -m "feat: make focus surfaces adaptive"
```

### Task 8: Sederhanakan onboarding menjadi native adaptive dialog

**Files:**
- Modify: `lib/features/onboarding/onboarding_overlay.dart:14-142`
- Modify: `test/features/onboarding/onboarding_test.dart`

**Interfaces:**
- Consumes: `shouldShowOnboardingProvider`, `dismissOnboarding(WidgetRef)`, existing calendar route.
- Produces: unchanged `OnboardingOverlay`; modal semantics, initial primary-button focus, compact inset, no duplicate shadow/runtime.

- [ ] **Step 1: Tambahkan tests compact, text scale, dan focus**

```dart
testWidgets('onboarding fits compact viewport at two times text scale', (tester) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(_buildApp(shouldShow: true));
  await tester.pumpAndSettle();
  expect(find.text('Create your first node'), findsOneWidget);
  expect(tester.takeException(), isNull);
});

testWidgets('onboarding primary action owns initial focus', (tester) async {
  await tester.pumpWidget(_buildApp(shouldShow: true));
  await tester.pumpAndSettle();
  final button = find.widgetWithText(FilledButton, 'Create your first node');
  expect(Focus.of(tester.element(button)).hasFocus, isTrue);
});
```

- [ ] **Step 2: Verifikasi RED**

Run: `flutter test test/features/onboarding/onboarding_test.dart`

Expected: FAIL pada compact text-scale overflow atau focus assertion.

- [ ] **Step 3: Terapkan native dialog minimal**

Pertahankan outer semantic modal/focus scope, tetapi gunakan global `DialogTheme`: hapus local `backgroundColor`, `elevation`, shape, duplicate `Container.boxShadow`, dan radius page. Gunakan `Dialog(insetPadding: const EdgeInsets.all(16))`, `ConstrainedBox(maxWidth: 420)`, `SingleChildScrollView`, padding 24 compact/32 expanded via `LayoutBuilder`, theme text roles, `FilledButton.icon(autofocus: true)`, dan `TextButton`. Pertahankan `_startFresh` dan `_dismiss` logic exact.

- [ ] **Step 4: Verifikasi GREEN**

Run: `flutter test test/features/onboarding/onboarding_test.dart`

Expected: PASS hidden/shown, compact text scaling, primary focus, dan dismissal/navigation behavior.

- [ ] **Step 5: Commit task**

```bash
git add lib/features/onboarding/onboarding_overlay.dart test/features/onboarding/onboarding_test.dart
git commit -m "feat: polish adaptive onboarding dialog"
```

### Task 9: Poles sync/recovery status dan destructive previews

**Files:**
- Modify: `lib/features/sync/presentation/recovery_center.dart:15-1138`
- Modify: `test/features/sync/presentation/recovery_center_test.dart`

**Interfaces:**
- Consumes: `syncControllerProvider`, `allMindmapNodesProvider`, `drawingDraftCheckpointsProvider`, existing preview/execute APIs.
- Produces: unchanged `RecoveryCenterPage`, preview-before-execute contract, destructive checkbox gates, sync/recovery actions; adaptive section layout dan explicit semantic statuses.

- [ ] **Step 1: Tambahkan tests width, status, dan destructive appearance**

```dart
testWidgets('recovery center fits representative widths', (tester) async {
  final repository = InMemoryMindmapRepository(seedNodes: [_node('local', 'Local node')]);
  for (final width in <double>[320, 768, 1024, 1440]) {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recovery-center')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }
});

testWidgets('sync message is announced as live status', (tester) async {
  await tester.pumpWidget(_app(InMemoryMindmapRepository()));
  await tester.pumpAndSettle();
  final status = find.byKey(const ValueKey('sync-last-message'));
  if (status.evaluate().isNotEmpty) {
    expect(tester.getSemantics(status).hasFlag(SemanticsFlag.isLiveRegion), isTrue);
  }
});
```

Perluas existing destructive import test:

```dart
final confirm = tester.widget<FilledButton>(
  find.byKey(const ValueKey('operation-preview-confirm-button')),
);
expect(confirm.onPressed, isNull);
expect(find.byIcon(Icons.warning_amber_outlined), findsWidgets);
```

- [ ] **Step 2: Verifikasi RED**

Run: `flutter test test/features/sync/presentation/recovery_center_test.dart`

Expected: FAIL pada compact overflow/live-region status atau warning icon preview.

- [ ] **Step 3: Terapkan adaptive recovery composition tanpa menyentuh controller**

Gunakan `LayoutBuilder` di page: `< 1024` satu list; `>= 1024` dua constrained columns, dengan Health/Recover/Drafts di kiri dan Sync/Activity di kanan. `_Section` tetap native `Card`, tanpa local elevation. Form rows menjadi `Wrap`/`Column` pada compact agar TextField dan buttons tidak overflow. Bungkus `state.lastMessage`, node-loading, drafts-loading/error, dan preview errors dengan `Semantics(liveRegion: true)`; gunakan icon + text untuk health/warning/error. Gunakan destructive `FilledButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError)` untuk confirmed delete/overwrite actions, tetapi jangan menghapus checkbox gate atau preview stage.

Pertahankan exact calls berikut:

```dart
await controller.importPortableBackup(
  package: _packageController.text,
  passphrase: _passphraseController.text,
  previewConfirmed: true,
);
```

```dart
await controller.restorePoint(point.id);
```

Jangan mengubah KDF, package contents, remote/local conflict rules, attachment sync, restore point generation, atau controller state.

- [ ] **Step 4: Verifikasi GREEN**

Run: `flutter test test/features/sync/presentation/recovery_center_test.dart test/features/sync/application/sync_controller_test.dart test/features/sync/application/portable_backup_codec_test.dart`

Expected: PASS; destructive operation tetap read-only sampai preview dan checkbox confirmation, empat widths bebas overflow, controller/codec regressions tidak muncul.

- [ ] **Step 5: Commit task**

```bash
git add lib/features/sync/presentation/recovery_center.dart test/features/sync/presentation/recovery_center_test.dart
git commit -m "feat: polish sync recovery surfaces"
```

### Task 10: Cross-surface accessibility dan regression gate

**Files:**
- Modify: `test/shared/layout/adaptive_scaffold_test.dart`
- Modify: `test/features/search/presentation/search_page_test.dart`
- Modify: `test/features/settings/settings_page_test.dart`
- Modify: `test/features/sync/presentation/recovery_center_test.dart`

**Interfaces:**
- Consumes: hasil Tasks 1–9.
- Produces: runnable cross-surface checks untuk representative widths, dark/light theme, keyboard, semantics, text scaling, dan reduced motion.

- [ ] **Step 1: Tambahkan reduced-motion dan dark-mode smoke loops pada existing helpers**

Gunakan exact viewport matrix berikut di masing-masing relevant test helper, bukan golden snapshots:

```dart
const representativeWidths = <double>[320, 768, 1024, 1440];
```

Tambahkan satu search reduced-motion test:

```dart
testWidgets('search empty state honors reduced motion', (tester) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(_searchApp(results: const []));
  await tester.pump();
  expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

Tambahkan shell dark-mode keyboard test:

```dart
testWidgets('keyboard shortcut opens capture in dark mode', (tester) async {
  await pumpShell(tester, width: 1024, theme: AppTheme.dark);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  expect(find.byType(QuickCaptureDock), findsOneWidget);
});
```

- [ ] **Step 2: Jalankan tests untuk memastikan checks mendeteksi gap**

Run: `flutter test test/shared/layout/adaptive_scaffold_test.dart test/features/search/presentation/search_page_test.dart test/features/settings/settings_page_test.dart test/features/sync/presentation/recovery_center_test.dart`

Expected: PASS bila Tasks 1–9 lengkap. Bila failure muncul, perbaiki hanya surface pemilik behavior dengan kembali ke RED/GREEN focused test; jangan longgarkan assertion.

- [ ] **Step 3: Format hanya files plan ini**

Run:

```bash
dart format lib/shared/layout/adaptive_scaffold.dart lib/shared/layout/desktop_window_chrome.dart lib/shared/widgets/animated_empty_state.dart lib/shared/widgets/error_message.dart lib/features/search/presentation/search_page.dart lib/features/search/presentation/search_filter_bar.dart lib/features/search/presentation/search_result_tile.dart lib/features/settings/settings_page.dart lib/features/capture/presentation/quick_capture_dialog.dart lib/features/command/presentation/quick_capture_dock.dart lib/features/focus/focus_page.dart lib/features/focus/widgets/focus_zen_view.dart lib/features/onboarding/onboarding_overlay.dart lib/features/sync/presentation/recovery_center.dart test/shared/layout/adaptive_scaffold_test.dart test/shared/layout/desktop_window_chrome_test.dart test/features/search/presentation/search_page_test.dart test/features/settings/settings_page_test.dart test/features/capture/presentation/quick_capture_dialog_test.dart test/features/command/presentation/quick_capture_dock_test.dart test/features/focus/focus_timer_test.dart test/features/onboarding/onboarding_test.dart test/features/sync/presentation/recovery_center_test.dart
```

Expected: exit 0; inspect `git diff --check` afterward.

- [ ] **Step 4: Jalankan focused suite**

Run:

```bash
flutter test test/shared/layout/adaptive_scaffold_test.dart test/shared/layout/desktop_window_chrome_test.dart test/shared/widgets/animated_empty_state_test.dart test/features/search/presentation/search_page_test.dart test/features/settings/settings_page_test.dart test/features/capture/presentation/quick_capture_dialog_test.dart test/features/command/presentation/quick_capture_dock_test.dart test/features/focus/focus_timer_test.dart test/features/focus/ambient_sound_test.dart test/features/onboarding/onboarding_test.dart test/features/sync/presentation/recovery_center_test.dart
```

Expected: all PASS tanpa exception, overflow, warning, atau pending timer.

- [ ] **Step 5: Jalankan analyzer dan full suite**

Run: `flutter analyze`

Expected: no issues introduced by changed files.

Run: `flutter test`

Expected: all tests PASS. Jika ada pre-existing unrelated failure, catat command, test name, dan exact error; jangan memperbaiki area di luar plan.

- [ ] **Step 6: Audit diff dan perubahan lokal sebelum commit gate**

Run:

```bash
git status --short
git diff --check
git diff --stat
git diff -- lib/shared/layout lib/shared/widgets/animated_empty_state.dart lib/shared/widgets/error_message.dart lib/features/search/presentation lib/features/settings/settings_page.dart lib/features/capture/presentation/quick_capture_dialog.dart lib/features/command/presentation/quick_capture_dock.dart lib/features/focus lib/features/onboarding lib/features/sync/presentation/recovery_center.dart test/shared/layout test/features/search/presentation test/features/settings/settings_page_test.dart test/features/capture/presentation/quick_capture_dialog_test.dart test/features/command/presentation/quick_capture_dock_test.dart test/features/focus test/features/onboarding test/features/sync/presentation/recovery_center_test.dart
```

Expected: tidak ada generated files, domain/persistence changes, unrelated local work, atau whitespace errors dalam diff task. Jangan gunakan `git add .`.

- [ ] **Step 7: Commit regression tests saja bila belum ikut task commits**

```bash
git add test/shared/layout/adaptive_scaffold_test.dart test/features/search/presentation/search_page_test.dart test/features/settings/settings_page_test.dart test/features/sync/presentation/recovery_center_test.dart
git commit -m "test: cover adaptive product surfaces"
```

## Completion Criteria

- Shell memakai destination order konsisten, route aktif benar, dan shortcuts/capture/menu dispatch tetap bekerja.
- Search, settings, capture, focus, onboarding, serta recovery usable pada 320, 768, 1024, dan 1440 logical pixels.
- Loading, empty, error, disabled, duplicate, conflict, dan destructive states memiliki text/icon/semantics, bukan warna saja.
- Destructive sync/recovery/data actions tetap memerlukan existing preview dan explicit confirmation; tidak ada mutation saat preview.
- Light/dark, text scale 2, keyboard focus, Escape flows, pointer/touch targets, dan reduced motion memiliki automated behavior coverage.
- `dart format`, focused tests, `flutter analyze`, dan `flutter test` lulus tanpa membundel perubahan lokal yang tidak terkait.

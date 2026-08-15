# Material 3 Adaptive Shadcn Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Membangun foundation Material 3 adaptive bergaya shadcn yang langsung memoles seluruh aplikasi sambil mempertahankan tujuh warna dan font Astryx.

**Architecture:** `AppSemanticColors`, `AppDesignTokens`, dan `AppTheme.forVariant` tetap menjadi satu sumber desain. Material widgets menyediakan behavior lintas platform; shared widgets hanya menambah komposisi atau semantics nyata. Plan ini tidak mengubah feature logic, canvas geometry, route, persistence, atau gesture.

**Tech Stack:** Flutter Material 3, Dart 3.11.4, ThemeExtension, flutter_test.

## Global Constraints

- Pertahankan tujuh varian warna/font Astryx dan light/dark mode.
- Jangan tambah dependency, `Shadcn*` widget family, CSS, React, atau runtime web.
- Minimum target interaksi tetap 44 logical pixels.
- Gunakan border dan surface hierarchy; elevation nol untuk card statis.
- Pertahankan keyboard, pointer, touch, semantics, text scaling, RTL, dan reduced motion.
- Jangan menimpa perubahan user yang belum di-commit.

---

### Task 1: Kunci kontrak token foundation

**Files:**
- Modify: `test/core/theme/astryx_neutral_theme_test.dart:66-125`
- Modify: `lib/core/theme/app_design_tokens.dart:44-84`

**Interfaces:**
- Consumes: `AppThemeVariant`, existing `ThemeExtension<AppDesignTokens>`.
- Produces: `AppDesignTokens.astryx` dengan radius `4/8/12/28`, spacing existing, shadow restrained, motion existing, controls `28/32/36`, minimum target `44`.

- [ ] **Step 1: Tambahkan assertion kontrak shadow dan geometry**

```dart
expect(tokens.radiusInner, 4);
expect(tokens.radiusElement, 8);
expect(tokens.radiusContainer, 12);
expect(tokens.radiusPage, 28);
expect(tokens.shadowLow, isEmpty);
expect(tokens.shadowMedium, hasLength(1));
expect(tokens.shadowHigh, hasLength(1));
expect(tokens.minimumTarget, 44);
```

- [ ] **Step 2: Jalankan test untuk membuktikan mismatch**

Run: `flutter test test/core/theme/astryx_neutral_theme_test.dart`
Expected: FAIL pada radius/shadow contract.

- [ ] **Step 3: Terapkan token minimal**

```dart
static const _shadowsLow = <BoxShadow>[];

static const _shadowsMedium = <BoxShadow>[
  BoxShadow(color: Color(0x1A000000), offset: Offset(0, 2), blurRadius: 8),
];

static const _shadowsHigh = <BoxShadow>[
  BoxShadow(color: Color(0x26000000), offset: Offset(0, 8), blurRadius: 24),
];

static const astryx = AppDesignTokens(
  spacing: _spacing,
  radiusInner: 4,
  radiusElement: 8,
  radiusContainer: 12,
  radiusPage: 28,
  shadowLow: _shadowsLow,
  shadowMedium: _shadowsMedium,
  shadowHigh: _shadowsHigh,
  motionFast: Duration(milliseconds: 175),
  motionMedium: Duration(milliseconds: 410),
  motionSlow: Duration(milliseconds: 975),
  motionCurve: Cubic(0.24, 1, 0.4, 1),
  controlSmall: 28,
  controlMedium: 32,
  controlLarge: 36,
  minimumTarget: 44,
);
```

- [ ] **Step 4: Jalankan focused test**

Run: `flutter test test/core/theme/astryx_neutral_theme_test.dart`
Expected: PASS.

### Task 2: Lengkapi shadcn-inspired Material component themes

**Files:**
- Modify: `test/core/theme/astryx_neutral_theme_test.dart:66-125`
- Modify: `lib/core/theme/app_theme.dart:40-536`

**Interfaces:**
- Consumes: semantic roles dan token Task 1.
- Produces: konsisten `ThemeData` untuk card, input, buttons, icon buttons, controls, chips, segmented buttons, dialogs, sheets, menus, list tiles, tabs, navigation, progress, slider, dan scrollbar.

- [ ] **Step 1: Tambahkan assertion theme hierarchy**

```dart
expect(theme.cardTheme.elevation, 0);
expect(theme.dialogTheme.elevation, greaterThan(0));
expect(theme.inputDecorationTheme.filled, isTrue);
expect(theme.inputDecorationTheme.fillColor, semantic.surface);
expect(theme.filledButtonTheme.style?.elevation?.resolve(<WidgetState>{}), 0);
expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
```

Tambahkan widget test yang merender `FilledButton`, `OutlinedButton`, `TextField`, `Card`, `Dialog`, `PopupMenuButton`, `SegmentedButton`, dan `NavigationBar` pada light/dark Neutral; pastikan tidak ada exception atau overflow.

- [ ] **Step 2: Jalankan focused test**

Run: `flutter test test/core/theme/astryx_neutral_theme_test.dart`
Expected: FAIL karena input masih memakai `surfaceRaised` dan dialog elevation belum mengikuti kontrak.

- [ ] **Step 3: Selaraskan global themes**

Gunakan aturan berikut di `AppTheme.forVariant`:

```dart
cardTheme: CardThemeData(
  color: semantic.card,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  shape: containerShape,
  margin: EdgeInsets.zero,
),
inputDecorationTheme: InputDecorationTheme(
  filled: true,
  fillColor: semantic.surface,
  border: _inputBorder(semantic.borderStrong, tokens.radiusElement),
  enabledBorder: _inputBorder(semantic.borderStrong, tokens.radiusElement),
  focusedBorder: _inputBorder(
    semantic.focusRing,
    tokens.radiusElement,
    width: 2,
  ),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  isDense: true,
),
dialogTheme: DialogThemeData(
  backgroundColor: semantic.popover,
  surfaceTintColor: Colors.transparent,
  elevation: 8,
  shadowColor: scheme.shadow.withValues(alpha: isDark ? 0.36 : 0.16),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(tokens.radiusContainer),
    side: BorderSide(color: semantic.border),
  ),
),
```

Pertahankan state overlay, focus ring, padded tap targets, dan existing adaptive transition builders. Jangan mengubah font mapping atau palette.

- [ ] **Step 4: Jalankan focused test**

Run: `flutter test test/core/theme/astryx_neutral_theme_test.dart`
Expected: PASS untuk semua tujuh variants dan kedua brightness.

### Task 3: Poles shared card semantics dan styling

**Files:**
- Modify: `lib/shared/widgets/astryx_card.dart`
- Create: `test/shared/widgets/astryx_card_test.dart`

**Interfaces:**
- Consumes: native `Card`, `InkWell`, `ThemeData.textTheme`, semantic colors, token radius.
- Produces: existing public APIs `AstryxCard`, `AstryxClickableCard`, dan `AstryxSelectableCard` tanpa call-site migration.

- [ ] **Step 1: Tulis failing widget tests**

```dart
testWidgets('card uses theme typography and no local shadow', (tester) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const Scaffold(body: AstryxCard(title: 'Title', subtitle: 'Subtitle', child: Text('Body')))));
  final card = tester.widget<Card>(find.byType(Card));
  expect(card.elevation, isNull);
});

testWidgets('clickable card exposes button semantics', (tester) async {
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: Scaffold(body: AstryxClickableCard(onTap: () {}, child: const Text('Open')))));
  expect(tester.getSemantics(find.text('Open')), matchesSemantics(isButton: true, hasTapAction: true));
  handle.dispose();
});
```

Tambahkan selected semantics test untuk `AstryxSelectableCard`.

- [ ] **Step 2: Jalankan test untuk membuktikan failure**

Run: `flutter test test/shared/widgets/astryx_card_test.dart`
Expected: FAIL karena base memakai `Container`, shadow lokal, dan semantics belum eksplisit.

- [ ] **Step 3: Implementasi minimal menggunakan native surfaces**

- Ganti base `Container` dengan `Card` + `Padding`.
- Gunakan `Theme.of(context).textTheme.titleMedium` dan `bodySmall`.
- Hapus `tokens.shadowLow` lokal.
- Bungkus clickable surface dengan `Semantics(button: true)`.
- Bungkus selectable surface dengan `Semantics(button: true, selected: selected)`.
- Pertahankan public constructors dan callback signatures.

- [ ] **Step 4: Jalankan focused tests**

Run: `flutter test test/shared/widgets/astryx_card_test.dart`
Expected: PASS.

### Task 4: Ganti segmented wrapper internals dengan Material semantics

**Files:**
- Modify: `lib/shared/widgets/astryx_segmented_control.dart`
- Create: `test/shared/widgets/astryx_segmented_control_test.dart`

**Interfaces:**
- Consumes: `AstryxSegmentOption<T>` existing API dan native `SegmentedButton<T>`.
- Produces: existing `AstryxSegmentedControl<T>` API dengan keyboard, selected semantics, dan minimum target native.

- [ ] **Step 1: Tulis failing behavior test**

```dart
testWidgets('segment exposes selected button semantics and changes value', (tester) async {
  var selected = 'board';
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    home: StatefulBuilder(builder: (context, setState) {
      return AstryxSegmentedControl<String>(
        options: const [
          AstryxSegmentOption(value: 'board', label: 'Board'),
          AstryxSegmentOption(value: 'table', label: 'Table'),
        ],
        selected: selected,
        onChanged: (value) => setState(() => selected = value),
      );
    }),
  ));
  await tester.tap(find.text('Table'));
  await tester.pump();
  expect(selected, 'table');
  expect(find.byType(SegmentedButton<String>), findsOneWidget);
});
```

- [ ] **Step 2: Jalankan test untuk membuktikan failure**

Run: `flutter test test/shared/widgets/astryx_segmented_control_test.dart`
Expected: FAIL karena implementasi belum memakai `SegmentedButton<String>`.

- [ ] **Step 3: Implementasi dengan native `SegmentedButton`**

```dart
return SegmentedButton<T>(
  segments: [
    for (final option in options)
      ButtonSegment<T>(
        value: option.value,
        label: Text(option.label),
        icon: option.icon == null ? null : Icon(option.icon),
      ),
  ],
  selected: <T>{selected},
  onSelectionChanged: (values) => onChanged(values.single),
  showSelectedIcon: false,
);
```

Hapus private `_SegmentTile` dan imports yang tidak digunakan.

- [ ] **Step 4: Jalankan focused tests**

Run: `flutter test test/shared/widgets/astryx_segmented_control_test.dart`
Expected: PASS.

### Task 5: Foundation regression gate

**Files:**
- Verify only; jangan ubah domain atau feature behavior untuk mengejar visual snapshot.

**Interfaces:**
- Consumes: hasil Tasks 1-4.
- Produces: foundation siap dipakai plan shell dan standard product surfaces.

- [ ] **Step 1: Format changed Dart files**

Run: `dart format lib/core/theme/app_design_tokens.dart lib/core/theme/app_theme.dart lib/shared/widgets/astryx_card.dart lib/shared/widgets/astryx_segmented_control.dart test/core/theme/astryx_neutral_theme_test.dart test/shared/widgets/astryx_card_test.dart test/shared/widgets/astryx_segmented_control_test.dart`
Expected: exit 0.

- [ ] **Step 2: Run focused test suite**

Run: `flutter test test/core/theme/astryx_neutral_theme_test.dart test/shared/widgets/astryx_card_test.dart test/shared/widgets/astryx_segmented_control_test.dart test/shared/layout/adaptive_scaffold_test.dart test/shared/layout/desktop_window_chrome_test.dart`
Expected: all pass.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`
Expected: no issues introduced by changed files.

- [ ] **Step 4: Run full test suite**

Run: `flutter test`
Expected: all tests pass. Existing unrelated failures, bila ada, dicatat dengan command dan output exact; jangan diperbaiki dalam plan ini.

## Checkpoint

Foundation dianggap selesai bila tujuh varian tetap bekerja, component themes konsisten, shared cards/segments accessible, focused tests lulus, dan analyzer tidak menunjukkan issue baru. Plan berikutnya mencakup adaptive shell, navigation, search, settings, dialogs, forms, dan lists.

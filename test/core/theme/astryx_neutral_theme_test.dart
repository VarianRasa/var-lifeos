import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/theme/app_colors.dart';
import 'package:var_app/core/theme/app_design_tokens.dart';
import 'package:var_app/core/theme/app_theme.dart';
import 'package:var_app/core/theme/app_theme_icon_set.dart';
import 'package:var_app/core/theme/node_visuals.dart';
import 'package:var_app/core/theme/theme_controller.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('only seven Astryx variants remain available', () {
    expect(AppThemeVariant.values, AppThemeVariant.valuesForSettings);
    expect(AppThemeVariant.values, hasLength(7));
    expect(
      AppThemeVariant.values.map((variant) => variant.displayName),
      containsAll(<String>[
        'Astryx Neutral',
        'Astryx Stone',
        'Astryx Gothic',
        'Astryx Matcha',
        'Astryx Y2K',
        'Astryx Butter',
        'Astryx Chocolate',
      ]),
    );
  });

  test('Neutral exposes official semantic colors', () {
    final palette = AppThemeVariantColors.of(AppThemeVariant.astryxNeutral);
    final light = palette.semanticColors(Brightness.light);
    final dark = palette.semanticColors(Brightness.dark);

    expect(light.background, const Color(0xFFF1F4F7));
    expect(light.surface, const Color(0xFFFFFFFF));
    expect(light.accent, const Color(0xFF0064E0));
    expect(light.textPrimary, const Color(0xFF0A1317));
    expect(dark.background, const Color(0xFF111112));
    expect(dark.surface, const Color(0xFF1F1F22));
    expect(dark.popover, const Color(0xFF28292C));
    expect(dark.accent, const Color(0xFF2694FE));
    expect(dark.textPrimary, const Color(0xFFDFE2E5));
    expect(dark.danger, const Color(0xFFF5394F));
    expect(dark.success, const Color(0xFF0D8626));
    expect(dark.warning, const Color(0xFFF2C00B));
    expect(light.borderStrong, const Color(0xFFCCD3DB));
    expect(dark.borderStrong, const Color(0xFF494D53));
    expect(light.accentMuted, const Color(0x330082FB));
    expect(dark.accentMuted, const Color(0x3F0082FB));
    expect(light.hoverOverlay, const Color(0x0C053659));
    expect(dark.pressedOverlay, const Color(0x19FFFFFF));
    expect(light.scrim, const Color(0x66011228));
    expect(dark.scrim, const Color(0x99111112));
    expect(light.track, const Color(0xFFCCD3DB));
    expect(dark.track, const Color(0xFF5A5E66));
  });

  test('all variants build Material themes with shared Astryx geometry', () {
    for (final variant in AppThemeVariant.values) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.forVariant(
          brightness,
          variant,
          AppFontSize.medium,
        );
        final semantic = theme.extension<AppSemanticColors>();
        final tokens = theme.extension<AppDesignTokens>();

        expect(semantic, isNotNull);
        expect(semantic!.variant, variant);
        expect(tokens, AppDesignTokens.astryx);
        expect(theme.extension<AppThemeIconSet>(), isNotNull);
        expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
        expect(theme.inputDecorationTheme.border, isA<OutlineInputBorder>());
        expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
        expect(theme.cardTheme.elevation, 0);
        expect(theme.dialogTheme.elevation, greaterThan(0));
        expect(theme.inputDecorationTheme.filled, isTrue);
        expect(theme.inputDecorationTheme.fillColor, semantic.surface);
        expect(
          theme.inputDecorationTheme.constraints?.minHeight,
          tokens!.minimumTarget,
        );
        expect(
          theme.filledButtonTheme.style?.elevation?.resolve(<WidgetState>{}),
          0,
        );
      }
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'Neutral ${brightness.name} renders and interacts with Material surfaces',
      (tester) async {
        final theme = AppTheme.forVariant(
          brightness,
          AppThemeVariant.astryxNeutral,
          AppFontSize.medium,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const TextField(key: Key('field')),
                    const SizedBox(height: 8),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Card'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Filled'),
                        ),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Outlined'),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Open menu',
                          itemBuilder: (context) =>
                              const <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'one',
                                  child: Text('Menu item'),
                                ),
                              ],
                        ),
                        Builder(
                          builder: (context) => FilledButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (context) => const Dialog(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('Dialog content'),
                                ),
                              ),
                            ),
                            child: const Text('Open dialog'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(value: 'one', label: Text('One')),
                        ButtonSegment<String>(value: 'two', label: Text('Two')),
                      ],
                      selected: const <String>{'one'},
                      onSelectionChanged: (_) {},
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: 0,
                destinations: const <NavigationDestination>[
                  NavigationDestination(
                    icon: Icon(Icons.today_outlined),
                    label: 'Today',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
          ),
        );

        expect(tester.getSize(find.byKey(const Key('field'))).height, 44);
        await tester.tap(find.byTooltip('Open menu'));
        await tester.pumpAndSettle();
        expect(find.text('Menu item'), findsOneWidget);
        await tester.tap(find.text('Menu item'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open dialog'));
        await tester.pumpAndSettle();
        expect(find.text('Dialog content'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Neutral ${brightness.name} drives real button states', (
      tester,
    ) async {
      final focusNode = FocusNode();
      final focusedStates = WidgetStatesController();
      final pressedStates = WidgetStatesController();
      final disabledStates = WidgetStatesController();
      addTearDown(focusNode.dispose);
      addTearDown(focusedStates.dispose);
      addTearDown(pressedStates.dispose);
      addTearDown(disabledStates.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.forVariant(
            brightness,
            AppThemeVariant.astryxNeutral,
            AppFontSize.medium,
          ),
          home: Scaffold(
            body: Column(
              children: <Widget>[
                OutlinedButton(
                  focusNode: focusNode,
                  statesController: focusedStates,
                  onPressed: () {},
                  child: const Text('Focus target'),
                ),
                FilledButton(
                  statesController: pressedStates,
                  onPressed: () {},
                  child: const Text('Press target'),
                ),
                FilledButton.icon(
                  statesController: disabledStates,
                  onPressed: null,
                  icon: const Icon(Icons.block, key: Key('disabled-icon')),
                  label: const Text('Disabled target'),
                ),
              ],
            ),
          ),
        ),
      );

      final semantic = AppTheme.forVariant(
        brightness,
        AppThemeVariant.astryxNeutral,
        AppFontSize.medium,
      ).extension<AppSemanticColors>()!;
      final focusButton = find.widgetWithText(OutlinedButton, 'Focus target');
      final pressButton = find.widgetWithText(FilledButton, 'Press target');

      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      expect(focusedStates.value, contains(WidgetState.focused));
      final focusedMaterial = tester.widget<Material>(
        find.descendant(of: focusButton, matching: find.byType(Material)).first,
      );
      expect(
        (focusedMaterial.shape! as RoundedRectangleBorder).side,
        BorderSide(color: semantic.focusRing, width: 2),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Press target')),
      );
      await tester.pump();
      expect(pressedStates.value, contains(WidgetState.pressed));
      final pressedInkWell = tester.widget<InkWell>(
        find.descendant(of: pressButton, matching: find.byType(InkWell)),
      );
      expect(
        pressedInkWell.overlayColor?.resolve(pressedStates.value),
        semantic.pressedOverlay,
      );
      await gesture.up();
      await tester.pump();
      expect(pressedStates.value, isNot(contains(WidgetState.pressed)));

      expect(disabledStates.value, contains(WidgetState.disabled));
      final disabledColor = DefaultTextStyle.of(
        tester.element(find.text('Disabled target')),
      ).style.color;
      final disabledIconColor = IconTheme.of(
        tester.element(find.byKey(const Key('disabled-icon'))),
      ).color;
      expect(disabledColor, semantic.textDisabled);
      expect(disabledIconColor, semantic.textDisabled);
      expect(
        tester.getSemantics(find.text('Disabled target')),
        matchesSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          label: 'Disabled target',
        ),
      );
    });
  }

  test('Astryx type scale and motion match design contract', () {
    final theme = AppTheme.dark;
    final tokens = theme.extension<AppDesignTokens>()!;

    expect(theme.textTheme.displayLarge?.fontSize, 42);
    expect(theme.textTheme.displayMedium?.fontSize, 35);
    expect(theme.textTheme.displaySmall?.fontSize, 29);
    expect(theme.textTheme.headlineLarge?.fontSize, 24);
    expect(theme.textTheme.headlineMedium?.fontSize, 20);
    expect(theme.textTheme.headlineSmall?.fontSize, 17);
    expect(theme.textTheme.bodyMedium?.fontSize, 14);
    expect(tokens.spacing, <double>[
      0,
      2,
      4,
      6,
      8,
      12,
      16,
      20,
      24,
      28,
      32,
      36,
      40,
      44,
      48,
    ]);
    expect(tokens.radiusInner, 4);
    expect(tokens.radiusElement, 8);
    expect(tokens.radiusContainer, 12);
    expect(tokens.radiusPage, 28);
    expect(tokens.shadowLow, isEmpty);
    expect(tokens.shadowMedium, hasLength(1));
    expect(tokens.shadowHigh, hasLength(1));
    expect(tokens.motionFast, const Duration(milliseconds: 175));
    expect(tokens.motionMedium, const Duration(milliseconds: 410));
    expect(tokens.motionSlow, const Duration(milliseconds: 975));
    expect(tokens.motionCurve, const Cubic(0.24, 1, 0.4, 1));
    expect(tokens.controlSmall, 28);
    expect(tokens.controlMedium, 32);
    expect(tokens.controlLarge, 36);
    expect(tokens.minimumTarget, 44);
  });

  for (final mediaCase
      in <({String name, MediaQueryData data, Duration expected})>[
        (
          name: 'disableAnimations',
          data: const MediaQueryData(disableAnimations: true),
          expected: Duration.zero,
        ),
        (
          name: 'accessibleNavigation',
          data: const MediaQueryData(accessibleNavigation: true),
          expected: Duration.zero,
        ),
        (
          name: 'default motion',
          data: const MediaQueryData(),
          expected: const Duration(milliseconds: 410),
        ),
      ]) {
    testWidgets('${mediaCase.name} resolves effective motion', (tester) async {
      Duration? duration;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: mediaCase.data,
            child: Builder(
              builder: (context) {
                duration = AppDesignTokens.of(context).effectiveDuration(
                  context,
                  AppDesignTokens.astryx.motionMedium,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(duration, mediaCase.expected);
    });
  }

  test('every node type has one icon and one theme color', () {
    for (final type in NodeType.values) {
      expect(NodeVisuals.icon(type), isA<IconData>());
      for (final variant in AppThemeVariant.values) {
        expect(NodeVisuals.colorForVariant(variant, type), isA<Color>());
      }
    }
  });

  test('Gothic stays dark-only while other variants preserve mode', () {
    expect(
      AppThemeVariant.astryxGothic.effectiveThemeMode(ThemeMode.light),
      ThemeMode.dark,
    );
    expect(
      AppThemeVariant.astryxNeutral.effectiveThemeMode(ThemeMode.system),
      ThemeMode.system,
    );
  });

  test('legacy stored variants fall back to Neutral', () async {
    await SharedPreferencesAsync().setString('theme_variant', 'blackboard');
    final notifier = ThemeVariantNotifier();
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(notifier.state, AppThemeVariant.astryxNeutral);
  });

  test('all Astryx selections persist and reload', () async {
    for (final variant in AppThemeVariant.values) {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final notifier = ThemeVariantNotifier();
      await notifier.setThemeVariant(variant);
      final reloaded = ThemeVariantNotifier();
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(reloaded.state, variant);
    }
  });
}

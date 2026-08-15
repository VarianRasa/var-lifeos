import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/theme/app_theme.dart';
import 'package:var_app/shared/widgets/astryx_segmented_control.dart';

void main() {
  test('requires at least one option', () {
    expect(
      () => AstryxSegmentedControl<String>(
        options: const [],
        selected: 'board',
        onChanged: (_) {},
      ),
      throwsAssertionError,
    );
  });

  test('requires unique option values', () {
    expect(
      () => AstryxSegmentedControl<String>(
        options: const [
          AstryxSegmentOption(value: 'board', label: 'Board'),
          AstryxSegmentOption(value: 'board', label: 'Duplicate'),
        ],
        selected: 'board',
        onChanged: (_) {},
      ),
      throwsAssertionError,
    );
  });

  test('requires selected value to appear exactly once', () {
    expect(
      () => AstryxSegmentedControl<String>(
        options: const [
          AstryxSegmentOption(value: 'board', label: 'Board'),
          AstryxSegmentOption(value: 'table', label: 'Table'),
        ],
        selected: 'calendar',
        onChanged: (_) {},
      ),
      throwsAssertionError,
    );
  });

  testWidgets('unbounded width preserves intrinsic native control', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AstryxSegmentedControl<String>(
                options: const [
                  AstryxSegmentOption(value: 'board', label: 'Board'),
                  AstryxSegmentOption(value: 'table', label: 'Table'),
                ],
                selected: 'board',
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long labels scroll horizontally without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: AstryxSegmentedControl<String>(
              options: const [
                AstryxSegmentOption(
                  value: 'board',
                  label: 'Projektübersicht und Aufgabenverwaltung',
                ),
                AstryxSegmentOption(
                  value: 'calendar',
                  label: 'Langfristige Kalenderplanung',
                ),
              ],
              selected: 'board',
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('segment exposes selected semantics and changes value on tap', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = 'board';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AstryxSegmentedControl<String>(
                options: const [
                  AstryxSegmentOption(value: 'board', label: 'Board'),
                  AstryxSegmentOption(value: 'table', label: 'Table'),
                ],
                selected: selected,
                onChanged: (value) => setState(() => selected = value),
              );
            },
          ),
        ),
      ),
    );

    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    for (final label in <String>['Board', 'Table']) {
      final segment = tester.getSemantics(find.text(label));
      expect(segment.rect.width, greaterThanOrEqualTo(44));
    }
    expect(
      tester.getSize(find.byType(SegmentedButton<String>)).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSemantics(find.text('Board')),
      matchesSemantics(
        isSelected: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isInMutuallyExclusiveGroup: true,
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.text('Table'));
    await tester.pump();

    expect(selected, 'table');
    expect(
      tester.getSemantics(find.text('Table')),
      matchesSemantics(
        isSelected: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isInMutuallyExclusiveGroup: true,
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('segment renders option icons and supports keyboard selection', (
    tester,
  ) async {
    var selected = 'board';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return AstryxSegmentedControl<String>(
                options: const [
                  AstryxSegmentOption(
                    value: 'board',
                    label: 'Board',
                    icon: Icons.dashboard_outlined,
                  ),
                  AstryxSegmentOption(
                    value: 'table',
                    label: 'Table',
                    icon: Icons.table_rows_outlined,
                  ),
                ],
                selected: selected,
                onChanged: (value) => setState(() => selected = value),
              );
            },
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
    expect(find.byIcon(Icons.table_rows_outlined), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(selected, 'table');
  });
}

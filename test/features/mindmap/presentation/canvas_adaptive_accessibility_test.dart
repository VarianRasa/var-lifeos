import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';

Future<void> pumpCanvas(
  WidgetTester tester, {
  required Size size,
  TextDirection textDirection = TextDirection.ltr,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
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
          accessibleNavigation: accessibleNavigation,
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

Future<void> openSearch(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  for (final variant in <({String name, bool disabled, bool accessible})>[
    (name: 'disableAnimations', disabled: true, accessible: false),
    (name: 'accessibleNavigation', disabled: false, accessible: true),
  ]) {
    testWidgets('${variant.name} reveals canvas chrome immediately', (
      tester,
    ) async {
      await pumpCanvas(
        tester,
        size: const Size(1024, 900),
        disableAnimations: variant.disabled,
        accessibleNavigation: variant.accessible,
      );

      final minimapAnimation = tester.widget<AnimatedSize>(
        find.descendant(
          of: find.byKey(const ValueKey('mindmap-minimap-anchor')),
          matching: find.byType(AnimatedSize),
        ),
      );
      expect(minimapAnimation.duration, Duration.zero);
    });
  }

  testWidgets('canvas labels counts and retains chrome semantics', (
    tester,
  ) async {
    await pumpCanvas(tester, size: const Size(1024, 900));

    expect(
      find.bySemanticsLabel('Mindmap canvas, 0 nodes and 0 canvas objects'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mindmap-minimap-anchor')),
      findsOneWidget,
    );
  });

  testWidgets('canvas chrome fits representative widths', (tester) async {
    for (final width in <double>[320, 768, 1024, 1440]) {
      await pumpCanvas(tester, size: Size(width, 900));
      expect(find.byKey(const ValueKey('mindmap-canvas')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width=$width');
      await openSearch(tester);
      final overlay = find.byKey(const ValueKey('mindmap-search-overlay'));
      expect(overlay, findsOneWidget);
      expect(tester.getSize(overlay).width, lessThanOrEqualTo(380));
      expect(tester.takeException(), isNull, reason: 'search width=$width');
    }
  });

  testWidgets('compact search supports 2x RTL and 44 pixel actions', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      size: const Size(320, 900),
      textDirection: TextDirection.rtl,
      textScaler: const TextScaler.linear(2),
      disableAnimations: true,
    );
    await openSearch(tester);
    await tester.enterText(find.byType(TextField).first, 'unmatched');
    await tester.pump();

    expect(find.byTooltip('Clear search'), findsOneWidget);
    final emptyState = tester.getSemantics(
      find.byKey(const ValueKey('mindmap-search-empty-state')),
    );
    expect(emptyState.label, contains('No canvas items match unmatched'));
    expect(emptyState.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(tester.takeException(), isNull);
    final overlay = find.byKey(const ValueKey('mindmap-search-overlay'));
    final overlayRect = tester.getRect(overlay);
    expect(overlayRect.left, greaterThanOrEqualTo(12));
    expect(overlayRect.right, lessThanOrEqualTo(320 - 16));
    expect(overlayRect.center.dx, greaterThan(160));
    final clearRect = tester.getRect(find.byTooltip('Clear search'));
    final hideRect = tester.getRect(find.byTooltip('Hide search filters'));
    expect(clearRect.center.dx, greaterThan(hideRect.center.dx));
    final firstFilter = find.byKey(const ValueKey('mindmap-search-filter-all'));
    final filterSize = tester.getSize(firstFilter);
    expect(filterSize.height, greaterThan(44));
    final filterRect = tester.getRect(firstFilter);
    expect(filterRect.top, greaterThanOrEqualTo(overlayRect.top));
    expect(filterRect.bottom, lessThanOrEqualTo(overlayRect.bottom));
    expect(
      find.ancestor(
        of: firstFilter,
        matching: find.byType(SingleChildScrollView),
      ),
      findsWidgets,
    );
    final minimapAnimation = tester.widget<AnimatedSize>(
      find.descendant(
        of: find.byKey(const ValueKey('mindmap-minimap-anchor')),
        matching: find.byType(AnimatedSize),
      ),
    );
    expect(minimapAnimation.duration, Duration.zero);
    final targetTypes = <Type>[
      IconButton,
      FilterChip,
      ChoiceChip,
      OutlinedButton,
      MenuItemButton,
      ActionChip,
    ];
    for (final type in targetTypes) {
      for (final element
          in find
              .descendant(of: overlay, matching: find.byType(type))
              .evaluate()) {
        final widget = element.widget;
        final enabled = switch (widget) {
          IconButton(:final onPressed) => onPressed != null,
          FilterChip(:final onSelected) => onSelected != null,
          ChoiceChip(:final onSelected) => onSelected != null,
          OutlinedButton(:final onPressed) => onPressed != null,
          MenuItemButton(:final onPressed) => onPressed != null,
          ActionChip(:final onPressed) => onPressed != null,
          _ => false,
        };
        if (!enabled) continue;
        final size = tester.getSize(find.byWidget(widget));
        expect(size.width, greaterThanOrEqualTo(44), reason: '$type width');
        expect(size.height, greaterThanOrEqualTo(44), reason: '$type height');
      }
    }
  });
}

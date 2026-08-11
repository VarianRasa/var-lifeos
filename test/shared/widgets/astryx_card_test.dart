import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/theme/app_theme.dart';
import 'package:var_app/shared/widgets/astryx_card.dart';

void main() {
  testWidgets('card uses theme typography and no local elevation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark.copyWith(
          textTheme: AppTheme.dark.textTheme.copyWith(
            titleMedium: const TextStyle(fontSize: 21),
            bodySmall: const TextStyle(fontSize: 11),
          ),
        ),
        home: const Scaffold(
          body: AstryxCard(
            title: 'Title',
            subtitle: 'Subtitle',
            child: Text('Body'),
          ),
        ),
      ),
    );

    final card = tester.widget<Card>(find.byType(Card));
    expect(card.elevation, isNull);
    expect(tester.widget<Text>(find.text('Title')).style?.fontSize, 21);
    expect(tester.widget<Text>(find.text('Subtitle')).style?.fontSize, 11);
  });

  testWidgets('clickable card exposes button semantics and activates', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: AstryxClickableCard(
            onTap: () => taps++,
            child: const Text('Open'),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text('Open')),
      matchesSemantics(
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.text('Open'));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('interactive cards keep ink inside clipped Card surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Column(
            children: [
              AstryxClickableCard(onTap: () {}, child: const Text('Open')),
              AstryxSelectableCard(
                selected: false,
                onSelected: (_) {},
                child: const Text('Choose'),
              ),
            ],
          ),
        ),
      ),
    );

    for (final label in <String>['Open', 'Choose']) {
      final card = find.ancestor(
        of: find.text(label),
        matching: find.byType(Card),
      );
      expect(card, findsOneWidget);
      final inkWellFinder = find.descendant(
        of: card,
        matching: find.byType(InkWell),
      );
      expect(inkWellFinder, findsOneWidget);
      final cardWidget = tester.widget<Card>(card);
      final cardShape = cardWidget.shape! as RoundedRectangleBorder;
      final inkWell = tester.widget<InkWell>(inkWellFinder);
      expect(cardShape.borderRadius, inkWell.borderRadius);
      expect(cardWidget.clipBehavior, isNot(Clip.none));
    }
  });

  testWidgets('selectable card keeps geometry when selection changes', (
    tester,
  ) async {
    var selected = false;
    late StateSetter setState;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) {
              setState = update;
              return AstryxSelectableCard(
                selected: selected,
                onSelected: (_) {},
                child: const Text('Stable'),
              );
            },
          ),
        ),
      ),
    );

    final unselectedSize = tester.getSize(find.byType(Card));
    setState(() => selected = true);
    await tester.pump();
    expect(tester.getSize(find.byType(Card)), unselectedSize);
  });

  testWidgets('selectable card exposes selected button semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    bool? nextSelection;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: AstryxSelectableCard(
            selected: true,
            onSelected: (value) => nextSelection = value,
            child: const Text('Chosen'),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text('Chosen')),
      matchesSemantics(
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.text('Chosen'));
    expect(nextSelection, isFalse);
    semantics.dispose();
  });
}

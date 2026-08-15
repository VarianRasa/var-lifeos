import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/theme/app_theme.dart';
import 'package:var_app/shared/widgets/animated_empty_state.dart';

void main() {
  for (final media in <MediaQueryData>[
    const MediaQueryData(disableAnimations: true),
    const MediaQueryData(accessibleNavigation: true),
  ]) {
    testWidgets(
      'reduced motion renders empty state without pending animation',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: media,
              child: const Scaffold(
                body: AnimatedEmptyState(
                  icon: Icons.event_busy_outlined,
                  label: 'No events',
                  subtitle: 'Create one to start planning.',
                  actionLabel: 'Create event',
                  secondaryActionLabel: 'Clear filters',
                  pulseIcon: true,
                ),
              ),
            ),
          ),
        );

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label ==
                    'No events. Create one to start planning.',
          ),
          findsOneWidget,
        );
        expect(find.text('Create event'), findsOneWidget);
        expect(find.text('Clear filters'), findsOneWidget);
        expect(await tester.pumpAndSettle(), 1);
      },
    );
  }
}

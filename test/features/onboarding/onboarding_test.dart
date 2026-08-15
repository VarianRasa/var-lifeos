import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:var_app/features/onboarding/onboarding_overlay.dart';
import 'package:var_app/features/onboarding/onboarding_providers.dart';

Widget _buildApp({required bool shouldShow}) {
  return ProviderScope(
    overrides: [
      shouldShowOnboardingProvider.overrideWith((ref) async => shouldShow),
    ],
    child: const MaterialApp(home: Scaffold(body: OnboardingOverlay())),
  );
}

void main() {
  testWidgets('Onboarding overlay hidden when shouldShow is false', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(shouldShow: false));
    await tester.pumpAndSettle();

    expect(find.text('Var'), findsNothing);
    expect(find.text('Create your first node'), findsNothing);
  });

  testWidgets('onboarding fits compact viewport at two times text scale', (
    tester,
  ) async {
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

    final primaryFocus = tester.binding.focusManager.primaryFocus;
    expect(primaryFocus, isNotNull);
    expect(
      primaryFocus!.context?.findAncestorWidgetOfExactType<FilledButton>(),
      isNotNull,
    );
  });

  testWidgets('onboarding exposes modal route semantics', (tester) async {
    await tester.pumpWidget(_buildApp(shouldShow: true));
    await tester.pumpAndSettle();

    final modal = tester.getSemantics(find.bySemanticsLabel('Onboarding'));
    expect(modal.flagsCollection.scopesRoute, isTrue);
    expect(modal.flagsCollection.namesRoute, isTrue);
    expect(
      tester
          .widget<Semantics>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == 'Onboarding',
            ),
          )
          .explicitChildNodes,
      isTrue,
    );
  });

  testWidgets('Escape does not dismiss onboarding', (tester) async {
    await tester.pumpWidget(_buildApp(shouldShow: true));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Create your first node'), findsOneWidget);
  });

  testWidgets('primary completion dismisses and navigates to calendar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: OnboardingOverlay()),
        ),
        GoRoute(
          path: '/calendar/:day',
          builder: (_, _) => const Scaffold(body: Text('Calendar day')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shouldShowOnboardingProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create your first node'));
    await tester.pumpAndSettle();

    expect(find.text('Calendar day'), findsOneWidget);
    expect(
      SharedPreferences.getInstance().then((p) => p.getBool('onboarding_seen')),
      completion(isTrue),
    );
  });

  testWidgets('secondary completion dismisses without navigation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_buildApp(shouldShow: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start fresh'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(OnboardingOverlay));
    expect(
      ProviderScope.containerOf(context).read(onboardingSeenProvider),
      isTrue,
    );
    expect(
      SharedPreferences.getInstance().then(
        (preferences) => preferences.getBool('onboarding_seen'),
      ),
      completion(isTrue),
    );
  });

  testWidgets('onboarding blocks shell semantics, focus, and Escape', (
    tester,
  ) async {
    var underlyingActivations = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shouldShowOnboardingProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp(
          home: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () {
                underlyingActivations++;
              },
            },
            child: Scaffold(
              body: Stack(
                children: [
                  Semantics(
                    label: 'Calendar shell action',
                    child: FilledButton(
                      onPressed: () => underlyingActivations++,
                      child: const Text('Underlying action'),
                    ),
                  ),
                  const Positioned.fill(child: OnboardingOverlay()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Calendar shell action'), findsNothing);
    for (var index = 0; index < 6; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final context = FocusManager.instance.primaryFocus?.context;
      expect(context, isNotNull);
      expect(
        context!.findAncestorWidgetOfExactType<OnboardingOverlay>(),
        isNotNull,
      );
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Create your first node'), findsOneWidget);
    expect(underlyingActivations, 0);
  });

  testWidgets('Onboarding overlay shown when shouldShow is true', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(shouldShow: true));
    await tester.pumpAndSettle();

    expect(find.text('Var'), findsOneWidget);
    expect(find.text('Create your first node'), findsOneWidget);
    expect(find.text('Start fresh'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).autofocus,
      isTrue,
    );
  });
}

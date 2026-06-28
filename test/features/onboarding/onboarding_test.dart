import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('Onboarding overlay shown when shouldShow is true', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(shouldShow: true));
    await tester.pumpAndSettle();

    expect(find.text('Var'), findsOneWidget);
    expect(find.text('Create your first node'), findsOneWidget);
    expect(find.text('Start fresh'), findsOneWidget);
  });
}

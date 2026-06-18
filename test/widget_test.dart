// Smoke test verifying the app boots after the Phase 0 rebrand.
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/main.dart';

void main() {
  testWidgets('App boots and shows the Var title', (tester) async {
    await tester.pumpWidget(const VarApp());

    expect(find.text('Var'), findsOneWidget);
    expect(find.text('Calendar-centric productivity'), findsOneWidget);
  });
}

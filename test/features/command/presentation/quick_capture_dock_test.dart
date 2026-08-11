import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:var_app/features/command/presentation/quick_capture_dock.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/shared/layout/adaptive_scaffold.dart';

void main() {
  testWidgets(
    'QuickCaptureDock renders when quickCaptureVisibleProvider is true',
    (tester) async {
      final repository = InMemoryMindmapRepository();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => AdaptiveScaffold(
              body: Semantics(
                label: 'Underlying shell',
                child: const SizedBox(),
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      expect(find.byType(QuickCaptureDock), findsNothing);

      final BuildContext context = tester.element(
        find.byType(AdaptiveScaffold),
      );
      final container = ProviderScope.containerOf(context);
      container.read(quickCaptureVisibleProvider.notifier).state = true;

      await tester.pumpAndSettle();

      expect(find.byType(QuickCaptureDock), findsOneWidget);
      expect(find.text('Quick Capture Dock'), findsOneWidget);
      final modal = tester.getSemantics(
        find.bySemanticsLabel('Quick Capture Dock'),
      );
      expect(modal.flagsCollection.scopesRoute, isTrue);
      expect(modal.flagsCollection.namesRoute, isTrue);
      expect(find.bySemanticsLabel('Underlying shell'), findsNothing);
      expect(
        tester
            .widget<Semantics>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.label == 'Quick Capture Dock',
              ),
            )
            .explicitChildNodes,
        isTrue,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(Focus.of(tester.element(find.byType(TextField))).hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(QuickCaptureDock), findsNothing);
    },
  );

  testWidgets('QuickCaptureDock fits 320px at two times text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(
            InMemoryMindmapRepository(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: QuickCaptureDock())),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('QuickCaptureDock saves node on submit', (tester) async {
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: Scaffold(body: QuickCaptureDock())),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Project alpha deadline');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    final nodes = await repository.listNodes();
    expect(nodes.any((n) => n.title == 'Project alpha deadline'), isTrue);
  });
}

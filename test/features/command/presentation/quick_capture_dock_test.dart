import 'package:flutter/material.dart';
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
            builder: (context, state) => AdaptiveScaffold(body: Container()),
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
      expect(find.byType(TextField), findsOneWidget);
    },
  );

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

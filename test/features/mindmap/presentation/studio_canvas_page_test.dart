import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/studio_canvas_page.dart';

void main() {
  testWidgets(
    'StudioCanvasPage renders top bar, layers tab, and workspace panels',
    (tester) async {
      final repository = InMemoryMindmapRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(repository),
            allMindmapNodesProvider.overrideWith((ref) async => <MindmapNode>[]),
          ],
          child: const MaterialApp(
            home: StudioCanvasPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Untitled Creative Project'), findsOneWidget);
      expect(find.text('Layers'), findsOneWidget);
      expect(find.text('Design & Properties'), findsOneWidget);
    },
  );

  testWidgets(
    'StudioCanvasPage switches between Layers and Assets tabs',
    (tester) async {
      final repository = InMemoryMindmapRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mindmapRepositoryProvider.overrideWithValue(repository),
            allMindmapNodesProvider.overrideWith((ref) async => <MindmapNode>[]),
          ],
          child: const MaterialApp(
            home: StudioCanvasPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assets'));
      await tester.pumpAndSettle();

      expect(find.text('Components & Presets'), findsOneWidget);
      expect(find.text('Frame (Artboard)'), findsOneWidget);
      expect(find.text('Milanote Card'), findsOneWidget);
    },
  );
}


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/node_editor_panel.dart';

void main() {
  testWidgets('NodeEditorPanel shows autocomplete list when typing [[', (
    tester,
  ) async {
    final today = DateTime(2026, 6, 18);
    final repository = InMemoryMindmapRepository(
      seedNodes: [
        MindmapNode.create(
          id: 'node-target',
          type: NodeType.note,
          title: 'Learn Flutter',
          day: today,
        ),
      ],
    );

    final editNode = MindmapNode.create(
      id: 'node-edit',
      type: NodeType.task,
      title: 'Write some code',
      day: today,
    );

    MindmapNode? savedResult;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(
            body: NodeEditorPanel(
              node: editNode,
              onSave: (node) => savedResult = node,
              onClose: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    // Initial load
    await tester.pumpAndSettle();

    final bodyFieldFinder = find.byKey(
      const ValueKey('node-editor-body-field'),
    );
    expect(bodyFieldFinder, findsOneWidget);

    // No autocomplete before typing [[
    expect(find.text('Link to Node'), findsNothing);

    // Type [[L
    await tester.enterText(bodyFieldFinder, '[[L');
    await tester.pumpAndSettle();

    // Verify autocomplete list shows up and lists "Learn Flutter"
    expect(find.text('Link to Node'), findsOneWidget);
    expect(find.text('Learn Flutter'), findsOneWidget);

    // Tap suggestion
    await tester.tap(find.text('Learn Flutter'));
    await tester.pumpAndSettle();

    // Verify text changed to [[Learn Flutter]]
    final textField = tester.widget<TextField>(bodyFieldFinder);
    expect(textField.controller?.text, '[[Learn Flutter]]');
    // And autocomplete closed
    expect(find.text('Link to Node'), findsNothing);

    // Save
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    // Verify savedResult contains node-target ID in relatedNodeIds
    expect(savedResult, isNotNull);
    expect(savedResult!.relatedNodeIds, contains('node-target'));
  });

  testWidgets(
    'NodeEditorPanel auto-creates placeholder nodes for non-existent links on save',
    (tester) async {
      final today = DateTime(2026, 6, 18);
      final repository = InMemoryMindmapRepository(seedNodes: []);

      final editNode = MindmapNode.create(
        id: 'node-edit',
        type: NodeType.task,
        title: 'Brainstorm',
        day: today,
      );

      MindmapNode? savedResult;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Scaffold(
              body: NodeEditorPanel(
                node: editNode,
                onSave: (node) => savedResult = node,
                onClose: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final bodyFieldFinder = find.byKey(
        const ValueKey('node-editor-body-field'),
      );
      await tester.enterText(bodyFieldFinder, 'Please read [[New Novel]]');
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.byKey(const ValueKey('save-node')));
      await tester.pumpAndSettle();

      // Verify savedResult is not null
      expect(savedResult, isNotNull);
      expect(savedResult!.relatedNodeIds, isNotEmpty);

      // Verify repository now has a node named "New Novel"
      final allNodes = await repository.listNodes();
      final newNovelNode = allNodes.firstWhere((n) => n.title == 'New Novel');
      expect(newNovelNode, isNotNull);
      expect(newNovelNode.type, NodeType.note);
      expect(savedResult!.relatedNodeIds, contains(newNovelNode.id));
    },
  );
}

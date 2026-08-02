import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/life_explorer.dart';

void main() {
  final day = DateTime(2026, 7, 10);

  MindmapNode node(String id, NodeType type, String title, int hour) {
    return MindmapNode.create(
      id: id,
      type: type,
      title: title,
      day: day,
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 7, 10, hour),
    );
  }

  testWidgets('LifeExplorer filters files and selects matching canvas node', (
    tester,
  ) async {
    final task = node('task-1', NodeType.task, 'Ship landing', 9);
    final note = node('note-1', NodeType.note, 'Research notes', 10);
    MindmapNode? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeExplorer(
            day: day,
            nodes: [task, note],
            selectedNodeId: null,
            onNodeSelected: (node) => selected = node,
            onCreateNode: (_) {},
            onCollapse: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('life-explorer')), findsOneWidget);
    expect(find.text('Ship landing'), findsOneWidget);
    expect(find.text('Research notes'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('life-explorer-search')),
      'research',
    );
    await tester.pump();

    expect(find.text('Ship landing'), findsNothing);
    expect(find.text('Research notes'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('life-explorer-node-note-1')));
    expect(selected, note);
  });

  testWidgets('LifeExplorer expands connected node files', (tester) async {
    final task = node(
      'task-1',
      NodeType.task,
      'Ship landing',
      9,
    ).copyWith(relatedNodeIds: const ['note-1']);
    final note = node(
      'note-1',
      NodeType.note,
      'Research notes',
      10,
    ).copyWith(relatedNodeIds: const ['idea-1', 'goal-1']);
    final idea = node('idea-1', NodeType.idea, 'Launch idea', 11);
    final goal = node('goal-1', NodeType.goal, 'Launch goal', 12);
    MindmapNode? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeExplorer(
            day: day,
            nodes: [task, note, idea, goal],
            selectedNodeId: null,
            onNodeSelected: (node) => selected = node,
            onCreateNode: (_) {},
            onCollapse: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('life-explorer-node-task-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('life-explorer-node-note-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('life-explorer-expand-task-1')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('life-explorer-connection-task-1-note-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('life-explorer-guide-task-1-note-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('life-explorer-expand-note-1')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('life-explorer-connection-note-1-idea-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('life-explorer-connection-note-1-goal-1')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('life-explorer-connection-task-1-note-1')),
    );
    expect(selected, note);
  });

  testWidgets('LifeExplorer exposes every supported node type', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeExplorer(
            day: day,
            nodes: const [],
            selectedNodeId: null,
            onNodeSelected: (_) {},
            onCreateNode: (_) {},
            onCollapse: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('life-explorer-new-file')));
    await tester.pumpAndSettle();

    expect(find.text('Action'), findsOneWidget);
    expect(find.text('People & Data'), findsOneWidget);
    final categoryTypes = <NodeType>{};
    for (final category in const [
      'Action',
      'Thinking',
      'Knowledge',
      'Life',
      'People & Data',
      'Media & Travel',
    ]) {
      final categoryFinder = find.byKey(
        ValueKey('life-explorer-category-$category'),
      );
      await tester.ensureVisible(categoryFinder);
      await tester.tap(categoryFinder);
      await tester.pump();
      categoryTypes.addAll(
        NodeType.values.where(
          (type) => find
              .byKey(ValueKey('life-explorer-create-${type.name}'))
              .evaluate()
              .isNotEmpty,
        ),
      );
      if (category == 'Life') {
        final canvas = find.byKey(
          const ValueKey('life-explorer-create-canvas'),
        );
        await tester.scrollUntilVisible(
          canvas,
          50,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('life-explorer-node-type-grid')),
            matching: find.byType(Scrollable),
          ),
        );
        categoryTypes.add(NodeType.canvas);
      }
      tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const ValueKey('life-explorer-node-type-grid')),
              matching: find.byType(Scrollable),
            ),
          )
          .position
          .jumpTo(0);
      await tester.pump();
    }
    expect(categoryTypes, NodeType.values.toSet());
  });

  testWidgets('LifeExplorer creates selected typed file', (tester) async {
    NodeType? createdType;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeExplorer(
            day: day,
            nodes: const [],
            selectedNodeId: null,
            onNodeSelected: (_) {},
            onCreateNode: (type) => createdType = type,
            onCollapse: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('life-explorer-new-file')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('life-explorer-category-Thinking')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('life-explorer-create-note')));
    await tester.pumpAndSettle();

    expect(createdType, NodeType.note);
  });

  testWidgets('LifeExplorer keeps pinned root nodes above recent nodes', (
    tester,
  ) async {
    final recent = node('recent', NodeType.note, 'Recent note', 12);
    final pinned = node(
      'pinned',
      NodeType.task,
      'Pinned task',
      9,
    ).copyWith(isPinned: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeExplorer(
            day: day,
            nodes: [recent, pinned],
            selectedNodeId: null,
            onNodeSelected: (_) {},
            onCreateNode: (_) {},
            onCollapse: () {},
          ),
        ),
      ),
    );

    expect(find.text('PINNED'), findsOneWidget);
    final pinnedY = tester.getTopLeft(find.text('Pinned task')).dy;
    final recentY = tester.getTopLeft(find.text('Recent note')).dy;
    expect(pinnedY, lessThan(recentY));
  });

  testWidgets('pinning a connected child also pins its root ancestor', (
    tester,
  ) async {
    final root = node(
      'root',
      NodeType.task,
      'Root task',
      9,
    ).copyWith(relatedNodeIds: const ['child']);
    final child = node('child', NodeType.note, 'Child note', 10);
    final updates = <MindmapNode>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeExplorer(
            day: day,
            nodes: [root, child],
            selectedNodeId: null,
            onNodeSelected: (_) {},
            onCreateNode: (_) {},
            onCollapse: () {},
            onNodeUpdated: updates.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('life-explorer-expand-root')));
    await tester.pump();
    await tester.longPress(
      find.byKey(const ValueKey('life-explorer-connection-root-child')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();

    expect(updates.map((node) => node.id), containsAll(['root', 'child']));
    expect(updates.every((node) => node.isPinned), isTrue);
  });

  testWidgets('LifeExplorer renames a node inline from its context menu', (
    tester,
  ) async {
    final task = node('task-1', NodeType.task, 'Old title', 9);
    MindmapNode? updated;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeExplorer(
            day: day,
            nodes: [task],
            selectedNodeId: null,
            onNodeSelected: (_) {},
            onCreateNode: (_) {},
            onCollapse: () {},
            onNodeUpdated: (node) => updated = node,
          ),
        ),
      ),
    );

    await tester.longPress(
      find.byKey(const ValueKey('life-explorer-node-task-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pump();

    final editor = find.byKey(const ValueKey('life-explorer-rename-task-1'));
    expect(editor, findsOneWidget);
    await tester.enterText(editor, 'New title');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(updated?.title, 'New title');
  });

  testWidgets('LifeExplorer long press exposes node actions', (tester) async {
    final task = node('task-1', NodeType.task, 'Ship landing', 9);
    MindmapNode? updated;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LifeExplorer(
            day: day,
            nodes: [task],
            selectedNodeId: null,
            onNodeSelected: (_) {},
            onCreateNode: (_) {},
            onCollapse: () {},
            onNodeUpdated: (node) => updated = node,
          ),
        ),
      ),
    );

    await tester.longPress(
      find.byKey(const ValueKey('life-explorer-node-task-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open / edit'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();
    expect(updated?.isPinned, isTrue);
  });
}

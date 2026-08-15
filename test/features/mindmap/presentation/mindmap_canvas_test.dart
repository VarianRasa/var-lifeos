import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/media_file_import_service.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/application/node_inline_edit_controller.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/connection_style.dart';
import 'package:var_app/features/mindmap/domain/hybrid_timer.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/kanban_board.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/domain/node_ui_state_codec.dart';
import 'package:var_app/features/mindmap/presentation/inline_node_workspace.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';
import 'package:var_app/features/mindmap/presentation/node_shell.dart';
import 'package:var_app/features/mindmap/presentation/widgets/connection_style_bar.dart';

Future<void> settleCanvas(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('renders exactly one expanded node at policy size', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 15);
    final nodes = <MindmapNode>[
      MindmapNode.create(
        id: 'note',
        type: NodeType.note,
        title: 'Note',
        day: day,
        now: day,
      ),
      MindmapNode.create(
        id: 'kanban',
        type: NodeType.kanban,
        title: 'Board',
        day: day,
        now: day,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: nodes,
            expandedNodeId: 'kanban',
            expandedNodeBuilder: (node) =>
                SizedBox(key: ValueKey('expanded-${node.id}')),
          ),
        ),
      ),
    );
    await settleCanvas(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('expanded-kanban')), findsOneWidget);
    expect(find.byKey(const ValueKey('expanded-note')), findsNothing);
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(
      nodes.firstWhere((n) => n.id == 'kanban'),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mindmap-node-kanban'))),
      Size(policy.width, policy.height),
    );
  });

  testWidgets('canvas auto layout menu exposes auto time-block action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var autoTimeBlockRequested = false;
    final day = DateTime(2026, 8, 13);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [
              MindmapNode.create(
                id: 'auto-time-block-task',
                type: NodeType.task,
                title: 'Schedule me',
                day: day,
                now: day,
              ),
            ],
            onAutoTimeBlockRequested: () => autoTimeBlockRequested = true,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    await tester.tap(find.byTooltip('Show canvas controls'));
    await settleCanvas(tester);
    await tester.tap(find.byTooltip('Auto layout'));
    await settleCanvas(tester);

    expect(find.text('Auto Time-Block'), findsOneWidget);
    await tester.tap(find.text('Auto Time-Block'));
    await settleCanvas(tester);

    expect(autoTimeBlockRequested, isTrue);
  });

  testWidgets('bookmark fields keep focus and autosave one merged node', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 17);
    var node = MindmapNode.create(
      id: 'bookmark-autosave',
      type: NodeType.bookmark,
      title: 'Bookmark',
      body: 'Saved reference',
      day: day,
      now: day,
    );
    final updates = <MindmapNode>[];
    final saveStatuses = <NodeSaveStatus>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 680,
              height: 900,
              child: StatefulBuilder(
                builder: (context, setState) =>
                    buildProductionNodeInlineEditorForTest(
                      node: node,
                      onNodeUpdated: (updated) {
                        updates.add(updated);
                        setState(() => node = updated);
                      },
                      onSaveStatusChanged: saveStatuses.add,
                    ),
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> typeProgressively(String key, String value) async {
      final finder = find.byKey(ValueKey<String>(key));
      await tester.tap(finder);
      await tester.pump();
      for (var index = 1; index <= value.length; index++) {
        tester.testTextInput.enterText(value.substring(0, index));
        await tester.pump();
        final editable = tester.widget<EditableText>(
          find.descendant(of: finder, matching: find.byType(EditableText)),
        );
        expect(editable.focusNode.hasFocus, isTrue);
      }
    }

    await typeProgressively(
      'knowledge-bookmark-url-field',
      'https://example.com/reference',
    );
    await typeProgressively(
      'knowledge-bookmark-why-field',
      'Useful architecture reference',
    );
    await typeProgressively('knowledge-bookmark-collection-field', 'Research');
    await settleCanvas(tester);

    final payload = LinkResourcePayload.fromNode(node);
    expect(payload.url, 'https://example.com/reference');
    expect(payload.description, 'Useful architecture reference');
    expect(payload.collection, 'Research');
    expect(updates, isNotEmpty);
    expect(saveStatuses.last, NodeSaveStatus.saved);
    expect(saveStatuses, isNot(contains(NodeSaveStatus.error)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('bookmark fields accept slash and external clipboard paste', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 17);
    var node = MindmapNode.create(
      id: 'bookmark-keyboard-input',
      type: NodeType.bookmark,
      title: 'Bookmark',
      body: 'Saved reference',
      day: day,
      now: day,
    );
    var clipboardText = 'example.com/path?q=a/b#section';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => MindmapCanvas(
                nodes: <MindmapNode>[node],
                expandedNodeId: node.id,
                expandedNodeBuilder: (_) =>
                    buildProductionNodeInlineEditorForTest(
                      node: node,
                      onNodeUpdated: (updated) {
                        setState(() => node = updated);
                      },
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    Future<void> pasteInto(String key, String value) async {
      clipboardText = value;
      final finder = find.byKey(ValueKey<String>(key));
      await tester.tap(finder);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    final urlField = find.byKey(
      const ValueKey<String>('knowledge-bookmark-url-field'),
    );
    await tester.tap(urlField);
    tester.testTextInput.enterText('https:');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
    await tester.pump();
    final urlEditable = tester.widget<EditableText>(
      find.descendant(of: urlField, matching: find.byType(EditableText)),
    );
    expect(urlEditable.focusNode.hasFocus, isTrue);
    tester.testTextInput.enterText('https://');
    await tester.pump();
    await pasteInto(
      'knowledge-bookmark-url-field',
      'example.com/path?q=a/b#section',
    );
    await pasteInto(
      'knowledge-bookmark-why-field',
      'Saved / copied from external source',
    );
    await pasteInto(
      'knowledge-bookmark-collection-field',
      'Research / Flutter',
    );
    await settleCanvas(tester);

    final payload = LinkResourcePayload.fromNode(node);
    expect(payload.url, 'https://example.com/path?q=a/b#section');
    expect(payload.description, 'Saved / copied from external source');
    expect(payload.collection, 'Research / Flutter');
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed bookmark stays finite at narrow custom size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 17);
    final base = MindmapNode.create(
      id: 'bookmark-narrow-collapse',
      type: NodeType.bookmark,
      title: 'New Bookmark',
      body: '## Bookmark',
      day: day,
      now: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 244.0,
        nodeUiHeightKey: 242.0,
      },
    );
    final node = const LinkResourcePayload(
      type: NodeType.bookmark,
      url: 'https://example.com/reference',
      description: 'Useful reference',
      bookmarkStatus: 'inbox',
      tags: <String>['bookmark'],
    ).toNode(base);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: <MindmapNode>[node])),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-bookmark-narrow-collapse'),
    );
    expect(tester.getSize(nodeFinder), const Size(244, 242));
    expect(find.text('URL: example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed bookmark remains finite around action threshold', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 17);

    for (final size in const <Size>[
      Size(244, 245),
      Size(280, 250),
      Size(340, 278),
      Size(340, 280),
      Size(340, 380),
    ]) {
      final base = MindmapNode.create(
        id: 'bookmark-threshold-${size.width}-${size.height}',
        type: NodeType.bookmark,
        title: 'Bookmark',
        body: '## Bookmark',
        day: day,
        now: day,
        data: <String, Object?>{
          nodeUiSizePresetKey: 'custom',
          nodeUiWidthKey: size.width,
          nodeUiHeightKey: size.height,
        },
      );
      final node = const LinkResourcePayload(
        type: NodeType.bookmark,
        url: 'https://example.com/reference',
        description: 'Useful reference',
        collection: 'Research',
        bookmarkStatus: 'inbox',
        isFavorite: true,
        tags: <String>['bookmark', 'research'],
      ).toNode(base);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MindmapCanvas(nodes: <MindmapNode>[node])),
        ),
      );
      await settleCanvas(tester);
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('expanded bookmark uses fixed content size without resize', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 17);
    final base = MindmapNode.create(
      id: 'bookmark-fixed-size',
      type: NodeType.bookmark,
      title: 'Bookmark',
      body: 'Saved reference',
      day: day,
      now: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 920.0,
        nodeUiHeightKey: 1040.0,
      },
    );
    final node = const LinkResourcePayload(
      type: NodeType.bookmark,
      url: 'https://example.com/reference',
      description: 'Useful architecture reference',
      collection: 'Research',
      tags: <String>['flutter', 'architecture'],
    ).toNode(base);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-bookmark-fixed-size'),
    );
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    expect(tester.getSize(nodeFinder), Size(policy.width, policy.height));
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded image uses fixed content size without resize', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 18);
    final base = MindmapNode.create(
      id: 'image-fixed-size',
      type: NodeType.image,
      title: 'Image',
      day: day,
      now: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 420.0,
        nodeUiHeightKey: 300.0,
      },
    );
    final node = base.copyWith(
      data: const ImagePayload(
        url: 'https://example.test/image.png',
        altText: 'Example image',
      ).toData(base.data),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-image-fixed-size'),
    );
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    expect(tester.getSize(nodeFinder), Size(policy.width, policy.height));
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded weather uses fixed size without resize', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 19);
    final node = MindmapNode.create(
      id: 'weather-fixed-size',
      type: NodeType.weather,
      title: 'Weather',
      day: day,
      now: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 320.0,
        nodeUiHeightKey: 240.0,
        'temp': '27',
        'weather': 'Clear',
        'weatherLocation': 'Jakarta, Indonesia',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-weather-fixed-size'),
    );
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    expect(tester.getSize(nodeFinder), Size(policy.width, policy.height));
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded fitness uses fixed size without resize', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 19);
    final node = MindmapNode.create(
      id: 'fitness-fixed-size',
      type: NodeType.fit,
      title: 'Morning fitness',
      day: day,
      now: day,
      data: const FitPayload(
        steps: 6000,
        water: 1.5,
        workout: 'Run',
      ).toData(const <String, Object?>{}),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-fitness-fixed-size'),
    );
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    expect(tester.getSize(nodeFinder), Size(policy.width, policy.height));
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed fitness shows full dashboard and quick actions', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 20);
    final base = MindmapNode.create(
      id: 'fitness-collapsed-dashboard',
      type: NodeType.fit,
      title: 'Cycling recovery',
      day: day,
      now: day,
    );
    var node = base.copyWith(
      data: const FitPayload(
        steps: 8123,
        stepGoal: 10000,
        water: 1.75,
        waterGoal: 2.5,
        waterUnit: 'L',
        distance: 12.4,
        durationMinutes: 52,
        durationGoalMinutes: 60,
        calories: 430,
        calorieGoal: 600,
        sleepHours: 7.25,
        restingHeartRate: 57,
        workout: 'Cycling',
        syncEnabled: true,
        syncSource: 'Health Connect',
      ).toData(base.data),
    );
    final updates = <MindmapNode>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: StatefulBuilder(
                builder: (context, setState) =>
                    buildCollapsedFitnessDetailsForTest(
                      node,
                      onNodeUpdated: (updated) {
                        updates.add(updated);
                        setState(() => node = updated);
                      },
                    ),
              ),
            ),
          ),
        ),
      ),
    );

    for (final key in <String>[
      'fit-collapse-workout',
      'fit-collapse-steps',
      'fit-collapse-active',
      'fit-collapse-water',
      'fit-collapse-calories',
      'fit-collapse-distance',
      'fit-collapse-sleep',
      'fit-collapse-heart-rate',
      'fit-collapse-sync',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget);
    }
    expect(find.text('Cycling'), findsOneWidget);
    expect(find.text('52 / 60 min'), findsOneWidget);
    expect(find.text('430 kcal'), findsOneWidget);
    expect(find.text('12.4 km'), findsOneWidget);
    expect(find.text('7.25 h'), findsOneWidget);
    expect(find.text('57 bpm'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('fit-collapse-steps-add')),
    );
    await tester.pump();
    var updatedPayload = FitPayload.fromNode(updates.last);
    expect(updatedPayload.steps, 9123);
    expect(updatedPayload.durationMinutes, 52);
    expect(updates.last.data.containsKey('stepTarget'), isFalse);

    await tester.tap(
      find.byKey(const ValueKey<String>('fit-collapse-water-add')),
    );
    await tester.pump();
    updatedPayload = FitPayload.fromNode(updates.last);
    expect(updatedPayload.water, 2);
    expect(updatedPayload.waterUnit, 'L');
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed quote shows collection features without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 17);
    final base = MindmapNode.create(
      id: 'quote-collapsed-features',
      type: NodeType.quote,
      title: 'Favorite Quote',
      body: 'The most dangerous phrase is: we have always done it this way.',
      day: day,
      now: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 280.0,
        nodeUiHeightKey: 260.0,
      },
    );
    final node = base.copyWith(
      data: const QuotePayload(
        author: 'Grace Hopper',
        source: 'Talk',
        collection: 'Computing',
        tags: <String>['wisdom', 'history'],
        isFavorite: true,
      ).toData(base.data),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            onNodeUpdated: (_) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(find.byKey(const ValueKey('quote-collapsed-text')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('quote-collapsed-author')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('quote-collapsed-favorite')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('quote-collapsed-copy')), findsOneWidget);
    expect(find.text('Computing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded quote uses content size without resize controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 17);
    final base = MindmapNode.create(
      id: 'quote-fixed-size',
      type: NodeType.quote,
      title: 'Quote',
      body: 'Stay curious and keep learning.',
      day: day,
      now: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 900.0,
        nodeUiHeightKey: 1000.0,
      },
    );
    final node = base.copyWith(
      data: const QuotePayload(
        author: 'Ada',
        collection: 'Computing',
        tags: <String>['wisdom'],
      ).toData(base.data),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-quote-fixed-size'),
    );
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    expect(tester.getSize(nodeFinder), Size(policy.width, policy.height));
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded idea uses auto size without resize controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 16);
    final base = MindmapNode.create(
      id: 'auto-size-idea',
      type: NodeType.idea,
      title: 'Idea',
      body: 'Context',
      day: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 900.0,
        nodeUiHeightKey: 1200.0,
      },
      now: day,
    );
    final node = base.copyWith(
      data: const IdeaPayload(
        hypothesis: 'Users need faster capture',
        impact: 'high',
        effort: 'medium',
        nextAction: 'Build prototype',
      ).toData(base.data),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-auto-size-idea'),
    );
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    expect(tester.getSize(nodeFinder), Size(policy.width, policy.height));
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed idea keeps manual resize controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 16);
    final node = MindmapNode.create(
      id: 'resizable-collapsed-idea',
      type: NodeType.idea,
      title: 'Idea',
      day: day,
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-resizable-collapsed-idea'),
    );
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNotNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded decision uses auto size without resize controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 16);
    final base = MindmapNode.create(
      id: 'auto-size-decision',
      type: NodeType.decision,
      title: 'Decision',
      day: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 1000.0,
        nodeUiHeightKey: 1300.0,
      },
      now: day,
    );
    final node = base.copyWith(
      data: const DecisionPayload(
        question: 'Which option?',
        criteria: <DecisionCriterion>[
          DecisionCriterion(id: 'impact', name: 'Impact'),
        ],
        options: <DecisionOption>[
          DecisionOption(id: 'a', title: 'A'),
          DecisionOption(id: 'b', title: 'B'),
        ],
      ).toData(base.data),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-auto-size-decision'),
    );
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    expect(tester.getSize(nodeFinder), Size(policy.width, policy.height));
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed decision keeps manual resize controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 16);
    final node = MindmapNode.create(
      id: 'resizable-collapsed-decision',
      type: NodeType.decision,
      title: 'Decision',
      day: day,
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-resizable-collapsed-decision'),
    );
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNotNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded question uses auto size without resize controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 16);
    final base = MindmapNode.create(
      id: 'auto-size-question',
      type: NodeType.question,
      title: 'Question',
      body: 'Context',
      day: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 900.0,
        nodeUiHeightKey: 1200.0,
      },
      now: day,
    );
    final node = base.copyWith(
      data: const QuestionPayload(
        questionText: 'Which option should ship?',
        possibleAnswers: <String>['Option A', 'Option B'],
        nextResearchAction: 'Run a usability test',
      ).toData(base.data),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-auto-size-question'),
    );
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    expect(tester.getSize(nodeFinder), Size(policy.width, policy.height));
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed question keeps manual resize controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 16);
    final node = MindmapNode.create(
      id: 'resizable-collapsed-question',
      type: NodeType.question,
      title: 'Question',
      day: day,
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-resizable-collapsed-question'),
    );
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNotNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded resource uses auto size without resize controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 17);
    final base = MindmapNode.create(
      id: 'auto-size-resource',
      type: NodeType.resource,
      title: 'Resource',
      day: day,
      now: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 980.0,
        nodeUiHeightKey: 1300.0,
      },
    );
    final node = base.copyWith(
      data: const ResourcePayload(
        primaryAsset: ResourceAsset(
          id: 'primary',
          kind: 'file',
          location: 'manual.pdf',
          fileName: 'manual.pdf',
          extension: 'pdf',
        ),
        relatedAssets: <ResourceAsset>[
          ResourceAsset(
            id: 'related',
            kind: 'url',
            location: 'https://example.test/reference',
          ),
        ],
        folderPath: <String>['Research', 'Flutter'],
        description: 'Reference document.',
        tags: <String>['flutter'],
      ).toData(base.data),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-auto-size-resource'),
    );
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    expect(tester.getSize(nodeFinder), Size(policy.width, policy.height));
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resource collapsed preview stays bounded and resizable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 17);
    final base = MindmapNode.create(
      id: 'collapsed-resource',
      type: NodeType.resource,
      title: 'Manual',
      day: day,
      now: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 357.5,
        nodeUiHeightKey: 243.7,
      },
    );
    final node = base.copyWith(
      data: const ResourcePayload(
        folders: <ResourceFolder>[
          ResourceFolder(id: 'research', name: 'Research'),
          ResourceFolder(id: 'flutter', name: 'Flutter', parentId: 'research'),
          ResourceFolder(
            id: 'rendering',
            name: 'Rendering',
            parentId: 'flutter',
          ),
        ],
        relatedAssets: <ResourceAsset>[
          ResourceAsset(
            id: 'related-1',
            kind: 'file',
            attachmentId: 'manual-attachment',
            fileName: 'manual.pdf',
            extension: 'pdf',
            folderId: 'rendering',
          ),
          ResourceAsset(
            id: 'related-2',
            kind: 'url',
            label: 'Reference',
            location: 'https://example.test/two',
            folderId: 'rendering',
          ),
        ],
        folderPath: <String>['Research', 'Flutter', 'Rendering'],
        tags: <String>['flutter', 'rendering', 'reference'],
      ).toData(base.data),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-collapsed-resource'),
    );
    expect(find.text('Resource'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Folder: Research / Flutter / Rendering'), findsOneWidget);
    expect(find.text('Assets: 2'), findsOneWidget);
    expect(find.text('2 assets'), findsOneWidget);
    expect(find.text('#flutter'), findsOneWidget);
    expect(find.text('Copy source'), findsOneWidget);
    expect(
      find.descendant(
        of: nodeFinder,
        matching: find.byKey(
          const ValueKey<String>('resource-collapsed-preview'),
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: nodeFinder,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNotNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed timer can pause without expanding', (tester) async {
    final day = DateTime(2026, 7, 16);
    final base = MindmapNode.create(
      id: 'timer-preview',
      type: NodeType.timer,
      title: 'Focus',
      day: day,
      now: day,
    );
    final timer = HybridTimerState(
      mode: TimerMode.countdown,
      status: TimerRunStatus.running,
      plannedSeconds: 1500,
      startedAt: DateTime.now().subtract(const Duration(seconds: 60)),
      sessionStartedAt: DateTime.now().subtract(const Duration(seconds: 60)),
    );
    final node = base.copyWith(
      data: TimerPayload(timer: timer).toData(base.data),
    );
    final updatedNodes = <MindmapNode>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            onNodeUpdated: updatedNodes.add,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('timer-collapsed-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('timer-primary-action')),
      findsNothing,
    );
    final collapsedAction = find.byKey(
      const ValueKey<String>('timer-collapsed-primary-action'),
    );
    expect(collapsedAction, findsOneWidget);
    expect(find.text('Running'), findsOneWidget);

    await tester.tap(collapsedAction);
    await tester.pump();

    expect(updatedNodes, hasLength(1));
    expect(
      TimerPayload.fromNode(updatedNodes.single).timer.status,
      TimerRunStatus.paused,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed checklist toggles item without expanding', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 16);
    final base = MindmapNode.create(
      id: 'checklist-preview',
      type: NodeType.checklist,
      title: 'Launch checklist',
      day: day,
      now: day,
    );
    final node =
        const ChecklistPayload(
          items: <ChecklistEntry>[
            ChecklistEntry(id: 'review', title: 'Review release'),
            ChecklistEntry(id: 'test', title: 'Run tests'),
            ChecklistEntry(id: 'ship', title: 'Ship release'),
          ],
        ).toNode(
          base.copyWith(
            body: '## Checklist\n- [ ] Task 1\n- [ ] Task 2\n- [ ] Task 3',
          ),
        );
    final updatedNodes = <MindmapNode>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            onNodeUpdated: updatedNodes.add,
            onTaskChecklistItemCompleted: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('checklist-collapsed-preview')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('checklist-collapsed-toggle-review')),
    );
    await tester.pump();

    expect(updatedNodes, hasLength(1));
    expect(
      ChecklistPayload.fromNode(
        updatedNodes.single,
      ).items.firstWhere((item) => item.id == 'review').isDone,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('expanded editor controls do not drag node', (tester) async {
    final day = DateTime(2026, 7, 15);
    final node = MindmapNode.create(
      id: 'expanded-drag',
      type: NodeType.note,
      title: 'Note',
      day: day,
      now: day,
    );
    var moves = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) =>
                const TextField(key: ValueKey('expanded-field')),
            onNodeMoved: (_, _) => moves++,
          ),
        ),
      ),
    );
    await settleCanvas(tester);
    await tester.drag(
      find.byKey(const ValueKey('expanded-field')),
      const Offset(80, 40),
    );
    await tester.pump();

    expect(moves, 0);
  });

  testWidgets('task tooltip closes safely during expanded transition', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_PersistingResizeHarnessState>();
    await tester.pumpWidget(_PersistingResizeHarness(key: key));
    await settleCanvas(tester);

    final toggle = find.byKey(
      const ValueKey('mindmap-task-toggle-persist-resize'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(toggle));
    await mouse.moveTo(tester.getCenter(toggle));
    await tester.pump(const Duration(milliseconds: 600));

    key.currentState!.setExpanded(true);
    await tester.pump();
    await settleCanvas(tester);

    expect(toggle, findsOneWidget);
    final visibility = tester.widget<AnimatedOpacity>(
      find.byKey(
        const ValueKey('mindmap-task-toggle-visibility-persist-resize'),
      ),
    );
    expect(visibility.opacity, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded task header hides collapsed checkbox overlay', (
    tester,
  ) async {
    final DateTime day = DateTime(2026, 7, 16);
    final MindmapNode node = MindmapNode.create(
      id: 'expanded-task-header',
      type: NodeType.task,
      title: 'Fitur kedua',
      day: day,
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const InlineNodeWorkspaceSurface(
              header: SizedBox(
                key: ValueKey('expanded-task-custom-header'),
                height: 64,
              ),
              body: SizedBox(),
              footer: SizedBox(height: 32),
            ),
            onTaskDoneChanged: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(
      find.byKey(const ValueKey('expanded-task-custom-header')),
      findsOneWidget,
    );
    final visibility = tester.widget<AnimatedOpacity>(
      find.byKey(
        const ValueKey('mindmap-task-toggle-visibility-expanded-task-header'),
      ),
    );
    expect(visibility.opacity, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('keyboard connection ports start and complete connection', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 16);
    final source = MindmapNode.create(
      id: 'keyboard-source',
      type: NodeType.note,
      title: 'Source',
      day: day,
      position: const CanvasPosition(-220, 0),
      now: day,
    );
    final target = MindmapNode.create(
      id: 'keyboard-target',
      type: NodeType.note,
      title: 'Target',
      day: day,
      position: const CanvasPosition(220, 0),
      now: day,
    );
    (MindmapNode, MindmapNode)? connected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [source, target],
            onNodeConnected: (source, target) => connected = (source, target),
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final output = find.byKey(
      const ValueKey('mindmap-output-port-keyboard-source'),
    );
    expect(tester.getSemantics(output).label, contains('Start connection'));
    final outputFocus = find.byKey(
      const ValueKey('mindmap-output-port-focus-keyboard-source'),
    );
    Focus.of(
      tester.element(
        find
            .descendant(of: outputFocus, matching: find.byType(Semantics))
            .first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_ConnectionDragPainter',
      ),
      findsOneWidget,
    );
    final inputFocus = find.byKey(
      const ValueKey('mindmap-input-port-focus-keyboard-target'),
    );
    Focus.of(
      tester.element(
        find.descendant(of: inputFocus, matching: find.byType(Semantics)).first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(connected?.$1.id, source.id);
    expect(connected?.$2.id, target.id);
  });

  testWidgets('expanded controls isolate drag wheel slider and shortcuts', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 16);
    final node = MindmapNode.create(
      id: 'isolation',
      type: NodeType.note,
      title: 'Isolation',
      day: day,
      now: day,
    );
    var moves = 0;
    var slider = 0.5;
    var footerPresses = 0;
    var mediaPresses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MindmapCanvas(
              nodes: [node],
              expandedNodeId: node.id,
              expandedNodeBuilder: (_) => InlineNodeWorkspaceSurface(
                header: const SizedBox(height: 64, child: Text('Header')),
                body: ListView(
                  children: [
                    const TextField(key: ValueKey('isolation-field')),
                    Slider(
                      key: const ValueKey('isolation-slider'),
                      value: slider,
                      onChanged: (value) => setState(() => slider = value),
                    ),
                    IconButton(
                      key: const ValueKey('isolation-media'),
                      onPressed: () => mediaPresses++,
                      icon: const Icon(Icons.play_arrow),
                    ),
                    const SizedBox(height: 800),
                  ],
                ),
                footer: TextButton(
                  key: const ValueKey('isolation-footer'),
                  onPressed: () => footerPresses++,
                  child: const Text('Footer'),
                ),
              ),
              onNodeMoved: (_, _) => moves++,
            ),
          ),
        ),
      ),
    );
    await settleCanvas(tester);
    final field = find.byKey(const ValueKey('isolation-field'));
    await tester.tap(field);
    await tester.enterText(field, '+-0/');
    final fieldController = tester
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .controller;
    await tester.drag(field, const Offset(80, 0));
    await tester.drag(
      find.byKey(const ValueKey('isolation-slider')),
      const Offset(40, 0),
    );
    await tester.tap(find.byKey(const ValueKey('isolation-media')));
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final beforeScroll = scrollable.position.pixels;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ListView)),
        scrollDelta: const Offset(0, 180),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('isolation-footer')));
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final beforeKeys = viewer.transformationController!.value.clone();
    for (final key in [
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.slash,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pump();

    expect(moves, 0);
    expect(mediaPresses, 1);
    expect(footerPresses, 1);
    expect(scrollable.position.pixels, greaterThan(beforeScroll));
    expect(viewer.transformationController!.value, equals(beforeKeys));
    expect(fieldController.text, '+-0/');
    expect(find.text('Command Palette'), findsNothing);
  });

  testWidgets('clear selection awaits guard and aborts when denied', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 15);
    final node = MindmapNode.create(
      id: 'guarded-clear',
      type: NodeType.note,
      title: 'Guarded',
      day: day,
      now: day,
    );
    final guard = Completer<bool>();
    var clears = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onExpandedSelectionChanging: (current, next) {
              expect(current, node.id);
              return next == null ? guard.future : true;
            },
            onSelectionCleared: () => clears++,
          ),
        ),
      ),
    );
    await settleCanvas(tester);
    await tester
        .state<MindmapCanvasState>(find.byType(MindmapCanvas))
        .selectAndFocusNode(node);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(clears, 0);
    guard.complete(false);
    await tester.pump();
    expect(clears, 0);
  });

  testWidgets('stale guarded clear cannot erase newer selection', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 15);
    final first = MindmapNode.create(
      id: 'race-a',
      type: NodeType.note,
      title: 'A',
      day: day,
      now: day,
    );
    final second = MindmapNode.create(
      id: 'race-b',
      type: NodeType.note,
      title: 'B',
      day: day,
      now: day,
    );
    final clearGuard = Completer<bool>();
    final selected = <String>[];
    var clears = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[first, second],
            expandedNodeId: first.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onExpandedSelectionChanging: (_, next) =>
                next == null ? clearGuard.future : true,
            onNodeSelected: (node) => selected.add(node.id),
            onSelectionCleared: () => clears++,
          ),
        ),
      ),
    );
    await settleCanvas(tester);
    final state = tester.state<MindmapCanvasState>(find.byType(MindmapCanvas));
    await state.selectAndFocusNode(first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await state.selectAndFocusNode(second);
    await tester.pump();
    clearGuard.complete(true);
    await tester.pump();

    expect(selected.last, second.id);
    expect(clears, 0);
  });

  testWidgets('rejected and stale selections do not move viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 15);
    final pending = MindmapNode.create(
      id: 'focus-pending',
      type: NodeType.note,
      title: 'Pending',
      day: day,
      position: const CanvasPosition(-1200, 0),
      now: day,
    );
    final accepted = MindmapNode.create(
      id: 'focus-accepted',
      type: NodeType.note,
      title: 'Accepted',
      day: day,
      position: const CanvasPosition(900, 400),
      now: day,
    );
    final rejected = MindmapNode.create(
      id: 'focus-rejected',
      type: NodeType.note,
      title: 'Rejected',
      day: day,
      position: const CanvasPosition(1600, -600),
      now: day,
    );
    final pendingGuard = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[pending, accepted, rejected],
            onExpandedSelectionChanging: (_, next) => switch (next) {
              'focus-pending' => pendingGuard.future,
              'focus-rejected' => false,
              _ => true,
            },
          ),
        ),
      ),
    );
    await settleCanvas(tester);
    final state = tester.state<MindmapCanvasState>(find.byType(MindmapCanvas));
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final initial = controller.value.storage.toList();

    expect(await state.selectAndFocusNode(rejected), isFalse);
    await settleCanvas(tester);
    expect(controller.value.storage, orderedEquals(initial));

    final staleSelection = state.selectAndFocusNode(pending);
    await tester.pump();
    expect(await state.selectAndFocusNode(accepted), isTrue);
    await settleCanvas(tester);
    final acceptedTransform = controller.value.storage.toList();
    pendingGuard.complete(true);
    expect(await staleSelection, isFalse);
    await settleCanvas(tester);
    expect(controller.value.storage, orderedEquals(acceptedTransform));
  });

  test('expanded geometry covers families and preserves identity', () {
    const cases = <NodeType, Size>{
      NodeType.empty: Size(280, 180),
      NodeType.note: Size(360, 280),
      NodeType.goal: Size(440, 360),
      NodeType.kanban: Size(560, 380),
    };
    const position = CanvasPosition(40, -20);
    const origin = Offset(1000, 700);
    const minimapSize = Size(180, 120);
    for (final entry in cases.entries) {
      final day = DateTime(2026, 7, 15);
      final node = MindmapNode.create(
        id: 'same-id',
        type: entry.key,
        title: entry.key.name,
        day: day,
        position: position,
        now: day,
      );
      final geometry = MindmapExpandedNodeGeometry(
        node: node,
        size: entry.value,
        origin: origin,
      );
      expect(geometry.node.id, 'same-id');
      expect(geometry.node.position, position);
      expect(
        geometry.hitRect,
        Rect.fromLTWH(1040, 680, entry.value.width, entry.value.height),
      );
      expect(geometry.inputPort, Offset(1042, 680 + entry.value.height / 2));
      expect(
        geometry.outputPort,
        Offset(1038 + entry.value.width, 680 + entry.value.height / 2),
      );
      final minimapRect = geometry.minimapRect(
        minimapSize: minimapSize,
        canvasSize: MindmapCanvas.canvasSize,
      );
      expect(
        minimapRect.left,
        closeTo(
          1040 * minimapSize.width / MindmapCanvas.canvasSize.width,
          1e-9,
        ),
      );
      expect(
        minimapRect.top,
        closeTo(
          680 * minimapSize.height / MindmapCanvas.canvasSize.height,
          1e-9,
        ),
      );
      expect(
        minimapRect.width,
        closeTo(
          entry.value.width *
              minimapSize.width /
              MindmapCanvas.canvasSize.width,
          1e-9,
        ),
      );
      expect(
        minimapRect.height,
        closeTo(
          entry.value.height *
              minimapSize.height /
              MindmapCanvas.canvasSize.height,
          1e-9,
        ),
      );
    }
  });

  testWidgets('expanded geometry drives canvas systems and restores size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 16);
    final expanded = MindmapNode.create(
      id: 'geometry-expanded',
      type: NodeType.kanban,
      title: 'Expanded',
      day: day,
      position: const CanvasPosition(-260, 0),
      data: const {
        'groupId': 'expanded-group',
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 420.0,
        nodeUiHeightKey: 240.0,
      },
      now: day,
    );
    final target = MindmapNode.create(
      id: 'geometry-target',
      type: NodeType.note,
      title: 'Target',
      day: day,
      position: const CanvasPosition(360, 0),
      data: const {'groupId': 'expanded-group'},
      now: day,
    );
    final canvasKey = GlobalKey<MindmapCanvasState>();
    StateSetter? rebuild;
    var expandedId = expanded.id;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MindmapCanvas(
                key: canvasKey,
                nodes: [expanded, target],
                expandedNodeId: expandedId,
                expandedNodeBuilder: (_) => const SizedBox(),
              );
            },
          ),
        ),
      ),
    );
    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.toggleMinimap,
    );
    await settleCanvas(tester);

    final node = find.byKey(const ValueKey('mindmap-node-geometry-expanded'));
    final expandedSize = InlineNodeWorkspacePolicy.expandedSizeForNode(
      expanded,
    );
    expect(tester.getSize(node), Size(expandedSize.width, expandedSize.height));
    final rect = tester.getRect(node);
    expect(
      tester
          .getCenter(
            find.byKey(const ValueKey('mindmap-output-port-geometry-expanded')),
          )
          .dy,
      closeTo(rect.center.dy, 1),
    );
    final groupRect = tester.getRect(
      find.byKey(const ValueKey('mindmap-group-expanded-group')),
    );
    expect(groupRect.contains(rect.topLeft), isTrue);
    expect(groupRect.contains(rect.bottomRight), isTrue);
    final marker = tester.getSize(
      find.byKey(const ValueKey('mindmap-minimap-node-geometry-expanded')),
    );
    final minimap = tester.getSize(
      find.byKey(const ValueKey('mindmap-minimap-semantics')),
    );
    expect(marker.width, greaterThan(40));
    expect(marker.width, lessThan(minimap.width));
    expect(marker.height, lessThan(minimap.height));
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final beforeFit = viewer.transformationController!.value.clone();
    await canvasKey.currentState!.runContextAction(CanvasContextAction.fitAll);
    await settleCanvas(tester);
    expect(viewer.transformationController!.value, isNot(equals(beforeFit)));

    rebuild!(() => expandedId = '');
    await settleCanvas(tester);
    expect(tester.getSize(node), const Size(420, 240));
  });

  test(
    'presentation cache reuses unchanged nodes and invalidates one update',
    () {
      final now = DateTime(2026, 7, 13, 8);
      final first = MindmapNode.create(
        id: 'cache-first',
        type: NodeType.note,
        title: 'First',
        day: now,
        now: now,
      );
      final second = MindmapNode.create(
        id: 'cache-second',
        type: NodeType.task,
        title: 'Second',
        day: now,
        now: now,
      );
      final cache = MindmapNodePresentationCache();

      cache.sizesFor([first, second]);
      expect(cache.parseCount, 2);
      expect(cache.payloadParseCount, 2);
      cache.sizesFor([first, second]);
      expect(cache.parseCount, 2);
      cache.sizesFor([first.copyWith(), second.copyWith()]);
      expect(cache.parseCount, 2);
      expect(cache.payloadParseCount, 2);
      expect(cache.typedPayloadFor(second), isA<TaskChecklistPayload>());
      cache.sizesFor([
        first.copyWith(title: 'Renamed', position: const CanvasPosition(8, 9)),
        second,
      ]);
      expect(cache.parseCount, 2);
      expect(cache.payloadParseCount, 2);

      final changed = first.copyWith(
        data: NodeUiStateCodec.write(
          first,
          NodeUiState(sizePreset: NodeSizePreset.wide, width: 520, height: 280),
        ),
        updatedAt: now.add(const Duration(seconds: 1)),
      );
      final sizes = cache.sizesFor([changed, second]);
      expect(cache.parseCount, 3);
      expect(cache.payloadParseCount, 3);
      final wide = NodePresentationSpec.forType(
        NodeType.note,
      ).resolve(preset: NodeSizePreset.wide);
      expect(sizes['cache-first'], Size(wide.width, wide.height));
    },
  );

  testWidgets('typing does not rebuild unrelated canvas node cards', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 7, 13, 8);
    final first = MindmapNode.create(
      id: 'typing-first',
      type: NodeType.note,
      title: 'First',
      day: now,
      position: const CanvasPosition(-220, 0),
      now: now,
    );
    final second = MindmapNode.create(
      id: 'typing-second',
      type: NodeType.note,
      title: 'Second',
      day: now,
      position: const CanvasPosition(220, 0),
      now: now,
    );
    final builds = <String, int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [first, second],
            highlightedNodeId: first.id,
            onNodeUpdated: (_) {},
            onNodeCardBuildProbe: (id) =>
                builds.update(id, (count) => count + 1, ifAbsent: () => 1),
          ),
        ),
      ),
    );
    await settleCanvas(tester);
    final state = tester.state<MindmapCanvasState>(find.byType(MindmapCanvas));
    state.beginInlineEdit(first.id);
    await tester.pump();
    builds.clear();

    await tester.enterText(
      find.byKey(ValueKey('node-inline-title-field-${first.id}')),
      'First edited',
    );
    await tester.pump();

    expect(builds, isEmpty);
  });

  testWidgets('MindmapCanvas supplies cached typed payload to node content', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 16);
    final repositoryPayload = ItineraryPayload(
      destination: 'Repository destination',
      startDate: day,
      endDate: day.add(const Duration(days: 1)),
      timezone: 'UTC',
      agenda: const <ItineraryAgendaItem>[],
    );
    final cachedPayload = repositoryPayload.copyWith(
      destination: 'Cached destination',
    );
    final node =
        MindmapNode.create(
          id: 'cached-itinerary',
          type: NodeType.itinerary,
          title: 'Trip',
          day: day,
          data: repositoryPayload.toData(),
          now: day,
        ).copyWithUiState(
          NodeUiState(
            sizePreset: NodeSizePreset.custom,
            width: 620,
            height: 440,
          ),
        );
    final cache = MindmapNodePresentationCache(
      typedPayloadParser: (_) => cachedPayload,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(nodes: [node], presentationCache: cache),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(find.text('Cached destination'), findsOneWidget);
    expect(find.text('Repository destination'), findsNothing);
    expect(cache.payloadParseCount, 1);
  });

  testWidgets('stable build notification does not loop after parent setState', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_BuildNotificationHarnessState>();
    await tester.pumpWidget(_BuildNotificationHarness(key: key));
    await settleCanvas(tester);

    expect(key.currentState!.notificationCount, 1);
    key.currentState!.rebuildParent();
    await settleCanvas(tester);
    expect(key.currentState!.notificationCount, 1);
  });
  testWidgets('canvas exposes professional context actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [])),
      ),
    );
    final state = tester.state<MindmapCanvasState>(find.byType(MindmapCanvas));
    expect(
      state.availableContextActions,
      contains(CanvasContextAction.selectAll),
    );
    expect(
      state.availableContextActions,
      contains(CanvasContextAction.tidyLayout),
    );
    expect(
      state.availableContextActions,
      contains(CanvasContextAction.toggleGrid),
    );
    expect(
      state.availableContextActions,
      contains(CanvasContextAction.commandPalette),
    );
    expect(
      state.availableContextActions,
      contains(CanvasContextAction.exportDialog),
    );
    expect(
      state.availableContextActions,
      contains(CanvasContextAction.templateGallery),
    );
    expect(
      state.availableContextActions,
      contains(CanvasContextAction.togglePresentation),
    );
  });

  testWidgets('selected canvas node exposes shared resize callbacks', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = MindmapNode.create(
      id: 'resizable-node',
      type: NodeType.task,
      title: 'Resizable',
      day: DateTime(2026, 7, 13),
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 7, 13, 8),
    );
    final commits = <NodeResizeChange>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            highlightedNodeId: node.id,
            onNodeResize: (_, change) => commits.add(change),
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-resizable-node'),
    );
    final originalTopLeft = tester.getTopLeft(nodeFinder);
    final shell = tester.widget<NodeShell>(find.byType(NodeShell));
    const preview = NodeResizeChange(
      size: Size(364, 338),
      positionDelta: Offset(12, 8),
      preset: NodeSizePreset.custom,
      phase: NodeResizePhase.preview,
    );
    shell.onResizeChanged?.call(preview);
    await tester.pump();
    expect(tester.getSize(nodeFinder), preview.size);
    expect(
      tester.getTopLeft(nodeFinder),
      originalTopLeft + preview.positionDelta,
    );
    expect(commits, isEmpty);

    shell.onResizeChanged?.call(
      const NodeResizeChange(
        size: Size(364, 338),
        positionDelta: Offset(12, 8),
        preset: NodeSizePreset.custom,
        phase: NodeResizePhase.commit,
      ),
    );
    await tester.pump();
    expect(commits, hasLength(1));
  });

  testWidgets(
    'top-left resize reconciles after persistence without double shift',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey<_PersistingResizeHarnessState>();
      await tester.pumpWidget(_PersistingResizeHarness(key: key));
      await settleCanvas(tester);

      final nodeFinder = find.byKey(
        const ValueKey<String>('mindmap-node-persist-resize'),
      );
      final initialTopLeft = tester.getTopLeft(nodeFinder);
      final shell = tester.widget<NodeShell>(
        find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
      );
      shell.onResizeChanged?.call(
        const NodeResizeChange(
          size: Size(320, 304),
          positionDelta: Offset(20, 16),
          preset: NodeSizePreset.custom,
          phase: NodeResizePhase.preview,
        ),
      );
      shell.onResizeChanged?.call(
        const NodeResizeChange(
          size: Size(320, 304),
          positionDelta: Offset(20, 16),
          preset: NodeSizePreset.custom,
          phase: NodeResizePhase.commit,
        ),
      );
      await settleCanvas(tester);

      expect(key.currentState!.commitCount, 1);
      expect(key.currentState!.node.position, const CanvasPosition(20, 16));
      expect(key.currentState!.node.uiState.width, 320);
      expect(key.currentState!.node.uiState.height, 304);
      final persistedTopLeft = tester.getTopLeft(nodeFinder);
      expect(tester.getSize(nodeFinder), const Size(320, 304));
      expect(persistedTopLeft, initialTopLeft + const Offset(20, 16));

      key.currentState!.applyExternalChange();
      await settleCanvas(tester);
      expect(key.currentState!.node.position, const CanvasPosition(60, 56));
      expect(tester.getSize(nodeFinder), const Size(360, 340));
      expect(
        tester.getTopLeft(nodeFinder),
        persistedTopLeft + const Offset(40, 40),
      );
    },
  );

  testWidgets('unrelated parent refresh keeps optimistic resize until saved', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_PersistingResizeHarnessState>();
    await tester.pumpWidget(
      _PersistingResizeHarness(key: key, deferPersistence: true),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-persist-resize'),
    );
    final initialTopLeft = tester.getTopLeft(nodeFinder);
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    shell.onResizeChanged?.call(
      const NodeResizeChange(
        size: Size(320, 304),
        positionDelta: Offset(20, 16),
        preset: NodeSizePreset.custom,
        phase: NodeResizePhase.preview,
      ),
    );
    shell.onResizeChanged?.call(
      const NodeResizeChange(
        size: Size(320, 304),
        positionDelta: Offset(20, 16),
        preset: NodeSizePreset.custom,
        phase: NodeResizePhase.commit,
      ),
    );
    await tester.pump();
    expect(tester.getSize(nodeFinder), const Size(320, 304));

    key.currentState!.applyUnrelatedChange();
    await tester.pump();
    expect(tester.getSize(nodeFinder), const Size(320, 304));
    expect(
      tester.getTopLeft(nodeFinder),
      initialTopLeft + const Offset(20, 16),
    );

    key.currentState!.persistPendingResize();
    await settleCanvas(tester);
    expect(key.currentState!.node.position, const CanvasPosition(20, 16));
    expect(tester.getSize(nodeFinder), const Size(320, 304));
    expect(
      tester.getTopLeft(nodeFinder),
      initialTopLeft + const Offset(20, 16),
    );
  });

  testWidgets('expanded node clamps an optimistic tiny resize to policy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_PersistingResizeHarnessState>();
    await tester.pumpWidget(
      _PersistingResizeHarness(key: key, deferPersistence: true),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-persist-resize'),
    );
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    shell.onResizeChanged?.call(
      const NodeResizeChange(
        size: Size(180, 98),
        positionDelta: Offset.zero,
        preset: NodeSizePreset.custom,
        phase: NodeResizePhase.preview,
      ),
    );
    await tester.pump();
    expect(tester.getSize(nodeFinder), const Size(180, 98));

    key.currentState!.setExpanded(true);
    await tester.pump();

    final policy = InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.task);
    expect(tester.getSize(nodeFinder), Size(policy.width, policy.height));
    expect(tester.takeException(), isNull);
  });
  testWidgets('expanded task size follows latest inline draft content', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 16);
    final persistedNode = MindmapNode.create(
      id: 'expanded-size-draft',
      type: NodeType.task,
      title: 'Draft-sized task',
      day: day,
      now: day,
    );
    final draftNode = persistedNode.copyWith(
      checklist: const [
        TaskChecklistItem(id: 'one', title: 'One'),
        TaskChecklistItem(id: 'two', title: 'Two'),
      ],
      updatedAt: day.add(const Duration(seconds: 1)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [persistedNode],
            expandedNodeId: persistedNode.id,
            expandedNodeOverride: draftNode,
            expandedNodeBuilder: (_) => const InlineNodeWorkspaceSurface(
              header: SizedBox(height: 64),
              body: SizedBox(),
              footer: SizedBox(height: 32),
            ),
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final expected = InlineNodeWorkspacePolicy.expandedSizeForNode(draftNode);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mindmap-node-expanded-size-draft')),
      ),
      Size(expected.width, expected.height),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('expanded task uses fixed workspace without resize handles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_PersistingResizeHarnessState>();
    await tester.pumpWidget(_PersistingResizeHarness(key: key, expanded: true));
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-persist-resize'),
    );
    final policy = InlineNodeWorkspacePolicy.expandedSizeForNode(
      key.currentState!.node,
    );

    expect(tester.getSize(nodeFinder), Size(policy.width, policy.height));
    expect(
      find.descendant(
        of: nodeFinder,
        matching: find.byKey(
          const ValueKey<String>('node-shell-resize-bottomRight'),
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('short completed task with body uses compact layout', (
    tester,
  ) async {
    final DateTime day = DateTime(2026, 7, 16);
    final MindmapNode node = MindmapNode.create(
      id: 'short-completed-task',
      type: NodeType.task,
      title: 'Fitur kedua',
      body: 'saya ingin Fitur',
      day: day,
      isDone: true,
      status: NodeStatus.done,
      progress: 1,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 229.0,
        nodeUiHeightKey: 204.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(
      tester.getSize(
        find.byKey(const ValueKey('mindmap-node-short-completed-task')),
      ),
      const Size(229, 204),
    );
    expect(tester.widget<NodeShell>(find.byType(NodeShell)).isCompact, isTrue);
    expect(
      find.byKey(const ValueKey('mindmap-node-done-short-completed-task')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('canvas preview renders structured non-interactive thumbnail', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 17);
    final base = MindmapNode.create(
      id: 'structured-canvas',
      type: NodeType.canvas,
      title: 'Visual plan',
      day: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 380.0,
        nodeUiHeightKey: 380.0,
      },
      now: day,
    );
    final node = base.copyWith(
      data: const CanvasPayload(
        background: 'grid',
        elements: <CanvasElement>[
          CanvasStroke(
            id: 'stroke',
            color: 'blue',
            points: <CanvasPoint>[CanvasPoint(0.1, 0.1), CanvasPoint(0.8, 0.8)],
          ),
          CanvasTextElement(
            id: 'text',
            color: 'neutral',
            position: CanvasPoint(0.2, 0.2),
            text: 'Label',
          ),
          CanvasStickyElement(
            id: 'sticky',
            color: 'neutral',
            position: CanvasPoint(0.5, 0.2),
            text: 'Note',
          ),
          CanvasShapeElement(
            id: 'shape',
            color: 'green',
            shape: 'ellipse',
            start: CanvasPoint(0.2, 0.5),
            end: CanvasPoint(0.5, 0.8),
          ),
          CanvasArrowElement(
            id: 'arrow',
            color: 'rose',
            start: CanvasPoint(0.5, 0.7),
            end: CanvasPoint(0.9, 0.4),
          ),
        ],
      ).toData(base.data),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(
      find.byKey(const ValueKey<String>('canvas-collapsed-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-document-renderer')),
      findsOneWidget,
    );
    expect(find.text('5 elements'), findsOneWidget);
    expect(find.text('Grid'), findsOneWidget);
    expect(
      tester.widget<IgnorePointer>(find.byType(IgnorePointer).last).ignoring,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded canvas uses fixed size without resize controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 17);
    final node = MindmapNode.create(
      id: 'fixed-expanded-canvas',
      type: NodeType.canvas,
      title: 'Canvas',
      day: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 980.0,
        nodeUiHeightKey: 1100.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            expandedNodeId: node.id,
            expandedNodeBuilder: (_) => const SizedBox(),
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-fixed-expanded-canvas'),
    );
    expect(
      tester.getSize(nodeFinder),
      Size(
        InlineNodeWorkspacePolicy.canvas.width,
        InlineNodeWorkspacePolicy.canvas.height,
      ),
    );
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed canvas keeps manual resize controls', (tester) async {
    final day = DateTime(2026, 7, 17);
    final node = MindmapNode.create(
      id: 'resizable-collapsed-canvas',
      type: NodeType.canvas,
      title: 'Canvas',
      day: day,
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-resizable-collapsed-canvas'),
    );
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.onResizeChanged, isNotNull);
    expect(
      find.byKey(NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed idea preview renders structured experiment summary', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 16);
    final node = MindmapNode.create(
      id: 'structured-idea',
      type: NodeType.idea,
      title: 'Faster capture',
      body: 'Supporting context',
      day: day,
      data: const <String, Object?>{
        'maturity': 'exploring',
        'hypothesis':
            'Users capture more ideas when entry takes under ten seconds.',
        'impact': 'high',
        'ideaEffort': 'medium',
        'confidence': 70,
        'evidence': 'Five interviews',
        'nextAction': 'Build and test a one-tap prototype.',
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 360.0,
        nodeUiHeightKey: 420.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(
      find.byKey(const ValueKey<String>('idea-collapsed-preview')),
      findsOneWidget,
    );
    expect(find.text('Exploring'), findsOneWidget);
    expect(find.text('Impact High'), findsOneWidget);
    expect(find.text('Effort Medium'), findsOneWidget);
    expect(find.text('Validation 3/3'), findsOneWidget);
    expect(find.text('Next experiment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collapsed question preview renders structured research summary',
    (tester) async {
      final day = DateTime(2026, 7, 16);
      final node = MindmapNode.create(
        id: 'structured-question',
        type: NodeType.question,
        title: 'Capture research',
        body: 'Supporting context',
        day: day,
        data: const <String, Object?>{
          'investigationStatus': 'researching',
          'questionText': 'Which capture flow is fastest for repeated use?',
          'possibleAnswers': <String>[
            'Global keyboard shortcut',
            'Quick capture panel',
            'Floating action button',
          ],
          'answer': 'Global keyboard shortcut',
          'evidence': 'Median completion time was lowest.',
          'questionSources': <String>['Usability study'],
          'nextResearchAction': 'Validate on mobile.',
          'questionConfidence': 82,
          nodeUiSizePresetKey: 'custom',
          nodeUiWidthKey: 360.0,
          nodeUiHeightKey: 420.0,
        },
        now: day,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(
              nodes: <MindmapNode>[node],
              highlightedNodeId: node.id,
            ),
          ),
        ),
      );
      await settleCanvas(tester);

      expect(
        find.byKey(const ValueKey<String>('question-collapsed-preview')),
        findsOneWidget,
      );
      expect(find.text('Researching'), findsOneWidget);
      expect(find.text('Confidence 82%'), findsOneWidget);
      expect(find.text('Research 4/4'), findsOneWidget);
      expect(find.textContaining('Global keyboard shortcut'), findsWidgets);
      expect(find.textContaining('Quick capture panel'), findsOneWidget);
      expect(find.textContaining('Floating action button'), findsNothing);
      expect(find.text('Accepted answer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('collapsed decision preview renders ranked summary', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 16);
    final base = MindmapNode.create(
      id: 'structured-decision',
      type: NodeType.decision,
      title: 'Release decision',
      day: day,
      now: day,
    );
    final node = base.copyWith(
      data: const DecisionPayload(
        status: 'decided',
        question: 'Which option should ship for beta?',
        reviewDate: '2026-08-16',
        confidence: 80,
        criteria: <DecisionCriterion>[
          DecisionCriterion(id: 'impact', name: 'Impact', weight: 2),
          DecisionCriterion(id: 'effort', name: 'Effort'),
        ],
        options: <DecisionOption>[
          DecisionOption(
            id: 'a',
            title: 'Option A',
            scores: <String, int>{'impact': 9, 'effort': 7},
          ),
          DecisionOption(
            id: 'b',
            title: 'Option B',
            scores: <String, int>{'impact': 7, 'effort': 8},
          ),
          DecisionOption(
            id: 'c',
            title: 'Option C',
            scores: <String, int>{'impact': 5, 'effort': 5},
          ),
        ],
        selectedOptionId: 'a',
        rationale: 'Best weighted value.',
      ).toData(base.data),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(
      find.byKey(const ValueKey<String>('decision-collapsed-preview')),
      findsOneWidget,
    );
    expect(find.text('Decided'), findsOneWidget);
    expect(find.text('Confidence 80%'), findsOneWidget);
    expect(find.text('Decision 5/5'), findsOneWidget);
    expect(find.text('Option A'), findsWidgets);
    expect(find.text('Option B'), findsOneWidget);
    expect(find.text('Option C'), findsNothing);
    expect(find.text('Selected outcome'), findsOneWidget);
    expect(find.text('Review 2026-08-16'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed note renders Markdown preview instead of raw syntax', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 16);
    final node = MindmapNode.create(
      id: 'markdown-preview-note',
      type: NodeType.note,
      title: 'Preview note',
      body:
          '## Preview heading\n\n**Bold text** and [Docs](https://example.test).\n\n- First item\n- Second item\n\nLast visible line',
      day: day,
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(
      find.byKey(const ValueKey<String>('note-collapsed-markdown-preview')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('mindmap-node-markdown-preview-note'),
            ),
          )
          .height,
      greaterThan(MindmapCanvas.nodeSize.height),
    );
    expect(find.text('Preview heading'), findsOneWidget);
    expect(find.text('Last visible line'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('note-collapsed-markdown-preview'),
            ),
          )
          .height,
      greaterThan(76),
    );
    expect(find.textContaining('## Preview heading'), findsNothing);
    expect(find.textContaining('**Bold text**'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('default collapsed note reserves layout safety margin', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 16);
    final node = MindmapNode.create(
      id: 'note-layout-margin',
      type: NodeType.note,
      title: 'Safe note',
      body: 'One preview line',
      day: day,
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('mindmap-node-note-layout-margin'),
            ),
          )
          .height,
      MindmapCanvas.nodeSize.height + 16,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('short full note grows without overflow', (tester) async {
    final DateTime day = DateTime(2026, 7, 16);
    final MindmapNode node = MindmapNode.create(
      id: 'short-full-note',
      type: NodeType.note,
      title: 'Melengkapi Fitur',
      body: 'nah sekarang sudah bisa ketik huruf f kecil gitu doang',
      day: day,
      isDone: true,
      status: NodeStatus.done,
      relatedNodeIds: const <String>['task-a', 'task-b'],
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 220.0,
        nodeUiHeightKey: 186.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final Size nodeSize = tester.getSize(
      find.byKey(const ValueKey('mindmap-node-short-full-note')),
    );
    expect(nodeSize.width, 220);
    expect(nodeSize.height, greaterThanOrEqualTo(186));
    expect(find.text('Melengkapi Fitur'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mindmap-node-done-short-full-note')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow long note grows without overflow', (tester) async {
    final DateTime day = DateTime(2026, 7, 16);
    final MindmapNode node = MindmapNode.create(
      id: 'narrow-long-note',
      type: NodeType.note,
      title: 'Catatan panjang dengan metadata lengkap',
      body: '''## Ringkasan

Paragraf panjang ini memastikan preview Markdown membungkus banyak baris pada node sempit tanpa dipotong atau memakai scroll internal.

- Item pertama dengan penjelasan panjang
- Item kedua dengan **teks tebal** dan detail tambahan
- Item ketiga dengan [tautan](https://example.test)

Baris penutup tetap harus terlihat penuh di mode collapse.''',
      day: day,
      status: NodeStatus.done,
      priority: NodePriority.high,
      project: 'Pengembangan aplikasi produktivitas',
      area: 'Mindmap dan catatan',
      tags: const <String>['flutter', 'markdown', 'preview'],
      relatedNodeIds: const <String>['task-a', 'task-b'],
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 276.0,
        nodeUiHeightKey: 240.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final Finder nodeFinder = find.byKey(
      const ValueKey('mindmap-node-narrow-long-note'),
    );
    final Finder previewFinder = find.byKey(
      const ValueKey<String>('note-collapsed-markdown-preview'),
    );
    final Rect nodeRect = tester.getRect(nodeFinder);
    final Rect previewRect = tester.getRect(previewFinder);
    expect(nodeRect.height, greaterThan(240));
    expect(previewRect.bottom, lessThanOrEqualTo(nodeRect.bottom));
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow tall task node renders its header without overflow', (
    tester,
  ) async {
    final DateTime day = DateTime(2026, 7, 16);
    final MindmapNode node = MindmapNode.create(
      id: 'narrow-tall-task',
      type: NodeType.task,
      title: 'Fitur utama',
      body: 'hari ini harus selesai semua iturnya',
      day: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 212.0,
        nodeUiHeightKey: 540.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(
      tester.getSize(
        find.byKey(const ValueKey('mindmap-node-narrow-tall-task')),
      ),
      const Size(212, 540),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('short custom node automatically uses compact layout', (
    tester,
  ) async {
    final DateTime day = DateTime(2026, 7, 16);
    final MindmapNode node = MindmapNode.create(
      id: 'short-custom-node',
      type: NodeType.task,
      title: 'Short custom node',
      day: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 640.0,
        nodeUiHeightKey: 127.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: <MindmapNode>[node])),
      ),
    );
    await settleCanvas(tester);

    expect(
      tester.getSize(
        find.byKey(const ValueKey('mindmap-node-short-custom-node')),
      ),
      const Size(640, 127),
    );
    expect(tester.widget<NodeShell>(find.byType(NodeShell)).isCompact, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact rendering preserves custom effective geometry', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 13);
    final nodes = <MindmapNode>[
      MindmapNode.create(
        id: 'compact-custom',
        type: NodeType.task,
        title: 'Compact custom',
        day: day,
        position: const CanvasPosition(0, 0),
        data: const <String, Object?>{
          nodeUiSizePresetKey: 'custom',
          nodeUiWidthKey: 420.0,
          nodeUiHeightKey: 260.0,
        },
        now: day,
      ),
      for (var index = 0; index < 60; index++)
        MindmapNode.create(
          id: 'heavy-$index',
          type: NodeType.note,
          title: 'Heavy $index',
          day: day,
          position: CanvasPosition(3000 + index * 400, 3000),
          now: day,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: nodes)),
      ),
    );
    await settleCanvas(tester);

    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-compact-custom'),
    );
    final shellFinder = find.descendant(
      of: nodeFinder,
      matching: find.byType(NodeShell),
    );
    expect(tester.widget<NodeShell>(shellFinder).isCompact, isTrue);
    expect(tester.getSize(shellFinder), const Size(420, 260));
  });

  testWidgets(
    'resize handles work through InteractiveViewer at supported zoom levels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final scale in <double>[0.5, 1, 2]) {
        for (final handle in NodeResizeHandle.values) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          final key = GlobalKey<_PersistingResizeHarnessState>();
          await tester.pumpWidget(
            _PersistingResizeHarness(key: key, deferPersistence: true),
          );
          await settleCanvas(tester);
          final nodeFinder = find.byKey(
            const ValueKey<String>('mindmap-node-persist-resize'),
          );
          _setCanvasScale(tester, nodeFinder, scale);
          await tester.pump();
          await _resizeThroughCanvas(
            tester,
            nodeFinder,
            handle,
            const Offset(20, 16),
          );
          await tester.pump();

          expect(
            key.currentState!.pendingResize?.phase,
            NodeResizePhase.commit,
            reason: '${handle.name} at ${scale}x must beat canvas gestures',
          );
        }
      }
    },
  );

  testWidgets('pointer cancel removes canvas preview override', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_PersistingResizeHarnessState>();
    await tester.pumpWidget(
      _PersistingResizeHarness(key: key, deferPersistence: true),
    );
    await settleCanvas(tester);
    final nodeFinder = find.byKey(
      const ValueKey<String>('mindmap-node-persist-resize'),
    );
    _setCanvasScale(tester, nodeFinder, 0.5);
    await tester.pump();
    final originalPosition = tester.getTopLeft(nodeFinder);
    final gesture = await _startResizeThroughCanvas(
      tester,
      nodeFinder,
      NodeResizeHandle.topLeft,
      const Offset(20, 16),
    );
    await tester.pump();
    expect(tester.getSize(nodeFinder), const Size(320, 304));

    await gesture.cancel();
    await tester.pump();
    expect(tester.getSize(nodeFinder), const Size(340, 320));
    expect(tester.getTopLeft(nodeFinder), originalPosition);
    expect(key.currentState!.commitCount, 0);
    expect(key.currentState!.pendingResize, isNull);
  });

  testWidgets('secondary click on a node does not open canvas context menu', (
    tester,
  ) async {
    var nodeMenuCount = 0;
    var canvasMenuCount = 0;
    final node = MindmapNode.create(
      id: 'context-node',
      type: NodeType.task,
      title: 'Context node',
      day: DateTime(2026, 6, 18),
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 6, 18, 8),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeContextMenu: (node, position) {
              nodeMenuCount += 1;
            },
            onCanvasContextMenu: (globalPosition, scenePosition) {
              canvasMenuCount += 1;
            },
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(
      tester.getCenter(find.byKey(const ValueKey('mindmap-node-context-node'))),
    );
    await tester.pump();
    await gesture.up();
    await settleCanvas(tester);
    expect(nodeMenuCount, 1);
    expect(canvasMenuCount, 0);
  });
  testWidgets('collaboration tools minimize and maximize', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const [CollaborationRoomBar(nodes: [])]),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Enable simulation'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('collab-room-bar'))).height,
      44,
    );
    await tester.tap(find.byKey(const ValueKey('collab-room-bar-toggle')));
    await tester.pump();
    expect(find.byTooltip('Enable simulation'), findsNothing);
    expect(find.byTooltip('Maximize collaboration tools'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('collab-room-bar-toggle')));
    await tester.pump();
    expect(find.byTooltip('Enable simulation'), findsOneWidget);
  });

  testWidgets(
    'MindmapCanvas renders positioned nodes inside an InteractiveViewer',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final nodes = [
        MindmapNode.create(
          id: 'task-1',
          type: NodeType.task,
          title: 'Plan the day',
          body: 'Pick top three outcomes.',
          day: day,
          position: const CanvasPosition(-120, -40),
          now: DateTime(2026, 6, 18, 8),
        ),
        MindmapNode.create(
          id: 'note-1',
          type: NodeType.note,
          title: 'Context',
          day: day,
          position: const CanvasPosition(90, 24),
          now: DateTime(2026, 6, 18, 9),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(nodes: nodes, highlightedNodeId: 'note-1'),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('mindmap-canvas')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byKey(const ValueKey('mindmap-node-task-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('mindmap-node-note-1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mindmap-highlight-note-1')),
        findsOneWidget,
      );
      expect(find.text('Plan the day'), findsOneWidget);
      expect(find.text('Context'), findsOneWidget);
      expect(find.text('Task'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
    },
  );

  testWidgets('MindmapCanvas selects and focuses node from explorer', (
    tester,
  ) async {
    final key = GlobalKey<MindmapCanvasState>();
    final node = MindmapNode.create(
      id: 'explorer-node',
      type: NodeType.note,
      title: 'Explorer note',
      day: DateTime(2026, 6, 18),
      position: const CanvasPosition(120, 40),
      now: DateTime(2026, 6, 18, 9),
    );
    MindmapNode? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: [node],
            onNodeSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await key.currentState!.selectAndFocusNode(node);
    await settleCanvas(tester);

    expect(selected, node);
    expect(
      find.byKey(const ValueKey('mindmap-highlight-explorer-node')),
      findsOneWidget,
    );
  });

  testWidgets('node inline button selects and focuses inline', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final node = MindmapNode.create(
      id: 'inline-open-node',
      type: NodeType.note,
      title: 'Inline open',
      day: DateTime(2026, 6, 18),
      position: const CanvasPosition(120, 40),
      now: DateTime(2026, 6, 18, 9),
    );
    MindmapNode? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeSelected: (value) => selected = value,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final openButton = find.byTooltip('Open Note inline');
    expect(find.byTooltip('Edit in node'), findsNothing);
    expect(
      find.byKey(const ValueKey('node-inline-edit-inline-open-node')),
      findsNothing,
    );
    await tester.ensureVisible(openButton);
    await tester.tap(openButton);
    await settleCanvas(tester);

    expect(selected, node);
    expect(
      find.byKey(const ValueKey('mindmap-highlight-inline-open-node')),
      findsOneWidget,
    );
  });

  testWidgets('MindmapCanvas does not paint cursor trails on hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [])),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byKey(const ValueKey('mindmap-canvas'))),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();

    final backgroundPaints = tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    );
    final hasCursorTrail = backgroundPaints.any((paint) {
      final painter = paint.painter as dynamic;
      try {
        // ignore: avoid_dynamic_calls
        return (painter.cursorTrail as List).isNotEmpty;
      } catch (_) {
        return false;
      }
    });

    expect(hasCursorTrail, isFalse);
  });

  testWidgets('MindmapCanvas exposes toolbar state and shortcut help', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [])),
      ),
    );

    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byTooltip('Show canvas controls'));
    await settleCanvas(tester);
    expect(find.text('Grid on'), findsOneWidget);
    expect(find.text('Snap off'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mindmap-shortcut-help')));
    await settleCanvas(tester);

    expect(find.text('Mindmap shortcuts'), findsOneWidget);
    expect(find.text('Ctrl+F'), findsOneWidget);
    expect(find.text('Focus search'), findsOneWidget);
    expect(find.text('Ctrl+G'), findsOneWidget);
    expect(find.text('Toggle grid'), findsOneWidget);
  });

  testWidgets('MindmapCanvas disables primary-button canvas panning', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [])),
      ),
    );

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('mindmap-canvas')),
    );

    expect(viewer.panEnabled, isFalse);
  });

  testWidgets('MindmapCanvas zooms at pointer with Ctrl and mouse wheel', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [])),
      ),
    );
    await settleCanvas(tester);

    final canvas = find.byKey(const ValueKey('mindmap-canvas'));
    final controller = tester
        .widget<InteractiveViewer>(canvas)
        .transformationController!;
    final pointer = tester.getCenter(canvas);
    final beforeScale = controller.value.getMaxScaleOnAxis();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: pointer, scrollDelta: const Offset(0, -120)),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(controller.value.getMaxScaleOnAxis(), greaterThan(beforeScale));
  });

  testWidgets('MindmapCanvas handles web Ctrl wheel scale events', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [])),
      ),
    );
    await settleCanvas(tester);

    final canvas = find.byKey(const ValueKey('mindmap-canvas'));
    final controller = tester
        .widget<InteractiveViewer>(canvas)
        .transformationController!;
    final beforeScale = controller.value.getMaxScaleOnAxis();

    await tester.sendEventToBinding(
      PointerScaleEvent(position: tester.getCenter(canvas), scale: 1.2),
    );
    await tester.pump();

    expect(controller.value.getMaxScaleOnAxis(), greaterThan(beforeScale));
  });

  testWidgets('zoom controls preserve scene point at canvas viewport center', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const [],
            onNodeMoved: (_, _) {},
            onNodeSelected: (_) {},
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final canvas = find.byKey(const ValueKey('mindmap-canvas'));
    final viewer = tester.widget<InteractiveViewer>(canvas);
    final sceneListener = tester.widget<Listener>(
      find.byKey(const ValueKey('mindmap-scene-listener')),
    );
    expect(sceneListener.onPointerSignal, isNull);
    final controller = viewer.transformationController!;
    final center = tester.getSize(canvas).center(Offset.zero);
    final before = controller.toScene(center);

    await tester.tap(find.byTooltip('Show canvas controls'));
    await settleCanvas(tester);
    await tester.tap(find.byTooltip('Zoom In'));
    await settleCanvas(tester);

    final after = controller.toScene(center);
    expect((after - before).distance, lessThan(0.01));
  });

  testWidgets('MindmapCanvas keeps node drag under cursor when zoomed out', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'task-zoom',
      type: NodeType.task,
      title: 'Zoom drag',
      day: day,
      position: const CanvasPosition(-120, -40),
      now: DateTime(2026, 6, 18, 8),
    );
    CanvasPosition? movedPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeMoved: (_, position) {
              movedPosition = position;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Show canvas controls'));
    await settleCanvas(tester);
    await tester.tap(find.byTooltip('Zoom Out'));
    await settleCanvas(tester);

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('mindmap-canvas')),
    );
    final scale = viewer.transformationController!.value.getMaxScaleOnAxis();
    expect(scale, lessThan(1));

    await tester.drag(
      find.byKey(const ValueKey('mindmap-node-task-zoom')),
      const Offset(32, 16),
    );
    await tester.pump();

    expect(movedPosition, const CanvasPosition(-81.6, -20.8));
  });

  testWidgets('MindmapCanvas reports a dragged node position', (tester) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Plan the day',
      day: day,
      position: const CanvasPosition(-120, -40),
      now: DateTime(2026, 6, 18, 8),
    );
    CanvasPosition? movedPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeMoved: (_, position) {
              movedPosition = position;
            },
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    await tester.drag(
      find.byKey(const ValueKey('mindmap-node-task-1')),
      const Offset(32, 16),
    );
    await tester.pump();

    expect(movedPosition, const CanvasPosition(-88, -24));
  });

  testWidgets(
    'MindmapCanvas opens Command Palette on Ctrl+K and parses command',
    (tester) async {
      NodeType? createdType;
      String? createdTitle;
      NodePriority? createdPriority;
      List<String>? createdTags;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(
              nodes: const [],
              onNodeQuickCreate:
                  (
                    NodeType type,
                    String title, {
                    NodePriority? priority,
                    List<String>? tags,
                  }) {
                    createdType = type;
                    createdTitle = title;
                    createdPriority = priority;
                    createdTags = tags;
                  },
            ),
          ),
        ),
      );

      // Press Ctrl+K to open Command Palette
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settleCanvas(tester);

      expect(
        find.byKey(const ValueKey('command-palette-input')),
        findsOneWidget,
      );

      // Type command
      await tester.enterText(
        find.byKey(const ValueKey('command-palette-input')),
        '/task Buy groceries #high @home @offline',
      );
      await tester.pump();

      // Submit
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleCanvas(tester);

      expect(createdType, NodeType.task);
      expect(createdTitle, 'Buy groceries');
      expect(createdPriority, NodePriority.high);
      expect(createdTags, containsAll(['home', 'offline']));
      expect(find.byKey(const ValueKey('command-palette-input')), findsNothing);
    },
  );

  testWidgets('MindmapCanvas drag-selects nodes from empty canvas space', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final nodes = [
      MindmapNode.create(
        id: 'task-1',
        type: NodeType.task,
        title: 'Plan the day',
        day: day,
        position: const CanvasPosition(-140, -50),
        data: const <String, Object?>{
          'uiSizePreset': 'custom',
          'uiWidth': 420.0,
          'uiHeight': 180.0,
        },
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'note-1',
        type: NodeType.note,
        title: 'Context',
        day: day,
        position: const CanvasPosition(120, 20),
        data: const <String, Object?>{
          'uiSizePreset': 'custom',
          'uiWidth': 240.0,
          'uiHeight': 420.0,
        },
        now: DateTime(2026, 6, 18, 9),
      ),
    ];

    List<MindmapNode>? deletedNodes;
    var selectionCleared = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: nodes,
            onNodeUpdated: (_) {},
            onNodesDeleted: (selected) => deletedNodes = selected,
            onSelectionCleared: () => selectionCleared += 1,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final firstRect = tester.getRect(
      find.byKey(const ValueKey('mindmap-node-task-1')),
    );
    final secondRect = tester.getRect(
      find.byKey(const ValueKey('mindmap-node-note-1')),
    );
    final dragStart = firstRect.topLeft - const Offset(40, 32);
    final dragEnd = secondRect.bottomRight + const Offset(40, 32);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(dragStart);
    await tester.pump();
    await gesture.moveTo(dragEnd);
    await tester.pump();
    await gesture.up();
    await settleCanvas(tester);

    expect(find.text('2 nodes selected'), findsOneWidget);
    final Rect archiveRect = tester.getRect(find.byTooltip('Archive selected'));
    final Rect deleteRect = tester.getRect(find.byTooltip('Delete selected'));
    final Rect clearRect = tester.getRect(find.byTooltip('Clear selection'));
    expect(deleteRect.left - archiveRect.right, greaterThanOrEqualTo(4));
    expect(clearRect.left - deleteRect.right, greaterThanOrEqualTo(4));
    await tester.tap(find.byTooltip('Delete selected'));
    await settleCanvas(tester);
    expect(find.text('Delete 2 selected nodes?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settleCanvas(tester);

    expect(
      deletedNodes?.map((node) => node.id),
      containsAll(<String>['task-1', 'note-1']),
    );
    expect(selectionCleared, 1);
    expect(find.text('2 nodes selected'), findsNothing);
  });

  testWidgets('MindmapCanvas lasso uses custom node bounds', (tester) async {
    final day = DateTime(2026, 7, 13);
    final node = MindmapNode.create(
      id: 'lasso-custom-width',
      type: NodeType.note,
      title: 'Wide selection target',
      day: day,
      position: const CanvasPosition(-300, -100),
      data: const <String, Object?>{
        'uiSizePreset': 'custom',
        'uiWidth': 600.0,
        'uiHeight': 220.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: <MindmapNode>[node])),
      ),
    );
    await settleCanvas(tester);

    final nodeRect = tester.getRect(
      find.byKey(const ValueKey('mindmap-node-lasso-custom-width')),
    );
    final legacyRight = nodeRect.left + MindmapCanvas.nodeSize.width;
    final dragStart = Offset(nodeRect.right + 30, nodeRect.top + 60);
    final dragEnd = Offset(nodeRect.right - 40, nodeRect.top + 120);
    expect(dragEnd.dx, greaterThan(legacyRight));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(dragStart);
    await tester.pump();
    await gesture.moveTo(dragEnd);
    await tester.pump();
    await gesture.up();
    await settleCanvas(tester);

    expect(
      find.byKey(const ValueKey('mindmap-highlight-lasso-custom-width')),
      findsOneWidget,
    );
  });

  testWidgets('MindmapCanvas lasso selects nodes and native objects', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 13);
    final node = MindmapNode.create(
      id: 'lasso-node',
      type: NodeType.note,
      title: 'Lasso node',
      day: day,
      position: const CanvasPosition(-240, -80),
      now: day,
    );
    final object = CanvasObject(
      id: 'lasso-shape',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 80, y: -80, width: 140, height: 100),
      createdAt: day,
      updatedAt: day,
    );
    final key = GlobalKey<MindmapCanvasState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:lasso-mixed',
              kind: CanvasBoardKind.project,
              title: 'Mixed lasso',
              objects: <CanvasObject>[object],
              createdAt: day,
              updatedAt: day,
            ),
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final nodeRect = tester.getRect(
      find.byKey(const ValueKey('mindmap-node-lasso-node')),
    );
    final objectRect = tester.getRect(
      find.byKey(const ValueKey('canvas-object-lasso-shape')),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(nodeRect.topLeft - const Offset(20, 20));
    await tester.pump();
    await gesture.moveTo(objectRect.bottomRight + const Offset(20, 20));
    await tester.pump();
    await gesture.up();
    await settleCanvas(tester);

    expect(find.text('1 node + 1 object selected'), findsOneWidget);
    expect(key.currentState!.selectedCanvasObjectIds, <String>{object.id});

    final toggle = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await toggle.down(nodeRect.topLeft - const Offset(20, 20));
    await toggle.moveTo(objectRect.bottomRight + const Offset(20, 20));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await toggle.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('1 node + 1 object selected'), findsNothing);
    expect(key.currentState!.selectedCanvasObjectIds, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settleCanvas(tester);
    final zoomedNodeRect = tester.getRect(
      find.byKey(const ValueKey('mindmap-node-lasso-node')),
    );
    final zoomedObjectRect = tester.getRect(
      find.byKey(const ValueKey('canvas-object-lasso-shape')),
    );
    final zoomed = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await zoomed.down(zoomedNodeRect.topLeft - const Offset(20, 20));
    await zoomed.moveTo(zoomedObjectRect.bottomRight + const Offset(20, 20));
    await zoomed.up();
    await tester.pump();
    expect(find.text('1 node + 1 object selected'), findsOneWidget);
  });

  testWidgets('lasso cancel preserves prior mixed selection', (tester) async {
    final day = DateTime(2026, 7, 13);
    final node = MindmapNode.create(
      id: 'cancel-node',
      type: NodeType.note,
      title: 'Cancel node',
      day: day,
      now: day,
    );
    final object = CanvasObject(
      id: 'cancel-object',
      type: CanvasObjectType.shape,
      geometry: const CanvasGeometry(x: 240, y: 80, width: 120, height: 80),
      createdAt: day,
      updatedAt: day,
    );
    final key = GlobalKey<MindmapCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: key,
            nodes: <MindmapNode>[node],
            board: CanvasBoard(
              id: 'project:cancel-lasso',
              kind: CanvasBoardKind.project,
              title: 'Cancel lasso',
              objects: <CanvasObject>[object],
              createdAt: day,
              updatedAt: day,
            ),
          ),
        ),
      ),
    );
    await settleCanvas(tester);
    await tester.tap(find.byKey(const ValueKey('mindmap-node-cancel-node')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    key.currentState!.selectCanvasObject(object.id);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final canvas = tester.getRect(find.byType(MindmapCanvas));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(canvas.topLeft + const Offset(20, 100));
    await tester.pump();
    expect(find.text('1 node + 1 object selected'), findsOneWidget);
    await gesture.moveBy(const Offset(30, 30));
    await gesture.cancel();
    await tester.pump();

    expect(find.text('1 node + 1 object selected'), findsOneWidget);
    expect(key.currentState!.selectedCanvasObjectIds, <String>{object.id});
  });

  testWidgets(
    'filtered nodes stay excluded from context select all and lasso',
    (tester) async {
      final day = DateTime(2026, 7, 13);
      final nodes = <MindmapNode>[
        MindmapNode.create(
          id: 'visible-task',
          type: NodeType.task,
          title: 'Visible task',
          day: day,
          position: const CanvasPosition(-220, -80),
          now: day,
        ),
        MindmapNode.create(
          id: 'filtered-contact',
          type: NodeType.contact,
          title: 'Filtered contact',
          day: day,
          position: const CanvasPosition(100, -80),
          now: day,
        ),
      ];
      final key = GlobalKey<MindmapCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(key: key, nodes: nodes),
          ),
        ),
      );
      await settleCanvas(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('mindmap-search-filter-task')),
      );
      await tester.pump();

      await key.currentState!.runContextAction(CanvasContextAction.selectAll);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mindmap-highlight-visible-task')),
        findsOneWidget,
      );
      expect(find.text('2 nodes selected'), findsNothing);

      final taskRect = tester.getRect(
        find.byKey(const ValueKey('mindmap-node-visible-task')),
      );
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(taskRect.topLeft - const Offset(30, 30));
      await gesture.moveTo(taskRect.bottomRight + const Offset(400, 30));
      await gesture.up();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mindmap-highlight-visible-task')),
        findsOneWidget,
      );
      expect(find.text('2 nodes selected'), findsNothing);
    },
  );

  testWidgets('MindmapCanvas reports a tapped node selection', (tester) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'note-1',
      type: NodeType.note,
      title: 'Context',
      day: day,
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 6, 18, 9),
    );
    MindmapNode? selectedNode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeSelected: (node) {
              selectedNode = node;
            },
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    await tester.tap(find.byKey(const ValueKey('mindmap-node-note-1')));
    await tester.pump();

    expect(selectedNode?.id, 'note-1');
  });

  testWidgets(
    'completed task stays visible when legacy setting hides completed',
    (tester) async {
      await SharedPreferencesAsync().setString(
        'mindmap_canvas_settings_v1',
        '{"showGrid":true,"snapToGrid":false,"showCompleted":false,"backgroundMode":0}',
      );
      final day = DateTime(2026, 7, 16);
      final node = MindmapNode.create(
        id: 'completed-visible-task',
        type: NodeType.task,
        title: 'Completed visible task',
        day: day,
        isDone: true,
        status: NodeStatus.done,
        progress: 1,
        now: day,
      );
      final canvasKey = GlobalKey<MindmapCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(key: canvasKey, nodes: <MindmapNode>[node]),
          ),
        ),
      );
      await settleCanvas(tester);

      expect(canvasKey.currentState!.areCompletedNodesVisible, isTrue);
      expect(
        find.byKey(const ValueKey('mindmap-node-completed-visible-task')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mindmap-node-done-completed-visible-task')),
        findsOneWidget,
      );

      await canvasKey.currentState!.runContextAction(
        CanvasContextAction.toggleMinimap,
      );
      await tester.pump();
      expect(
        find.byKey(
          const ValueKey('mindmap-minimap-node-completed-visible-task'),
        ),
        findsOneWidget,
      );

      await canvasKey.currentState!.runContextAction(
        CanvasContextAction.toggleCompleted,
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('mindmap-node-completed-visible-task')),
        findsOneWidget,
      );
    },
  );
  testWidgets('MindmapCanvas reports a task done toggle', (tester) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Plan the day',
      day: day,
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 6, 18, 8),
    );
    bool? toggledValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onTaskDoneChanged: (_, isDone) {
              toggledValue = isDone;
            },
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final toggle = find.byKey(const ValueKey('mindmap-task-toggle-task-1'));
    final semantics = tester.getSemantics(toggle);
    expect(semantics.label, 'Mark task complete');
    final flags = semantics.getSemanticsData().flagsCollection;
    expect(flags.isButton, isTrue);
    expect(flags.isChecked.name, 'isFalse');

    await tester.tap(toggle);
    await tester.pump();

    expect(toggledValue, isTrue);
  });

  testWidgets('MindmapCanvas minimap supports semantics and arrow keys', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 15);
    final canvasKey = GlobalKey<MindmapCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: canvasKey,
            nodes: [
              MindmapNode.create(
                id: 'minimap-keyboard',
                type: NodeType.note,
                title: 'Keyboard map',
                day: day,
                now: day,
              ),
            ],
          ),
        ),
      ),
    );
    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.toggleMinimap,
    );
    await tester.pump();

    final focus = find.byKey(const ValueKey('mindmap-minimap-focus'));
    final semantics = tester
        .widgetList<Semantics>(
          find.ancestor(
            of: find.byKey(const ValueKey('mindmap-minimap-semantics')),
            matching: find.byType(Semantics),
          ),
        )
        .firstWhere(
          (widget) =>
              widget.properties.label?.startsWith('Minimap with') == true,
        );
    expect(
      semantics.properties.label,
      'Minimap with 1 nodes and 0 canvas objects. Tap to move viewport',
    );
    expect(
      semantics.properties.hint,
      'Use arrow keys to move around the canvas',
    );
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final before = viewer.transformationController!.value.clone();

    final result = tester.widget<Focus>(focus).onKeyEvent!(
      FocusNode(),
      const KeyDownEvent(
        timeStamp: Duration.zero,
        physicalKey: PhysicalKeyboardKey.arrowRight,
        logicalKey: LogicalKeyboardKey.arrowRight,
      ),
    );
    await settleCanvas(tester);

    expect(result, KeyEventResult.handled);
    expect(viewer.transformationController!.value, isNot(equals(before)));
  });

  testWidgets('MindmapCanvas reports a task checklist advance request', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Launch task',
      day: day,
      checklist: const [
        TaskChecklistItem(id: 'item-1', title: 'Draft copy'),
        TaskChecklistItem(id: 'item-2', title: 'Review scope'),
      ],
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 6, 18, 8),
    );
    MindmapNode? advancedNode;
    MindmapNode? selectedNode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeSelected: (node) {
              selectedNode = node;
            },
            onTaskChecklistItemCompleted: (node) {
              advancedNode = node;
            },
          ),
        ),
      ),
    );

    await _pressButton(
      tester,
      find.byKey(const ValueKey('mindmap-task-checklist-next-task-1')),
    );

    expect(advancedNode?.id, 'task-1');
    expect(selectedNode, isNull);
  });

  testWidgets('MindmapCanvas disables checklist advance when items are done', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'task-1',
      type: NodeType.task,
      title: 'Launch task',
      day: day,
      checklist: const [
        TaskChecklistItem(id: 'item-1', title: 'Draft copy', isDone: true),
      ],
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onTaskChecklistItemCompleted: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Checklist done'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('mindmap-task-checklist-next-task-1')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('MindmapCanvas reports a habit completion request', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'habit-1',
      type: NodeType.habit,
      title: 'Workout',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'habit': {'recurrence': 'daily', 'target': '30 min'},
      },
      now: DateTime(2026, 6, 18, 8),
    );
    MindmapNode? loggedNode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onHabitCompleted: (node) {
              loggedNode = node;
            },
          ),
        ),
      ),
    );

    await _pressButton(
      tester,
      find.byKey(const ValueKey('mindmap-habit-log-habit-1')),
    );

    expect(loggedNode?.id, 'habit-1');
  });

  testWidgets('MindmapCanvas disables habit logging once completed today', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'habit-1',
      type: NodeType.habit,
      title: 'Workout',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'habit': {
          'recurrence': 'daily',
          'completions': ['2026-06-18'],
        },
      },
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(nodes: [node], onHabitCompleted: (_) {}),
        ),
      ),
    );

    expect(find.text('Logged'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('mindmap-habit-log-habit-1')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('MindmapCanvas reports a goal milestone advance request', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'goal-1',
      type: NodeType.goal,
      title: 'Launch v1',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'goal': {
          'milestones': ['Prototype', 'Beta'],
          'completedMilestones': ['Prototype'],
        },
      },
      now: DateTime(2026, 6, 18, 8),
    );
    MindmapNode? advancedNode;
    MindmapNode? selectedNode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeSelected: (node) {
              selectedNode = node;
            },
            onGoalMilestoneAdvanced: (node) {
              advancedNode = node;
            },
          ),
        ),
      ),
    );

    await _pressButton(
      tester,
      find.byKey(const ValueKey('mindmap-goal-advance-goal-1')),
    );

    expect(advancedNode?.id, 'goal-1');
    expect(selectedNode, isNull);
  });

  testWidgets('MindmapCanvas disables goal advancement when complete', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'goal-1',
      type: NodeType.goal,
      title: 'Launch v1',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'goal': {
          'milestones': ['Prototype', 'Beta'],
          'completedMilestones': ['Prototype', 'Beta'],
        },
      },
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(nodes: [node], onGoalMilestoneAdvanced: (_) {}),
        ),
      ),
    );

    expect(find.text('Complete'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('mindmap-goal-advance-goal-1')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('MindmapCanvas reports a plan step advance request', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'plan-1',
      type: NodeType.plan,
      title: 'Sprint plan',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'plan': {
          'steps': ['Scope', 'Build'],
          'completedSteps': ['Scope'],
        },
      },
      now: DateTime(2026, 6, 18, 8),
    );
    MindmapNode? advancedNode;
    MindmapNode? selectedNode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onNodeSelected: (node) {
              selectedNode = node;
            },
            onPlanStepAdvanced: (node) {
              advancedNode = node;
            },
          ),
        ),
      ),
    );

    await _pressButton(
      tester,
      find.byKey(const ValueKey('mindmap-plan-advance-plan-1')),
    );

    expect(advancedNode?.id, 'plan-1');
    expect(selectedNode, isNull);
  });

  testWidgets('MindmapCanvas disables plan advancement when complete', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'plan-1',
      type: NodeType.plan,
      title: 'Sprint plan',
      day: day,
      position: const CanvasPosition(0, 0),
      data: const {
        'plan': {
          'steps': ['Scope', 'Build'],
          'completedSteps': ['Scope', 'Build'],
        },
      },
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(nodes: [node], onPlanStepAdvanced: (_) {}),
        ),
      ),
    );

    expect(find.text('Plan done'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('mindmap-plan-advance-plan-1')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('MindmapCanvas renders advanced node metadata chips', (
    tester,
  ) async {
    final today = DateTime.now();
    final node = MindmapNode.create(
      id: 'task-advanced',
      type: NodeType.task,
      title: 'Launch task',
      day: today,
      status: NodeStatus.doing,
      priority: NodePriority.high,
      tags: const ['work'],
      dueDate: today,
      progress: 0.5,
      checklist: const [
        TaskChecklistItem(id: 'item-1', title: 'Draft copy', isDone: true),
        TaskChecklistItem(id: 'item-2', title: 'Review scope'),
      ],
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );

    expect(find.text('High'), findsOneWidget);
    expect(find.text('Doing'), findsOneWidget);
    expect(find.text('#work'), findsOneWidget);
    expect(find.text('Due Today'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('MindmapCanvas opens canvas search from Ctrl+F', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [])),
      ),
    );

    expect(find.byType(TextField), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
    );
  });

  testWidgets('MindmapCanvas shows empty search state when no nodes match', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'note-1',
      type: NodeType.note,
      title: 'Project context',
      day: day,
      position: const CanvasPosition(0, 0),
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-search-empty-state')),
      findsOneWidget,
    );
    expect(find.text('No canvas items match missing'), findsOneWidget);
    expect(find.byKey(const ValueKey('mindmap-node-note-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mindmap-search-clear-empty')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-search-empty-state')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('mindmap-node-note-1')), findsOneWidget);
  });

  testWidgets('collapsed contact shows selected names and roles only', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'contact-selected',
      type: NodeType.contact,
      title: 'Primary',
      body: 'Name:\nRole:',
      day: day,
      data: const {
        'role': 'Owner',
        'contact': {
          'collapsedContactIds': ['secondary'],
          'additionalContacts': [
            {
              'id': 'secondary',
              'name': 'Warrick',
              'role': 'Student',
              'email': 'warrick@example.com',
              'dialCode': '+62',
              'phone': '8177',
            },
          ],
        },
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );
    await settleCanvas(tester);

    expect(find.text('Name: Warrick'), findsOneWidget);
    expect(find.text('Role: Student'), findsOneWidget);
    expect(find.text('Name:'), findsNothing);
    expect(find.text('Role:'), findsNothing);
    expect(find.text('Name: Primary'), findsNothing);
    expect(
      find.byKey(const ValueKey('contact-copy-email-secondary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mindmap-node-quick-action-contact-selected')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('MindmapCanvas type filter chips filter visible nodes', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final task = MindmapNode.create(
      id: 'task-filter',
      type: NodeType.task,
      title: 'Task item',
      day: day,
      position: const CanvasPosition(-80, 0),
      now: DateTime(2026, 6, 18, 8),
    );
    final contact = MindmapNode.create(
      id: 'contact-filter',
      type: NodeType.contact,
      title: 'Contact item',
      day: day,
      position: const CanvasPosition(80, 0),
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [task, contact])),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mindmap-search-filter-task')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-node-task-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mindmap-node-contact-filter')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('mindmap-search-filter-all')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-node-task-filter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mindmap-node-contact-filter')),
      findsOneWidget,
    );
  });

  testWidgets('MindmapCanvas renders relation count metadata', (tester) async {
    final node = MindmapNode.create(
      id: 'task-linked',
      type: NodeType.task,
      title: 'Connected task',
      day: DateTime(2026, 6, 18),
      relatedNodeIds: const ['note-1', 'goal-1'],
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );

    expect(find.text('2 links'), findsOneWidget);
  });

  testWidgets('MindmapCanvas renders project and area metadata chips', (
    tester,
  ) async {
    final node = MindmapNode.create(
      id: 'task-context',
      type: NodeType.task,
      title: 'Scoped task',
      day: DateTime(2026, 6, 18),
      project: 'Launch App',
      area: 'Work Ops',
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );

    expect(find.text('Project: Launch App'), findsOneWidget);
    expect(find.text('Area: Work Ops'), findsOneWidget);
  });

  testWidgets('collapsed mood normalizes legacy text without duplicate body', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 19);
    final node = MindmapNode.create(
      id: 'mood-legacy',
      type: NodeType.mood,
      title: 'Mood check-in',
      body: 'Mood: broken legacy text\nEnergy: 3/5',
      day: day,
      data: const {
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 340.0,
        nodeUiHeightKey: 320.0,
        'mood': 'broken legacy text',
        'energy': 4.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );
    await settleCanvas(tester);

    expect(find.text('🙂'), findsOneWidget);
    expect(find.textContaining('broken legacy text'), findsNothing);
    expect(find.text('4/5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed event summary stays bounded when short', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 19);
    final node = MindmapNode.create(
      id: 'event-short',
      type: NodeType.event,
      title: 'Planning session with long title',
      day: day,
      data: const {
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 220.0,
        nodeUiHeightKey: 130.0,
        'startDate': '2026-07-19',
        'endDate': '2026-07-19',
        'startTime': '09:00',
        'endTime': '10:30',
        'location': 'Long meeting room location',
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );
    await settleCanvas(tester);

    expect(
      find.byKey(const ValueKey('event-collapsed-summary-event-short')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed goal scales milestone preview into remaining space', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'goal-tight-preview',
      type: NodeType.goal,
      title: 'Launch product',
      body: 'Long-term motivation',
      day: day,
      data: const {
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 336.0,
        nodeUiHeightKey: 310.0,
        'goal': {
          'milestones': ['Target', 'Motivation', 'Launch'],
          'completedMilestones': <String>[],
        },
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );
    await settleCanvas(tester);

    expect(find.text('Target'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed goal uses bounded compact summary when short', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'goal-short',
      type: NodeType.goal,
      title: 'Launch product',
      day: day,
      data: const {
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 336.0,
        nodeUiHeightKey: 240.0,
        'goal': {
          'milestones': ['Target', 'Motivation'],
          'completedMilestones': <String>[],
        },
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );
    await settleCanvas(tester);

    expect(find.text('0/2 milestones'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed habit tracker fits short custom node', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'habit-short',
      type: NodeType.habit,
      title: 'Workout',
      day: day,
      data: const {
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 240.0,
        nodeUiHeightKey: 220.0,
        'habit': {
          'recurrence': 'daily',
          'completions': ['2026-06-18'],
        },
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );
    await settleCanvas(tester);

    expect(
      find.byKey(const ValueKey<String>('habit-collapsed-tracker-habit-short')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('habit-collapsed-heatmap-habit-short')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('MindmapCanvas renders type-specific metadata chips', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final nodes = [
      MindmapNode.create(
        id: 'habit-1',
        type: NodeType.habit,
        title: 'Workout',
        day: day,
        data: const {
          'habit': {
            'recurrence': 'daily',
            'target': '30 min',
            'completions': ['2026-06-16', '2026-06-17', '2026-06-18'],
          },
        },
        now: DateTime(2026, 6, 18, 8),
      ),
      MindmapNode.create(
        id: 'goal-1',
        type: NodeType.goal,
        title: 'Launch v1',
        day: day,
        data: const {
          'goal': {
            'milestones': ['Prototype', 'Beta'],
            'completedMilestones': ['Prototype'],
          },
        },
        now: DateTime(2026, 6, 18, 9),
      ),
      MindmapNode.create(
        id: 'plan-1',
        type: NodeType.plan,
        title: 'Sprint plan',
        day: day,
        data: const {
          'plan': {
            'steps': ['Scope', 'Build'],
          },
        },
        now: DateTime(2026, 6, 18, 10),
      ),
      MindmapNode.create(
        id: 'note-1',
        type: NodeType.note,
        title: 'Reference',
        day: day,
        data: const {
          'note': {'source': 'Spec'},
        },
        now: DateTime(2026, 6, 18, 11),
      ),
      MindmapNode.create(
        id: 'journal-1',
        type: NodeType.journal,
        title: 'Daily journal',
        day: day,
        data: const {
          'journal': {'mood': 4, 'energy': 3, 'isWeeklyReview': true},
        },
        now: DateTime(2026, 6, 18, 12),
      ),
      MindmapNode.create(
        id: 'journal-monthly',
        type: NodeType.journal,
        title: 'Monthly review',
        day: day,
        data: const {
          'journal': {'isMonthlyReview': true},
        },
        now: DateTime(2026, 6, 18, 13),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: nodes)),
      ),
    );

    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('3 streak'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('habit-collapsed-tracker-habit-1')),
      findsOneWidget,
    );
    expect(find.text('3/7'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('habit-collapsed-heatmap-habit-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'habit-collapsed-heatmap-day-habit-1-2026-06-18',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('1/2 milestones'), findsOneWidget);
    expect(find.text('2 steps'), findsOneWidget);
    expect(find.text('Source: Spec'), findsOneWidget);
    expect(find.text('Mood 4'), findsOneWidget);
    expect(find.text('Energy 3'), findsOneWidget);
    expect(find.text('Weekly Review'), findsOneWidget);
    expect(find.text('Monthly Review'), findsOneWidget);
  });

  testWidgets('MindmapCanvas renders calendar payload summary', (tester) async {
    final day = DateTime(2026, 6, 18);
    final node = MindmapNode.create(
      id: 'meeting-1',
      type: NodeType.note,
      title: 'Launch sync',
      day: day,
      data: const {
        'calendar_kind': 'meeting',
        'agenda': 'Decide launch scope',
        'attendees': 'Maya\nRafi',
      },
      now: DateTime(2026, 6, 18, 8),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [node])),
      ),
    );

    expect(
      find.byKey(const ValueKey('mindmap-calendar-payload-meeting-1')),
      findsOneWidget,
    );
    expect(find.text('Meeting \u00b7 2 attendees'), findsOneWidget);
    expect(find.text('Decide launch scope'), findsOneWidget);
  });

  testWidgets('MindmapCanvas renders read-only kanban preview', (tester) async {
    final day = DateTime(2026, 6, 18);
    const board = KanbanBoard(
      cards: [
        KanbanCard(
          id: 'card-1',
          title: 'Draft copy',
          checklist: <KanbanChecklistItem>[
            KanbanChecklistItem(id: 'check-1', title: 'Review'),
          ],
          attachments: <KanbanAttachmentReference>[
            KanbanAttachmentReference(
              id: 'file-1',
              fileName: 'brief.pdf',
              mimeType: 'application/pdf',
              byteLength: 42,
            ),
          ],
        ),
        KanbanCard(
          id: 'card-2',
          title: 'Review scope',
          column: KanbanColumn.doing,
        ),
        KanbanCard(
          id: 'card-3',
          title: 'Ship update',
          column: KanbanColumn.done,
        ),
      ],
    );
    final node = MindmapNode.create(
      id: 'kanban-1',
      type: NodeType.kanban,
      title: 'Launch board',
      day: day,
      data: {'kanban': board.toJson()},
      now: DateTime(2026, 6, 18, 8),
    );
    String? advancedCardId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [node],
            onKanbanCardAdvanced: (_, cardId) {
              advancedCardId = cardId;
            },
          ),
        ),
      ),
    );

    expect(find.text('Backlog'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Draft copy'), findsOneWidget);
    expect(find.text('Review scope'), findsOneWidget);
    expect(find.text('Ship update'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('kanban-advance-kanban-1-card-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('kanban-card-menu-kanban-1-card-1')),
      findsNothing,
    );
    expect(advancedCardId, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'MindmapCanvas centers connection endpoint on custom-height target',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final node1 = MindmapNode.create(
        id: 'task-1',
        type: NodeType.task,
        title: 'Task 1',
        day: day,
        position: const CanvasPosition(-100, -100),
        relatedNodeIds: ['task-2'],
        data: const <String, Object?>{
          'uiSizePreset': 'custom',
          'uiWidth': 460.0,
          'uiHeight': 280.0,
        },
        now: day,
      );
      final node2 = MindmapNode.create(
        id: 'task-2',
        type: NodeType.task,
        title: 'Task 2',
        day: day,
        position: const CanvasPosition(100, 100),
        data: const <String, Object?>{
          'uiSizePreset': 'custom',
          'uiWidth': 240.0,
          'uiHeight': 160.0,
        },
        now: day,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MindmapCanvas(nodes: [node1, node2])),
        ),
      );

      final node2Finder = find.byKey(const ValueKey('mindmap-node-task-2'));
      final node2Center = tester.getCenter(node2Finder);
      final endpointFinder = find.byKey(
        const ValueKey('mindmap-connection-end-task-1-task-2'),
      );
      final endpointCenter = tester.getCenter(endpointFinder);
      expect(endpointCenter.dy, closeTo(node2Center.dy, 0.01));
    },
  );

  testWidgets(
    'MindmapCanvas selects and updates connection line style and stroke pattern',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final source = MindmapNode.create(
        id: 'style-source',
        type: NodeType.task,
        title: 'Source',
        day: day,
        position: const CanvasPosition(-180, 0),
        relatedNodeIds: const ['style-target'],
        now: day,
      );
      final target = MindmapNode.create(
        id: 'style-target',
        type: NodeType.note,
        title: 'Target',
        day: day,
        position: const CanvasPosition(180, 0),
        now: day,
      );
      MindmapNode? updated;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(
              nodes: [source, target],
              onNodeUpdated: (node) => updated = node,
            ),
          ),
        ),
      );
      await settleCanvas(tester);

      final line = find.byKey(
        const ValueKey('mindmap-connection-line-style-source-style-target'),
      );
      tester.widget<GestureDetector>(line).onTap!();
      await settleCanvas(tester);

      expect(find.byType(ConnectionStyleBar), findsOneWidget);

      // Trigger Line Style change on PopupMenuButton
      final lineTypeBtn = tester.widget<PopupMenuButton<ConnectionLineType>>(
        find.byWidgetPredicate((w) => w is PopupMenuButton<ConnectionLineType>),
      );
      lineTypeBtn.onSelected!(ConnectionLineType.straight);
      await settleCanvas(tester);

      final stylesMap1 = updated?.data['connection_styles'] as Map?;
      final targetStyleMap1 = stylesMap1?['style-target'] as Map?;
      expect(targetStyleMap1?['lineType'], 'straight');

      // Re-pump with updated node to verify persistent state in bar UI
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(
              nodes: [updated!, target],
              onNodeUpdated: (node) => updated = node,
            ),
          ),
        ),
      );
      await settleCanvas(tester);

      // Re-select connection
      tester.widget<GestureDetector>(line).onTap!();
      await settleCanvas(tester);

      // Trigger Stroke Pattern change on PopupMenuButton
      final linePatternBtn = tester
          .widget<PopupMenuButton<ConnectionLinePattern>>(
            find.byWidgetPredicate(
              (w) => w is PopupMenuButton<ConnectionLinePattern>,
            ),
          );
      linePatternBtn.onSelected!(ConnectionLinePattern.dashed);
      await settleCanvas(tester);

      final stylesMap2 = updated?.data['connection_styles'] as Map?;
      final targetStyleMap2 = stylesMap2?['style-target'] as Map?;
      expect(targetStyleMap2?['lineType'], 'straight');
      expect(targetStyleMap2?['linePattern'], 'dashed');
    },
  );

  testWidgets('MindmapCanvas selects and labels a connection', (tester) async {
    final day = DateTime(2026, 6, 18);
    final source = MindmapNode.create(
      id: 'source',
      type: NodeType.task,
      title: 'Source',
      day: day,
      position: const CanvasPosition(-180, 0),
      relatedNodeIds: const ['target'],
      now: day,
    );
    final target = MindmapNode.create(
      id: 'target',
      type: NodeType.note,
      title: 'Target',
      day: day,
      position: const CanvasPosition(180, 0),
      now: day,
    );
    MindmapNode? updated;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [source, target],
            onNodeUpdated: (node) => updated = node,
          ),
        ),
      ),
    );

    final connection = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('mindmap-connection-source-target')),
    );
    connection.onDoubleTap!();
    await settleCanvas(tester);
    await tester.enterText(
      find.byKey(const ValueKey('connection-label-field')),
      'Depends on',
    );
    await tester.tap(find.text('Save'));
    await settleCanvas(tester);

    expect(
      (updated?.data['connectionLabels'] as Map?)?['target'],
      'Depends on',
    );
  });

  testWidgets('MindmapCanvas selects a connection and opens its context menu', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final source = MindmapNode.create(
      id: 'menu-source',
      type: NodeType.task,
      title: 'Source',
      day: day,
      position: const CanvasPosition(-180, 0),
      relatedNodeIds: const ['menu-target'],
      now: day,
    );
    final target = MindmapNode.create(
      id: 'menu-target',
      type: NodeType.note,
      title: 'Target',
      day: day,
      position: const CanvasPosition(180, 0),
      now: day,
    );
    MindmapNode? detachedSource;
    MindmapNode? detachedTarget;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [source, target],
            onNodeDisconnected: (source, target) {
              detachedSource = source;
              detachedTarget = target;
            },
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final line = find.byKey(
      const ValueKey('mindmap-connection-line-menu-source-menu-target'),
    );
    tester.widget<GestureDetector>(line).onTap!();
    await tester.pump();

    final label = find.byKey(
      const ValueKey('mindmap-connection-menu-source-menu-target'),
    );
    tester.widget<GestureDetector>(label).onSecondaryTapUp!(
      TapUpDetails(
        kind: PointerDeviceKind.mouse,
        globalPosition: tester.getCenter(label),
      ),
    );
    await settleCanvas(tester);

    expect(find.text('Edit connection label'), findsOneWidget);
    expect(find.text('Select source node'), findsOneWidget);
    expect(find.text('Select target node'), findsOneWidget);
    expect(find.text('Delete connection'), findsOneWidget);

    await tester.tap(find.text('Delete connection'));
    await settleCanvas(tester);
    expect(detachedSource?.id, 'menu-source');
    expect(detachedTarget?.id, 'menu-target');
  });

  testWidgets(
    'MindmapCanvas clears connection selection on empty canvas click',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final source = MindmapNode.create(
        id: 'clear-source',
        type: NodeType.task,
        title: 'Source',
        day: day,
        position: const CanvasPosition(-180, 0),
        relatedNodeIds: const ['clear-target'],
        now: day,
      );
      final target = MindmapNode.create(
        id: 'clear-target',
        type: NodeType.note,
        title: 'Target',
        day: day,
        position: const CanvasPosition(180, 0),
        now: day,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MindmapCanvas(nodes: [source, target])),
        ),
      );
      await settleCanvas(tester);

      final line = find.byKey(
        const ValueKey('mindmap-connection-line-clear-source-clear-target'),
      );
      tester.widget<GestureDetector>(line).onTap!();
      await tester.pump();
      expect(find.byType(ConnectionStyleBar), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pump();

      expect(find.byType(ConnectionStyleBar), findsNothing);
    },
  );

  testWidgets('secondary click on connection suppresses canvas context menu', (
    tester,
  ) async {
    final day = DateTime(2026, 6, 18);
    final source = MindmapNode.create(
      id: 'guard-source',
      type: NodeType.task,
      title: 'Source',
      day: day,
      position: const CanvasPosition(-180, 0),
      relatedNodeIds: const ['guard-target'],
      now: day,
    );
    final target = MindmapNode.create(
      id: 'guard-target',
      type: NodeType.note,
      title: 'Target',
      day: day,
      position: const CanvasPosition(180, 0),
      now: day,
    );
    var canvasMenuCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [source, target],
            onCanvasContextMenu: (globalPosition, scenePosition) {
              canvasMenuCount += 1;
            },
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final connection = find.byKey(
      const ValueKey('mindmap-connection-guard-source-guard-target'),
    );
    final connectionCenter = tester.getCenter(connection);
    tester.widget<GestureDetector>(connection).onSecondaryTapUp!(
      TapUpDetails(
        kind: PointerDeviceKind.mouse,
        globalPosition: connectionCenter,
      ),
    );
    final canvasListener = tester
        .widgetList<Listener>(find.byType(Listener))
        .firstWhere((listener) => listener.onPointerDown != null);
    canvasListener.onPointerDown!(
      PointerDownEvent(
        buttons: kSecondaryMouseButton,
        position: connectionCenter,
      ),
    );
    await settleCanvas(tester);

    expect(find.text('Edit connection label'), findsOneWidget);
    expect(canvasMenuCount, 0);
  });

  testWidgets(
    'MindmapCanvas navigates selection and pans viewport using keyboard keys',
    (tester) async {
      final day = DateTime(2026, 6, 18);
      final nodeA = MindmapNode.create(
        id: 'node-a',
        type: NodeType.task,
        title: 'Node A',
        day: day,
        position: const CanvasPosition(0, 0),
        now: DateTime(2026, 6, 18, 8),
      );
      final nodeB = MindmapNode.create(
        id: 'node-b',
        type: NodeType.task,
        title: 'Node B',
        day: day,
        position: const CanvasPosition(0, 200), // Below node A
        now: DateTime(2026, 6, 18, 8),
      );

      MindmapNode? selectedNode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(
              nodes: [nodeA, nodeB],
              onNodeSelected: (node) {
                selectedNode = node;
              },
            ),
          ),
        ),
      );
      await settleCanvas(tester);

      // Focus the canvas
      final focusFinder = find.byType(Focus);
      expect(focusFinder, findsAtLeast(1));

      // 1. Initial selection: Tap node A
      await tester.tap(find.byKey(const ValueKey('mindmap-node-node-a')));
      await settleCanvas(tester);
      expect(selectedNode?.id, 'node-a');

      // 2. Press ArrowDown to navigate selection to Node B
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settleCanvas(tester);
      expect(selectedNode?.id, 'node-b');

      // 3. Press ArrowUp to navigate selection back to Node A
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await settleCanvas(tester);
      expect(selectedNode?.id, 'node-a');
    },
  );
  testWidgets('MindmapCanvas renders and drags a persisted group', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 11);
    final nodes = [
      MindmapNode.create(
        id: 'group-a',
        type: NodeType.task,
        title: 'Grouped A',
        day: day,
        position: const CanvasPosition(-180, 0),
        data: const {'groupId': 'group-test'},
        now: day,
      ),
      MindmapNode.create(
        id: 'group-b',
        type: NodeType.note,
        title: 'Grouped B',
        day: day,
        position: const CanvasPosition(180, 0),
        data: const {'groupId': 'group-test'},
        now: day,
      ),
    ];
    final moved = <String, CanvasPosition>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: nodes,
            onNodeMoved: (node, position) async {
              moved[node.id] = position;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-group-group-test')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const ValueKey('mindmap-group-handle-group-test')),
      const Offset(60, 40),
    );
    await tester.pump();

    expect(moved.keys, containsAll(['group-a', 'group-b']));
    expect(moved['group-a'], const CanvasPosition(-150, 20));
    expect(moved['group-b'], const CanvasPosition(210, 20));
  });

  testWidgets(
    'MindmapCanvas renders item badge and color accent in group header',
    (tester) async {
      final day = DateTime(2026, 7, 11);
      final nodes = [
        MindmapNode.create(
          id: 'group-a',
          type: NodeType.task,
          title: 'Task A',
          day: day,
          position: const CanvasPosition(-180, 0),
          data: const {
            'groupId': 'styled-group',
            'groupTitle': 'Sprint',
            'groupColor': 'emerald',
          },
          now: day,
        ),
        MindmapNode.create(
          id: 'group-b',
          type: NodeType.note,
          title: 'Note B',
          day: day,
          position: const CanvasPosition(180, 0),
          data: const {
            'groupId': 'styled-group',
            'groupTitle': 'Sprint',
            'groupColor': 'emerald',
          },
          now: day,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MindmapCanvas(nodes: nodes)),
        ),
      );
      await tester.pump();

      expect(find.text('Sprint'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mindmap-group-collapse-styled-group')),
        findsOneWidget,
      );
    },
  );

  testWidgets('MindmapCanvas does not drag a locked persisted group', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 11);
    final nodes = [
      MindmapNode.create(
        id: 'locked-a',
        type: NodeType.task,
        title: 'Locked A',
        day: day,
        position: const CanvasPosition(-180, 0),
        data: const {'groupId': 'locked-group', 'groupLocked': true},
        now: day,
      ),
      MindmapNode.create(
        id: 'locked-b',
        type: NodeType.note,
        title: 'Locked B',
        day: day,
        position: const CanvasPosition(180, 0),
        data: const {'groupId': 'locked-group', 'groupLocked': true},
        now: day,
      ),
    ];
    var moveCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(nodes: nodes, onNodeMoved: (_, _) => moveCount++),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('mindmap-group-handle-locked-group')),
      const Offset(60, 40),
    );
    await tester.pump();

    expect(moveCount, 0);
  });

  testWidgets('MindmapCanvas applies matrix and priorityGrid layout modes', (
    tester,
  ) async {
    final canvasKey = GlobalKey<MindmapCanvasState>();
    final day = DateTime(2026, 7, 11);
    final moved = <String, CanvasPosition>{};
    final nodes = [
      MindmapNode.create(
        id: 'node-u',
        type: NodeType.task,
        title: 'Urgent Node',
        day: day,
        priority: NodePriority.urgent,
        now: day,
      ),
      MindmapNode.create(
        id: 'node-h',
        type: NodeType.note,
        title: 'High Node',
        day: day,
        priority: NodePriority.high,
        now: day,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: canvasKey,
            nodes: nodes,
            onNodeMoved: (node, pos) async {
              moved[node.id] = pos;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.matrixLayout,
    );
    await tester.pump();
    expect(moved.keys, containsAll(['node-u', 'node-h']));

    moved.clear();
    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.priorityGridLayout,
    );
    await tester.pump();
    expect(moved.keys, containsAll(['node-u', 'node-h']));
  });

  testWidgets('MindmapCanvas group menu locks persisted group nodes', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 11);
    final nodes = [
      MindmapNode.create(
        id: 'menu-a',
        type: NodeType.task,
        title: 'Menu A',
        day: day,
        data: const {'groupId': 'menu-group'},
        now: day,
      ),
      MindmapNode.create(
        id: 'menu-b',
        type: NodeType.note,
        title: 'Menu B',
        day: day,
        data: const {'groupId': 'menu-group'},
        now: day,
      ),
    ];
    final updates = <MindmapNode>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: nodes,
            onNodeUpdated: (node) async => updates.add(node),
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    tester
        .state<PopupMenuButtonState<String>>(
          find.byKey(const ValueKey('mindmap-group-menu-menu-group')),
        )
        .showButtonMenu();
    await settleCanvas(tester);
    await tester.tap(find.text('Lock group'));
    await settleCanvas(tester);

    expect(updates, hasLength(2));
    expect(updates.map((node) => node.id), containsAll(['menu-a', 'menu-b']));
    expect(updates.every((node) => node.data['groupLocked'] == true), isTrue);
  });

  testWidgets('MindmapCanvas presentation mode hides controls until Escape', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 11);
    final node = MindmapNode.create(
      id: 'presentation-node',
      type: NodeType.note,
      title: 'Presentation node',
      day: day,
      now: day,
    );
    final canvasKey = GlobalKey<MindmapCanvasState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(key: canvasKey, nodes: [node]),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Show canvas controls'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mindmap-presentation-mode')),
      findsOneWidget,
    );

    canvasKey.currentState!.setPresentationMode(true);
    await settleCanvas(tester);

    expect(canvasKey.currentState!.isPresentationMode, isTrue);
    expect(
      find.byKey(const ValueKey('mindmap-node-presentation-node')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mindmap-presentation-mode')),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(canvasKey.currentState!.isPresentationMode, isFalse);
    expect(
      find.byKey(const ValueKey('mindmap-presentation-mode')),
      findsOneWidget,
    );
  });

  testWidgets('MindmapCanvas presentation navigates grouped slides', (
    tester,
  ) async {
    final key = GlobalKey<MindmapCanvasState>();
    final day = DateTime(2026, 7, 28);
    final nodes = [
      MindmapNode.create(
        id: 'slide-1a',
        type: NodeType.task,
        title: 'Slide 1A',
        day: day,
        data: const {'groupId': 'slide-1', 'groupTitle': 'Slide 1'},
        now: day,
      ),
      MindmapNode.create(
        id: 'slide-1b',
        type: NodeType.note,
        title: 'Slide 1B',
        day: day,
        data: const {'groupId': 'slide-1', 'groupTitle': 'Slide 1'},
        now: day,
      ),
      MindmapNode.create(
        id: 'slide-2a',
        type: NodeType.idea,
        title: 'Slide 2A',
        day: day,
        data: const {'groupId': 'slide-2', 'groupTitle': 'Slide 2'},
        now: day,
      ),
      MindmapNode.create(
        id: 'slide-2b',
        type: NodeType.question,
        title: 'Slide 2B',
        day: day,
        data: const {'groupId': 'slide-2', 'groupTitle': 'Slide 2'},
        now: day,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(key: key, nodes: nodes),
        ),
      ),
    );
    await tester.pump();

    key.currentState!.setPresentationMode(true);
    await settleCanvas(tester);
    expect(find.text('Slide 1 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Next slide'));
    await settleCanvas(tester);
    expect(find.text('Slide 2 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous slide'));
    await settleCanvas(tester);
    expect(find.text('Slide 1 / 2'), findsOneWidget);
  });

  testWidgets('MindmapCanvas paints uniform canvas background', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: RepaintBoundary(
          key: boundaryKey,
          child: const MindmapCanvas(nodes: []),
        ),
      ),
    );
    await tester.pump();

    final background = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('mindmap-background-mode-0')),
    );
    final recorder = ui.PictureRecorder();
    background.painter!.paint(Canvas(recorder), const Size(800, 600));
    final pixels = await tester.runAsync(() async {
      final image = await recorder.endRecording().toImage(800, 600);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      Color pixelAt(int x, int y) {
        final offset = (y * image.width + x) * 4;
        return Color.fromARGB(
          255,
          bytes!.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }

      return (center: pixelAt(400, 300), edge: pixelAt(50, 50));
    });

    expect(pixels!.center, pixels.edge);
  });

  testWidgets('MindmapCanvas cycles distinct background painter modes', (
    tester,
  ) async {
    final canvasKey = GlobalKey<MindmapCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(key: canvasKey, nodes: const []),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mindmap-background-mode-0')),
      findsOneWidget,
    );

    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.cycleBackground,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mindmap-background-mode-1')),
      findsOneWidget,
    );

    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.cycleBackground,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mindmap-background-mode-2')),
      findsOneWidget,
    );

    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.cycleBackground,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('mindmap-background-mode-0')),
      findsOneWidget,
    );
  });
  testWidgets('MindmapCanvas restores persisted background settings', (
    tester,
  ) async {
    await SharedPreferencesAsync().setString(
      'mindmap_canvas_settings_v1',
      '{"showGrid":true,"snapToGrid":false,"showCompleted":true,"backgroundMode":2}',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [])),
      ),
    );
    await settleCanvas(tester);

    expect(
      find.byKey(const ValueKey('mindmap-background-mode-2')),
      findsOneWidget,
    );
  });

  testWidgets('MindmapCanvas persists one group id across selected nodes', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 11);
    final nodes = [
      MindmapNode.create(
        id: 'group-meta-a',
        type: NodeType.task,
        title: 'A',
        day: day,
        now: day,
      ),
      MindmapNode.create(
        id: 'group-meta-b',
        type: NodeType.note,
        title: 'B',
        day: day,
        now: day,
      ),
    ];
    final updates = <MindmapNode>[];
    final canvasKey = GlobalKey<MindmapCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: canvasKey,
            nodes: nodes,
            onNodeUpdated: (node) async => updates.add(node),
          ),
        ),
      ),
    );

    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.selectAll,
    );
    await tester.pump();
    expect(find.text('2 nodes selected'), findsOneWidget);
    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.groupSelection,
    );

    expect(updates, hasLength(2));
    final groupIds = updates.map((node) => node.data['groupId']).toSet();
    expect(groupIds, hasLength(1));
    expect(groupIds.single, isA<String>());
    expect(updates.map((node) => node.data['groupTitle']).toSet(), {'Group'});
  });

  testWidgets('MindmapCanvas timeline layout orders due date then id', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 11);
    final nodes = [
      MindmapNode.create(
        id: 'late',
        type: NodeType.task,
        title: 'Late',
        day: day,
        dueDate: DateTime(2026, 7, 13),
        now: DateTime(2026, 7, 11, 8),
      ),
      MindmapNode.create(
        id: 'early-b',
        type: NodeType.task,
        title: 'Early B',
        day: day,
        dueDate: DateTime(2026, 7, 12),
        now: DateTime(2026, 7, 11, 9),
      ),
      MindmapNode.create(
        id: 'early-a',
        type: NodeType.task,
        title: 'Early A',
        day: day,
        dueDate: DateTime(2026, 7, 12),
        now: DateTime(2026, 7, 11, 10),
      ),
    ];
    final moved = <String, CanvasPosition>{};
    final canvasKey = GlobalKey<MindmapCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: canvasKey,
            nodes: nodes,
            onNodeMoved: (node, position) async {
              moved[node.id] = position;
            },
          ),
        ),
      ),
    );

    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.timelineLayout,
    );

    expect(moved['early-a']!.dx, lessThan(moved['early-b']!.dx));
    expect(moved['early-b']!.dx, lessThan(moved['late']!.dx));
    expect(moved['early-a']!.dy, -90);
    expect(moved['early-b']!.dy, 90);
    expect(moved['late']!.dy, -90);
  });

  for (final action in <CanvasContextAction>[
    CanvasContextAction.tidyLayout,
    CanvasContextAction.radialLayout,
    CanvasContextAction.typeLayout,
    CanvasContextAction.timelineLayout,
  ]) {
    testWidgets('MindmapCanvas ${action.name} avoids mixed-size overlap', (
      tester,
    ) async {
      final day = DateTime(2026, 7, 13);
      final sizes = <String, Size>{
        'wide': const Size(620, 260),
        'tall': const Size(260, 500),
        'small': const Size(220, 140),
        'medium': const Size(380, 240),
      };
      final types = <String, NodeType>{
        'wide': NodeType.note,
        'tall': NodeType.task,
        'small': NodeType.note,
        'medium': NodeType.goal,
      };
      final ids = sizes.keys.toList();
      final nodes = sizes.entries.map((entry) {
        return MindmapNode.create(
          id: entry.key,
          type: types[entry.key]!,
          title: entry.key,
          day: day,
          data: <String, Object?>{
            'uiSizePreset': 'custom',
            'uiWidth': entry.value.width,
            'uiHeight': entry.value.height,
          },
          now: day.add(Duration(minutes: ids.indexOf(entry.key))),
        );
      }).toList();
      final moved = <String, CanvasPosition>{};
      final canvasKey = GlobalKey<MindmapCanvasState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MindmapCanvas(
              key: canvasKey,
              nodes: nodes,
              onNodeMoved: (node, position) => moved[node.id] = position,
            ),
          ),
        ),
      );

      await canvasKey.currentState!.runContextAction(action);

      final rects = <String, Rect>{
        for (final entry in moved.entries)
          entry.key: Offset(entry.value.dx, entry.value.dy) & sizes[entry.key]!,
      };
      for (var first = 0; first < nodes.length; first++) {
        for (var second = first + 1; second < nodes.length; second++) {
          expect(
            rects[nodes[first].id]!.overlaps(rects[nodes[second].id]!),
            isFalse,
            reason: '${nodes[first].id} overlaps ${nodes[second].id}',
          );
        }
      }
    });
  }

  testWidgets('MindmapCanvas radial layout handles zero nodes', (tester) async {
    final canvasKey = GlobalKey<MindmapCanvasState>();
    var moveCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: canvasKey,
            nodes: const <MindmapNode>[],
            onNodeMoved: (node, position) => moveCount++,
          ),
        ),
      ),
    );

    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.radialLayout,
    );

    expect(moveCount, 0);
  });

  testWidgets('MindmapCanvas radial layout centers one custom node', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 13);
    final canvasKey = GlobalKey<MindmapCanvasState>();
    final node = MindmapNode.create(
      id: 'radial-single',
      type: NodeType.note,
      title: 'Single',
      day: day,
      data: const <String, Object?>{
        'uiSizePreset': 'custom',
        'uiWidth': 600.0,
        'uiHeight': 400.0,
      },
      now: day,
    );
    CanvasPosition? moved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: canvasKey,
            nodes: <MindmapNode>[node],
            onNodeMoved: (node, position) => moved = position,
          ),
        ),
      ),
    );

    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.radialLayout,
    );

    expect(moved, isNotNull);
    expect(moved!.dx.isFinite, isTrue);
    expect(moved!.dy.isFinite, isTrue);
    expect(moved, const CanvasPosition(-300, -200));
    final sceneRect =
        Offset(
          MindmapCanvas.canvasSize.width / 2 + moved!.dx,
          MindmapCanvas.canvasSize.height / 2 + moved!.dy,
        ) &
        const Size(600, 400);
    expect(sceneRect.left, greaterThanOrEqualTo(0));
    expect(sceneRect.top, greaterThanOrEqualTo(0));
    expect(sceneRect.right, lessThanOrEqualTo(MindmapCanvas.canvasSize.width));
    expect(
      sceneRect.bottom,
      lessThanOrEqualTo(MindmapCanvas.canvasSize.height),
    );
  });

  testWidgets('MindmapCanvas classifies clipboard URL and text imports', (
    tester,
  ) async {
    final created = <MindmapNode>[];
    final canvasKey = GlobalKey<MindmapCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            key: canvasKey,
            nodes: const [],
            onNodeUpdated: (node) async => created.add(node),
          ),
        ),
      ),
    );

    var clipboardText = 'https://example.com/path';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.importClipboard,
      scenePosition: const Offset(12, 34),
    );
    clipboardText = 'https://example.com/photo.webp?size=large';
    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.importClipboard,
      scenePosition: const Offset(40, 50),
    );
    clipboardText = 'Plain note\nBody';
    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.importClipboard,
      scenePosition: const Offset(56, 78),
    );

    expect(created, hasLength(3));
    expect(created.first.type, NodeType.bookmark);
    expect(created.first.title, 'example.com');
    expect(created.first.data['url'], 'https://example.com/path');
    expect(created.first.position, const CanvasPosition(12, 34));
    expect(created[1].type, NodeType.image);
    expect(
      ImagePayload.fromNode(created[1]).url,
      'https://example.com/photo.webp?size=large',
    );
    expect(created.last.type, NodeType.note);
    expect(created.last.title, 'Plain note');
    expect(created.last.body, 'Plain note\nBody');
    expect(created.last.position, const CanvasPosition(56, 78));
  });
  testWidgets('MindmapCanvas renames every member from group frame', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 11);
    final nodes = [
      MindmapNode.create(
        id: 'rename-a',
        type: NodeType.task,
        title: 'A',
        day: day,
        position: const CanvasPosition(-180, 0),
        data: const {'groupId': 'rename-group', 'groupTitle': 'Sprint'},
        now: day,
      ),
      MindmapNode.create(
        id: 'rename-b',
        type: NodeType.note,
        title: 'B',
        day: day,
        position: const CanvasPosition(180, 0),
        data: const {'groupId': 'rename-group', 'groupTitle': 'Sprint'},
        now: day,
      ),
    ];
    final updates = <MindmapNode>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: nodes,
            onNodeUpdated: (node) async => updates.add(node),
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(find.text('Sprint'), findsOneWidget);
    tester
        .state<PopupMenuButtonState<String>>(
          find.byKey(const ValueKey('mindmap-group-menu-rename-group')),
        )
        .showButtonMenu();
    await settleCanvas(tester);
    await tester.tap(find.text('Rename group'));
    await settleCanvas(tester);
    await tester.enterText(
      find.byKey(const ValueKey('group-title-field')),
      'Release',
    );
    await tester.tap(find.text('Save'));
    await settleCanvas(tester);

    expect(updates, hasLength(2));
    expect(updates.map((node) => node.data['groupTitle']).toSet(), {'Release'});
  });

  testWidgets('MindmapCanvas ungroups every member from group frame menu', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 11);
    final nodes = [
      MindmapNode.create(
        id: 'ungroup-a',
        type: NodeType.task,
        title: 'A',
        day: day,
        position: const CanvasPosition(-180, 0),
        data: const {'groupId': 'ungroup-test', 'groupTitle': 'Release'},
        now: day,
      ),
      MindmapNode.create(
        id: 'ungroup-b',
        type: NodeType.note,
        title: 'B',
        day: day,
        position: const CanvasPosition(180, 0),
        data: const {'groupId': 'ungroup-test', 'groupTitle': 'Release'},
        now: day,
      ),
    ];
    final updates = <MindmapNode>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: nodes,
            onNodeUpdated: (node) async => updates.add(node),
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    tester
        .state<PopupMenuButtonState<String>>(
          find.byKey(const ValueKey('mindmap-group-menu-ungroup-test')),
        )
        .showButtonMenu();
    await settleCanvas(tester);
    tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const ValueKey('mindmap-group-menu-ungroup-test')),
        )
        .onSelected!('ungroup');
    await settleCanvas(tester);

    expect(updates, hasLength(2));
    expect(updates.every((node) => !node.data.containsKey('groupId')), isTrue);
    expect(
      updates.every((node) => !node.data.containsKey('groupTitle')),
      isTrue,
    );
  });
  testWidgets('MindmapCanvas renders custom node dimensions exactly', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 13);
    final node = MindmapNode.create(
      id: 'custom-size',
      type: NodeType.note,
      title: 'Custom size',
      day: day,
      position: const CanvasPosition(-180, -120),
      data: const <String, Object?>{
        'uiSizePreset': 'custom',
        'uiWidth': 460.0,
        'uiHeight': 280.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: <MindmapNode>[node])),
      ),
    );

    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('mindmap-node-custom-size')),
      ),
      const Size(460, 280),
    );
  });

  testWidgets('MindmapCanvas zooms to mixed custom-size selection', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 13);
    final canvasKey = GlobalKey<MindmapCanvasState>();
    final nodes = <MindmapNode>[
      MindmapNode.create(
        id: 'zoom-wide',
        type: NodeType.note,
        title: 'Wide',
        day: day,
        position: const CanvasPosition(-900, -300),
        data: const <String, Object?>{
          'uiSizePreset': 'custom',
          'uiWidth': 800.0,
          'uiHeight': 220.0,
        },
        now: day,
      ),
      MindmapNode.create(
        id: 'zoom-tall',
        type: NodeType.task,
        title: 'Tall',
        day: day,
        position: const CanvasPosition(700, 180),
        data: const <String, Object?>{
          'uiSizePreset': 'custom',
          'uiWidth': 240.0,
          'uiHeight': 560.0,
        },
        now: day,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(key: canvasKey, nodes: nodes),
        ),
      ),
    );
    final initialViewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final initialMatrix = initialViewer.transformationController!.value.clone();
    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.selectAll,
    );
    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.zoomToSelection,
    );
    await settleCanvas(tester);

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final matrix = viewer.transformationController!.value;
    expect(matrix, isNot(equals(initialMatrix)));
    final origin = Offset(
      MindmapCanvas.canvasSize.width / 2,
      MindmapCanvas.canvasSize.height / 2,
    );
    final sizes = <String, Size>{
      'zoom-wide': const Size(800, 220),
      'zoom-tall': const Size(240, 560),
    };
    Rect? selectionBounds;
    for (final node in nodes) {
      final rect =
          (origin + Offset(node.position.dx, node.position.dy)) &
          sizes[node.id]!;
      selectionBounds = selectionBounds == null
          ? rect
          : selectionBounds.expandToInclude(rect);
    }
    final paddedBounds = selectionBounds!.inflate(120);
    final viewportSize = tester.getSize(find.byType(InteractiveViewer));
    final transformedCenter = MatrixUtils.transformPoint(
      matrix,
      paddedBounds.center,
    );
    final viewportCenter = Offset(
      viewportSize.width / 2,
      viewportSize.height / 2,
    );
    expect(transformedCenter.dx, closeTo(viewportCenter.dx, 1));
    expect(transformedCenter.dy, closeTo(viewportCenter.dy, 1));
    for (final corner in <Offset>[
      paddedBounds.topLeft,
      paddedBounds.topRight,
      paddedBounds.bottomLeft,
      paddedBounds.bottomRight,
    ]) {
      final transformed = MatrixUtils.transformPoint(matrix, corner);
      expect(transformed.dx, inInclusiveRange(-1, viewportSize.width + 1));
      expect(transformed.dy, inInclusiveRange(-1, viewportSize.height + 1));
    }
  });

  testWidgets('MindmapCanvas group frame encloses mixed custom sizes', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 13);
    final nodes = <MindmapNode>[
      MindmapNode.create(
        id: 'group-wide',
        type: NodeType.note,
        title: 'Wide',
        day: day,
        position: const CanvasPosition(-180, 0),
        data: const <String, Object?>{
          'groupId': 'custom-bounds',
          'uiSizePreset': 'custom',
          'uiWidth': 500.0,
          'uiHeight': 180.0,
        },
        now: day,
      ),
      MindmapNode.create(
        id: 'group-tall',
        type: NodeType.task,
        title: 'Tall',
        day: day,
        position: const CanvasPosition(180, 0),
        data: const <String, Object?>{
          'groupId': 'custom-bounds',
          'uiSizePreset': 'custom',
          'uiWidth': 260.0,
          'uiHeight': 420.0,
        },
        now: day,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: nodes)),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('mindmap-group-custom-bounds'))),
      const Size(676, 476),
    );
  });

  testWidgets('MindmapCanvas minimap uses custom node rectangle dimensions', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 13);
    final canvasKey = GlobalKey<MindmapCanvasState>();
    final node = MindmapNode.create(
      id: 'minimap-custom',
      type: NodeType.image,
      title: 'Preview',
      day: day,
      data: const <String, Object?>{
        'uiSizePreset': 'custom',
        'uiWidth': 800.0,
        'uiHeight': 700.0,
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(key: canvasKey, nodes: <MindmapNode>[node]),
        ),
      ),
    );
    await canvasKey.currentState!.runContextAction(
      CanvasContextAction.toggleMinimap,
    );
    await tester.pump();

    final markerSize = tester.getSize(
      find.byKey(const ValueKey('mindmap-minimap-node-minimap-custom')),
    );
    final minimapSize = tester.getSize(
      find.byKey(const ValueKey('mindmap-minimap-semantics')),
    );
    expect(markerSize.width, greaterThan(40));
    expect(markerSize.height, greaterThan(40));
    expect(markerSize.width, lessThan(minimapSize.width));
    expect(markerSize.height, lessThan(minimapSize.height));
  });

  testWidgets('resource loads primary image attachment', (tester) async {
    final day = DateTime(2026, 7, 17);
    const attachmentId = '12345678-1234-1234-1234-123456789abc';
    final base = MindmapNode.create(
      id: 'production-resource',
      type: NodeType.resource,
      title: 'Resource image',
      day: day,
      now: day,
    );
    final node = base.copyWith(
      data: const ResourcePayload(
        primaryAsset: ResourceAsset(
          id: 'primary',
          kind: 'file',
          attachmentId: attachmentId,
          mimeType: 'image/png',
          fileName: 'reference.png',
          extension: 'png',
        ),
      ).toData(base.data),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => const _MemoryAttachmentRepository(
              attachmentId: attachmentId,
              bytes: _onePixelPng,
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: buildProductionNodeTypeContentForTest(node),
            ),
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    expect(
      find.byKey(
        const ValueKey<String>('production-node-content-production-resource-0'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-preview-image')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-collapsed-preview')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed audio renders real attachment playback controls', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 18);
    const attachmentId = 'audio-attachment';
    final base = MindmapNode.create(
      id: 'collapsed-audio',
      type: NodeType.audio,
      title: 'Voice note',
      day: day,
      now: day,
    );
    final node = base.copyWith(
      data: const AudioPayload(
        sourceType: AudioSourceType.attachment,
        attachmentId: attachmentId,
        fileName: 'voice-note.wav',
        mimeType: 'audio/wav',
      ).toData(base.data),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => const _MemoryAttachmentRepository(
              attachmentId: attachmentId,
              bytes: <int>[82, 73, 70, 70],
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: buildCollapsedAudioDetailsForTest(node)),
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('audio-collapsed-play-toggle')),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('voice-note.wav'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'canvas renders Image through dispatcher and attachment provider',
    (tester) async {
      final day = DateTime(2026, 7, 13);
      const attachmentId = '12345678-1234-1234-1234-123456789abc';
      final node = MindmapNode.create(
        id: 'production-image',
        type: NodeType.image,
        title: 'Production image',
        day: day,
        now: day,
        data: const ImagePayload(
          attachmentId: attachmentId,
          mimeType: 'image/png',
          fileName: 'photo.png',
          altText: 'Production alt',
        ).toData(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nodeAttachmentRepositoryProvider.overrideWith(
              (ref) async => const _MemoryAttachmentRepository(
                attachmentId: attachmentId,
                bytes: _onePixelPng,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: MindmapCanvas(nodes: [node])),
          ),
        ),
      );
      await settleCanvas(tester);
      expect(
        find.byKey(
          const ValueKey('production-node-content-production-image-0'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('image-local-preview')), findsOneWidget);
    },
  );

  testWidgets(
    'production image editor loads attachment from active draft payload',
    (tester) async {
      final day = DateTime(2026, 7, 18);
      const attachmentId = '12345678-1234-1234-1234-123456789abc';
      final node = MindmapNode.create(
        id: 'draft-image-preview',
        type: NodeType.image,
        title: 'Draft image',
        day: day,
        now: day,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nodeAttachmentRepositoryProvider.overrideWith(
              (ref) async => const _MemoryAttachmentRepository(
                attachmentId: attachmentId,
                bytes: _onePixelPng,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1000,
                height: 900,
                child: buildProductionNodeInlineEditorForTest(
                  node: node,
                  initialPayload: const ImagePayload(
                    attachmentId: attachmentId,
                    mimeType: 'image/png',
                    fileName: 'draft-photo.png',
                  ),
                  onNodeUpdated: null,
                ),
              ),
            ),
          ),
        ),
      );
      await settleCanvas(tester);

      expect(find.byKey(const ValueKey('image-local-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('production image editor replaces local attachment and preview', (
    tester,
  ) async {
    final day = DateTime(2026, 7, 18);
    final repository = _ReplacingAttachmentRepository();
    final importService = MediaFileImportService(
      repository: repository,
      picker: _SingleMediaPicker(
        PickedMediaFile(
          fileName: 'replacement.png',
          byteLength: _onePixelPng.length,
          mimeType: 'image/png',
          bytes: _onePixelPng,
        ),
      ),
    );
    final node = MindmapNode.create(
      id: 'replace-image-inline',
      type: NodeType.image,
      title: 'Replace image',
      day: day,
      now: day,
      data: const ImagePayload(
        attachmentId: _attachmentA,
        mimeType: 'image/png',
        fileName: 'original.png',
        caption: 'Keep caption',
        altText: 'Keep alt',
      ).toData(),
    );
    final updates = <MindmapNode>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          mediaFileImportServiceProvider.overrideWith(
            (ref) async => importService,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 900,
              child: buildProductionNodeInlineEditorForTest(
                node: node,
                onNodeUpdated: updates.add,
              ),
            ),
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    await tester.tap(find.text('Replace'));
    await settleCanvas(tester);

    expect(updates, isNotEmpty);
    final payload = ImagePayload.fromNode(updates.last);
    expect(payload.attachmentId, _attachmentB);
    expect(payload.fileName, 'replacement.png');
    expect(payload.caption, 'Keep caption');
    expect(payload.altText, 'Keep alt');
    expect(repository.reads, contains(_attachmentB));
    expect(find.text('replacement.png'), findsOneWidget);
    expect(find.textContaining('file picker is unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'production image editor saves edits and restores original attachment',
    (tester) async {
      final day = DateTime(2026, 7, 18);
      final repository = _ReplacingAttachmentRepository();
      final node = MindmapNode.create(
        id: 'save-edited-image-inline',
        type: NodeType.image,
        title: 'Save edited image',
        day: day,
        now: day,
        data: const ImagePayload(
          attachmentId: _attachmentA,
          mimeType: 'image/png',
          fileName: 'original.png',
          altText: 'Edited image',
          brightness: 0.2,
          annotations: <ImageAnnotation>[
            ImageAnnotation(
              id: 'save-annotation',
              type: ImageAnnotationType.rectangle,
            ),
          ],
        ).toData(),
      );
      final updates = <MindmapNode>[];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nodeAttachmentRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1000,
                height: 900,
                child: buildProductionNodeInlineEditorForTest(
                  node: node,
                  onNodeUpdated: updates.add,
                ),
              ),
            ),
          ),
        ),
      );
      await settleCanvas(tester);

      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save as new image'),
      );
      expect(saveButton.onPressed, isNotNull);
      saveButton.onPressed!();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      for (var index = 0; index < 6; index++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(repository.importCount, 1);
      expect(updates, isNotEmpty);
      var payload = ImagePayload.fromNode(updates.last);
      expect(payload.attachmentId, _attachmentB);
      expect(payload.originalAttachmentId, _attachmentA);
      expect(payload.brightness, 0);
      expect(payload.annotations, isEmpty);
      expect(repository.reads, contains(_attachmentB));
      expect(find.text('Restore original'), findsOneWidget);

      await tester.tap(find.text('Restore original'));
      for (var index = 0; index < 4; index++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      payload = ImagePayload.fromNode(updates.last);
      expect(payload.attachmentId, _attachmentA);
      expect(payload.fileName, 'original.png');
      expect(payload.mimeType, 'image/png');
      expect(payload.originalAttachmentId, isEmpty);
      expect(repository.reads.last, _attachmentA);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'open production image editor loads attachment added without remount',
    (tester) async {
      final key = GlobalKey<_OpenImageAttachmentHarnessState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nodeAttachmentRepositoryProvider.overrideWith(
              (ref) async => const _MemoryAttachmentRepository(
                attachmentId: _attachmentA,
                bytes: _onePixelPng,
              ),
            ),
          ],
          child: MaterialApp(home: _OpenImageAttachmentHarness(key: key)),
        ),
      );
      await settleCanvas(tester);
      expect(find.byKey(const ValueKey('image-local-preview')), findsNothing);

      key.currentState!.attachImage();
      expect(
        ImagePayload.fromNode(key.currentState!.node).fileName,
        'uploaded.png',
      );
      await settleCanvas(tester);

      expect(find.text('uploaded.png'), findsOneWidget);
      expect(find.byKey(const ValueKey('image-local-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'production image editor preserves local draft and accepts same-id external update',
    (tester) async {
      final key = GlobalKey<_ImageRevisionHarnessState>();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: _ImageRevisionHarness(key: key)),
        ),
      );
      await settleCanvas(tester);
      tester
          .state<MindmapCanvasState>(find.byType(MindmapCanvas))
          .beginInlineEdit('revision-image');
      await settleCanvas(tester);
      expect(find.byKey(const ValueKey('image-editor-wide')), findsOneWidget);
      Finder captionField() => find.byWidgetPredicate((widget) {
        final key = widget.key;
        return widget is TextFormField &&
            key is ValueKey<String> &&
            key.value.startsWith('image-caption-revision-image-');
      });
      final caption = captionField();
      expect(caption, findsOneWidget);
      await tester.enterText(caption, 'Local optimistic');
      key.currentState!.rebuildStaleParent();
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: caption, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'Local optimistic',
      );
      key.currentState!.applyExternalCaption('External persisted');
      await settleCanvas(tester);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: captionField(),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'External persisted',
      );
    },
  );

  testWidgets(
    'renderer ignores stale attachment completion and reuses Uint8List',
    (tester) async {
      final repository = _DelayedAttachmentRepository();
      final key = GlobalKey<_AttachmentRaceHarnessState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nodeAttachmentRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
          ],
          child: MaterialApp(home: _AttachmentRaceHarness(key: key)),
        ),
      );
      await tester.pump();
      await tester.pump();
      key.currentState!.switchAttachment(_attachmentB);
      for (var index = 0; index < 5; index++) {
        await tester.pump();
      }
      expect(repository.reads, contains(_attachmentB));
      final bytesB = Uint8List.fromList(_onePixelPng);
      repository.complete(_attachmentB, bytesB);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      repository.complete(
        _attachmentA,
        Uint8List.fromList([..._onePixelPng, 0]),
      );
      await tester.pump();
      await tester.pump();
      expect(_memoryBytes(tester), same(bytesB));
    },
  );

  testWidgets('inline owner ignores stale attachment completion', (
    tester,
  ) async {
    final repository = _DelayedAttachmentRepository();
    final key = GlobalKey<_AttachmentRaceHarnessState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp(
          home: _AttachmentRaceHarness(key: key, editing: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    key.currentState!.switchAttachment(_attachmentB);
    for (var index = 0; index < 5; index++) {
      await tester.pump();
    }
    expect(repository.reads, contains(_attachmentB));
    final bytesB = Uint8List.fromList(_onePixelPng);
    repository.complete(_attachmentB, bytesB);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    repository.complete(_attachmentA, Uint8List.fromList([..._onePixelPng, 0]));
    await tester.pump();
    expect(_memoryBytes(tester), same(bytesB));
  });

  testWidgets('inline export ignores stale source and reuses Uint8List', (
    tester,
  ) async {
    final repository = _DelayedAttachmentRepository();
    final exports = <(Uint8List, String)>[];
    final key = GlobalKey<_AttachmentRaceHarnessState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp(
          home: _AttachmentRaceHarness(
            key: key,
            editing: true,
            onImageExport: (bytes, fileName) => exports.add((bytes, fileName)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Export'));
    await tester.pump();
    expect(repository.exports, contains(_attachmentA));
    key.currentState!.switchAttachment(_attachmentB);
    await tester.pump();
    repository.completeExport(_attachmentA, Uint8List.fromList(_onePixelPng));
    await tester.pump();
    expect(exports, isEmpty);

    await tester.tap(find.text('Export'));
    await tester.pump();
    final bytesB = Uint8List.fromList(_onePixelPng);
    repository.completeExport(_attachmentB, bytesB);
    await tester.pump();
    expect(exports, hasLength(1));
    expect(exports.single.$1, same(bytesB));
    expect(exports.single.$2, 'race-b.png');
  });

  testWidgets('inline export failure is contained as media error', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeAttachmentRepositoryProvider.overrideWith(
            (ref) async => const _ThrowingExportAttachmentRepository(),
          ),
        ],
        child: const MaterialApp(home: _AttachmentRaceHarness(editing: true)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('export failed'), findsWidgets);
  });

  testWidgets('connection target picker ListTiles paint ink and connect', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 15);
    final source = MindmapNode.create(
      id: 'picker-source',
      type: NodeType.note,
      title: 'Picker source',
      day: day,
      position: const CanvasPosition(-220, 0),
      now: day,
    );
    final target = MindmapNode.create(
      id: 'picker-target',
      type: NodeType.note,
      title: 'Picker target',
      day: day,
      position: const CanvasPosition(220, 0),
      now: day,
    );
    (MindmapNode, MindmapNode)? connected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [source, target],
            onNodeConnected: (source, target) async {
              connected = (source, target);
            },
            onConnectedNodeCreate: (source, type, position) async => null,
          ),
        ),
      ),
    );
    await settleCanvas(tester);

    final sourceRect = tester.getRect(
      find.byKey(const ValueKey('mindmap-node-picker-source')),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(Offset(sourceRect.right - 2, sourceRect.center.dy));
    await gesture.moveTo(const Offset(600, 700));
    await gesture.up();
    await settleCanvas(tester);

    expect(
      find.byKey(const ValueKey('connection-target-menu-panel')),
      findsOneWidget,
    );
    expect(find.widgetWithText(ListTile, 'Picker target'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Create Note'), findsOneWidget);
    final targetTile = find.widgetWithText(ListTile, 'Picker target');
    final panelMaterial = tester.widget<Material>(
      find.ancestor(of: targetTile, matching: find.byType(Material)).first,
    );
    expect(panelMaterial.color, isNot(Colors.transparent));
    expect(panelMaterial.clipBehavior, Clip.antiAlias);
    await gesture.moveTo(tester.getCenter(targetTile));
    await tester.pump();
    await gesture.down(tester.getCenter(targetTile));
    await gesture.up();
    await settleCanvas(tester);

    expect(tester.takeException(), isNull);
    expect(connected?.$1.id, source.id);
    expect(connected?.$2.id, target.id);
  });

  testWidgets('compact right-center drag previews and connects nodes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 15);
    final source = MindmapNode.create(
      id: 'compact-connect-source',
      type: NodeType.note,
      title: 'Compact source',
      day: day,
      position: const CanvasPosition(-220, 0),
      data: const {nodeUiSizePresetKey: 'compact'},
      now: day,
    );
    final target = MindmapNode.create(
      id: 'compact-connect-target',
      type: NodeType.note,
      title: 'Target',
      day: day,
      position: const CanvasPosition(220, 0),
      now: day,
    );
    (MindmapNode, MindmapNode)? connected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: [source, target],
            onNodeConnected: (source, target) async {
              connected = (source, target);
            },
          ),
        ),
      ),
    );
    await settleCanvas(tester);
    final sourceRect = tester.getRect(
      find.byKey(const ValueKey('mindmap-node-compact-connect-source')),
    );
    final targetCenter = tester.getCenter(
      find.byKey(const ValueKey('mindmap-node-compact-connect-target')),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(Offset(sourceRect.right - 2, sourceRect.center.dy));
    await tester.pump();
    await gesture.moveTo(targetCenter);
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_ConnectionDragPainter',
      ),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pump();

    expect(connected?.$1.id, source.id);
    expect(connected?.$2.id, target.id);
  });

  testWidgets('compact Image and Itinerary presets render without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 15);
    final image = MindmapNode.create(
      id: 'compact-image-render',
      type: NodeType.image,
      title: 'Compact image',
      day: day,
      position: const CanvasPosition(-180, 0),
      data: {
        ...const ImagePayload(url: 'https://example.com/image.png').toData(),
        nodeUiSizePresetKey: 'compact',
      },
      now: day,
    );
    final itinerary = MindmapNode.create(
      id: 'compact-itinerary-render',
      type: NodeType.itinerary,
      title: 'Compact itinerary',
      day: day,
      position: const CanvasPosition(180, 0),
      data: {
        ...ItineraryPayload(
          destination: 'Bandung',
          startDate: day,
          endDate: day,
          timezone: 'Asia/Jakarta',
        ).toData(),
        nodeUiSizePresetKey: 'compact',
      },
      now: day,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MindmapCanvas(nodes: [image, itinerary])),
      ),
    );
    await settleCanvas(tester);

    expect(tester.takeException(), isNull);
    for (final nodeId in ['compact-image-render', 'compact-itinerary-render']) {
      final shell = tester.widget<NodeShell>(
        find.descendant(
          of: find.byKey(ValueKey('mindmap-node-$nodeId')),
          matching: find.byType(NodeShell),
        ),
      );
      expect(shell.isCompact, isTrue);
      expect(shell.preset, NodeSizePreset.compact);
    }
  });
}

const _attachmentA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _attachmentB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

Uint8List _memoryBytes(WidgetTester tester) {
  final image = tester.widget<Image>(
    find.byKey(const ValueKey('image-local-preview')).last,
  );
  final provider = image.image;
  return switch (provider) {
    final ResizeImage resize => (resize.imageProvider as MemoryImage).bytes,
    final MemoryImage memory => memory.bytes,
    _ => throw StateError('Expected memory image provider.'),
  };
}

const List<int> _onePixelPng = [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  8,
  215,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  0,
  1,
  255,
  137,
  153,
  61,
  29,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

final class _MemoryAttachmentRepository implements NodeAttachmentRepository {
  const _MemoryAttachmentRepository({
    required this.attachmentId,
    required this.bytes,
  });
  final String attachmentId;
  final List<int> bytes;
  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() async => const [];
  @override
  Future<void> delete(String attachmentId) async {}
  @override
  Future<List<int>?> exportBytes(String attachmentId) async =>
      readBytes(attachmentId);
  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) => throw UnimplementedError();
  @override
  Future<List<int>?> readBytes(String attachmentId) async =>
      attachmentId == this.attachmentId ? bytes : null;
  @override
  Future<NodeAttachment?> resolve(String attachmentId) async => null;
}

final class _SingleMediaPicker implements MediaFilePicker {
  const _SingleMediaPicker(this.file);

  final PickedMediaFile? file;

  @override
  Future<PickedMediaFile?> pick(MediaFileKind kind) async => file;
}

final class _ReplacingAttachmentRepository implements NodeAttachmentRepository {
  final Map<String, List<int>> _bytes = <String, List<int>>{
    _attachmentA: _onePixelPng,
  };
  final List<String> reads = <String>[];
  int importCount = 0;

  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    importCount += 1;
    _bytes[_attachmentB] = List<int>.of(bytes);
    return NodeAttachment(
      id: _attachmentB,
      fileName: fileName,
      mimeType: mimeType,
      byteLength: bytes.length,
      checksum: 'b' * 64,
      createdAt: DateTime.utc(2026, 7, 18),
    );
  }

  @override
  Future<List<int>?> readBytes(String attachmentId) async {
    reads.add(attachmentId);
    return _bytes[attachmentId];
  }

  @override
  Future<List<int>?> exportBytes(String attachmentId) async =>
      _bytes[attachmentId];

  @override
  Future<void> delete(String attachmentId) async {
    _bytes.remove(attachmentId);
  }

  @override
  Future<NodeAttachment?> resolve(String attachmentId) async {
    final bytes = _bytes[attachmentId];
    if (bytes == null) return null;
    return NodeAttachment(
      id: attachmentId,
      fileName: attachmentId == _attachmentA
          ? 'original.png'
          : 'replacement.png',
      mimeType: 'image/png',
      byteLength: bytes.length,
      checksum: 'c' * 64,
      createdAt: DateTime.utc(2026, 7, 18),
    );
  }

  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() async => const [];
}

final class _ThrowingExportAttachmentRepository
    implements NodeAttachmentRepository {
  const _ThrowingExportAttachmentRepository();
  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() async => const [];
  @override
  Future<void> delete(String attachmentId) async {}
  @override
  Future<List<int>?> exportBytes(String attachmentId) =>
      Future<List<int>?>.error(StateError('export failed'));
  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) => throw UnimplementedError();
  @override
  Future<List<int>?> readBytes(String attachmentId) async => _onePixelPng;
  @override
  Future<NodeAttachment?> resolve(String attachmentId) async => null;
}

final class _DelayedAttachmentRepository implements NodeAttachmentRepository {
  final Map<String, Completer<List<int>?>> _reads = {};
  final Map<String, Completer<List<int>?>> _exports = {};
  final List<String> reads = [];
  final List<String> exports = [];

  void complete(String id, List<int> bytes) =>
      _reads.putIfAbsent(id, Completer<List<int>?>.new).complete(bytes);

  void completeExport(String id, List<int> bytes) =>
      _exports.putIfAbsent(id, Completer<List<int>?>.new).complete(bytes);

  @override
  Future<List<int>?> readBytes(String attachmentId) {
    reads.add(attachmentId);
    return _reads.putIfAbsent(attachmentId, Completer<List<int>?>.new).future;
  }

  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() async => const [];
  @override
  Future<void> delete(String attachmentId) async {}
  @override
  Future<List<int>?> exportBytes(String attachmentId) {
    exports.add(attachmentId);
    return _exports.putIfAbsent(attachmentId, Completer<List<int>?>.new).future;
  }

  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) => throw UnimplementedError();
  @override
  Future<NodeAttachment?> resolve(String attachmentId) async => null;
}

class _AttachmentRaceHarness extends StatefulWidget {
  const _AttachmentRaceHarness({
    super.key,
    this.editing = false,
    this.onImageExport,
  });
  final bool editing;
  final ImageExportCallback? onImageExport;
  @override
  State<_AttachmentRaceHarness> createState() => _AttachmentRaceHarnessState();
}

class _AttachmentRaceHarnessState extends State<_AttachmentRaceHarness> {
  String attachmentId = _attachmentA;
  void switchAttachment(String value) => setState(() => attachmentId = value);
  MindmapNode get node {
    final day = DateTime(2026, 7, 13);
    final updatedAt = attachmentId == _attachmentA
        ? day
        : day.add(const Duration(minutes: 1));
    return MindmapNode.create(
      id: 'race-image',
      type: NodeType.image,
      title: 'Race image',
      day: day,
      now: updatedAt,
      data: ImagePayload(
        attachmentId: attachmentId,
        mimeType: 'image/png',
        fileName: attachmentId == _attachmentA ? 'race-a.png' : 'race-b.png',
        altText: 'Race',
      ).toData({'uiSizePreset': 'wide'}),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SizedBox(
      width: 640,
      height: 480,
      child: KeyedSubtree(
        key: ValueKey(attachmentId),
        child: widget.editing
            ? buildProductionNodeInlineEditorForTest(
                node: node,
                onNodeUpdated: (_) async {},
                onImageExport: widget.onImageExport,
              )
            : buildProductionNodeTypeContentForTest(node),
      ),
    ),
  );
}

class _ImageRevisionHarness extends StatefulWidget {
  const _ImageRevisionHarness({super.key});
  @override
  State<_ImageRevisionHarness> createState() => _ImageRevisionHarnessState();
}

class _OpenImageAttachmentHarness extends StatefulWidget {
  const _OpenImageAttachmentHarness({super.key});

  @override
  State<_OpenImageAttachmentHarness> createState() =>
      _OpenImageAttachmentHarnessState();
}

class _OpenImageAttachmentHarnessState
    extends State<_OpenImageAttachmentHarness> {
  late MindmapNode node = _nodeWithPayload(const ImagePayload());

  MindmapNode _nodeWithPayload(ImagePayload payload) {
    final day = DateTime(2026, 7, 18);
    return MindmapNode.create(
      id: 'open-image-attachment',
      type: NodeType.image,
      title: 'Image',
      day: day,
      now: day,
      data: payload.toData({'uiSizePreset': 'wide'}),
    );
  }

  void attachImage() => setState(() {
    node = _nodeWithPayload(
      const ImagePayload(
        attachmentId: _attachmentA,
        mimeType: 'image/png',
        fileName: 'uploaded.png',
      ),
    ).copyWith(updatedAt: DateTime(2026, 7, 18, 1));
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SizedBox(
      width: 1000,
      height: 900,
      child: buildProductionNodeInlineEditorForTest(
        node: node,
        onNodeUpdated: (_) async {},
      ),
    ),
  );
}

class _ImageRevisionHarnessState extends State<_ImageRevisionHarness> {
  late MindmapNode node = _nodeWithCaption('Persisted');

  MindmapNode _nodeWithCaption(String caption) {
    final day = DateTime(2026, 7, 13);
    return MindmapNode.create(
      id: 'revision-image',
      type: NodeType.image,
      title: 'Revision image',
      day: day,
      now: day,
      data: ImagePayload(
        url: 'https://example.test/photo.png',
        caption: caption,
        altText: 'Revision alt',
      ).toData({'uiSizePreset': 'wide'}),
    );
  }

  void rebuildStaleParent() => setState(() {});

  void applyExternalCaption(String caption) => setState(() {
    node = _nodeWithCaption(caption).copyWith(updatedAt: DateTime(2026, 7, 14));
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: MindmapCanvas(
      nodes: [node],
      highlightedNodeId: node.id,
      onNodeUpdated: (_) async {},
    ),
  );
}

class _PersistingResizeHarness extends StatefulWidget {
  const _PersistingResizeHarness({
    super.key,
    this.deferPersistence = false,
    this.expanded = false,
  });

  final bool deferPersistence;
  final bool expanded;

  @override
  State<_PersistingResizeHarness> createState() =>
      _PersistingResizeHarnessState();
}

class _PersistingResizeHarnessState extends State<_PersistingResizeHarness> {
  late bool expanded = widget.expanded;
  late MindmapNode node = MindmapNode.create(
    id: 'persist-resize',
    type: NodeType.task,
    title: 'Persist resize',
    day: DateTime(2026, 7, 13),
    position: const CanvasPosition(0, 0),
    now: DateTime(2026, 7, 13, 8),
  );
  int commitCount = 0;
  NodeResizeChange? pendingResize;

  void setExpanded(bool value) => setState(() => expanded = value);

  void applyUnrelatedChange() {
    setState(() {
      node = node.copyWith(
        title: '${node.title} refreshed',
        updatedAt: node.updatedAt.add(const Duration(milliseconds: 1)),
      );
    });
  }

  void persistPendingResize() {
    final change = pendingResize;
    if (change == null) return;
    pendingResize = null;
    _applyPersistedResize(node, change);
  }

  void applyExternalChange() {
    final current = node.uiState;
    setState(() {
      node = node.copyWith(
        position: const CanvasPosition(60, 56),
        data: NodeUiStateCodec.write(
          node,
          NodeUiState(
            sizePreset: NodeSizePreset.custom,
            width: 360,
            height: 340,
            collapsedSections: current.collapsedSections,
            editorVersion: current.editorVersion,
          ),
        ),
        updatedAt: node.updatedAt.add(const Duration(seconds: 1)),
      );
    });
  }

  void _persistResize(MindmapNode source, NodeResizeChange change) {
    commitCount += 1;
    if (widget.deferPersistence) {
      pendingResize = change;
      return;
    }
    _applyPersistedResize(source, change);
  }

  void _applyPersistedResize(MindmapNode source, NodeResizeChange change) {
    final current = source.uiState;
    setState(() {
      node = source.copyWith(
        position: CanvasPosition(
          source.position.dx + change.positionDelta.dx,
          source.position.dy + change.positionDelta.dy,
        ),
        data: NodeUiStateCodec.write(
          source,
          NodeUiState(
            sizePreset: change.preset,
            width: change.size.width,
            height: change.size.height,
            collapsedSections: current.collapsedSections,
            editorVersion: current.editorVersion,
          ),
        ),
        updatedAt: source.updatedAt.add(const Duration(milliseconds: 1)),
      );
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: MindmapCanvas(
        nodes: <MindmapNode>[node],
        highlightedNodeId: node.id,
        expandedNodeId: expanded ? node.id : null,
        expandedNodeBuilder: expanded
            ? (_) => const InlineNodeWorkspaceSurface(
                header: SizedBox(height: 64),
                body: SizedBox(),
                footer: SizedBox(height: 32),
              )
            : null,
        onNodeResize: _persistResize,
      ),
    ),
  );
}

Future<void> _pressButton(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  final widget = tester.widget(finder);
  if (widget is ButtonStyleButton) {
    widget.onPressed?.call();
  } else if (widget is IconButton) {
    widget.onPressed?.call();
  } else {
    await tester.tap(finder, warnIfMissed: false);
  }
  await tester.pump();
}

class _BuildNotificationHarness extends StatefulWidget {
  const _BuildNotificationHarness({super.key});

  @override
  State<_BuildNotificationHarness> createState() =>
      _BuildNotificationHarnessState();
}

class _BuildNotificationHarnessState extends State<_BuildNotificationHarness> {
  int notificationCount = 0;

  void rebuildParent() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final now = DateTime(2026, 7, 14, 8);
    return MaterialApp(
      home: Scaffold(
        body: MindmapCanvas(
          nodes: [
            MindmapNode.create(
              id: 'build-loop',
              type: NodeType.note,
              title: 'Stable',
              day: now,
              now: now,
            ),
          ],
          onNodeCardBuilt: (_) {
            notificationCount++;
            setState(() {});
          },
        ),
      ),
    );
  }
}

void _setCanvasScale(WidgetTester tester, Finder nodeFinder, double scale) {
  final interactiveFinder = find.byType(InteractiveViewer);
  final interactive = tester.widget<InteractiveViewer>(interactiveFinder);
  final controller = interactive.transformationController!;
  final viewport = tester.getRect(interactiveFinder);
  final localCenter = viewport.center - viewport.topLeft;
  final nodeLocalCenter = tester.getCenter(nodeFinder) - viewport.topLeft;
  final sceneCenter = controller.toScene(nodeLocalCenter);
  controller.value = Matrix4.identity()
    ..translateByDouble(localCenter.dx, localCenter.dy, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1)
    ..translateByDouble(-sceneCenter.dx, -sceneCenter.dy, 0, 1);
}

Future<_DirectResizeGesture> _startResizeThroughCanvas(
  WidgetTester tester,
  Finder nodeFinder,
  NodeResizeHandle handle,
  Offset delta,
) async {
  final handleFinder = find.descendant(
    of: nodeFinder,
    matching: find.byKey(NodeShell.resizeHandleKey(handle)),
  );
  final detector = tester.widget<GestureDetector>(handleFinder);
  detector.onPanStart?.call(
    DragStartDetails(
      globalPosition: tester.getCenter(handleFinder),
      localPosition: Offset.zero,
    ),
  );
  detector.onPanUpdate?.call(
    DragUpdateDetails(
      globalPosition: tester.getCenter(handleFinder) + delta,
      delta: delta,
    ),
  );
  await tester.pump();
  return _DirectResizeGesture(
    up: () {
      detector.onPanEnd?.call(DragEndDetails());
      return tester.pump();
    },
    cancel: () {
      detector.onPanCancel?.call();
      return tester.pump();
    },
  );
}

final class _DirectResizeGesture {
  const _DirectResizeGesture({
    required Future<void> Function() up,
    required Future<void> Function() cancel,
  }) : _up = up,
       _cancel = cancel;

  final Future<void> Function() _up;
  final Future<void> Function() _cancel;

  Future<void> up() => _up();
  Future<void> cancel() => _cancel();
}

Future<void> _resizeThroughCanvas(
  WidgetTester tester,
  Finder nodeFinder,
  NodeResizeHandle handle,
  Offset delta,
) async {
  final gesture = await _startResizeThroughCanvas(
    tester,
    nodeFinder,
    handle,
    delta,
  );
  await gesture.up();
}

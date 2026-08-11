import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/node_graph.dart';
import 'package:var_app/features/mindmap/domain/node_relations.dart';
import 'package:var_app/features/mindmap/presentation/node_mini_apps/node_detail_global_tabs.dart';

void main() {
  testWidgets('relations renders focused neighborhood graph without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 8, 11);
    final neighbor = MindmapNode.create(
      id: 'neighbor',
      type: NodeType.note,
      title: 'Neighbor',
      day: day,
      now: day,
    );
    final current = MindmapNode.create(
      id: 'current',
      type: NodeType.task,
      title: 'Current',
      day: day,
      now: day,
    ).copyWith(relatedNodeIds: const ['neighbor']);
    final graph = NodeGraph.fromNodes([current, neighbor]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allMindmapNodesProvider.overrideWith(
            (ref) async => [current, neighbor],
          ),
          nodeGraphProvider.overrideWith((ref) async => graph),
          nodeRelationsProvider(current.id).overrideWith(
            (ref) async => NodeRelations(
              nodeId: current.id,
              relatedNodes: [neighbor],
              backlinks: const [],
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NodeRelationsTab(node: current, onNodeSaved: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('node-relations-neighborhood-graph')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Current'), findsOneWidget);
    expect(find.bySemanticsLabel('Neighbor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('relations serializes rapid links against latest saved node', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 8, 11);
    final first = MindmapNode.create(
      id: 'first',
      type: NodeType.note,
      title: 'First',
      day: day,
      now: day,
    );
    final second = MindmapNode.create(
      id: 'second',
      type: NodeType.note,
      title: 'Second',
      day: day,
      now: day,
    );
    final current = MindmapNode.create(
      id: 'current',
      type: NodeType.task,
      title: 'Current',
      day: day,
      now: day,
    );
    final repository = _DelayedMindmapRepository(
      seedNodes: [current, first, second],
    );
    var visible = current;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(repository),
          allMindmapNodesProvider.overrideWith(
            (ref) async => [visible, first, second],
          ),
          nodeGraphProvider.overrideWith(
            (ref) async => NodeGraph.fromNodes([visible, first, second]),
          ),
          nodeRelationsProvider(current.id).overrideWith(
            (ref) async => NodeRelations(
              nodeId: current.id,
              relatedNodes: const [],
              backlinks: const [],
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NodeRelationsTab(
              node: visible,
              prepareMutation: () async => visible,
              onNodeSaved: (saved) => visible = saved,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final links = find.byTooltip('Link node');
    expect(links, findsNWidgets(2));
    await tester.tap(links.first);
    await tester.tap(links.last);
    await tester.pump();

    expect(repository.pendingSaveCount, 1);
    repository.completeNextSave();
    await tester.pump();
    await tester.pump();
    expect(repository.pendingSaveCount, 1);
    repository.completeNextSave();
    await tester.pumpAndSettle();

    expect((await repository.getNode(current.id))?.relatedNodeIds, {
      first.id,
      second.id,
    });
  });

  testWidgets('relations graph shows empty state for isolated node', (
    tester,
  ) async {
    final day = DateTime(2026, 8, 11);
    final current = MindmapNode.create(
      id: 'current',
      type: NodeType.note,
      title: 'Current',
      day: day,
      now: day,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allMindmapNodesProvider.overrideWith((ref) async => [current]),
          nodeGraphProvider.overrideWith(
            (ref) async => NodeGraph.fromNodes([current]),
          ),
          nodeRelationsProvider(current.id).overrideWith(
            (ref) async => NodeRelations(
              nodeId: current.id,
              relatedNodes: const [],
              backlinks: const [],
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NodeRelationsTab(node: current, onNodeSaved: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Link another node to build this neighborhood.'),
      findsOneWidget,
    );
  });
}

final class _DelayedMindmapRepository implements MindmapRepository {
  _DelayedMindmapRepository({required Iterable<MindmapNode> seedNodes})
    : _base = InMemoryMindmapRepository(seedNodes: seedNodes);

  final InMemoryMindmapRepository _base;
  final List<(MindmapNode, Completer<MindmapNode>)> _pending = [];

  int get pendingSaveCount => _pending.length;

  @override
  Future<void> deleteNode(String id) => _base.deleteNode(id);

  @override
  Future<MindmapNode?> getNode(String id) => _base.getNode(id);

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      _base.listNodes(day: day);

  @override
  Future<MindmapNode> saveNode(MindmapNode node) {
    final completer = Completer<MindmapNode>();
    _pending.add((node, completer));
    return completer.future;
  }

  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      _base.searchNodes(query);

  void completeNextSave() {
    final pending = _pending.removeAt(0);
    _base.saveNode(pending.$1).then(pending.$2.complete);
  }
}

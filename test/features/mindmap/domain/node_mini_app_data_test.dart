import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_mini_app_data.dart';

void main() {
  MindmapNode node() => MindmapNode.create(
    id: 'node-1',
    type: NodeType.task,
    title: 'Original',
    day: DateTime(2026, 8, 11),
  );

  test('updates mini-app section without dropping node payload', () {
    final source = node().copyWith(
      data: const <String, Object?>{'task': 'keep'},
    );
    final updated = updateNodeMiniAppSection(
      source,
      'task',
      const <String, Object?>{'important': true},
    );

    expect(updated.data['task'], 'keep');
    expect(nodeMiniAppSection(updated, 'task')['important'], isTrue);
  });

  test('describes user-facing differences between node revisions', () {
    final previous = node();
    final current = previous.copyWith(
      title: 'Renamed',
      progress: 0.5,
      relatedNodeIds: const <String>['node-2'],
    );

    expect(
      describeNodeChanges(current, previous),
      containsAll(<String>['Title', 'Progress', 'Relations']),
    );
  });
}

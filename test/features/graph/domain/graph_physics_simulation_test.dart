import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/graph/domain/graph_physics_simulation.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_graph.dart';

void main() {
  group('GraphPhysicsSimulation Engine', () {
    final now = DateTime(2026, 8, 7);

    test('initializes physics nodes and steps simulation without throwing', () {
      final n1 = MindmapNode.create(
        id: 'n1',
        type: NodeType.note,
        title: 'Node 1',
        day: now,
      );
      final n2 = MindmapNode.create(
        id: 'n2',
        type: NodeType.note,
        title: 'Node 2',
        day: now,
      );

      final graph = NodeGraph.fromNodes([n1, n2]);
      final simulation = GraphPhysicsSimulation(nodes: [n1, n2], graph: graph);

      expect(simulation.physicsNodes.length, equals(2));
      expect(simulation.physicsNodes['n1']!.type, NodeType.note);
      final initialX1 = simulation.physicsNodes['n1']!.x;

      simulation.step();
      final steppedX1 = simulation.physicsNodes['n1']!.x;

      expect(initialX1, isNot(equals(steppedX1)));
    });

    test('settles after bounded simulation steps', () {
      final nodes = [
        for (var index = 0; index < 6; index++)
          MindmapNode.create(
            id: 'n$index',
            type: NodeType.note,
            title: 'Node $index',
            day: now,
          ),
      ];
      final simulation = GraphPhysicsSimulation(
        nodes: nodes,
        graph: NodeGraph.fromNodes(nodes),
      );

      for (var index = 0; index < 1000; index++) {
        simulation.step();
      }

      expect(simulation.isSettled(), isTrue);
    });
  });
}

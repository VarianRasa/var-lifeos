/// Spring force-directed physics simulation engine for Obsidian-style Knowledge Graph.
library;

import 'dart:math' as math;

import '../../../core/constants/app_constants.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_graph.dart';

final class GraphPhysicsNode {
  GraphPhysicsNode({
    required this.id,
    required this.title,
    required this.type,
    required this.x,
    required this.y,
  });

  final String id;
  final String title;
  final NodeType type;
  double x;
  double y;
  double vx = 0.0;
  double vy = 0.0;
}

final class GraphPhysicsEdge {
  const GraphPhysicsEdge({required this.sourceId, required this.targetId});

  final String sourceId;
  final String targetId;
}

final class GraphPhysicsSimulation {
  GraphPhysicsSimulation({
    required List<MindmapNode> nodes,
    required NodeGraph graph,
    this.repulsion = 4000.0,
    this.springLength = 100.0,
    this.stiffness = 0.05,
    this.damping = 0.85,
    this.centering = 0.002,
  }) {
    final rand = math.Random(42);
    final count = nodes.length;

    for (var i = 0; i < count; i++) {
      final node = nodes[i];
      final angle = (i / count) * 2 * math.pi;
      final radius = 150.0 + rand.nextDouble() * 50.0;
      physicsNodes[node.id] = GraphPhysicsNode(
        id: node.id,
        title: node.title,
        type: node.type,
        x: math.cos(angle) * radius,
        y: math.sin(angle) * radius,
      );
    }

    for (final edge in graph.edges) {
      if (physicsNodes.containsKey(edge.sourceId) &&
          physicsNodes.containsKey(edge.targetId)) {
        edges.add(
          GraphPhysicsEdge(sourceId: edge.sourceId, targetId: edge.targetId),
        );
      }
    }
  }

  final Map<String, GraphPhysicsNode> physicsNodes = {};
  final List<GraphPhysicsEdge> edges = [];
  final double repulsion;
  final double springLength;
  final double stiffness;
  final double damping;
  final double centering;

  double get maxSpeed => physicsNodes.values.fold<double>(0, (fastest, node) {
    return math.max(fastest, math.sqrt(node.vx * node.vx + node.vy * node.vy));
  });

  bool isSettled({double speedThreshold = 0.05}) => maxSpeed <= speedThreshold;

  void step() {
    final nodeList = physicsNodes.values.toList();

    // 1. Repulsion forces between nodes
    for (var i = 0; i < nodeList.length; i++) {
      for (var j = i + 1; j < nodeList.length; j++) {
        final n1 = nodeList[i];
        final n2 = nodeList[j];

        final dx = n2.x - n1.x;
        final dy = n2.y - n1.y;
        final distSq = math.max(dx * dx + dy * dy, 100.0);
        final dist = math.sqrt(distSq);

        final force = repulsion / distSq;
        final fx = (dx / dist) * force;
        final fy = (dy / dist) * force;

        n1.vx -= fx;
        n1.vy -= fy;
        n2.vx += fx;
        n2.vy += fy;
      }
    }

    // 2. Spring attraction along edges
    for (final edge in edges) {
      final n1 = physicsNodes[edge.sourceId];
      final n2 = physicsNodes[edge.targetId];
      if (n1 == null || n2 == null) continue;

      final dx = n2.x - n1.x;
      final dy = n2.y - n1.y;
      final dist = math.max(math.sqrt(dx * dx + dy * dy), 1.0);

      final force = (dist - springLength) * stiffness;
      final fx = (dx / dist) * force;
      final fy = (dy / dist) * force;

      n1.vx += fx;
      n1.vy += fy;
      n2.vx -= fx;
      n2.vy -= fy;
    }

    // 3. Pull the layout toward the scene center, then update positions.
    for (final node in nodeList) {
      node.vx = (node.vx - node.x * centering) * damping;
      node.vy = (node.vy - node.y * centering) * damping;
      if (node.vx.abs() < 0.001) node.vx = 0;
      if (node.vy.abs() < 0.001) node.vy = 0;
      node.x += node.vx;
      node.y += node.vy;
    }
  }
}

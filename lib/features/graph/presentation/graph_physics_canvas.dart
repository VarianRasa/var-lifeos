import 'package:flutter/material.dart';

import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_graph.dart';
import '../domain/graph_physics_simulation.dart';

class GraphPhysicsCanvas extends StatefulWidget {
  const GraphPhysicsCanvas({
    super.key,
    required this.nodes,
    required this.graph,
    required this.onNodeTap,
  });

  final List<MindmapNode> nodes;
  final NodeGraph graph;
  final ValueChanged<String> onNodeTap;

  @override
  State<GraphPhysicsCanvas> createState() => _GraphPhysicsCanvasState();
}

class _GraphPhysicsCanvasState extends State<GraphPhysicsCanvas>
    with SingleTickerProviderStateMixin {
  late GraphPhysicsSimulation _simulation;
  late AnimationController _controller;
  final TransformationController _transformationController =
      TransformationController();
  bool _motionConfigured = false;
  bool _reduceMotion = false;
  int _settledFrames = 0;

  @override
  void initState() {
    super.initState();
    _initSimulation();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _controller.addListener(_onTick);
    _transformationController.addListener(_onTransformChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerScene());
  }

  void _initSimulation() {
    _simulation = GraphPhysicsSimulation(
      nodes: widget.nodes,
      graph: widget.graph,
    );
  }

  void _centerScene() {
    final size = context.size;
    if (!mounted || size == null) return;
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(
        (size.width - 1600) / 2,
        (size.height - 1200) / 2,
        0,
        1,
      );
  }

  void _onTransformChanged() => setState(() {});

  void _onTick() {
    _simulation.step();
    if (_simulation.isSettled()) {
      _settledFrames++;
      if (_settledFrames >= 12) _controller.stop();
    } else {
      _settledFrames = 0;
    }
    setState(() {});
  }

  void _configureMotion() {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
    if (_motionConfigured && reduceMotion == _reduceMotion) return;
    _motionConfigured = true;
    _reduceMotion = reduceMotion;
    _settledFrames = 0;
    if (reduceMotion) {
      _controller.stop();
      for (var stepIndex = 0; stepIndex < 240; stepIndex++) {
        _simulation.step();
      }
    } else {
      _controller.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureMotion();
  }

  @override
  void didUpdateWidget(covariant GraphPhysicsCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodes != widget.nodes || oldWidget.graph != widget.graph) {
      _initSimulation();
      _motionConfigured = false;
      _configureMotion();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final targetSize = 44 / scale;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Physics graph canvas, ${widget.nodes.length} nodes',
      child: InteractiveViewer(
        transformationController: _transformationController,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(1000),
        minScale: 0.2,
        maxScale: 3.5,
        child: SizedBox(
          width: 1600,
          height: 1200,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GraphPhysicsPainter(
                    simulation: _simulation,
                    theme: theme,
                  ),
                ),
              ),
              for (final node in _simulation.physicsNodes.values)
                Positioned(
                  left: 800 + node.x - targetSize / 2,
                  top: 600 + node.y - targetSize / 2,
                  child: Semantics(
                    button: true,
                    label: node.title,
                    child: SizedBox.square(
                      dimension: targetSize,
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => widget.onNodeTap(node.id),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GraphPhysicsPainter extends CustomPainter {
  _GraphPhysicsPainter({required this.simulation, required this.theme});

  final GraphPhysicsSimulation simulation;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final edgePaint = Paint()
      ..color = theme.colorScheme.primary.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final nodePaint = Paint()
      ..color = theme.colorScheme.primary
      ..style = PaintingStyle.fill;

    // Draw Edges
    for (final edge in simulation.edges) {
      final n1 = simulation.physicsNodes[edge.sourceId];
      final n2 = simulation.physicsNodes[edge.targetId];
      if (n1 == null || n2 == null) continue;

      final p1 = center + Offset(n1.x, n1.y);
      final p2 = center + Offset(n2.x, n2.y);
      canvas.drawLine(p1, p2, edgePaint);
    }

    // Draw Nodes & Labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final node in simulation.physicsNodes.values) {
      final pos = center + Offset(node.x, node.y);

      canvas.drawCircle(pos, 8, nodePaint);

      textPainter.text = TextSpan(
        text: node.title,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, pos + const Offset(12, -6));
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPhysicsPainter oldDelegate) => true;
}

import 'package:var_app/core/constants/app_constants.dart';

enum NodeSizePreset { auto, compact, standard, large, wide, custom }

final class NodePresentationState {
  const NodePresentationState({
    required this.preset,
    required this.width,
    required this.height,
  });

  final NodeSizePreset preset;
  final double width;
  final double height;
}

final class NodePresentationSpec {
  const NodePresentationSpec._({
    required this.defaultPreset,
    required this.minWidth,
    required this.minHeight,
    required this.maxWidth,
    required this.maxHeight,
  });

  factory NodePresentationSpec.forType(NodeType type) {
    switch (type) {
      case NodeType.kanban:
      case NodeType.itinerary:
      case NodeType.video:
        return const NodePresentationSpec._(
          defaultPreset: NodeSizePreset.wide,
          minWidth: 320,
          minHeight: 180,
          maxWidth: 960,
          maxHeight: 720,
        );
      case NodeType.resource:
        return const NodePresentationSpec._(
          defaultPreset: NodeSizePreset.standard,
          minWidth: 220,
          minHeight: 270,
          maxWidth: 800,
          maxHeight: 720,
        );
      case NodeType.note:
      case NodeType.plan:
      case NodeType.goal:
      case NodeType.decision:
      case NodeType.checklist:
      case NodeType.canvas:
      case NodeType.image:
        return const NodePresentationSpec._(
          defaultPreset: NodeSizePreset.standard,
          minWidth: 220,
          minHeight: 140,
          maxWidth: 800,
          maxHeight: 720,
        );
      case NodeType.journal:
        return const NodePresentationSpec._(
          defaultPreset: NodeSizePreset.large,
          minWidth: 300,
          minHeight: 220,
          maxWidth: 900,
          maxHeight: 850,
        );
      case NodeType.task:
        return const NodePresentationSpec._(
          defaultPreset: NodeSizePreset.standard,
          minWidth: 180,
          minHeight: 96,
          maxWidth: 900,
          maxHeight: 1100,
        );
      case NodeType.habit:
      case NodeType.link:
      case NodeType.event:
      case NodeType.idea:
      case NodeType.question:
      case NodeType.contact:
      case NodeType.metric:
      case NodeType.expense:
      case NodeType.bookmark:
      case NodeType.routine:
      case NodeType.mood:
      case NodeType.timer:
      case NodeType.quote:
      case NodeType.audio:
      case NodeType.weather:
      case NodeType.fit:
      case NodeType.empty:
        return const NodePresentationSpec._(
          defaultPreset: NodeSizePreset.standard,
          minWidth: 180,
          minHeight: 96,
          maxWidth: 640,
          maxHeight: 560,
        );
    }
  }

  final NodeSizePreset defaultPreset;
  final double minWidth;
  final double minHeight;
  final double maxWidth;
  final double maxHeight;

  NodePresentationState resolve({
    NodeSizePreset preset = NodeSizePreset.auto,
    double? customWidth,
    double? customHeight,
  }) {
    final NodeSizePreset dimensionPreset = preset == NodeSizePreset.auto
        ? defaultPreset
        : preset;
    final (double, double) dimensions = _dimensionsFor(dimensionPreset);
    final bool hasCustomWidth = customWidth?.isFinite ?? false;
    final bool hasCustomHeight = customHeight?.isFinite ?? false;
    final double width = hasCustomWidth ? customWidth! : dimensions.$1;
    final double height = hasCustomHeight ? customHeight! : dimensions.$2;

    return NodePresentationState(
      preset: hasCustomWidth || hasCustomHeight
          ? NodeSizePreset.custom
          : preset,
      width: width.clamp(minWidth, maxWidth).toDouble(),
      height: height.clamp(minHeight, maxHeight).toDouble(),
    );
  }

  (double, double) _dimensionsFor(NodeSizePreset preset) {
    switch (preset) {
      case NodeSizePreset.auto:
        return _dimensionsFor(defaultPreset);
      case NodeSizePreset.compact:
        return (minWidth, minHeight);
      case NodeSizePreset.standard:
        return (
          _interpolate(minWidth, maxWidth, 0.25),
          _interpolate(minHeight, maxHeight, 0.25),
        );
      case NodeSizePreset.large:
        return (
          _interpolate(minWidth, maxWidth, 0.6),
          _interpolate(minHeight, maxHeight, 0.6),
        );
      case NodeSizePreset.wide:
        return (
          _interpolate(minWidth, maxWidth, 0.9),
          _interpolate(minHeight, maxHeight, 0.6),
        );
      case NodeSizePreset.custom:
        return _dimensionsFor(defaultPreset);
    }
  }

  double _interpolate(double minimum, double maximum, double fraction) {
    return minimum + ((maximum - minimum) * fraction);
  }
}

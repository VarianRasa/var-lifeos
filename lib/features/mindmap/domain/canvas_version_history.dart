import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

class CanvasVersionSnapshot {
  final String id;
  final String label;
  final DateTime timestamp;
  final List<MindmapNode> nodes;

  const CanvasVersionSnapshot({
    required this.id,
    required this.label,
    required this.timestamp,
    required this.nodes,
  });
}

class CanvasVersionHistoryEngine {
  final List<CanvasVersionSnapshot> _history = [];

  List<CanvasVersionSnapshot> get history => List.unmodifiable(_history);

  void recordSnapshot({
    required String label,
    required List<MindmapNode> nodes,
  }) {
    _history.add(
      CanvasVersionSnapshot(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        label: label,
        timestamp: DateTime.now(),
        nodes: List.unmodifiable(nodes),
      ),
    );
  }

  List<MindmapNode>? rollbackToVersion(String snapshotId) {
    for (final snapshot in _history) {
      if (snapshot.id == snapshotId) return snapshot.nodes;
    }
    return null;
  }
}

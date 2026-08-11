import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

class TrashedCanvasNode {
  final MindmapNode node;
  final DateTime deletedAt;

  const TrashedCanvasNode({required this.node, required this.deletedAt});
}

class CanvasTrashBin {
  final List<TrashedCanvasNode> _items = [];

  List<TrashedCanvasNode> get items => List.unmodifiable(_items);

  void moveNodeToTrash(MindmapNode node) {
    _items.add(TrashedCanvasNode(node: node, deletedAt: DateTime.now()));
  }

  MindmapNode? restoreNode(String nodeId) {
    final index = _items.indexWhere((item) => item.node.id == nodeId);
    if (index != -1) {
      final item = _items.removeAt(index);
      return item.node;
    }
    return null;
  }

  void emptyTrash() {
    _items.clear();
  }
}

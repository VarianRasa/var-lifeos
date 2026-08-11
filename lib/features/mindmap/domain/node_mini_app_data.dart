import 'mindmap_node.dart';

const String nodeMiniAppDataKey = 'miniApp';

Map<String, Object?> nodeMiniAppData(MindmapNode node) {
  return _stringMap(node.data[nodeMiniAppDataKey]);
}

Map<String, Object?> nodeMiniAppSection(MindmapNode node, String section) {
  return _stringMap(nodeMiniAppData(node)[section]);
}

MindmapNode updateNodeMiniAppSection(
  MindmapNode node,
  String section,
  Map<String, Object?> values,
) {
  final miniApp = nodeMiniAppData(node);
  return node.copyWith(
    data: <String, Object?>{
      ...node.data,
      nodeMiniAppDataKey: <String, Object?>{
        ...miniApp,
        section: <String, Object?>{..._stringMap(miniApp[section]), ...values},
      },
    },
  );
}

List<String> describeNodeChanges(MindmapNode current, MindmapNode previous) {
  final changes = <String>[];
  if (current.title != previous.title) changes.add('Title');
  if (current.body != previous.body) changes.add('Body');
  if (current.status != previous.status) changes.add('Status');
  if (current.priority != previous.priority) changes.add('Priority');
  if (current.progress != previous.progress) changes.add('Progress');
  if (current.dueDate != previous.dueDate) changes.add('Due date');
  if (current.relatedNodeIds.join('|') != previous.relatedNodeIds.join('|')) {
    changes.add('Relations');
  }
  if (current.blockedByNodeIds.join('|') !=
      previous.blockedByNodeIds.join('|')) {
    changes.add('Dependencies');
  }
  if (current.presentationDataKey != previous.presentationDataKey) {
    changes.add('App data');
  }
  return List<String>.unmodifiable(changes);
}

Map<String, Object?> _stringMap(Object? value) {
  if (value is! Map) return <String, Object?>{};
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

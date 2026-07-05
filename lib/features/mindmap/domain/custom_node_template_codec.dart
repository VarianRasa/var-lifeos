/// JSON codec for user-created node templates.
library;

import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';
import 'node_template.dart';

const customNodeTemplatesPreferenceKey = 'custom_node_templates';

Map<String, Object?> nodeTemplateToJson(NodeTemplate template) => {
  'id': template.id,
  'label': template.label,
  'type': template.type.name,
  'title': template.title,
  'body': template.body,
  'status': template.status.name,
  'priority': template.priority.name,
  'project': template.project,
  'area': template.area,
  'tags': template.tags,
  'progress': template.progress,
  'checklist': template.checklist,
  'data': template.data,
};

NodeTemplate? nodeTemplateFromJson(Object? value) {
  if (value case final Map<String, Object?> map) {
    final id = map['id']?.toString() ?? '';
    final label = map['label']?.toString() ?? '';
    final type = _enumByName(NodeType.values, map['type']?.toString());
    final status = _enumByName(NodeStatus.values, map['status']?.toString());
    final priority = _enumByName(
      NodePriority.values,
      map['priority']?.toString(),
    );
    if (id.isEmpty || label.isEmpty || type == null) return null;
    return NodeTemplate(
      id: id,
      label: label,
      type: type,
      title: map['title']?.toString() ?? label,
      body: map['body']?.toString() ?? '',
      status: status ?? NodeStatus.open,
      priority: priority ?? NodePriority.none,
      project: map['project']?.toString() ?? '',
      area: map['area']?.toString() ?? '',
      tags: _stringList(map['tags']),
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      checklist: _stringList(map['checklist']),
      data: _objectMap(map['data']),
    );
  }
  return null;
}

List<NodeTemplate> nodeTemplatesFromJsonList(Object? value) {
  if (value is! List<Object?>) return const [];
  return value.map(nodeTemplateFromJson).nonNulls.toList(growable: false);
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?>) return const [];
  return [
    for (final item in value)
      if (item != null && item.toString().trim().isNotEmpty)
        item.toString().trim(),
  ];
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map<Object?, Object?>) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key != null) entry.key.toString(): entry.value,
  };
}

T? _enumByName<T extends Enum>(Iterable<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
